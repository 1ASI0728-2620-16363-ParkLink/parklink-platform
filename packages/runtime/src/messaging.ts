import amqp, { type ChannelModel, type ConfirmChannel } from 'amqplib';
import { randomUUID } from 'node:crypto';
import { EXCHANGE, MessageSchema, type Message } from '@parklink/contracts';
import { pool, transaction, type Tx } from './database';

export async function enqueue(tx: Tx, type: string, payload: Record<string, unknown>, actorId: string, correlationId: string, exchange: string = EXCHANGE.EVENTS, id: string = randomUUID()) {
  const message: Message = { id, type, payload, actorId, correlationId, version: 1, occurredAt: new Date().toISOString() };
  await tx.query('INSERT INTO outbox(id,exchange,routing_key,message) VALUES($1,$2,$3,$4)', [id, exchange, type, message]);
  return message;
}
export async function inbox(tx: Tx, id: string) { return (await tx.query('INSERT INTO inbox(id) VALUES($1) ON CONFLICT DO NOTHING RETURNING id', [id])).rowCount === 1; }
export class Bus {
  private connection?: ChannelModel;
  private channel?: ConfirmChannel;
  private timer?: NodeJS.Timeout;
  private retry?: NodeJS.Timeout;
  private stopped = false;
  private relaying = false;
  private subscriptions: Array<{ queue: string; exchange: string; keys: string[]; handler: (m: Message) => Promise<void> }> = [];
  get ready() { return !!this.channel; }
  subscribe(queue: string, exchange: string, keys: string[], handler: (m: Message) => Promise<void>) { this.subscriptions.push({ queue, exchange, keys, handler }); }
  async start() {
    if (this.stopped) return;
    try {
      const connection = await amqp.connect(process.env.AMQP_URL ?? 'amqp://localhost'); this.connection = connection;
      connection.on('error', () => {});
      connection.on('close', () => { this.channel = undefined; if (!this.stopped) this.retry = setTimeout(() => void this.start(), 3000); });
      const ch = await connection.createConfirmChannel();
      ch.on('error', () => {}); ch.on('close', () => { this.channel = undefined; if (!this.stopped) void connection.close().catch(() => {}); });
      for (const exchange of Object.values(EXCHANGE)) await ch.assertExchange(exchange, 'topic', { durable: true });
      await ch.prefetch(8);
      const topology = [
        {queue:'reservation.commands.v1',exchange:EXCHANGE.COMMANDS,keys:['reservation.*.v1']},
        {queue:'payment.commands.v1',exchange:EXCHANGE.COMMANDS,keys:['payment.*.v1']},
        {queue:'supply.events.v1',exchange:EXCHANGE.EVENTS,keys:['supply.revision-accepted.v1','supply.revision-rejected.v1']},
        {queue:'reservation.events.v1',exchange:EXCHANGE.EVENTS,keys:['supply.revision-proposed.v1','payment.authorized.v1','payment.failed.v1']},
        {queue:'discovery.events.v1',exchange:EXCHANGE.EVENTS,keys:['supply.revision-accepted.v1','reservation.*.v1']},
        {queue:'notification.events.v1',exchange:EXCHANGE.EVENTS,keys:['reservation.confirmed.v1','reservation.cancelled.v1','reservation.expired.v1','reservation.payment-failed.v1','payment.refunded.v1']},
        {queue:'audit.events.v1',exchange:EXCHANGE.EVENTS,keys:['#']}
      ];
      for (const s of [...topology,...this.subscriptions.filter(s=>!topology.some(t=>t.queue===s.queue))]) {
        const dead = `${s.queue}.dlq`; const retry = `${s.queue}.retry`;
        await ch.assertQueue(dead, { durable: true, arguments: { 'x-queue-type': 'quorum' } });
        await ch.bindQueue(dead, EXCHANGE.DEAD, s.queue);
        await ch.assertQueue(s.queue, { durable: true, arguments: { 'x-queue-type': 'quorum', 'x-dead-letter-exchange': EXCHANGE.DEAD, 'x-dead-letter-routing-key': s.queue } });
        await ch.assertQueue(retry, { durable: true, arguments: { 'x-queue-type': 'quorum', 'x-message-ttl': 3000, 'x-dead-letter-exchange': '', 'x-dead-letter-routing-key': s.queue } });
        for (const key of s.keys) await ch.bindQueue(s.queue, s.exchange, key);
      }
      for (const s of this.subscriptions) {
        const retry = `${s.queue}.retry`;
        await ch.consume(s.queue, async raw => {
          if (!raw) return;
          try { await s.handler(MessageSchema.parse(JSON.parse(raw.content.toString()))); ch.ack(raw); }
          catch (error) {
            console.error(JSON.stringify({event:'message_handler_retry',queue:s.queue,messageId:raw.properties.messageId,code:(error as {code?:string}).code,error:error instanceof Error ? error.message.slice(0,200) : 'invalid_message'}));
            const attempts = Number(raw.properties.headers?.['x-attempt'] ?? 0);
            if (attempts >= 3) { ch.nack(raw, false, false); return; }
            try {
              ch.sendToQueue(retry, raw.content, { persistent: true, contentType: 'application/json', headers: { 'x-attempt': attempts + 1 }, messageId: raw.properties.messageId, correlationId: raw.properties.correlationId });
              await ch.waitForConfirms(); ch.ack(raw);
            } catch { void connection.close().catch(() => {}); }
          }
        }, { noAck: false });
      }
      this.channel = ch;
      if (!this.timer) this.timer = setInterval(() => void this.relay(), 250);
    } catch { this.channel = undefined; if (this.connection) await this.connection.close().catch(() => {}); if (!this.stopped && !this.connection) this.retry = setTimeout(() => void this.start(), 3000); }
  }
  async relay() {
    const ch = this.channel; if (!ch || this.relaying) return; this.relaying = true;
    try {
      await transaction(async tx => {
        const result = await tx.query('SELECT * FROM outbox WHERE published_at IS NULL ORDER BY created_at LIMIT 25 FOR UPDATE SKIP LOCKED');
        for (const row of result.rows) {
          ch.publish(row.exchange, row.routing_key, Buffer.from(JSON.stringify(row.message)), { persistent: true, contentType: 'application/json', messageId: row.id, correlationId: row.message.correlationId });
          await ch.waitForConfirms(); await tx.query('UPDATE outbox SET published_at=now() WHERE id=$1', [row.id]);
        }
      });
    } catch { console.error(JSON.stringify({ event: 'outbox_relay_retry' })); } finally { this.relaying = false; }
  }
  async stop() { this.stopped = true; clearInterval(this.timer); clearTimeout(this.retry); await this.connection?.close(); await pool.end(); }
}

import { createHash, randomUUID } from 'node:crypto';
import { ConflictException, NotFoundException } from '@nestjs/common';
import { EXCHANGE, HoldSchema, ConfirmSchema, CancelSchema, SpaceSchema, type Actor, type Message } from '@parklink/contracts';
import { transaction, pool, enqueue, inbox, type Tx, owns } from '@parklink/runtime';
import { DomainError, assertInterval, allows, quote, canConfirm, refundAmount, type Interval } from '../domain/reservation';

export class Reservations {
 async submit(kind: string, input: unknown, key: string, actor: Actor, correlationId: string) {
  if (!key || key.length > 128) throw new DomainError('Idempotency-Key required (maximum 128 characters)', 400);
  const payload = kind === 'hold' ? HoldSchema.parse(input) : kind === 'confirm' ? ConfirmSchema.parse(input) : CancelSchema.parse(input);
  const hash = createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  return transaction(async tx => {
   await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`${actor.id}:${kind}:${key}`]);
   const existing = (await tx.query('SELECT * FROM operations WHERE actor_id=$1 AND kind=$2 AND key=$3', [actor.id, kind, key])).rows[0];
   if (existing) { if (existing.hash !== hash) throw new ConflictException('Idempotency key reused with different payload'); return { commandId: existing.id }; }
   const commandId = randomUUID();
   await tx.query('INSERT INTO operations(id,actor_id,kind,key,hash) VALUES($1,$2,$3,$4,$5)', [commandId, actor.id, kind, key, hash]);
   await enqueue(tx, `reservation.${kind}.v1`, { ...payload, commandId }, actor.id, correlationId, EXCHANGE.COMMANDS, commandId);
   return { commandId };
  });
 }
 async operation(id: string, actor: Actor) { const row = (await pool.query('SELECT id,status,result,http_status FROM operations WHERE id=$1 AND actor_id=$2', [id, actor.id])).rows[0]; if (!row) throw new NotFoundException(); return row; }
 async lock(tx: Tx, spaceId: string) { await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))', [spaceId]); }
 async publishState(tx: Tx, id: string, type: string, m: Message) {
  const row = (await tx.query('SELECT * FROM reservations WHERE id=$1', [id])).rows[0];
  await tx.query('INSERT INTO reservation_history(reservation_id,status,correlation_id) VALUES($1,$2,$3)', [id, row.status, m.correlationId]);
  await enqueue(tx, type, { reservationId: id, spaceId: row.space_id, driverId: row.driver_id, ownerId: row.owner_id, start: row.start_time.toISOString(), end: row.end_time.toISOString(), status: row.status, version: row.version, expiresAt: row.expires_at.toISOString(), amount: row.amount, code: row.code }, m.actorId, m.correlationId);
 }
 async expireSpace(tx: Tx, spaceId: string, m: Message) {
  const expired = await tx.query("UPDATE reservations SET status='EXPIRED',version=version+1 WHERE space_id=$1 AND status='PENDING_PAYMENT' AND expires_at<=now() RETURNING id", [spaceId]);
  for (const row of expired.rows) await this.publishState(tx, row.id, 'reservation.expired.v1', m);
 }
 async command(m: Message) {
  await transaction(async tx => {
   if (!await inbox(tx, m.id)) return;
   await tx.query(`INSERT INTO operations(id,actor_id,kind,key,hash) VALUES($1::uuid,$2,$3,$1::uuid::text,$4) ON CONFLICT DO NOTHING`, [m.payload.commandId,m.actorId,m.type.split('.')[1],createHash('sha256').update(JSON.stringify(m.payload)).digest('hex')]);
   await tx.query('SAVEPOINT command_effect');
   try {
    let result: Record<string, unknown>;
    if (m.type === 'reservation.hold.v1' || m.type === 'reservation.hold_and_pay.v1') {
     result = await this.hold(tx, m);
     if (m.type === 'reservation.hold_and_pay.v1') {
      await this.change(tx, {...m,type:'reservation.confirm.v1',payload:{reservationId:result.id,expectedAmount:result.amount,expectedVersion:result.version,sandboxResult:'approved'}});
     }
    }
    else result = await this.change(tx, m);
    await tx.query("UPDATE operations SET status='SUCCEEDED',result=$2,http_status=200 WHERE id=$1", [m.payload.commandId, result]);
   } catch (error) {
    await tx.query('ROLLBACK TO SAVEPOINT command_effect');
    const exclusion = (error as { code?: string }).code === '23P01';
    if (!(error instanceof DomainError) && !exclusion) throw error;
    await tx.query("UPDATE operations SET status='FAILED',result=$2,http_status=$3 WHERE id=$1", [m.payload.commandId, { message: exclusion ? 'Interval unavailable' : (error as Error).message }, exclusion ? 409 : (error as DomainError).status]);
   }
  });
 }
 private async hold(tx: Tx, m: Message) {
  const payload={...m.payload}; delete payload.commandId;
  const p = HoldSchema.parse(payload); assertInterval(p);
  await this.lock(tx, p.spaceId); await this.expireSpace(tx, p.spaceId, m);
  const snapshot = (await tx.query('SELECT * FROM space_snapshots WHERE id=$1', [p.spaceId])).rows[0];
  if (!snapshot || !snapshot.body.active || !allows(snapshot.body.windows, p)) throw new DomainError('Space is not available for this interval');
  if (snapshot.owner_id === m.actorId) throw new DomainError('Owners cannot book their own space', 403);
  const id = randomUUID(); const amount = quote(snapshot.body.hourlyRate, p);
  if ((p.expectedAmount!==undefined && p.expectedAmount!==amount)||(p.supplyRevision!==undefined&&p.supplyRevision!==snapshot.revision)) throw new DomainError('Quote changed; request a new confirmation');
  await tx.query(`INSERT INTO reservations(id,space_id,driver_id,owner_id,start_time,end_time,amount,hourly_rate,supply_revision,status,expires_at,code)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'PENDING_PAYMENT',now()+interval '10 minutes',$10)`, [id,p.spaceId,m.actorId,snapshot.owner_id,p.start,p.end,amount,snapshot.body.hourlyRate,snapshot.revision,randomUUID().slice(0,8).toUpperCase()]);
  await this.publishState(tx, id, 'reservation.held.v1', m);
  return (await tx.query('SELECT * FROM reservations WHERE id=$1', [id])).rows[0];
 }
 private async change(tx: Tx, m: Message) {
  const initial = (await tx.query('SELECT space_id FROM reservations WHERE id=$1', [m.payload.reservationId])).rows[0];
  if (!initial) throw new DomainError('Reservation not found', 404);
  await this.lock(tx, initial.space_id); await this.expireSpace(tx, initial.space_id, m);
  const row = (await tx.query('SELECT * FROM reservations WHERE id=$1 FOR UPDATE', [m.payload.reservationId])).rows[0];
  if (row.driver_id !== m.actorId) throw new DomainError('Reservation belongs to another driver', 403);
  if ((m.payload.expectedVersion!==undefined&&m.payload.expectedVersion!==row.version)||(m.payload.expectedAmount!==undefined&&m.payload.expectedAmount!==row.amount)) throw new DomainError('Reservation changed; review a new confirmation');
  if (m.type === 'reservation.confirm.v1') {
   if (row.status !== 'PENDING_PAYMENT') throw new DomainError('Hold is no longer payable');
   if (row.payment_attempt) return { reservationId: row.id, status: row.status };
   const attempt = randomUUID();
   await tx.query('UPDATE reservations SET payment_attempt=$2,version=version+1 WHERE id=$1', [row.id, attempt]);
   await enqueue(tx, 'payment.authorize.v1', { reservationId: row.id, attemptId: attempt, amount: row.amount, currency: 'PEN', driverId: row.driver_id, ownerId: row.owner_id, sandboxResult: m.payload.sandboxResult }, m.actorId, m.correlationId, EXCHANGE.COMMANDS);
   return { reservationId: row.id, status: 'PENDING_PAYMENT' };
  }
  if (row.status === 'CANCELLED') return { reservationId: row.id, status: row.status };
  if (!['PENDING_PAYMENT','CONFIRMED','ACTIVE'].includes(row.status)) throw new DomainError('Reservation cannot be cancelled');
  const refund = row.payment_id ? refundAmount(row.start_time, row.amount, process.env.LATE_CANCELLATION_FEE_BPS === undefined ? undefined : Number(process.env.LATE_CANCELLATION_FEE_BPS)) : 0;
  if (m.payload.expectedRefund!==undefined&&m.payload.expectedRefund!==refund) throw new DomainError('Cancellation terms changed; review a new confirmation');
  await tx.query("UPDATE reservations SET status='CANCELLED',version=version+1 WHERE id=$1", [row.id]);
  await this.publishState(tx, row.id, 'reservation.cancelled.v1', m);
  if (row.payment_id && refund) await enqueue(tx, 'payment.refund.v1', { paymentId: row.payment_id, reservationId: row.id, amount: refund, reason: 'cancellation' }, m.actorId, m.correlationId, EXCHANGE.COMMANDS);
  return { reservationId: row.id, status: 'CANCELLED', refundRequested: refund };
 }
 async supply(m: Message) {
  const { spaceId, ownerId, revision, ...data } = m.payload; const body = SpaceSchema.parse(data);
  await transaction(async tx => {
   if (!await inbox(tx, m.id)) return; await this.lock(tx, String(spaceId));
   const old = (await tx.query('SELECT revision FROM space_snapshots WHERE id=$1', [spaceId])).rows[0];
   if (old && old.revision >= Number(revision)) return;
   const bookings = await tx.query("SELECT start_time,end_time FROM reservations WHERE space_id=$1 AND status IN ('PENDING_PAYMENT','CONFIRMED','ACTIVE') AND end_time>now()", [spaceId]);
   const incompatible = body.active && bookings.rows.some(r => !allows(body.windows, { start: r.start_time.toISOString(), end: r.end_time.toISOString() }));
   if (incompatible) { await enqueue(tx, 'supply.revision-rejected.v1', { spaceId, revision, reason: 'Schedule would invalidate an existing reservation' }, m.actorId, m.correlationId); return; }
   await tx.query(`INSERT INTO space_snapshots(id,owner_id,revision,body) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO UPDATE SET revision=$3,body=$4`, [spaceId,ownerId,revision,body]);
   await enqueue(tx, 'supply.revision-accepted.v1', m.payload, m.actorId, m.correlationId);
  });
 }
 async payment(m: Message) {
  await transaction(async tx => {
   if (!await inbox(tx, m.id)) return;
   const first = (await tx.query('SELECT space_id FROM reservations WHERE id=$1', [m.payload.reservationId])).rows[0];
   if (!first) throw new Error('Unknown payment reservation');
   await this.lock(tx, first.space_id); await this.expireSpace(tx, first.space_id, m);
   const row = (await tx.query('SELECT * FROM reservations WHERE id=$1 FOR UPDATE', [m.payload.reservationId])).rows[0];
   if (m.payload.amount !== row.amount || m.payload.currency !== row.currency) throw new Error('Payment amount mismatch');
   if (m.type === 'payment.authorized.v1') {
    if (row.payment_id === m.payload.paymentId) return;
    if (canConfirm(row.status, row.expires_at, row.payment_attempt, String(m.payload.attemptId))) {
     await tx.query("UPDATE reservations SET status='CONFIRMED',payment_id=$2,version=version+1 WHERE id=$1", [row.id,m.payload.paymentId]);
     await this.publishState(tx,row.id,'reservation.confirmed.v1',m);
    } else await enqueue(tx,'payment.refund.v1',{ paymentId:m.payload.paymentId,reservationId:row.id,amount:row.amount,reason:'late_or_incompatible_authorization' },m.actorId,m.correlationId,EXCHANGE.COMMANDS);
   } else if (row.status === 'PENDING_PAYMENT' && row.payment_attempt === m.payload.attemptId) {
    await tx.query("UPDATE reservations SET payment_attempt=NULL,expires_at=LEAST(expires_at,now()+interval '5 minutes'),version=version+1 WHERE id=$1",[row.id]);
    await this.publishState(tx,row.id,'reservation.payment-failed.v1',m);
   }
  });
 }
 async tick() {
  const spaces = await pool.query("SELECT DISTINCT space_id FROM reservations WHERE (status='PENDING_PAYMENT' AND expires_at<=now()) OR (status IN ('CONFIRMED','ACTIVE') AND start_time<=now())");
  for (const row of spaces.rows) await transaction(async tx => {
   await this.lock(tx,row.space_id);
   const m: Message = { id:randomUUID(),version:1,type:'scheduler',actorId:'00000000-0000-4000-8000-000000000001',correlationId:randomUUID(),occurredAt:new Date().toISOString(),payload:{} };
   await this.expireSpace(tx,row.space_id,m);
   const changed = await tx.query("UPDATE reservations SET status=CASE WHEN end_time<=now() THEN 'COMPLETED' ELSE 'ACTIVE' END,version=version+1 WHERE space_id=$1 AND ((status='CONFIRMED' AND start_time<=now()) OR (status='ACTIVE' AND end_time<=now())) RETURNING id,status",[row.space_id]);
   for (const r of changed.rows) await this.publishState(tx,r.id,`reservation.${r.status.toLowerCase()}.v1`,m);
  });
 }
 async list(actor: Actor, owner = false) { return (await pool.query(`SELECT * FROM reservations WHERE ${owner ? 'owner_id' : 'driver_id'}=$1 ORDER BY start_time DESC LIMIT 500`,[actor.id])).rows; }
 async get(id: string, actor: Actor) { const row=(await pool.query('SELECT * FROM reservations WHERE id=$1',[id])).rows[0]; if (!row) throw new NotFoundException(); if (row.owner_id !== actor.id) owns(actor,row.driver_id); return row; }
 async availability(spaceId: string, interval: Interval) {
  const result=await pool.query("SELECT EXISTS(SELECT 1 FROM reservations WHERE space_id=$1 AND status IN ('PENDING_PAYMENT','CONFIRMED','ACTIVE') AND (status<>'PENDING_PAYMENT' OR expires_at>now()) AND tstzrange(start_time,end_time,'[)') && tstzrange($2::timestamptz,$3::timestamptz,'[)')) AS blocked",[spaceId,interval.start,interval.end]);
  const snapshot=(await pool.query('SELECT body FROM space_snapshots WHERE id=$1',[spaceId])).rows[0];
  return { available:!!snapshot && snapshot.body.active && allows(snapshot.body.windows,interval) && !result.rows[0].blocked, authoritativeAt:new Date().toISOString(), reservesNothing:true };
 }
}

import { randomUUID } from 'node:crypto';
import { pool,transaction,inbox,enqueue,owns,type Tx } from '@parklink/runtime';
import { type Message,type Actor } from '@parklink/contracts';
import { NotFoundException } from '@nestjs/common';
import type { PaymentGateway,PaymentOutcome,PaymentOrder } from '../domain/gateway';
import { MercadoPagoGateway,SandboxGateway } from '../infrastructure/providers';
export class Payments {
 readonly gateway:PaymentGateway;
 private working=false;
 constructor(){
  const provider=process.env.PAYMENT_PROVIDER??'sandbox';if(!['sandbox','mercadopago'].includes(provider))throw new Error('Unsupported payment provider');
  if(provider==='sandbox'&&process.env.NODE_ENV==='production')throw new Error('Sandbox cannot run in production');
  this.gateway=provider==='mercadopago'?new MercadoPagoGateway():new SandboxGateway();
 }
 async command(m:Message){
  await transaction(async tx=>{
   if(!await inbox(tx,m.id))return;const p=m.payload;
   if(m.type==='payment.authorize.v1'){
    await tx.query(`INSERT INTO payments(id,attempt_id,reservation_id,driver_id,owner_id,amount,currency,provider,scenario,correlation_id)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(attempt_id) DO NOTHING`,[randomUUID(),p.attemptId,p.reservationId,p.driverId,p.ownerId,p.amount,p.currency,this.gateway.name,p.sandboxResult??'approved',m.correlationId]);
   }else{
    const payment=(await tx.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[p.paymentId])).rows[0];
    if(!payment)throw new Error('Unknown payment');
    const key=`${p.paymentId}:${p.reason}`;
    const previous=(await tx.query('SELECT amount FROM refunds WHERE operation_key=$1',[key])).rows[0];
    if(previous){if(previous.amount!==p.amount)throw new Error('Refund payload mismatch');return;}
    const refunds=(await tx.query('SELECT COALESCE(sum(amount),0)::integer AS total FROM refunds WHERE payment_id=$1',[p.paymentId])).rows[0].total;
    if(payment.status!=='APPROVED'||!Number.isInteger(p.amount)||Number(p.amount)<=0||refunds+Number(p.amount)>payment.amount)throw new Error('Invalid refund');
    await tx.query('INSERT INTO refunds(id,payment_id,operation_key,amount) VALUES($1,$2,$3,$4)',[randomUUID(),p.paymentId,key,p.amount]);
   }
  });
 }
 private async outcome(tx:Tx,id:string,outcome:PaymentOutcome){
  const row=(await tx.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[id])).rows[0];
  if(!row||row.status!=='PENDING')return;
  if(outcome.checkoutUrl)await tx.query('UPDATE payments SET checkout_url=$2 WHERE id=$1',[id,outcome.checkoutUrl]);
  if(outcome.state==='PENDING')return;
  if(outcome.amount!==row.amount||outcome.currency!==row.currency)throw new Error('Provider amount/currency mismatch');
  await tx.query('UPDATE payments SET status=$2,reference=$3,updated_at=now() WHERE id=$1',[id,outcome.state,outcome.reference]);
  await enqueue(tx,outcome.state==='APPROVED'?'payment.authorized.v1':'payment.failed.v1',{paymentId:id,reservationId:row.reservation_id,attemptId:row.attempt_id,amount:row.amount,currency:row.currency,driverId:row.driver_id,ownerId:row.owner_id,provider:row.provider},row.driver_id,row.correlation_id);
 }
 async tick(){
  if(this.working)return;this.working=true;
  try{
   const jobs=await transaction(async tx=>(await tx.query(`UPDATE payments SET lease_until=now()+interval '20 seconds' WHERE id IN
    (SELECT id FROM payments WHERE status='PENDING' AND (lease_until IS NULL OR lease_until<now()) ORDER BY created_at LIMIT 10 FOR UPDATE SKIP LOCKED) RETURNING *`)).rows);
   for(const row of jobs){
    try{const order:PaymentOrder={id:row.id,amount:row.amount,currency:row.currency,scenario:row.scenario};const outcome=row.checkout_url?await this.gateway.reconcile(order):await this.gateway.prepare(order);await transaction(tx=>this.outcome(tx,row.id,outcome));}
    catch{console.error(JSON.stringify({event:'payment_reconciliation_pending',paymentId:row.id}));}
   }
   const refunds=await transaction(async tx=>(await tx.query(`UPDATE refunds SET lease_until=now()+interval '20 seconds' WHERE id IN
    (SELECT id FROM refunds WHERE status='PENDING' AND (lease_until IS NULL OR lease_until<now()) LIMIT 10 FOR UPDATE SKIP LOCKED) RETURNING *`)).rows);
   for(const refund of refunds){
    try{
     const p=(await pool.query('SELECT * FROM payments WHERE id=$1',[refund.payment_id])).rows[0];
     const reference=await this.gateway.refund(p.reference,refund.amount,refund.id);
     await transaction(async tx=>{
      const updated=await tx.query("UPDATE refunds SET status='PROCESSED',reference=$2 WHERE id=$1 AND status='PENDING' RETURNING id",[refund.id,reference]);if(!updated.rowCount)return;
      await tx.query('SELECT id FROM payments WHERE id=$1 FOR UPDATE',[p.id]);
      const total=(await tx.query("SELECT sum(amount)::integer AS total FROM refunds WHERE payment_id=$1 AND status='PROCESSED'",[p.id])).rows[0].total;
      if(total===p.amount)await tx.query("UPDATE payments SET status='REFUNDED',updated_at=now() WHERE id=$1",[p.id]);
      await enqueue(tx,'payment.refunded.v1',{paymentId:p.id,reservationId:p.reservation_id,driverId:p.driver_id,ownerId:p.owner_id,amount:refund.amount,currency:p.currency,refundId:refund.id,provider:p.provider},p.driver_id,p.correlation_id);
     });
    }catch{console.error(JSON.stringify({event:'refund_reconciliation_pending',refundId:refund.id}));}
   }
  }finally{this.working=false;}
 }
 async list(actor:Actor,owner=false){return (await pool.query(`SELECT p.id,p.reservation_id,p.amount,p.currency,p.status,p.provider,p.checkout_url,p.created_at,COALESCE((SELECT sum(amount) FROM refunds r WHERE r.payment_id=p.id AND r.status='PROCESSED'),0)::integer AS refunded_amount FROM payments p WHERE ${owner?'owner_id':'driver_id'}=$1 ORDER BY created_at DESC LIMIT 500`,[actor.id])).rows;}
 async get(id:string,actor:Actor){const row=(await pool.query('SELECT id,driver_id,amount,currency,status,provider,checkout_url FROM payments WHERE id=$1',[id])).rows[0];if(!row)throw new NotFoundException();owns(actor,row.driver_id);return row;}
}

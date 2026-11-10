import { createHmac,timingSafeEqual } from 'node:crypto';
import type { PaymentGateway,PaymentOrder,PaymentOutcome } from '../domain/gateway';
export class SandboxGateway implements PaymentGateway {
 readonly name='sandbox';
 async prepare(p:PaymentOrder):Promise<PaymentOutcome>{return {state:p.scenario==='rejected'?'REJECTED':'APPROVED',reference:`sandbox-${p.id}`,amount:p.amount,currency:p.currency};}
 reconcile(p:PaymentOrder){return this.prepare(p);}
 async refund(reference:string,_amount:number,key:string){return `sandbox-refund-${reference}-${key}`;}
}
export class MercadoPagoGateway implements PaymentGateway {
 readonly name='mercadopago';
 private async request(path:string,method='GET',body?:unknown,key?:string):Promise<Record<string,unknown>>{
  if(!process.env.MP_ACCESS_TOKEN)throw new Error('MP_ACCESS_TOKEN required');
  const response=await fetch(`https://api.mercadopago.com${path}`,{method,headers:{Authorization:`Bearer ${process.env.MP_ACCESS_TOKEN}`,'Content-Type':'application/json',...(key?{'X-Idempotency-Key':key}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(8000)});
  if(!response.ok)throw new Error(`Payment provider HTTP ${response.status}`);return response.json() as Promise<Record<string,unknown>>;
 }
 async prepare(p:PaymentOrder):Promise<PaymentOutcome>{
  const previous=await this.reconcile(p);if(previous.state!=='PENDING')return previous;
  const data=await this.request('/checkout/preferences','POST',{
   external_reference:p.id,items:[{id:p.id,title:'ParkLink parking reservation',quantity:1,currency_id:'PEN',unit_price:p.amount/100}],
   notification_url:process.env.MP_WEBHOOK_URL,expires:true,expiration_date_to:new Date(Date.now()+600000).toISOString()
  },p.id);
  const checkoutUrl=process.env.MP_TEST_MODE==='true'?data.sandbox_init_point:data.init_point;
  if(typeof checkoutUrl!=='string')throw new Error('Missing provider checkout URL');
  return {state:'PENDING',checkoutUrl};
 }
 async reconcile(p:PaymentOrder):Promise<PaymentOutcome>{
  const data=await this.request(`/v1/payments/search?external_reference=${encodeURIComponent(p.id)}&sort=date_created&criteria=desc`);
  const results=data.results as Array<Record<string,unknown>>|undefined;
  const approved=results?.find(r=>r.status==='approved'); const r=approved??results?.[0];
  if(!r)return {state:'PENDING'};
  return {state:r.status==='approved'?'APPROVED':r.status==='rejected'||r.status==='cancelled'?'REJECTED':'PENDING',reference:String(r.id),amount:Math.round(Number(r.transaction_amount)*100),currency:String(r.currency_id)};
 }
 async refund(reference:string,amount:number,key:string){const result=await this.request(`/v1/payments/${encodeURIComponent(reference)}/refunds`,'POST',{amount:amount/100},key);return String(result.id);}
}
export function verifyMercadoPago(signature:string,requestId:string,dataId:string,secret:string,now=Date.now()){
 const fields=Object.fromEntries(signature.split(',').map(p=>p.trim().split('=')));const ts=fields.ts, supplied=fields.v1;
 if(!ts||!supplied||!/^\d+$/.test(ts)||!requestId||!dataId)return false;
 const timestamp=Number(ts)*(ts.length<=10?1000:1);if(Math.abs(now-timestamp)>300000)return false;
 const expected=createHmac('sha256',secret).update(`id:${dataId.toLowerCase()};request-id:${requestId};ts:${ts};`).digest();
 const actual=Buffer.from(supplied,'hex');return actual.length===expected.length&&timingSafeEqual(actual,expected);
}

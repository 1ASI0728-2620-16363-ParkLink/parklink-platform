import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const base=process.env.TEST_API_URL??'http://localhost:3000';
interface Session{token:string;user:{id:string;roles:string[]}}
interface Operation{status:string;result:Record<string,unknown>;http_status:number;id:string}
async function api<T=Record<string,unknown>>(path:string,token?:string,method='GET',body?:unknown,key?:string,status?:number):Promise<T>{
 const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`} : {}),...(key?{'Idempotency-Key':key}: {})},body:body?JSON.stringify(body):undefined});
 const data=await r.json();if(status!==undefined)assert.equal(r.status,status,JSON.stringify(data));else assert.ok(r.ok,`${path}: ${r.status} ${JSON.stringify(data)}`);return data as T;
}
async function until<T>(fn:()=>Promise<T>,check:(v:T)=>boolean,timeout=20000):Promise<T>{const deadline=Date.now()+timeout;let value:T;do{value=await fn();if(check(value))return value;await new Promise(r=>setTimeout(r,500));}while(Date.now()<deadline);throw new Error(`Condition timed out: ${JSON.stringify(value)}`);}
async function command(kind:string,payload:unknown,session:Session,key=randomUUID()){
 const accepted=await api<{commandId:string}>(`/reservations/commands/${kind}`,session.token,'POST',payload,key,202);
 return until(()=>api<Operation>(`/operations/${accepted.commandId}`,session.token),r=>r.status!=='PENDING');
}
function sql(db:string,query:string){return execFileSync('docker',['compose','exec','-T',`${db}-db`,'psql','-U',db,'-d',db,'-At','-c',query],{encoding:'utf8'}).trim();}

test('real gateway, independent PostgreSQL stores and RabbitMQ saga', {timeout:180000}, async t=>{
 await api('/health',undefined,'GET',undefined,undefined,200);
 const password=`Test-${randomUUID()}-long`;
 const register=(owner=false)=>api<Session>('/auth/register',undefined,'POST',{name:owner?'Test Owner':'Test Driver',email:`${randomUUID()}@example.com`,password,owner},undefined,201);
 const owner=await register(true),driver=await register(),other=await register();
 const start=new Date(Date.now()+86400000).toISOString(),end=new Date(Date.now()+90000000).toISOString();
 const body={title:`Garage ${randomUUID().slice(0,8)}`,address:'Avenida Arequipa 123, Lima',description:'Integration fixture; not a real public listing',latitude:-12.0464,longitude:-77.0428,hourlyRate:750,widthCm:250,lengthCm:500,accessInstructions:'Call on arrival',features:['covered'],active:true,windows:[{start:new Date(Date.now()).toISOString(),end:new Date(Date.now()+7*86400000).toISOString()}]};
 let spaceId:string,reservationId:string;
 await t.test('authentication and RBAC reject unauthenticated users and publication by drivers',async()=>{
  await api('/spaces/mine',undefined,'GET',undefined,undefined,401);
  await api('/spaces',driver.token,'POST',body,undefined,403);
  await api('/auth/login',undefined,'POST',{email:`${randomUUID()}@example.com`,password},undefined,401);
 });
 await t.test('owner publishes; accepted supply revision reaches the PostGIS projection',async()=>{
  const space=await api<{id:string}>('/spaces',owner.token,'POST',body,undefined,201);spaceId=space.id;
  const results=await until(()=>api<{items:Array<{id:string}>}>('/discovery/search?latitude=-12.0464&longitude=-77.0428&radius=1000',driver.token),r=>r.items.some(s=>s.id===spaceId));
  assert.ok(results.items.some(s=>s.id===spaceId));
  await api(`/spaces/${spaceId}`,other.token,'PUT',{revision:1,space:body},undefined,403);
 });
 await t.test('two concurrent commands produce exactly one hold and one 409 result',async()=>{
  const payload={spaceId:spaceId!,start,end};
  const results=await Promise.all([command('hold',payload,driver),command('hold',payload,other)]);
  assert.equal(results.filter(r=>r.status==='SUCCEEDED').length,1);assert.equal(results.filter(r=>r.http_status===409).length,1);
  reservationId=String(results.find(r=>r.status==='SUCCEEDED')!.result.id);
  const winner=results[0]!.status==='SUCCEEDED'?driver:other;
  if(winner===other){const temp=driver.token;driver.token=other.token;other.token=temp;}
  assert.equal(sql('reservation',`SELECT count(*) FROM reservations WHERE space_id='${spaceId!}' AND status='PENDING_PAYMENT'`),'1');
  await api(`/reservations/${reservationId}`,other.token,'GET',undefined,undefined,403);
 });
 await t.test('sandbox payment confirms only through PaymentAuthorized; cancellation refunds asynchronously',async()=>{
  const result=await command('confirm',{reservationId:reservationId!,sandboxResult:'approved'},driver);assert.equal(result.status,'SUCCEEDED');
  const reservation=await until(()=>api(`/reservations/${reservationId!}`,driver.token),r=>r.status==='CONFIRMED');assert.ok(reservation.payment_id);
  const dashboard=await api('/owner/dashboard',owner.token);assert.ok(Number(dashboard.income)>=750);
  const cancelled=await command('cancel',{reservationId:reservationId!},driver);assert.equal(cancelled.result.status,'CANCELLED');
  const payments=await until(()=>api<Array<Record<string,unknown>>>('/payments/mine',driver.token),rows=>rows.some(p=>p.reservation_id===reservationId&&p.status==='REFUNDED'));
  assert.ok(payments.some(p=>p.status==='REFUNDED'));
 });
 await t.test('idempotency replays the same command and rejects a different payload',async()=>{
  const key=randomUUID(),payload={spaceId:spaceId!,start,end};
  const one=await api<{commandId:string}>('/reservations/commands/hold',driver.token,'POST',payload,key,202);
  const two=await api<{commandId:string}>('/reservations/commands/hold',driver.token,'POST',payload,key,202);assert.equal(one.commandId,two.commandId);
  await api('/reservations/commands/hold',driver.token,'POST',{...payload,end:new Date(Date.parse(end)+3600000).toISOString()},key,409);
  const result=await until(()=>api<Operation>(`/operations/${one.commandId}`,driver.token),r=>r.status!=='PENDING');reservationId=String(result.result.id);
 });
 await t.test('payment rejection permits a bounded retry; expiry releases the SQL exclusion',async()=>{
  await command('confirm',{reservationId:reservationId!,sandboxResult:'rejected'},driver);
  await until(()=>api<Array<Record<string,unknown>>>('/payments/mine',driver.token),rows=>rows.some(p=>p.reservation_id===reservationId&&p.status==='REJECTED'));
  sql('reservation',`UPDATE reservations SET expires_at=now()-interval '1 second' WHERE id='${reservationId!}'`);
  await until(()=>api(`/reservations/${reservationId!}`,driver.token),r=>r.status==='EXPIRED');
  const replacement=await command('hold',{spaceId:spaceId!,start,end},other);assert.equal(replacement.status,'SUCCEEDED');
  await command('cancel',{reservationId:replacement.result.id},other);
 });
 await t.test('monitoring tokens cannot issue operational commands; audit evidence is append-only',async()=>{
  const ownerEmail=sql('identity',`SELECT email FROM users WHERE id='${owner.user.id}'`);
  const monitor=await api<Session>('/auth/monitor-login',undefined,'POST',{email:ownerEmail,password},undefined,201);
  await api('/owner/dashboard',monitor.token);
  await api('/spaces',monitor.token,'POST',body,undefined,403);
  const n=Number(sql('audit','SELECT count(*) FROM audit_events'));assert.ok(n>0);
  assert.throws(()=>sql('audit',"DELETE FROM audit_events"));
  await api('/payments/webhook/mercadopago',undefined,'POST',{data:{id:'forged'}},undefined,401);
 });
});

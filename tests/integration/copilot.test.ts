import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base=process.env.TEST_API_URL??'http://localhost:3000';
interface Session{token:string}
interface Operation{status:string;http_status:number;result:Record<string,unknown>}
async function api<T=Record<string,unknown>>(path:string,session?:Session,method='GET',body?:unknown,status?:number):Promise<T>{
 const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(session?{Authorization:`Bearer ${session.token}`}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(55000)});
 const data=await r.json();if(status!==undefined)assert.equal(r.status,status,JSON.stringify(data));else assert.ok(r.ok,`${path}: ${r.status}`);return data as T;
}
async function until<T>(fn:()=>Promise<T>,check:(r:T)=>boolean){for(let i=0;i<60;i++){const r=await fn();if(check(r))return r;await new Promise(resolve=>setTimeout(resolve,300));}throw new Error('Timed out');}
test('Copilot proposal, consent, ownership and compensation use real services',{timeout:150000},async t=>{
 const account=(owner=false)=>api<Session>('/auth/register',undefined,'POST',{name:'Copilot Integration',email:`${randomUUID()}@example.com`,password:`Test-${randomUUID()}`,owner},201);
 const owner=await account(true),driver=await account(),other=await account();
 const now=Date.now(),start=new Date(now+3*86400000).toISOString(),end=new Date(now+3*86400000+3600000).toISOString();
 const body={title:`Copilot ${randomUUID().slice(0,8)}`,address:'Lima integration fixture',description:'Fictitious integration data',latitude:-12.0464,longitude:-77.0428,hourlyRate:750,widthCm:250,lengthCm:500,accessInstructions:'Development test',features:[],active:true,windows:[{start:new Date().toISOString(),end:new Date(Date.now()+7*86400000).toISOString()}]};
 const space=await api<{id:string}>('/spaces',owner,'POST',body);
 await until(()=>api<Array<Record<string,unknown>>>('/spaces/mine',owner),rows=>rows.some(r=>r.id===space.id&&r.state==='PUBLISHED'));
 let reservationId:string;
 await t.test('real OpenCode daemon is isolated and discovery ranks by price',async()=>{
  const status=await api('/copilot/status',driver);assert.equal(status.configuredEngine,'opencode');assert.equal(status.runtimeReady,true);
  const search=await api<{items:Array<{body:{hourlyRate:number}}>}>('/copilot/search',driver,'POST',{text:'',latitude:-12.0464,longitude:-77.0428,sort:'cheapest'});
  const rates=search.items.map(i=>i.body.hourlyRate);assert.deepEqual(rates,[...rates].sort((a,b)=>a-b));
 });
 await t.test('proposal alone creates no reservation; another user cannot confirm',async()=>{
  const before=await api<unknown[]>('/reservations/mine',driver);
  const proposal=await api<{confirmationId:string;summary:{amount:number}}>('/copilot/propose-hold',driver,'POST',{spaceId:space.id,start,end});
  assert.equal(proposal.summary.amount,750);assert.equal((await api<unknown[]>('/reservations/mine',driver)).length,before.length);
  await api(`/copilot/confirm/${proposal.confirmationId}`,other,'POST',undefined,404);
  const accepted=await api<{commandId:string}>(`/copilot/confirm/${proposal.confirmationId}`,driver,'POST',undefined,202);
  const replay=await api<{commandId:string}>(`/copilot/confirm/${proposal.confirmationId}`,driver,'POST',undefined,202);assert.equal(accepted.commandId,replay.commandId);
  const operation=await until(()=>api<Operation>(`/copilot/commands/${accepted.commandId}`,driver),r=>r.status!=='PENDING');assert.equal(operation.status,'SUCCEEDED');reservationId=String(operation.result.id);
  assert.equal((await api(`/reservations/${reservationId}`,driver)).status,'PENDING_PAYMENT');
 });
 await t.test('pay/cancel proposals require consent and reject client-supplied amounts',async()=>{
  await api('/copilot/propose-action',other,'POST',{action:'pay',reservationId:reservationId!},403);
  await api('/copilot/propose-action',driver,'POST',{action:'pay',reservationId:reservationId!,amount:1},400);
  const pay=await api<{confirmationId:string}>('/copilot/propose-action',driver,'POST',{action:'pay',reservationId:reservationId!});
  assert.equal((await api(`/reservations/${reservationId!}`,driver)).payment_attempt,null);
  await api(`/copilot/confirm/${pay.confirmationId}`,driver,'POST',undefined,202);
  await until(()=>api(`/reservations/${reservationId!}`,driver),r=>r.status==='CONFIRMED');
  const cancel=await api<{confirmationId:string;summary:{refundAmount:number}}>('/copilot/propose-action',driver,'POST',{action:'cancel',reservationId:reservationId!});assert.equal(cancel.summary.refundAmount,750);
  assert.equal((await api(`/reservations/${reservationId!}`,driver)).status,'CONFIRMED');
  await api(`/copilot/confirm/${cancel.confirmationId}`,driver,'POST',undefined,202);
  await until(()=>api(`/reservations/${reservationId!}`,driver),r=>r.status==='CANCELLED');
  await until(()=>api<Array<Record<string,unknown>>>('/payments/mine',driver),rows=>rows.some(p=>p.reservation_id===reservationId&&p.status==='REFUNDED'));
 });
 await t.test('an offer price change invalidates an earlier human confirmation',async()=>{
  const proposal=await api<{confirmationId:string}>('/copilot/propose-hold',driver,'POST',{spaceId:space.id,start,end});
  await api(`/spaces/${space.id}`,owner,'PUT',{revision:1,space:{...body,hourlyRate:900}});
  await until(()=>api<Array<Record<string,unknown>>>('/spaces/mine',owner),rows=>rows.some(r=>r.id===space.id&&r.accepted_revision===2));
  await api(`/copilot/confirm/${proposal.confirmationId}`,driver,'POST',undefined,202);
  const operation=await until(()=>api<Operation>(`/copilot/commands/${proposal.confirmationId}`,driver),r=>r.status!=='PENDING');assert.equal(operation.status,'FAILED');assert.equal(operation.http_status,409);
 });
  await t.test('chat request replay is idempotent and cross-user access is rejected',async()=>{
  const body={requestId:randomUUID(),message:'Muéstrame mis reservas',latitude:-12.0464,longitude:-77.0428};
  const response=await api<{conversationId:string;engine:string;reservations:unknown[]}>('/copilot/chat',driver,'POST',body);
   assert.equal(response.engine,'opencode');assert.ok(response.reservations.length>0);
  const replay=await api('/copilot/chat',driver,'POST',body);assert.deepEqual(replay,response);
  await api('/copilot/chat',other,'POST',{...body,requestId:randomUUID(),conversationId:response.conversationId},404);
   await api('/copilot/chat',driver,'POST',{...body,requestId:randomUUID(),action:'approve_payment'},400);
  });
  await t.test('chat reservation requires one consent and then initiates payment once',async()=>{
   const begin=new Date(Date.now()+4*86400000).toISOString(),finish=new Date(Date.now()+4*86400000+3600000).toISOString();
   const before=await api<unknown[]>('/reservations/mine',driver);
   const response=await api<{engine:string;proposal:{confirmationId:string;summary:{action:string}}}>('/copilot/chat',driver,'POST',{requestId:randomUUID(),message:'Reserva el estacionamiento más barato',latitude:-12.0464,longitude:-77.0428,start:begin,end:finish});
   assert.equal(response.engine,'opencode');assert.equal(response.proposal.summary.action,'hold_and_pay');
   assert.equal((await api<unknown[]>('/reservations/mine',driver)).length,before.length);
   const id=response.proposal.confirmationId;
   await api(`/copilot/confirm/${id}`,other,'POST',undefined,404);
   await api(`/copilot/confirm/${id}`,driver,'POST',undefined,202);
   await api(`/copilot/confirm/${id}`,driver,'POST',undefined,202);
   const operation=await until(()=>api<Operation>(`/copilot/commands/${id}`,driver),r=>r.status!=='PENDING');
   assert.equal(operation.status,'SUCCEEDED');const bookedId=String(operation.result.id);
   await until(()=>api(`/reservations/${bookedId}`,driver),r=>r.status==='CONFIRMED');
   const payments=await until(()=>api<Array<Record<string,unknown>>>('/payments/mine',driver),rows=>rows.some(p=>p.reservation_id===bookedId));
   assert.equal(payments.filter(p=>p.reservation_id===bookedId).length,1);
  });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID,createHmac } from 'node:crypto';
import { assertInterval,allows,quote,canConfirm,refundAmount } from '../services/reservation-service/src/domain/reservation';
import { validWindows } from '../services/parking-supply-service/src/domain/schedule';
import { hashPassword,verifyPassword } from '../services/identity-service/src/domain/password';
import { verifyMercadoPago,SandboxGateway } from '../services/payment-service/src/infrastructure/providers';
import { HoldSchema,MessageSchema,RegistrationSchema,SpaceSchema } from '../packages/shared-contracts/src';
const now=Date.now(),start=new Date(now+7200000).toISOString(),end=new Date(now+10800000).toISOString();
test('publication photos are optional and must be HTTPS; existing publications remain valid',()=>{
 const space={title:'Registered parking',address:'Registered street 123',description:'',latitude:-12,longitude:-77,hourlyRate:750,widthCm:250,lengthCm:500,accessInstructions:'Use the main entrance',features:[],windows:[{start,end}],active:true};
 assert.equal(SpaceSchema.safeParse(space).success,true);
 assert.equal(SpaceSchema.safeParse({...space,photoUrl:'https://photos.example.org/parking.jpg'}).success,true);
 for(const photoUrl of ['http://photos.example.org/parking.jpg','file:///private/photo.jpg','javascript:alert(1)','invalid'])assert.equal(SpaceSchema.safeParse({...space,photoUrl}).success,false);
});
test('future valid intervals; reject reversed, past and invalid intervals',()=>{
 assert.doesNotThrow(()=>assertInterval({start,end}));
 for(const interval of [{start:end,end:start},{start:'invalid',end},{start:new Date(0).toISOString(),end}])assert.throws(()=>assertInterval(interval));
});
test('quote uses integer centimos and rounds fractional hours upward',()=>{
 assert.equal(quote(750,{start,end}),750);
 assert.equal(quote(751,{start,end:new Date(Date.parse(start)+1800000).toISOString()}),376);
});
test('availability windows must contain the entire requested interval',()=>{
 assert.equal(allows([{start,end}],{start,end}),true);
 assert.equal(allows([{start,end}],{start,end:new Date(Date.parse(end)+1).toISOString()}),false);
 assert.equal(validWindows([{start,end},{start:end,end:new Date(Date.parse(end)+3600000).toISOString()}]),true);
 assert.equal(validWindows([{start,end},{start,end}]),false);
});
test('late or cancelled holds never become confirmed; payment attempts must match',()=>{
 const attempt=randomUUID();
 assert.equal(canConfirm('PENDING_PAYMENT',new Date(Date.now()+10000),attempt,attempt),true);
 assert.equal(canConfirm('PENDING_PAYMENT',new Date(0),attempt,attempt),false);
 assert.equal(canConfirm('CANCELLED',new Date(Date.now()+10000),attempt,attempt),false);
 assert.equal(canConfirm('PENDING_PAYMENT',new Date(Date.now()+10000),attempt,randomUUID()),false);
});
test('free cancellation includes exactly sixty minutes; no invented late fee',()=>{
 const now=Date.now();
 assert.equal(refundAmount(new Date(now+3600000),1000,undefined,now),1000);
 assert.throws(()=>refundAmount(new Date(now+3599999),1000,undefined,now));
 assert.equal(refundAmount(new Date(now),1000,2500,now),750);
 assert.throws(()=>refundAmount(new Date(now),1000,10001,now));
});
test('scrypt hashes have independent salts and verify without plain text storage',async()=>{
 const a=await hashPassword('a long passphrase'),b=await hashPassword('a long passphrase');assert.notEqual(a,b);
 assert.equal(await verifyPassword('a long passphrase',a),true);assert.equal(await verifyPassword('incorrect',a),false);
});
test('contracts reject unknown fields, missing versions and role escalation',()=>{
 assert.equal(HoldSchema.safeParse({spaceId:randomUUID(),start,end}).success,true);
 assert.equal(HoldSchema.safeParse({spaceId:randomUUID(),start,end,amount:1}).success,false);
 assert.equal(MessageSchema.safeParse({id:randomUUID(),type:'reserved'}).success,false);
 assert.equal(RegistrationSchema.safeParse({email:'u@example.com',password:'long-enough-password',name:'User',roles:['SUPPORT']}).success,false);
});
test('provider webhook verifies HMAC, request binding and freshness',()=>{
 const now=Date.now(),ts=String(Math.floor(now/1000)),id='123',request='request-id',secret='test-webhook-secret';
 const digest=createHmac('sha256',secret).update(`id:${id};request-id:${request};ts:${ts};`).digest('hex');
 const signature=`ts=${ts},v1=${digest}`;
 assert.equal(verifyMercadoPago(signature,request,id,secret,now),true);
 assert.equal(verifyMercadoPago(signature,'forged',id,secret,now),false);
 assert.equal(verifyMercadoPago(signature,request,id,secret,now+3600000),false);
});
test('sandbox is deterministic, visibly named and never calls a provider',async()=>{
 const gateway=new SandboxGateway(),order={id:randomUUID(),amount:1000,currency:'PEN',scenario:'approved'};
 assert.equal(gateway.name,'sandbox');assert.deepEqual(await gateway.prepare(order),await gateway.reconcile(order));
 assert.equal((await gateway.prepare({...order,scenario:'rejected'})).state,'REJECTED');
});

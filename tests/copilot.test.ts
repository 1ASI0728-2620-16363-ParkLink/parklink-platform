import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {randomUUID} from 'node:crypto';
import {IntentSchema,ChatInputSchema} from '../services/conversational-agent-service/src/domain/intent';
import {OpenCodeIntentProvider} from '../services/conversational-agent-service/src/infrastructure/opencode';

test('intent schema rejects computer tools and client-provided financial outcomes',()=>{
 assert.equal(IntentSchema.safeParse({action:'bash',command:'delete files'}).success,false);
 const p={action:'search',sort:'cheapest',text:'',start:null,end:null,reservationId:null,maxRate:null,reply:'Buscaré opciones.'};
 assert.equal(IntentSchema.safeParse({...p,paymentApproved:true}).success,false);
 assert.equal(ChatInputSchema.safeParse({requestId:randomUUID(),message:'Busca',latitude:100,longitude:0}).success,false);
});
test('OpenCode tries another verified free model when the first fails',async()=>{
 const previous={url:process.env.OPENCODE_URL,password:process.env.OPENCODE_SERVER_PASSWORD,enabled:process.env.OPENCODE_INFERENCE_ENABLED};
 const prompted:string[]=[],deleted:string[]=[];let sessions=0;
 const output={action:'search',sort:'nearest',text:'',start:null,end:null,reservationId:null,maxRate:null,reply:'Buscaré espacios.'};
 const free={cost:{input:0,output:0,cache:{read:0,write:0}}};
 const server=createServer(async(req,res)=>{
  let raw='';for await(const part of req)raw+=part;res.setHeader('content-type','application/json');
  if(req.url==='/provider'){res.end(JSON.stringify({all:[{id:'opencode',models:{'glm-5.3-flash-free':free,'deepseek-v4.1-flash-free':free,'mimo-v2.6-flash-free':{cost:{input:1,output:0,cache:{read:0,write:0}}}}}],connected:['opencode'],default:{opencode:'mimo-v2.6-flash-free'}}));return;}
  if(req.url==='/session'&&req.method==='POST'){res.end(JSON.stringify({id:`ses_${++sessions}`}));return;}
  if(req.url?.endsWith('/message')){const body=JSON.parse(raw);prompted.push(body.model.modelID);assert.equal(body.format.retryCount,0);res.end(JSON.stringify({info:prompted.length===1?{error:{name:'failed'}}:{structured:output},parts:[]}));return;}
  if(req.method==='DELETE')deleted.push(req.url!);res.end('true');
 });
 await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));const address=server.address();assert.ok(address&&typeof address!=='string');
 process.env.OPENCODE_URL=`http://127.0.0.1:${address.port}`;process.env.OPENCODE_SERVER_PASSWORD='isolated-test-secret';process.env.OPENCODE_INFERENCE_ENABLED='true';
 try{assert.deepEqual(await new OpenCodeIntentProvider().interpret('Busca',{now:new Date().toISOString(),history:[]}),output);assert.deepEqual(prompted,['glm-5.3-flash-free','deepseek-v4.1-flash-free']);assert.equal(deleted.length,2);}
 finally{for(const[key,value]of Object.entries({OPENCODE_URL:previous.url,OPENCODE_SERVER_PASSWORD:previous.password,OPENCODE_INFERENCE_ENABLED:previous.enabled})){if(value===undefined)delete process.env[key];else process.env[key]=value;}await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
test('OpenCode SDK uses isolated session, personality, tool denial and session cleanup',async()=>{
 const previous={url:process.env.OPENCODE_URL,password:process.env.OPENCODE_SERVER_PASSWORD,enabled:process.env.OPENCODE_INFERENCE_ENABLED};
 let created=0,prompted=0,deleted=0,paid=false;
 const output={action:'search',sort:'cheapest',text:'',start:null,end:null,reservationId:null,maxRate:null,reply:'Buscaré opciones económicas.'};
 const server=createServer(async(req,res)=>{
  assert.equal(req.headers.authorization,`Basic ${Buffer.from('opencode:isolated-test-secret').toString('base64')}`);
  let raw='';for await(const part of req)raw+=part;
  res.setHeader('content-type','application/json');
  if(req.url==='/provider'){res.end(JSON.stringify({all:[{id:'opencode',models:{'free-default':{cost:{input:paid?1:0,output:0,cache:{read:0,write:0}}}}}],connected:['opencode'],default:{opencode:'free-default'}}));return;}
  if(req.url==='/session'&&req.method==='POST'){
   created++;const body=JSON.parse(raw);assert.deepEqual(body.permission[0],{permission:'*',pattern:'*',action:'deny'});res.end(JSON.stringify({id:'ses_test'}));return;
  }
  if(req.url==='/session/ses_test/message'){
   prompted++;const body=JSON.parse(raw);assert.match(body.system,/ParkLink Copilot/);assert.match(body.system,/human confirmation/);assert.equal(body.tools.bash,false);assert.equal(body.tools.task,false);assert.equal(body.tools.read,false);assert.equal(body.format.type,'json_schema');res.end(JSON.stringify({info:{structured:output},parts:[]}));return;
  }
  if(req.method==='DELETE')deleted++;
  res.end('true');
 });
 await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
 const address=server.address();assert.ok(address&&typeof address!=='string');
 process.env.OPENCODE_URL=`http://127.0.0.1:${address.port}`;process.env.OPENCODE_SERVER_PASSWORD='isolated-test-secret';process.env.OPENCODE_INFERENCE_ENABLED='true';
 try{
  const provider=new OpenCodeIntentProvider();assert.deepEqual(await provider.interpret('Busca el más barato',{now:new Date().toISOString(),history:[]}),output);
  assert.equal(created,1);assert.equal(prompted,1);assert.equal(deleted,1);
  paid=true;await assert.rejects(()=>provider.interpret('Busca',{now:new Date().toISOString(),history:[]}),/zero-cost/);
  assert.equal(prompted,1,'A paid model must never receive a prompt');
 }finally{
  for(const[key,value]of Object.entries({OPENCODE_URL:previous.url,OPENCODE_SERVER_PASSWORD:previous.password,OPENCODE_INFERENCE_ENABLED:previous.enabled})){if(value===undefined)delete process.env[key];else process.env[key]=value;}
  await new Promise<void>(resolve=>server.close(()=>resolve()));
 }
});

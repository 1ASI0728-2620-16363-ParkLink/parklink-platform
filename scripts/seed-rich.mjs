import {randomUUID,randomBytes} from 'node:crypto';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
const base=process.env.PARKLINK_API_URL??'http://localhost:3000';
if(!['localhost','127.0.0.1'].includes(new URL(base).hostname)||process.env.NODE_ENV==='production')throw new Error('Rich fixtures are restricted to local development.');
const directory=new URL('../.local/',import.meta.url),file=new URL('demo-accounts.json',directory);
await mkdir(directory,{recursive:true,mode:0o700});
let state;
try{state=JSON.parse(await readFile(file,'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;}
const password=label=>`ParkLink-${label}-${randomBytes(5).toString('hex')}!`;
if(!state){
 state={version:1,createdAt:new Date().toISOString(),users:[
  {email:'cliente@parklink.test',name:'Cliente Demo',password:password('Cliente'),owner:false},
  ...['Lucía','Mateo','Valentina','Diego','Camila','Sebastián'].map((name,i)=>({email:`propietario${i+1}@parklink.test`,name:`${name} · Propietario Demo`,password:password('Owner'),owner:true})),
  ...['Sofía','Nicolás','Isabella','Gabriel','Mariana','Adrián','Renata','Emilio'].map((name,i)=>({email:`conductor${i+1}@parklink.test`,name:`${name} · Demo`,password:password('Driver'),owner:false}))
 ],spaces:[],bookings:[],history:[]};
 await persist();
}
async function persist(){await writeFile(file,JSON.stringify(state,null,2)+'\n',{mode:0o600});}
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function api(path,session,method='GET',body,key){
 for(let attempt=0;attempt<4;attempt++){
  const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(session?{Authorization:`Bearer ${session.token}`} : {}),...(key?{'Idempotency-Key':key}: {})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(15000)});
  if(r.status===429){await wait(15000);continue;}const data=await r.json();if(!r.ok)throw Object.assign(new Error(`Seed ${path}: HTTP ${r.status}`),{status:r.status});return data;
 }throw new Error('Seed rate limit exceeded; rerun safely after a minute.');
}
const sessions=[];
for(const user of state.users){
 let session;try{session=await api('/auth/login',null,'POST',{email:user.email,password:user.password});}
 catch(error){if(error.status!==401)throw error;session=await api('/auth/register',null,'POST',{name:user.name,email:user.email,password:user.password,owner:user.owner});}
 user.id=session.user.id;sessions.push(session);
}
await persist();
const zones=[
 {name:'Centro de Lima',lat:-12.0464,lon:-77.0428,street:'Av. Nicolás de Piérola'},
 {name:'Miraflores',lat:-12.1211,lon:-77.0297,street:'Av. José Larco'},
 {name:'San Isidro',lat:-12.0975,lon:-77.0361,street:'Av. Javier Prado Oeste'},
 {name:'Barranco',lat:-12.1492,lon:-77.0217,street:'Av. San Martín'},
 {name:'Santiago de Surco',lat:-12.1106,lon:-76.9902,street:'Av. Caminos del Inca'},
 {name:'San Miguel',lat:-12.0763,lon:-77.0863,street:'Av. La Marina'},
 {name:'Jesús María',lat:-12.0740,lon:-77.0430,street:'Av. Brasil'},
 {name:'Pueblo Libre',lat:-12.0700,lon:-77.0630,street:'Av. Bolívar'},
 {name:'Magdalena del Mar',lat:-12.0920,lon:-77.0690,street:'Av. Brasil'},
 {name:'Lince',lat:-12.0840,lon:-77.0300,street:'Av. Arenales'},
 {name:'Breña',lat:-12.0590,lon:-77.0540,street:'Av. Arica'},
 {name:'La Victoria',lat:-12.0690,lon:-77.0190,street:'Av. México'},
 {name:'San Borja',lat:-12.1010,lon:-77.0010,street:'Av. San Luis'},
 {name:'Surquillo',lat:-12.1170,lon:-77.0080,street:'Av. República de Panamá'},
 {name:'La Molina',lat:-12.0810,lon:-76.9400,street:'Av. La Molina'},
 {name:'Chorrillos',lat:-12.1780,lon:-77.0200,street:'Av. Defensores del Morro'},
 {name:'Los Olivos',lat:-11.9900,lon:-77.0700,street:'Av. Alfredo Mendiola'},
 {name:'San Juan de Lurigancho',lat:-12.0000,lon:-77.0040,street:'Av. Próceres de la Independencia'}
];
const epoch=Date.parse(state.createdAt),rates=[300,450,600,750,900,1100,500,650,800,1200];
for(let i=0;i<zones.length*10;i++){
 if(state.spaces[i]?.id)continue;
 const zone=zones[Math.floor(i/10)],ownerIndex=1+Math.floor(i/10)%6,slot=i%10;
 const body={title:`[DEMO ${String(i+1).padStart(2,'0')}] ${['Cochera privada','Plaza techada','Espacio residencial','Estacionamiento con vigilancia','Plaza de fácil acceso'][i%5]} · ${zone.name}`,
  address:`${zone.street} ${100+slot*30}, ${zone.name}, Lima · Datos ficticios`,
  description:'Publicación de prueba de ParkLink. No corresponde a una oferta comercial real. Las coordenadas, precios y condiciones son ficticios.',
  latitude:zone.lat+(slot%5-2)*0.0012,longitude:zone.lon+(Math.floor(slot/5)-0.5)*0.003,
  hourlyRate:rates[slot],widthCm:240+(slot%3)*20,lengthCm:480+(slot%4)*20,
  accessInstructions:`Prueba: acceso ${slot%2?'con portón':'directo'}. Contactar al anfitrión al llegar.`,
  features:[...(slot%2===0?['covered']:[]),...(slot%3===0?['security']:[]),...(slot%4===0?['ev']:[]),...(slot%5===0?['accessible']:[])],
  active:slot!==9,windows:[{start:new Date(epoch-120*86400000).toISOString(),end:new Date(epoch+120*86400000).toISOString()}]};
 const result=await api('/spaces',sessions[ownerIndex],'POST',body);
 state.spaces[i]={id:result.id,ownerIndex,body};await persist();
}
for(const session of sessions.slice(1,7)){
 for(let tries=0;tries<60;tries++){
  const spaces=await api('/spaces/mine',session);if(spaces.every(s=>s.state==='PUBLISHED'))break;
  if(tries===59)throw new Error('Offer acceptance is still pending; check RabbitMQ.');await wait(500);
 }
}
if(!state.history.length){
 const drivers=[0,7,8,9,10,11,12,13,14];
 for(let i=0;i<100;i++){
  const space=state.spaces[(i%54)+(Math.floor((i%54)/9))];
  const active=i>=90&&i<95,expired=i>=95;
  const start=active?epoch-1800000:epoch-(6+i*12)*3600000,end=active?epoch+7200000:start+(1+i%3)*3600000;
  const driver=state.users[drivers[i%drivers.length]],id=randomUUID(),paymentId=expired?null:randomUUID();
  state.history.push({id,spaceId:space.id,ownerId:state.users[space.ownerIndex].id,driverId:driver.id,
   start:new Date(start).toISOString(),end:new Date(end).toISOString(),amount:Math.ceil(space.body.hourlyRate*(end-start)/3600000),hourlyRate:space.body.hourlyRate,
   status:expired?'EXPIRED':active?'ACTIVE':'COMPLETED',paymentId,attemptId:paymentId?randomUUID():null,code:`DEMO-${randomUUID().slice(0,8).toUpperCase()}`,createdAt:new Date(start-7200000).toISOString(),correlationId:randomUUID()});
 }
 await persist();
}
for(const [service,script] of [['reservation-service','../services/reservation-service/scripts/seed-history.mjs'],['payment-service','../services/payment-service/scripts/seed-history.mjs']]){
 const code=await readFile(new URL(script,import.meta.url),'utf8');
 const report=execFileSync('docker',['compose','exec','-T','-e','ALLOW_FIXTURE_SEED=true',service,'node','--input-type=module','-e',code],{input:JSON.stringify(state.history),encoding:'utf8',maxBuffer:1024*1024});
 console.log(report.trim());
}
async function command(kind,payload,session,key){
 const accepted=await api(`/reservations/commands/${kind}`,session,'POST',payload,key);
 for(let tries=0;tries<60;tries++){const result=await api(`/operations/${accepted.commandId}`,session);if(result.status==='FAILED')throw new Error(`Fixture command ${kind} failed: ${result.result.message}`);if(result.status==='SUCCEEDED')return result.result;await wait(250);}
 throw new Error(`Fixture command ${kind} pending; rerun with the same persisted keys.`);
}
for(let i=0;i<36;i++){
 if(state.bookings[i]?.done)continue;
 const space=state.spaces[(i%54)+Math.floor((i%54)/9)],driverIndex=[0,7,8,9,10,11,12,13,14][i%9],session=sessions[driverIndex];
 if(!state.bookings[i]){const start=epoch+(24+Math.floor(i/12)*24+i%4*3)*3600000;state.bookings[i]={key:randomUUID(),spaceId:space.id,driverIndex,start:new Date(start).toISOString(),end:new Date(start+(1+i%3)*3600000).toISOString()};await persist();}
 const fixture=state.bookings[i];
 if(!fixture.reservationId){const held=await command('hold',{spaceId:fixture.spaceId,start:fixture.start,end:fixture.end},session,fixture.key);fixture.reservationId=held.id;await persist();}
 const scenario=i%8===6?'rejected':'approved';
 if(i%8!==7){await command('confirm',{reservationId:fixture.reservationId,sandboxResult:scenario},session,`${fixture.key}-pay`);
  for(let tries=0;tries<60;tries++){const r=await api(`/reservations/${fixture.reservationId}`,session);if(r.status==='CONFIRMED'||(scenario==='rejected'&&r.payment_attempt===null))break;await wait(250);}
 }
 if(i%8===5)await command('cancel',{reservationId:fixture.reservationId},session,`${fixture.key}-cancel`);
 fixture.done=true;await persist();
}
const verify=await api('/auth/login',null,'POST',{email:state.users[0].email,password:state.users[0].password});
const mine=await api('/reservations/mine',verify),payments=await api('/payments/mine',verify);
console.log(JSON.stringify({users:state.users.length,spaces:state.spaces.length,historicalReservations:state.history.length,workflowReservations:state.bookings.length,clientEmail:state.users[0].email,clientReservations:mine.length,clientPayments:payments.length,credentialsFile:'.local/demo-accounts.json',allPayments:'sandbox only',loginVerified:true},null,2));

import {randomUUID} from 'node:crypto';
const base=process.env.PARKLINK_API_URL??'http://localhost:3000';
const password=process.env.SEED_PASSWORD;
if(!password||password.length<12)throw new Error('Set SEED_PASSWORD (at least 12 characters). No default account passwords are shipped.');
async function request(path,body,token){const response=await fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});if(!response.ok)throw new Error(`Seed request ${path}: ${response.status}`);return response.json();}
const suffix=randomUUID().slice(0,8);
const owner=await request('/auth/register',{name:'Development Owner',email:`owner-${suffix}@parklink.local`,password,owner:true});
const driver=await request('/auth/register',{name:'Development Driver',email:`driver-${suffix}@parklink.local`,password,owner:false});
await request('/spaces',{title:'Development parking space',address:'Avenida Arequipa, Lima (development fixture)',description:'Development fixture, not a real parking listing',latitude:-12.0464,longitude:-77.0428,hourlyRate:750,widthCm:250,lengthCm:500,accessInstructions:'Development fixture',features:['covered'],active:true,windows:[{start:new Date().toISOString(),end:new Date(Date.now()+30*86400000).toISOString()}]},owner.token);
console.log(JSON.stringify({owner:owner.user.email,driver:driver.user.email,note:'Use the SEED_PASSWORD you supplied. No tokens or passwords are printed.'}));

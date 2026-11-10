import {z} from '@parklink/contracts';
import {IntentSchema,type IntentProvider,type IntentContext} from '../domain/intent';
import {COPILOT_PERSONALITY} from '../domain/personality';

export class OpenCodeIntentProvider implements IntentProvider{
 readonly name='opencode';
 private async client(){
  const baseUrl=process.env.OPENCODE_URL;
  if(!baseUrl||!process.env.OPENCODE_SERVER_PASSWORD)throw new Error('Isolated OpenCode runtime is not configured');
  const {createOpencodeClient}=await import('@opencode-ai/sdk/v2');
  return createOpencodeClient({baseUrl,headers:{Authorization:`Basic ${Buffer.from(`opencode:${process.env.OPENCODE_SERVER_PASSWORD}`).toString('base64')}`}});
 }
 async health(){const result=await (await this.client()).global.health({signal:AbortSignal.timeout(3000)});return !!result.data?.healthy;}
 async interpret(text:string,context:IntentContext){
  if(process.env.OPENCODE_INFERENCE_ENABLED!=='true')throw new Error('OpenCode model inference has not been enabled');
  const client=await this.client();
  const available=await client.provider.list({},{throwOnError:true,signal:AbortSignal.timeout(5000)});
  const provider=available.data.all.find(p=>p.id==='opencode');
  const preferred=['glm-5.3-flash-free','deepseek-v4.1-flash-free','mimo-v2.6-flash-free','big-pickle',available.data.default.opencode].filter((id):id is string=>typeof id==='string');
  const candidates=[...new Set(preferred)].filter(id=>{
   const model=provider?.models[id];
   return !!model&&model.cost?.input===0&&model.cost?.output===0&&model.cost?.cache?.read===0&&model.cost?.cache?.write===0;
  }).slice(0,3);
  if(!available.data.connected.includes('opencode')||!candidates.length)throw new Error('No verified zero-cost OpenCode model is available');
  for(const modelID of candidates){
   let sessionID:string|undefined;
   try{
   const created=await client.session.create({title:'ParkLink ephemeral intent',permission:[
    {permission:'*',pattern:'*',action:'deny'},
    {permission:'StructuredOutput',pattern:'*',action:'allow'}
   ]},{throwOnError:true,signal:AbortSignal.timeout(5000)});
   sessionID=created.data.id;
   const result=await client.session.prompt({sessionID,system:COPILOT_PERSONALITY,model:{providerID:'opencode',modelID},
    tools:{bash:false,shell:false,read:false,write:false,edit:false,apply_patch:false,glob:false,grep:false,task:false,webfetch:false,websearch:false,todowrite:false,question:false},
     parts:[{type:'text',text:JSON.stringify({context:{...context,history:context.history.slice(-3)},message:text})}],
     format:{type:'json_schema',schema:z.toJSONSchema(IntentSchema),retryCount:0}
    },{throwOnError:true,signal:AbortSignal.timeout(8000)});
   if(result.data.info.error)throw new Error('OpenCode did not produce a valid intent');
   return IntentSchema.parse(result.data.info.structured);
   }catch{
    // Try the next verified free model after timeout, provider error or invalid output.
   }finally{
   if(sessionID){
     await client.session.abort({sessionID},{signal:AbortSignal.timeout(1000)}).catch(()=>{});
     await client.session.delete({sessionID},{signal:AbortSignal.timeout(1000)}).catch(()=>{});
   }
   }
  }
  throw new Error('All verified zero-cost OpenCode models failed');
 }
}

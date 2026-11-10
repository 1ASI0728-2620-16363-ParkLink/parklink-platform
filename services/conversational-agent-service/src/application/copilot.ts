import {createHash,randomUUID} from 'node:crypto';
import {z,HoldSchema,EXCHANGE} from '@parklink/contracts';
import {ServiceUnavailableException,ConflictException,NotFoundException,ForbiddenException,HttpException} from '@nestjs/common';
import {pool,transaction,enqueue,role,type AuthRequest} from '@parklink/runtime';
import {ChatInputSchema,type ChatInput,type IntentProvider,type IntentContext,ACTION} from '../domain/intent';
import {OpenCodeIntentProvider} from '../infrastructure/opencode';

interface SearchItem{id:string;revision:number;distance_m:number;body:Record<string,unknown>}
const money=(amount:number)=>`S/ ${(amount/100).toFixed(2)}`;
export class Copilot{
 constructor(private readonly provider?:IntentProvider){}
 enabled(){if(process.env.COPILOT_ENABLED!=='true')throw new ServiceUnavailableException('Copilot está desactivado. Puedes usar la búsqueda visual.');}
 private async get(path:string,r:AuthRequest){
  const base=path.startsWith('/discovery')?process.env.DISCOVERY_URL:process.env.RESERVATION_URL;
  if(!base)throw new ServiceUnavailableException('Servicio no configurado');
  const response=await fetch(base+path,{headers:{authorization:r.headers.authorization!,'x-correlation-id':r.correlationId},signal:AbortSignal.timeout(5000)});
  if(response.status===404)throw new NotFoundException('No se encontró el recurso');
  if(response.status===403)throw new ForbiddenException('Este recurso no te pertenece');
  if(!response.ok)throw new ServiceUnavailableException('No se pudo verificar la información. Usa el flujo visual.');
  return response.json() as Promise<Record<string,unknown>>;
 }
 async status(){
  const enabled=process.env.COPILOT_ENABLED==='true';let runtimeReady=false;
  try{runtimeReady=await new OpenCodeIntentProvider().health();}catch{/* Readiness is reported, never invented. */}
  return {enabled,configuredEngine:'opencode',runtimeReady,inferenceEnabled:process.env.OPENCODE_INFERENCE_ENABLED==='true',name:'ParkLink Copilot',sensitiveActionsRequireConfirmation:true};
 }
 private async proposal(kind:string,payload:Record<string,unknown>,summary:Record<string,unknown>,r:AuthRequest){
  const id=randomUUID();
  await transaction(async tx=>{
   await tx.query("INSERT INTO confirmations(id,actor_id,payload,summary,expires_at) VALUES($1,$2,$3,$4,now()+interval '5 minutes')",[id,r.actor.id,{kind,...payload},summary]);
   await enqueue(tx,'agent.action-proposed.v1',{commandId:id,spaceId:payload.spaceId,reservationId:payload.reservationId,amount:summary.amount},r.actor.id,r.correlationId);
  });
  return {confirmationId:id,summary,expiresIn:300};
 }
 async propose(input:unknown,r:AuthRequest,payAfterHold=false){
  this.enabled();role(r.actor,'DRIVER');const p=HoldSchema.parse(input);
  if(Date.parse(p.start)<=Date.now()||Date.parse(p.start)>=Date.parse(p.end))throw new ConflictException('Elige un horario futuro válido.');
  const space=await this.get(`/discovery/spaces/${p.spaceId}`,r),body=space.body as Record<string,unknown>;
  if(body.ownerId===r.actor.id)throw new ForbiddenException('No puedes reservar tu propio espacio');
  const amount=Math.ceil(Number(body.hourlyRate)*(Date.parse(p.end)-Date.parse(p.start))/3600000);
  if(!Number.isSafeInteger(amount)||amount<=0)throw new ConflictException('Cotización inválida');
  return this.proposal(payAfterHold?'hold_and_pay':'hold',{...p,expectedAmount:amount,supplyRevision:space.revision},{title:body.title,address:body.address,start:p.start,end:p.end,amount,currency:'PEN',action:payAfterHold?'hold_and_pay':'hold',policy:payAfterHold?'Se retendrá la plaza y se iniciará el pago sandbox; no se mueve dinero real. La reserva queda confirmada solo cuando el servidor verifique el pago. Reembolso total al cancelar con al menos 60 minutos de antelación; la cancelación tardía depende de una política configurada.':'Retención máxima de 10 minutos. No se cobra con esta acción. Reembolso total al cancelar con al menos 60 minutos de antelación; la cancelación tardía depende de una política configurada.'},r);
 }
 async proposeAction(input:unknown,r:AuthRequest){
  this.enabled();role(r.actor,'DRIVER');
  const p=z.object({action:z.enum(['pay','cancel']),reservationId:z.uuid()}).strict().parse(input);
  const reservation=await this.get(`/reservations/${p.reservationId}`,r);
  if(reservation.driver_id!==r.actor.id)throw new ForbiddenException('Solo el conductor de esta reserva puede modificarla');
  const amount=Number(reservation.amount),expectedVersion=Number(reservation.version);
  if(p.action==='pay'){
   if(reservation.status!=='PENDING_PAYMENT'||Date.parse(String(reservation.expires_at))<=Date.now())throw new ConflictException('La reserva ya no admite un pago. Consulta su estado.');
   return this.proposal('confirm',{reservationId:p.reservationId,expectedAmount:amount,expectedVersion,sandboxResult:'approved'},{action:'pay',reservationId:p.reservationId,title:`Reserva ${reservation.code}`,amount,currency:'PEN',policy:'Esta acción inicia el pago. En el entorno local es sandbox y no mueve dinero real. Solo el servidor de reservas puede confirmar la plaza.'},r);
  }
  if(!['PENDING_PAYMENT','CONFIRMED','ACTIVE'].includes(String(reservation.status)))throw new ConflictException('Esta reserva ya no se puede cancelar');
  const policy=await this.get('/reservations/policy/cancellation',r);
  const timely=Date.parse(String(reservation.start_time))-Date.now()>=3600000;
  if(reservation.payment_id&&!timely&&policy.lateFeeBps===null)throw new ConflictException('La cancelación tardía no tiene una política aprobada. Contacta con soporte.');
  const refund=reservation.payment_id?(timely?amount:Math.floor(amount*(10000-Number(policy.lateFeeBps))/10000)):0;
  return this.proposal('cancel',{reservationId:p.reservationId,expectedAmount:amount,expectedVersion,expectedRefund:refund},{action:'cancel',reservationId:p.reservationId,title:`Reserva ${reservation.code}`,amount,currency:'PEN',refundAmount:refund,policy:`Se libera la plaza. Devolución solicitada: ${money(refund)}. Una cancelación confirmada no significa que la devolución ya se haya abonado.`},r);
 }
 async confirm(id:string,r:AuthRequest){
  this.enabled();role(r.actor,'DRIVER');return transaction(async tx=>{
   const row=(await tx.query('SELECT * FROM confirmations WHERE id=$1 AND actor_id=$2 FOR UPDATE',[id,r.actor.id])).rows[0];
   if(!row)throw new NotFoundException();
   if(!row.consumed_at&&row.expires_at.getTime()<=Date.now())throw new ConflictException('La confirmación venció. Revisa un nuevo resumen.');
   if(!row.consumed_at){
    const {kind='hold',...payload}=row.payload;
    z.enum(['hold','hold_and_pay','confirm','cancel']).parse(kind);
    await tx.query('UPDATE confirmations SET consumed_at=now() WHERE id=$1',[id]);
    await enqueue(tx,`reservation.${kind}.v1`,{...payload,commandId:id},r.actor.id,r.correlationId,EXCHANGE.COMMANDS,id);
    await enqueue(tx,'agent.human-confirmed.v1',{commandId:id,spaceId:payload.spaceId,reservationId:payload.reservationId,amount:row.summary.amount},r.actor.id,r.correlationId);
   }
   return {commandId:id,status:'PENDING'};
  });
 }
 async result(id:string,r:AuthRequest){
  const row=(await pool.query('SELECT consumed_at FROM confirmations WHERE id=$1 AND actor_id=$2',[id,r.actor.id])).rows[0];
  if(!row)throw new NotFoundException();if(!row.consumed_at)throw new ConflictException('Falta tu confirmación');
  try{return await this.get(`/operations/${id}`,r);}catch(error){if(error instanceof NotFoundException)return {id,status:'PENDING',result:null,http_status:null};throw error;}
 }
 async search(input:unknown,r:AuthRequest){
  this.enabled();const p=z.object({text:z.string().max(100),latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),sort:z.enum(['nearest','cheapest']).default('nearest')}).strict().parse(input);
  return this.get(`/discovery/search?${new URLSearchParams({latitude:String(p.latitude),longitude:String(p.longitude),text:p.text,sort:p.sort})}`,r);
 }
 async chat(input:unknown,r:AuthRequest){
  this.enabled();role(r.actor,'DRIVER');const p=ChatInputSchema.parse(input);
  const hash=createHash('sha256').update(JSON.stringify(p)).digest('hex');
  const claim=await transaction(async tx=>{
   await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',[`copilot:${r.actor.id}`]);
   const old=(await tx.query('SELECT * FROM chat_turns WHERE id=$1',[p.requestId])).rows[0];
   if(old){if(old.actor_id!==r.actor.id||old.request_hash!==hash)throw new ConflictException('Identificador de mensaje reutilizado');if(old.status==='COMPLETE')return {cached:old.response,conversationId:old.conversation_id};throw new ConflictException(old.status==='PENDING'?'El mensaje sigue en proceso. Consulta antes de repetirlo.':'Este mensaje no pudo procesarse. Envía uno nuevo.');}
   const recent=await tx.query("SELECT count(*)::integer AS n FROM chat_turns WHERE actor_id=$1 AND created_at>now()-interval '1 minute'",[r.actor.id]);
   if(recent.rows[0].n>=12)throw new HttpException('Espera un momento antes de enviar otro mensaje.',429);
   const conversationId=p.conversationId??randomUUID();
   if(p.conversationId){const conversation=(await tx.query('SELECT actor_id,expires_at FROM conversations WHERE id=$1',[conversationId])).rows[0];if(!conversation||conversation.actor_id!==r.actor.id||conversation.expires_at.getTime()<=Date.now())throw new NotFoundException('La conversación venció');}
   else await tx.query('INSERT INTO conversations(id,actor_id) VALUES($1,$2)',[conversationId,r.actor.id]);
   await tx.query('INSERT INTO chat_turns(id,conversation_id,actor_id,request_hash,user_text) VALUES($1,$2,$3,$4,$5)',[p.requestId,conversationId,r.actor.id,hash,p.message]);
   const history=(await tx.query("SELECT user_text,response->>'message' AS assistant FROM chat_turns WHERE conversation_id=$1 AND status='COMPLETE' ORDER BY created_at DESC LIMIT 6",[conversationId])).rows.reverse();
   return {conversationId,history};
  });
  if(claim.cached)return claim.cached;
  try{
   const context:IntentContext={now:new Date().toISOString(),start:p.start,end:p.end,history:(claim.history??[]).map(h=>({user:String(h.user_text),assistant:String(h.assistant)}))};
   const engine=this.provider??new OpenCodeIntentProvider();
   let intent;
   try{intent=await engine.interpret(p.message,context);}
   catch{await pool.query('DELETE FROM chat_turns WHERE id=$1 AND status=$2',[p.requestId,'PENDING']);throw new ServiceUnavailableException('OpenCode no está disponible. Inténtalo de nuevo más tarde.');}
   const result=await this.executeIntent(intent,p,r);
   const response={...result,conversationId:claim.conversationId,engine:engine.name,configuredEngine:'opencode'};
   await pool.query("UPDATE chat_turns SET status='COMPLETE',response=$2 WHERE id=$1",[p.requestId,response]);
   await pool.query("UPDATE conversations SET updated_at=now(),expires_at=now()+interval '24 hours' WHERE id=$1",[claim.conversationId]);
   return response;
  }catch(error){await pool.query("UPDATE chat_turns SET status='FAILED' WHERE id=$1",[p.requestId]);throw error;}
 }
 private async executeIntent(intent:Awaited<ReturnType<IntentProvider['interpret']>>,p:ChatInput,r:AuthRequest):Promise<Record<string,unknown>>{
  if(intent.action===ACTION.CLARIFY)return {message:'Puedo buscar espacios cercanos o económicos, consultar tus reservas y preparar una reserva, cancelación o pago. ¿Qué necesitas?',action:'clarify'};
  if(intent.action===ACTION.LIST||([ACTION.PAY,ACTION.CANCEL] as string[]).includes(intent.action)&&!intent.reservationId){
   const data=await this.get('/reservations/mine',r) as unknown as Array<Record<string,unknown>>;
   return {message:intent.action===ACTION.LIST?'Estas son tus reservas registradas.':'Selecciona la reserva sobre la que quieres actuar.',action:intent.action,reservations:data.slice(0,20)};
  }
  if(intent.action===ACTION.PAY||intent.action===ACTION.CANCEL){const proposal=await this.proposeAction({action:intent.action,reservationId:intent.reservationId},r);return {message:'Revisa los datos y confirma para continuar. Todavía no se ha realizado ninguna operación.',action:intent.action,proposal};}
  const start=p.start??intent.start,end=p.end??intent.end;
  if(intent.action===ACTION.RESERVE&&(!start||!end))return {message:'¿Qué día y en qué horario necesitas el estacionamiento? Puedes elegir ingreso y salida en el selector.',action:'clarify',requiresInterval:true};
  const params=new URLSearchParams({latitude:String(p.latitude),longitude:String(p.longitude),radius:String(p.radius),text:intent.text,sort:intent.sort,limit:'5',...(intent.maxRate?{maxRate:String(intent.maxRate)}:{}),...(start&&end?{start,end}:{})});
  const found=await this.get(`/discovery/search?${params}`,r);const items=found.items as SearchItem[];
  if(!items.length)return {message:'No encontré espacios que coincidan en esta zona y horario. Prueba otra zona o intervalo.',action:'search',items:[]};
  if(intent.action===ACTION.RESERVE){const selected=items[0]!;const proposal=await this.propose({spaceId:selected.id,start,end,expectedAmount:undefined},r,true);return {message:`Elegí la opción ${intent.sort==='cheapest'?'más económica':'más cercana'} dentro de ${(p.radius/1000).toFixed(1)} km. Revisa el importe y el horario antes de pagar.`,action:'reserve',items:[selected],proposal};}
  return {message:`Encontré ${items.length} opciones ordenadas por ${intent.sort==='cheapest'?'menor precio':'menor distancia'}. La disponibilidad se valida de nuevo al reservar.`,action:'search',items};
 }
}

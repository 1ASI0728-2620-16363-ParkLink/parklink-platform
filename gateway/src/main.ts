import { All,Controller,Get,Module,Req,Res,ServiceUnavailableException } from '@nestjs/common';
import type { Response } from 'express';
import { bootstrap,role,type AuthRequest } from '@parklink/runtime';
const routes:Record<string,string>={auth:'IDENTITY_URL',spaces:'SUPPLY_URL',discovery:'DISCOVERY_URL',reservations:'RESERVATION_URL',operations:'RESERVATION_URL',payments:'PAYMENT_URL',notifications:'NOTIFICATION_URL',copilot:'AGENT_URL',audit:'AUDIT_URL'};
async function upstream(path:string,r:AuthRequest){
 const key=routes[path.split('/')[1]??''];if(!key||!process.env[key])throw new ServiceUnavailableException('Route unavailable');
 const headers:Record<string,string>={'Content-Type':'application/json','X-Correlation-Id':r.correlationId};
 for(const name of ['authorization','idempotency-key','x-signature','x-request-id']){const v=r.headers[name];if(typeof v==='string')headers[name]=v;}
 return fetch(`${process.env[key]}${path}`,{method:r.method,headers,body:['GET','HEAD'].includes(r.method)?undefined:JSON.stringify(r.body),signal:AbortSignal.timeout(path.startsWith('/copilot/chat')?50000:10000),redirect:'error'});
}
@Controller()class GatewayController{
 @Get('owner/dashboard')async dashboard(@Req()r:AuthRequest){
  role(r.actor,'OWNER');const responses=await Promise.all(['/spaces/mine','/reservations/owner','/payments/owner'].map(path=>upstream(path,r)));
  if(responses.some(x=>!x.ok))throw new ServiceUnavailableException('Owner metrics unavailable; no estimated values returned');
  const [spaces,reservations,payments]=await Promise.all(responses.map(x=>x.json())) as [Array<Record<string,unknown>>,Array<Record<string,unknown>>,Array<Record<string,unknown>>];
  const approved=payments.filter(p=>p.status==='APPROVED'||p.status==='REFUNDED');
  const net=(p:Record<string,unknown>)=>Number(p.amount)-Number(p.refunded_amount);
  const byMonth:Record<string,number>={};for(const p of approved){const month=String(p.created_at).slice(0,7);byMonth[month]=(byMonth[month]??0)+net(p);}
  return {observedAt:new Date().toISOString(),currency:'PEN',monitoringOnly:true,truncated:spaces.length>=500||reservations.length>=500||payments.length>=500,
   spaces:{total:spaces.length,active:spaces.filter(s=>s.state==='PUBLISHED'&&(s.body as Record<string,unknown>).active).length},
   reservations:{pending:reservations.filter(r=>r.status==='PENDING_PAYMENT').length,active:reservations.filter(r=>r.status==='ACTIVE').length,confirmed:reservations.filter(r=>r.status==='CONFIRMED').length,completed:reservations.filter(r=>r.status==='COMPLETED').length},
   income:approved.reduce((sum,p)=>sum+net(p),0),byMonth,upcoming:reservations.filter(r=>r.status==='CONFIRMED'&&Date.parse(String(r.start_time))>Date.now()).sort((a,b)=>Date.parse(String(a.start_time))-Date.parse(String(b.start_time))).slice(0,20),
   occupiedSpaces:new Set(reservations.filter(r=>r.status==='ACTIVE').map(r=>r.space_id)).size,transactions:payments,inventory:spaces};
 }
 @All('*path')async proxy(@Req()r:AuthRequest,@Res()res:Response){
  const path=r.originalUrl;if(!routes[r.path.split('/')[1]??'']){res.status(404).json({message:'Route not found'});return;}
  try{const response=await upstream(path,r);res.status(response.status).type('application/json').send(await response.text());}catch{throw new ServiceUnavailableException('Service unavailable; retry queries before resubmitting an operation');}
 }
}
@Module({controllers:[GatewayController]})class AppModule{}
void bootstrap(AppModule,'gateway',{database:false,publicPaths:['/auth/register','/auth/login','/auth/monitor-login','/payments/webhook/mercadopago']}).catch(error=>{console.error(error);process.exit(1);});

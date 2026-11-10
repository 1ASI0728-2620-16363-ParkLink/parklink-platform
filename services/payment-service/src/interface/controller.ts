import { Controller,Get,Post,Param,ParseUUIDPipe,Req,UnauthorizedException,HttpCode } from '@nestjs/common';
import { type AuthRequest,required,role } from '@parklink/runtime';
import { Payments } from '../application/payments';
import { verifyMercadoPago } from '../infrastructure/providers';
export const payments=new Payments();
@Controller('payments')export class PaymentsController{
 @Get('mine')mine(@Req()r:AuthRequest){return payments.list(r.actor);}
 @Get('owner')owner(@Req()r:AuthRequest){role(r.actor,'OWNER');return payments.list(r.actor,true);}
 @Get(':id')get(@Param('id',ParseUUIDPipe)id:string,@Req()r:AuthRequest){return payments.get(id,r.actor);}
 @Post('webhook/mercadopago')@HttpCode(200)async webhook(@Req()r:AuthRequest){
  if(process.env.PAYMENT_PROVIDER!=='mercadopago'||!verifyMercadoPago(String(r.headers['x-signature']??''),String(r.headers['x-request-id']??''),String(r.query['data.id']??''),required('MP_WEBHOOK_SECRET')))throw new UnauthorizedException('Invalid webhook signature');
  // Provider payloads never decide local payment state. Reconciliation reads the authenticated provider API.
  await payments.tick();return {accepted:true};
 }
}

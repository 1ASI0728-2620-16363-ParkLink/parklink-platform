import { Body, Controller, Get, Headers, HttpCode, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import { z } from '@parklink/contracts';
import { type AuthRequest, role } from '@parklink/runtime';
import { Reservations } from '../application/reservations';
@Controller() export class ReservationsController {
 private readonly reservations=new Reservations();
 @Post('reservations/commands/:kind') @HttpCode(202) submit(@Param('kind') kind:string,@Body() body:unknown,@Headers('idempotency-key') key:string,@Req() req:AuthRequest) {
  role(req.actor,'DRIVER'); z.enum(['hold','confirm','cancel']).parse(kind); return this.reservations.submit(kind,body,key,req.actor,req.correlationId);
 }
 @Get('operations/:id') operation(@Param('id',ParseUUIDPipe) id:string,@Req() r:AuthRequest) { return this.reservations.operation(id,r.actor); }
 @Get('reservations/mine') mine(@Req() r:AuthRequest) { return this.reservations.list(r.actor); }
 @Get('reservations/owner') owner(@Req() r:AuthRequest) { role(r.actor,'OWNER'); return this.reservations.list(r.actor,true); }
 @Get('reservations/availability') availability(@Query() q:unknown) { const p=z.object({spaceId:z.string().uuid(),start:z.string().datetime({offset:true}),end:z.string().datetime({offset:true})}).strict().parse(q); return this.reservations.availability(p.spaceId,p); }
 @Get('reservations/:id') get(@Param('id',ParseUUIDPipe) id:string,@Req() r:AuthRequest) { return this.reservations.get(id,r.actor); }
 @Get('reservations/policy/cancellation') policy() { return {freeCancellationMinutes:60,lateFeeBps:process.env.LATE_CANCELLATION_FEE_BPS === undefined ? null : Number(process.env.LATE_CANCELLATION_FEE_BPS),holdMinutes:10}; }
}

import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Put, Req } from '@nestjs/common';
import { z } from '@parklink/contracts';
import type { AuthRequest } from '@parklink/runtime';
import { Supply } from '../application/supply';
@Controller('spaces') export class SupplyController {
 private readonly supply = new Supply();
 @Get('mine') mine(@Req() r: AuthRequest) { return this.supply.mine(r.actor); }
 @Post() create(@Body() body: unknown, @Req() r: AuthRequest) { return this.supply.save(body, r.actor, r.correlationId); }
 @Put(':id') edit(@Param('id', ParseUUIDPipe) id: string, @Body() input: unknown, @Req() r: AuthRequest) {
   const { revision, space } = z.object({ revision: z.number().int().positive(), space: z.unknown() }).strict().parse(input);
   return this.supply.save(space, r.actor, r.correlationId, id, revision);
 }
}

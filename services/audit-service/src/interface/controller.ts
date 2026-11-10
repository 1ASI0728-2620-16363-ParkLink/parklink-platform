import { Controller,Get,Query,Req } from '@nestjs/common';
import { z } from '@parklink/contracts';
import { pool,role,type AuthRequest } from '@parklink/runtime';
@Controller('audit')export class AuditController{
 @Get()async query(@Query('correlationId')id:string,@Req()r:AuthRequest){role(r.actor,'SUPPORT');z.string().uuid().parse(id);return(await pool.query('SELECT * FROM audit_events WHERE correlation_id=$1 ORDER BY occurred_at LIMIT 1000',[id])).rows;}
}

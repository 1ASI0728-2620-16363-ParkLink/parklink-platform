import { Controller, Get, Query, Param, ParseUUIDPipe, NotFoundException, Req } from '@nestjs/common';
import { pool, type AuthRequest } from '@parklink/runtime';
import { Discovery } from '../application/discovery';
@Controller('discovery') export class DiscoveryController {
 private readonly discovery=new Discovery();
 @Get('search') search(@Query() query:unknown,@Req()r:AuthRequest){return this.discovery.search(query,r.actor.id);}
 @Get('spaces/:id') async detail(@Param('id',ParseUUIDPipe) id:string){const row=(await pool.query('SELECT id,revision,body,updated_at FROM space_documents WHERE id=$1',[id])).rows[0];if(!row)throw new NotFoundException();return row;}
}

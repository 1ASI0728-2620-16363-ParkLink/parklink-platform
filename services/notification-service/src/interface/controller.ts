import { Body,Controller,Get,Param,ParseUUIDPipe,Put,Req } from '@nestjs/common';
import { z } from '@parklink/contracts';
import { pool,type AuthRequest } from '@parklink/runtime';
@Controller('notifications')export class NotificationsController{
 @Get()async list(@Req()r:AuthRequest){return(await pool.query('SELECT * FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100',[r.actor.id])).rows;}
 @Get('preferences')async preferences(@Req()r:AuthRequest){return(await pool.query('SELECT in_app FROM preferences WHERE user_id=$1',[r.actor.id])).rows[0]??{in_app:true};}
 @Put('preferences')async save(@Body()body:unknown,@Req()r:AuthRequest){const p=z.object({inApp:z.boolean()}).strict().parse(body);await pool.query('INSERT INTO preferences(user_id,in_app) VALUES($1,$2) ON CONFLICT(user_id) DO UPDATE SET in_app=$2',[r.actor.id,p.inApp]);return{inApp:p.inApp};}
 @Put(':id/read')async read(@Param('id',ParseUUIDPipe)id:string,@Req()r:AuthRequest){await pool.query('UPDATE notifications SET read_at=now() WHERE id=$1 AND user_id=$2',[id,r.actor.id]);return{read:true};}
}

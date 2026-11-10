import { Body,Controller,Param,ParseUUIDPipe,Post,Req,HttpCode,Get } from '@nestjs/common';
import type { AuthRequest } from '@parklink/runtime';
import { Copilot } from '../application/copilot';
@Controller('copilot')export class CopilotController{
 private readonly copilot=new Copilot();
 @Get('status')status(){return this.copilot.status();}
 @Post('chat')chat(@Body()body:unknown,@Req()r:AuthRequest){return this.copilot.chat(body,r);}
 @Post('search')search(@Body()body:unknown,@Req()r:AuthRequest){return this.copilot.search(body,r);}
 @Post('propose-hold')propose(@Body()body:unknown,@Req()r:AuthRequest){return this.copilot.propose(body,r);}
 @Post('propose-action')action(@Body()body:unknown,@Req()r:AuthRequest){return this.copilot.proposeAction(body,r);}
 @Get('commands/:id')result(@Param('id',ParseUUIDPipe)id:string,@Req()r:AuthRequest){return this.copilot.result(id,r);}
 @Post('confirm/:id')@HttpCode(202)confirm(@Param('id',ParseUUIDPipe)id:string,@Req()r:AuthRequest){return this.copilot.confirm(id,r);}
}

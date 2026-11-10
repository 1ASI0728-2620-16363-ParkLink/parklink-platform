import { Module } from '@nestjs/common';
import { bootstrap,migrate,commonSchema,Bus } from '@parklink/runtime';
import { EXCHANGE } from '@parklink/contracts';
import { audit } from './application/audit';
import { AuditController } from './interface/controller';
@Module({controllers:[AuditController]})class AppModule{}
async function main(){await migrate();await commonSchema();if(process.argv.includes('--migrate'))process.exit(0);const bus=new Bus();bus.subscribe('audit.events.v1',EXCHANGE.EVENTS,['#'],audit);await bus.start();await bootstrap(AppModule,'audit-service',{ready:()=>bus.ready});}
void main().catch(error=>{console.error(error);process.exit(1);});

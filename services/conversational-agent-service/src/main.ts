import { Module } from '@nestjs/common';
import { bootstrap,migrate,commonSchema,Bus,pool } from '@parklink/runtime';
import { CopilotController } from './interface/controller';
@Module({controllers:[CopilotController]})class AppModule{}
async function main(){await migrate();await commonSchema();if(process.argv.includes('--migrate'))process.exit(0);const bus=new Bus();await bus.start();setInterval(()=>{void pool.query("DELETE FROM confirmations WHERE created_at<now()-interval '24 hours'").catch(()=>{});void pool.query('DELETE FROM conversations WHERE expires_at<now()').catch(()=>{});},60000).unref();await bootstrap(AppModule,'conversational-agent-service',{ready:()=>bus.ready});}
void main().catch(error=>{console.error(error);process.exit(1);});

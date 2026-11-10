import { Module } from '@nestjs/common';
import { bootstrap,migrate,commonSchema,Bus } from '@parklink/runtime';
import { EXCHANGE } from '@parklink/contracts';
import { PaymentsController,payments } from './interface/controller';
@Module({controllers:[PaymentsController]})class AppModule{}
async function main(){await migrate();await commonSchema();if(process.argv.includes('--migrate'))process.exit(0);const bus=new Bus();bus.subscribe('payment.commands.v1',EXCHANGE.COMMANDS,['payment.*.v1'],m=>payments.command(m));await bus.start();setInterval(()=>void payments.tick().catch(()=>console.error('payment worker retry')),1000).unref();await bootstrap(AppModule,'payment-service',{publicPaths:['/payments/webhook/mercadopago'],ready:()=>bus.ready});}
void main().catch(error=>{console.error(error);process.exit(1);});

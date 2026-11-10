import { Module } from '@nestjs/common';
import { bootstrap,migrate,commonSchema,Bus } from '@parklink/runtime';
import { EXCHANGE } from '@parklink/contracts';
import { notify } from './application/notifications';
import { NotificationsController } from './interface/controller';
@Module({controllers:[NotificationsController]})class AppModule{}
async function main(){await migrate();await commonSchema();if(process.argv.includes('--migrate'))process.exit(0);const bus=new Bus();bus.subscribe('notification.events.v1',EXCHANGE.EVENTS,['reservation.confirmed.v1','reservation.cancelled.v1','reservation.expired.v1','reservation.payment-failed.v1','payment.refunded.v1'],notify);await bus.start();await bootstrap(AppModule,'notification-service',{ready:()=>bus.ready});}
void main().catch(error=>{console.error(error);process.exit(1);});

import { Module } from '@nestjs/common';
import { bootstrap, migrate, commonSchema, Bus } from '@parklink/runtime';
import { EXCHANGE } from '@parklink/contracts';
import { Reservations } from './application/reservations';
import { ReservationsController } from './interface/controller';
@Module({controllers:[ReservationsController]}) class AppModule {}
async function main() {
 await migrate(); await commonSchema(); if(process.argv.includes('--migrate')) process.exit(0);
 const bus=new Bus(), app=new Reservations();
 bus.subscribe('reservation.commands.v1',EXCHANGE.COMMANDS,['reservation.*.v1'],m=>app.command(m));
 bus.subscribe('reservation.events.v1',EXCHANGE.EVENTS,['supply.revision-proposed.v1','payment.authorized.v1','payment.failed.v1'],m=>m.type.startsWith('supply.')?app.supply(m):app.payment(m));
 await bus.start(); const timer=setInterval(()=>void app.tick().catch(()=>console.error('reservation scheduler retry')),1000);
 timer.unref(); await bootstrap(AppModule,'reservation-service',{ready:()=>bus.ready});
}
void main().catch(error=>{console.error(error);process.exit(1);});

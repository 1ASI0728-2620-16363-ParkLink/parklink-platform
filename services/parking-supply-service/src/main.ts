import { Module } from '@nestjs/common';
import { bootstrap, migrate, commonSchema, Bus } from '@parklink/runtime';
import { EXCHANGE } from '@parklink/contracts';
import { SupplyController } from './interface/controller';
import { Supply } from './application/supply';
@Module({ controllers: [SupplyController] }) class AppModule {}
async function main() {
 await migrate(); await commonSchema(); if (process.argv.includes('--migrate')) process.exit(0);
 const bus = new Bus(); const supply = new Supply();
 bus.subscribe('supply.events.v1', EXCHANGE.EVENTS, ['supply.revision-accepted.v1','supply.revision-rejected.v1'], m => supply.outcome(m));
 await bus.start(); await bootstrap(AppModule, 'parking-supply-service', { ready: () => bus.ready });
}
void main().catch(error => { console.error(error); process.exit(1); });

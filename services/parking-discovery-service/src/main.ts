import { Module } from '@nestjs/common';
import { bootstrap,migrate,commonSchema,Bus } from '@parklink/runtime';
import { EXCHANGE } from '@parklink/contracts';
import { Discovery } from './application/discovery';
import { DiscoveryController } from './interface/controller';
@Module({controllers:[DiscoveryController]})class AppModule{}
async function main(){await migrate();await commonSchema();if(process.argv.includes('--migrate'))process.exit(0);const bus=new Bus(),app=new Discovery();bus.subscribe('discovery.events.v1',EXCHANGE.EVENTS,['supply.revision-accepted.v1','reservation.*.v1'],m=>app.project(m));await bus.start();await bootstrap(AppModule,'parking-discovery-service',{ready:()=>bus.ready});}
void main().catch(error=>{console.error(error);process.exit(1);});

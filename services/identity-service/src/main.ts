import { Module } from '@nestjs/common';
import { bootstrap, migrate, commonSchema, Bus } from '@parklink/runtime';
import { AccountsController } from './interface/controller';
@Module({ controllers: [AccountsController] }) class AppModule {}
async function main() {
 await migrate(); await commonSchema(); if (process.argv.includes('--migrate')) process.exit(0);
 const bus = new Bus(); await bus.start(); await bootstrap(AppModule, 'identity-service', { publicPaths: ['/auth/register','/auth/login','/auth/monitor-login'], ready: () => bus.ready });
}
void main().catch(error => { console.error(error); process.exit(1); });

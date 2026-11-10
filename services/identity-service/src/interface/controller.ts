import { Body, Controller, Get, Post, Req } from '@nestjs/common';
import { pool, type AuthRequest } from '@parklink/runtime';
import { Accounts } from '../application/accounts';
@Controller('auth')
export class AccountsController {
  private readonly accounts = new Accounts();
  @Post('register') register(@Body() body: unknown, @Req() req: AuthRequest) { return this.accounts.register(body, req.correlationId); }
  @Post('login') login(@Body() body: unknown) { return this.accounts.login(body); }
  @Post('monitor-login') monitor(@Body() body: unknown) { return this.accounts.login(body, true); }
  @Get('me') async me(@Req() req: AuthRequest) { return (await pool.query('SELECT id,email,name,roles FROM users WHERE id=$1', [req.actor.id])).rows[0]; }
}

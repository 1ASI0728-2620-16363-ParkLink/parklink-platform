import { randomUUID } from 'node:crypto';
import { UnauthorizedException, ForbiddenException } from '@nestjs/common';
import { RegistrationSchema, LoginSchema } from '@parklink/contracts';
import { pool, transaction, enqueue, token } from '@parklink/runtime';
import { hashPassword, verifyPassword } from '../domain/password';
export class Accounts {
  async register(input: unknown, correlationId: string) {
    const dto = RegistrationSchema.parse(input); const id = randomUUID(); const hash = await hashPassword(dto.password);
    const roles = dto.owner ? ['DRIVER', 'OWNER'] : ['DRIVER'];
    await transaction(async tx => {
      await tx.query('INSERT INTO users(id,email,name,password_hash,roles) VALUES($1,$2,$3,$4,$5)', [id, dto.email, dto.name, hash, roles]);
      await enqueue(tx, 'identity.registered.v1', { userId: id }, id, correlationId);
    });
    return { token: await token({ id, roles }), user: { id, name: dto.name, email: dto.email, roles }, expiresIn: 3600 };
  }
  async login(input: unknown, monitor = false) {
    const dto = LoginSchema.parse(input); const result = await pool.query('SELECT * FROM users WHERE email=$1', [dto.email]); const user = result.rows[0];
    const fallback = '00000000000000000000000000000000:' + '00'.repeat(64);
    const valid = await verifyPassword(dto.password, user?.password_hash ?? fallback);
    if (!user || !valid) throw new UnauthorizedException('Invalid credentials');
    if (monitor && !user.roles.includes('OWNER')) throw new ForbiddenException('Owner account required');
    return { token: await token({ id: user.id, roles: user.roles }, monitor ? 'parklink-monitor' : 'parklink-mobile'), user: { id: user.id, email: user.email, name: user.name, roles: user.roles }, expiresIn: 3600 };
  }
}

import 'reflect-metadata';
import { Catch, HttpException, UnauthorizedException, ForbiddenException, type ArgumentsHost, type ExceptionFilter, type Type } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { jwtVerify, SignJWT } from 'jose';
import { randomUUID } from 'node:crypto';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import type { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import type { Actor } from '@parklink/contracts';
import { pool } from './database';

export interface AuthRequest extends Request { actor: Actor; correlationId: string }
export function required(name: string): string {
  const value = process.env[name]; if (!value || value.length < 16) throw new Error(`${name} must contain at least 16 characters`); return value;
}
function key() { return new TextEncoder().encode(required('JWT_SECRET')); }
export async function token(actor: Actor, audience = 'parklink-mobile') {
  return new SignJWT({ roles: actor.roles }).setProtectedHeader({ alg: 'HS256' }).setSubject(actor.id)
    .setIssuer('parklink-identity').setAudience(audience).setIssuedAt().setExpirationTime('1h').sign(key());
}
export async function authenticate(req: Request): Promise<Actor> {
  try {
    const bearer = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
    if (!bearer) throw new Error();
    const { payload } = await jwtVerify(bearer, key(), { algorithms: ['HS256'], issuer: 'parklink-identity', audience: ['parklink-mobile', 'parklink-monitor'] });
    if (!payload.sub || !Array.isArray(payload.roles) || !payload.roles.every(v => typeof v === 'string')) throw new Error();
    if (payload.aud === 'parklink-monitor' && !['GET', 'HEAD'].includes(req.method)) throw new ForbiddenException('Monitoring sessions are read-only');
    return { id: payload.sub, roles: payload.roles as string[] };
  } catch (error) { if (error instanceof ForbiddenException) throw error; throw new UnauthorizedException(); }
}
export function role(actor: Actor, expected: string) { if (!actor.roles.includes(expected)) throw new ForbiddenException('Role not permitted'); }
export function owns(actor: Actor, id: string) { if (actor.id !== id) throw new ForbiddenException('Resource not owned by this user'); }
export function correlation(req: Request): string {
  const candidate = req.headers['x-correlation-id'];
  return typeof candidate === 'string' && /^[0-9a-f-]{36}$/i.test(candidate) ? candidate : randomUUID();
}
@Catch()
class Errors implements ExceptionFilter {
  catch(error: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp(); const req = ctx.getRequest<AuthRequest>(); const res = ctx.getResponse<Response>();
    const code = (error as { code?: string })?.code;
    const domain = error instanceof Error && error.constructor.name === 'DomainError' ? error as Error & { status: number } : undefined;
    const status = error instanceof ZodError ? 400 : error instanceof HttpException ? error.getStatus() : domain ? domain.status : code === '23P01' || code === '23505' ? 409 : 500;
    const message = error instanceof ZodError ? error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('; ') : error instanceof HttpException ? error.message : domain ? domain.message : status === 409 ? 'Conflicting resource or interval' : 'Internal service error';
    console.error(JSON.stringify({ level: 'error', status, correlationId: req.correlationId, code, path: req.path }));
    res.status(status).json({ statusCode: status, message, correlationId: req.correlationId });
  }
}
export async function bootstrap(module: Type<unknown>, name: string, options: { publicPaths?: string[]; database?: boolean; ready?: () => boolean } = {}) {
  required('JWT_SECRET');
  const app = await NestFactory.create(module, { rawBody: true });
  app.enableShutdownHooks(); app.use(helmet()); app.useGlobalFilters(new Errors());
  app.enableCors({ origin: (process.env.CORS_ORIGINS ?? 'http://localhost:5173').split(','), allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key', 'X-Correlation-Id'], exposedHeaders: ['X-Correlation-Id'] });
  app.use(rateLimit({ windowMs: 60000, limit: Number(process.env.RATE_LIMIT_PER_MINUTE ?? 120), standardHeaders: 'draft-7', legacyHeaders: false, message: { statusCode: 429, message: 'Too many requests; wait before retrying' } }));
  let requests = 0;
  app.use(async (req: AuthRequest, res: Response, next: NextFunction) => {
    req.correlationId = correlation(req); res.setHeader('X-Correlation-Id', req.correlationId); requests++;
    const started = Date.now();
    res.on('finish', () => console.log(JSON.stringify({ service: name, method: req.method, path: req.path, status: res.statusCode, ms: Date.now() - started, correlationId: req.correlationId })));
    if (req.path === '/health') { res.json({ status: 'alive', service: name }); return; }
    if (req.path === '/ready') {
      try { if (options.database !== false) await pool.query('SELECT 1'); if (options.ready && !options.ready()) throw new Error(); res.json({ status: 'ready' }); }
      catch { res.status(503).json({ status: 'unavailable' }); } return;
    }
    if (req.path === '/metrics') { res.type('text/plain').send(`# TYPE parklink_http_requests_total counter\nparklink_http_requests_total{service="${name}"} ${requests}\n`); return; }
    if (req.path.startsWith('/docs') && process.env.NODE_ENV !== 'production') { next(); return; }
    if (options.publicPaths?.includes(req.path)) { next(); return; }
    try { req.actor = await authenticate(req); next(); } catch (error) { new Errors().catch(error, { switchToHttp: () => ({ getRequest: () => req, getResponse: () => res }) } as ArgumentsHost); }
  });
  if (process.env.NODE_ENV !== 'production') SwaggerModule.setup('docs', app, SwaggerModule.createDocument(app, new DocumentBuilder().setTitle(name).setVersion('1').addBearerAuth().build()));
  await app.listen(Number(process.env.PORT ?? 3000), '0.0.0.0');
  return app;
}
export async function internalFetch(url: string, authorization: string, correlationId: string) {
  const response = await fetch(url, { headers: { authorization, 'x-correlation-id': correlationId }, signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new HttpException('Upstream service unavailable', 503);
  return response.json() as Promise<Record<string, unknown>>;
}

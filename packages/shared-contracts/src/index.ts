import { z } from 'zod';
export { z } from 'zod';
export const MessageSchema = z.object({
  id: z.string().uuid(), version: z.literal(1), type: z.string().min(1),
  correlationId: z.string().uuid(), actorId: z.string().uuid(),
  occurredAt: z.string().datetime(), payload: z.record(z.string(), z.unknown())
}).strict();
export type Message = z.infer<typeof MessageSchema>;
export const EXCHANGE = { COMMANDS: 'parklink.commands.v1', EVENTS: 'parklink.events.v1', DEAD: 'parklink.dead.v1' } as const;
export const ROLE = { DRIVER: 'DRIVER', OWNER: 'OWNER', SUPPORT: 'SUPPORT' } as const;
export interface Actor { id: string; roles: string[] }
export const HoldSchema = z.object({ spaceId: z.string().uuid(), start: z.string().datetime({ offset: true }), end: z.string().datetime({ offset: true }), expectedAmount: z.number().int().positive().optional(), supplyRevision: z.number().int().positive().optional() }).strict();
export const ConfirmSchema = z.object({ reservationId: z.string().uuid(), sandboxResult: z.enum(['approved', 'rejected']).default('approved'), expectedAmount: z.number().int().positive().optional(), expectedVersion: z.number().int().positive().optional() }).strict();
export const CancelSchema = z.object({ reservationId: z.string().uuid(), expectedAmount: z.number().int().positive().optional(), expectedVersion: z.number().int().positive().optional(), expectedRefund: z.number().int().nonnegative().optional() }).strict();
export const SpaceSchema = z.object({
   title: z.string().min(3).max(100), address: z.string().min(5).max(300), description: z.string().max(2000),
   photoUrl: z.string().max(2048).url().refine(value => new URL(value).protocol === 'https:', { message: 'Photo URLs must use HTTPS' }).optional(),
  latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180),
  hourlyRate: z.number().int().positive().max(1000000),
  widthCm: z.number().int().min(100).max(2000), lengthCm: z.number().int().min(200).max(5000),
  accessInstructions: z.string().min(3).max(1000), features: z.array(z.enum(['covered', 'security', 'ev', 'accessible'])).max(4),
  windows: z.array(z.object({ start: z.string().datetime({ offset: true }), end: z.string().datetime({ offset: true }) }).strict()).min(1).max(100),
  active: z.boolean().default(true)
}).strict();
export type SpaceInput = z.infer<typeof SpaceSchema>;
export const RegistrationSchema = z.object({ email: z.string().email().max(254).transform(v => v.toLowerCase()), password: z.string().min(12).max(128), name: z.string().min(2).max(100), owner: z.boolean().default(false) }).strict();
export const LoginSchema = z.object({ email: z.string().email().transform(v => v.toLowerCase()), password: z.string().min(1).max(128) }).strict();

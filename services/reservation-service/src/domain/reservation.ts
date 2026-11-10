export const STATUS = { PENDING: 'PENDING_PAYMENT', CONFIRMED: 'CONFIRMED', ACTIVE: 'ACTIVE', COMPLETED: 'COMPLETED', CANCELLED: 'CANCELLED', EXPIRED: 'EXPIRED' } as const;
export interface Interval { start: string; end: string }
export class DomainError extends Error { constructor(message: string, public readonly status = 409) { super(message); } }
export function assertInterval(interval: Interval, now = Date.now()) {
 const start = Date.parse(interval.start), end = Date.parse(interval.end);
 if (!Number.isFinite(start) || !Number.isFinite(end) || start <= now || start >= end || end - start > 30 * 86400000) throw new DomainError('Choose a future interval up to 30 days', 400);
}
export function allows(windows: Interval[], interval: Interval) { return windows.some(w => Date.parse(w.start) <= Date.parse(interval.start) && Date.parse(w.end) >= Date.parse(interval.end)); }
export function quote(hourlyRate: number, interval: Interval) { return Math.ceil(hourlyRate * (Date.parse(interval.end) - Date.parse(interval.start)) / 3600000); }
export function canConfirm(status: string, expiresAt: Date, expectedAttempt: string, attempt: string, now = Date.now()) { return status === STATUS.PENDING && expiresAt.getTime() > now && expectedAttempt === attempt; }
export function refundAmount(start: Date, amount: number, lateFeeBps?: number, now = Date.now()) {
 if (start.getTime() - now >= 3600000) return amount;
 if (lateFeeBps === undefined) throw new DomainError('Late cancellation policy is not configured; contact support', 422);
 if (!Number.isInteger(lateFeeBps) || lateFeeBps < 0 || lateFeeBps > 10000) throw new DomainError('Invalid cancellation policy', 500);
 return Math.floor(amount * (10000 - lateFeeBps) / 10000);
}

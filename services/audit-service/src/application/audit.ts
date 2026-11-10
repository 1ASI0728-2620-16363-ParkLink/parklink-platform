import { transaction,inbox } from '@parklink/runtime';
import type { Message } from '@parklink/contracts';
const fields=new Set(['spaceId','userId','reservationId','paymentId','refundId','attemptId','ownerId','driverId','revision','version','status','amount','currency','reason','provider','commandId']);
export async function audit(m:Message){
 const payload=Object.fromEntries(Object.entries(m.payload).filter(([k,v])=>fields.has(k)&&['string','number','boolean'].includes(typeof v)));
 await transaction(async tx=>{if(!await inbox(tx,m.id))return;await tx.query('INSERT INTO audit_events(id,actor_id,correlation_id,type,payload,occurred_at) VALUES($1,$2,$3,$4,$5,$6)',[m.id,m.actorId,m.correlationId,m.type,payload,m.occurredAt]);});
}

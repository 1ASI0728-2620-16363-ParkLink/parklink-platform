import { randomUUID } from 'node:crypto';
import { transaction,inbox } from '@parklink/runtime';
import type { Message } from '@parklink/contracts';
export async function notify(m:Message){
 await transaction(async tx=>{
  if(!await inbox(tx,m.id))return;
  for(const userId of new Set([m.payload.driverId,m.payload.ownerId].filter(v=>typeof v==='string'))){
   const preference=(await tx.query('SELECT in_app FROM preferences WHERE user_id=$1',[userId])).rows[0];
   if(preference?.in_app===false)continue;
   const body={reservationId:m.payload.reservationId,status:m.payload.status,code:m.payload.code,amount:m.payload.amount,currency:m.payload.currency??'PEN'};
   await tx.query('INSERT INTO notifications(id,user_id,event_id,type,body) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING',[randomUUID(),userId,m.id,m.type,body]);
  }
 });
}

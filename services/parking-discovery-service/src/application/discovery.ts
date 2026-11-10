import { z } from '@parklink/contracts';
import { transaction, inbox, pool } from '@parklink/runtime';
import type { Message } from '@parklink/contracts';
export const SearchSchema=z.object({
 latitude:z.coerce.number().min(-90).max(90),longitude:z.coerce.number().min(-180).max(180),
 radius:z.coerce.number().positive().max(50000).default(1000), maxRate:z.coerce.number().int().positive().optional(),
 text:z.string().max(100).default(''),feature:z.enum(['covered','security','ev','accessible']).optional(),
 start:z.string().datetime({offset:true}).optional(),end:z.string().datetime({offset:true}).optional(),
  limit:z.coerce.number().int().min(1).max(100).default(50),sort:z.enum(['nearest','cheapest']).default('nearest')
}).strict().refine(p=>(!p.start&&!p.end)||(!!p.start&&!!p.end&&Date.parse(p.start)<Date.parse(p.end)),{message:'Provide a valid start and end together'});
export class Discovery {
 async project(m:Message) {
  await transaction(async tx=>{
   if(!await inbox(tx,m.id))return; const p=m.payload;
   if(m.type==='supply.revision-accepted.v1') {
    await tx.query(`INSERT INTO space_documents(id,revision,body,location) VALUES($1,$2,$3,ST_SetSRID(ST_MakePoint($4,$5),4326)::geography)
      ON CONFLICT(id) DO UPDATE SET revision=EXCLUDED.revision,body=EXCLUDED.body,location=EXCLUDED.location,updated_at=now() WHERE space_documents.revision<EXCLUDED.revision`,[p.spaceId,p.revision,p,p.longitude,p.latitude]);
   }else await tx.query(`INSERT INTO reservation_windows(id,space_id,version,start_time,end_time,status,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT(id) DO UPDATE SET version=EXCLUDED.version,start_time=EXCLUDED.start_time,end_time=EXCLUDED.end_time,status=EXCLUDED.status,expires_at=EXCLUDED.expires_at WHERE reservation_windows.version<EXCLUDED.version`,[p.reservationId,p.spaceId,p.version,p.start,p.end,p.status,p.expiresAt]);
  });
 }
  async search(input:unknown,actorId?:string){
  const p=SearchSchema.parse(input);
  const result=await pool.query(`SELECT id,body,revision,updated_at,ST_Distance(location,ST_SetSRID(ST_MakePoint($1,$2),4326)::geography) AS distance_m
   FROM space_documents s WHERE (body->>'active')::boolean AND ($11::uuid IS NULL OR (body->>'ownerId')::uuid<>$11) AND ST_DWithin(location,ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,$3)
   AND ($4::integer IS NULL OR (body->>'hourlyRate')::integer<=$4) AND ($5='' OR body->>'title' ILIKE '%'||$5||'%' OR body->>'address' ILIKE '%'||$5||'%')
   AND ($6::text IS NULL OR body->'features' ? $6)
   AND ($7::timestamptz IS NULL OR (EXISTS(SELECT 1 FROM jsonb_array_elements(body->'windows') w WHERE (w->>'start')::timestamptz<=$7 AND (w->>'end')::timestamptz>=$8)
      AND NOT EXISTS(SELECT 1 FROM reservation_windows r WHERE r.space_id=s.id AND r.status IN ('PENDING_PAYMENT','CONFIRMED','ACTIVE') AND (r.status<>'PENDING_PAYMENT' OR r.expires_at>now()) AND tstzrange(r.start_time,r.end_time,'[)') && tstzrange($7,$8,'[)'))))
   ORDER BY CASE WHEN $10='cheapest' THEN (body->>'hourlyRate')::integer END,distance_m,id LIMIT $9`,[p.longitude,p.latitude,p.radius,p.maxRate??null,p.text,p.feature??null,p.start??null,p.end??null,p.limit,p.sort,actorId??null]);
  return { items:result.rows, informationalOnly:true, observedAt:new Date().toISOString() };
 }
}

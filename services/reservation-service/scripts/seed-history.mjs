import {pool,transaction,enqueue} from '@parklink/runtime';
import {z} from '@parklink/contracts';
if(process.env.NODE_ENV==='production'||process.env.ALLOW_FIXTURE_SEED!=='true')throw new Error('Explicit local fixture import required');
let raw='';for await(const part of process.stdin)raw+=part;
const rows=z.array(z.object({id:z.uuid(),spaceId:z.uuid(),ownerId:z.uuid(),driverId:z.uuid(),start:z.iso.datetime(),end:z.iso.datetime(),amount:z.number().int().positive(),hourlyRate:z.number().int().positive(),status:z.enum(['COMPLETED','ACTIVE','EXPIRED']),paymentId:z.uuid().nullable(),attemptId:z.uuid().nullable(),code:z.string().startsWith('DEMO-'),createdAt:z.iso.datetime(),correlationId:z.uuid()}).strict()).max(1000).parse(JSON.parse(raw));
let inserted=0;
for(const r of rows)await transaction(async tx=>{
 await tx.query('SELECT pg_advisory_xact_lock(hashtext($1))',[r.spaceId]);
 const snapshot=(await tx.query('SELECT revision,owner_id FROM space_snapshots WHERE id=$1',[r.spaceId])).rows[0];if(!snapshot||snapshot.owner_id!==r.ownerId)throw new Error('Fixture space ownership mismatch');
 const result=await tx.query(`INSERT INTO reservations(id,space_id,driver_id,owner_id,start_time,end_time,amount,hourly_rate,supply_revision,status,expires_at,code,payment_id,payment_attempt,created_at)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) ON CONFLICT(id) DO NOTHING RETURNING id`,[r.id,r.spaceId,r.driverId,r.ownerId,r.start,r.end,r.amount,r.hourlyRate,snapshot.revision,r.status,new Date(Date.parse(r.createdAt)+600000),r.code,r.paymentId,r.attemptId,r.createdAt]);
 if(!result.rowCount)return;inserted++;
 await tx.query('INSERT INTO reservation_history(reservation_id,status,correlation_id,at) VALUES($1,$2,$3,$4)',[r.id,r.status,r.correlationId,r.createdAt]);
 await enqueue(tx,`reservation.${r.status.toLowerCase()}.v1`,{reservationId:r.id,spaceId:r.spaceId,driverId:r.driverId,ownerId:r.ownerId,start:r.start,end:r.end,status:r.status,version:1,expiresAt:new Date(Date.parse(r.createdAt)+600000).toISOString(),amount:r.amount,code:r.code,reason:'development_fixture'},r.driverId,r.correlationId);
});
await pool.end();console.log(JSON.stringify({service:'reservation',fixturesInserted:inserted}));

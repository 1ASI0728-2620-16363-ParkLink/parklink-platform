import {pool,transaction,enqueue} from '@parklink/runtime';
import {z} from '@parklink/contracts';
if(process.env.NODE_ENV==='production'||process.env.ALLOW_FIXTURE_SEED!=='true'||process.env.PAYMENT_PROVIDER!=='sandbox')throw new Error('Fixtures require explicit local sandbox mode');
let raw='';for await(const part of process.stdin)raw+=part;
const rows=z.array(z.object({id:z.uuid(),ownerId:z.uuid(),driverId:z.uuid(),amount:z.number().int().positive(),paymentId:z.uuid().nullable(),attemptId:z.uuid().nullable(),createdAt:z.iso.datetime(),correlationId:z.uuid()}).passthrough()).max(1000).parse(JSON.parse(raw));
let inserted=0;
for(const r of rows){if(!r.paymentId)continue;await transaction(async tx=>{
 const result=await tx.query(`INSERT INTO payments(id,attempt_id,reservation_id,driver_id,owner_id,amount,currency,status,provider,reference,scenario,correlation_id,created_at,updated_at)
 VALUES($1,$2,$3,$4,$5,$6,'PEN','APPROVED','sandbox',$7,'approved',$8,$9,$9) ON CONFLICT(id) DO NOTHING RETURNING id`,[r.paymentId,r.attemptId,r.id,r.driverId,r.ownerId,r.amount,`seed-sandbox-${r.paymentId}`,r.correlationId,r.createdAt]);
 if(!result.rowCount)return;inserted++;
 await enqueue(tx,'payment.fixture-imported.v1',{paymentId:r.paymentId,reservationId:r.id,driverId:r.driverId,ownerId:r.ownerId,amount:r.amount,currency:'PEN',provider:'sandbox',reason:'development_fixture'},r.driverId,r.correlationId);
});}
await pool.end();console.log(JSON.stringify({service:'payment',fixturesInserted:inserted}));

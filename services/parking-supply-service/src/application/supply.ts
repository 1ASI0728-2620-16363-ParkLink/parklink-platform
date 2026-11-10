import { randomUUID } from 'node:crypto';
import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { SpaceSchema, type Actor, type Message } from '@parklink/contracts';
import { pool, transaction, enqueue, inbox, role, owns } from '@parklink/runtime';
import { validWindows } from '../domain/schedule';
export class Supply {
  async save(input: unknown, actor: Actor, correlationId: string, id: string = randomUUID(), expectedRevision?: number) {
    role(actor, 'OWNER'); const body = SpaceSchema.parse(input);
    if (!validWindows(body.windows)) throw new BadRequestException('Availability windows must be valid and non-overlapping');
    return transaction(async tx => {
      const previous = (await tx.query('SELECT * FROM spaces WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (expectedRevision !== undefined && !previous) throw new NotFoundException();
      if (previous) { owns(actor, previous.owner_id); if (previous.state === 'REVIEWING' || previous.revision !== expectedRevision) throw new ConflictException('Wait for revision acceptance or reload space'); }
      const revision = previous ? previous.revision + 1 : 1;
      await tx.query(`INSERT INTO spaces(id,owner_id,revision,body,state) VALUES($1,$2,$3,$4,'REVIEWING')
        ON CONFLICT(id) DO UPDATE SET revision=$3,body=$4,state='REVIEWING',rejection=NULL`, [id, actor.id, revision, body]);
      await enqueue(tx, 'supply.revision-proposed.v1', { spaceId: id, ownerId: actor.id, revision, ...body }, actor.id, correlationId);
      return { id, revision, state: 'REVIEWING' };
    });
  }
  async outcome(m: Message) {
    await transaction(async tx => {
      if (!await inbox(tx, m.id)) return;
      await tx.query(`UPDATE spaces SET state=$3,accepted_revision=CASE WHEN $3='PUBLISHED' THEN $2 ELSE accepted_revision END,rejection=$4
        WHERE id=$1 AND revision=$2`, [m.payload.spaceId, m.payload.revision, m.type === 'supply.revision-accepted.v1' ? 'PUBLISHED' : 'REJECTED', m.payload.reason ?? null]);
    });
  }
  async mine(actor: Actor) { role(actor, 'OWNER'); return (await pool.query('SELECT * FROM spaces WHERE owner_id=$1 ORDER BY created_at DESC', [actor.id])).rows; }
}

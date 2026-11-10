import { Pool, type PoolClient } from 'pg';
import { readdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

export const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 12, connectionTimeoutMillis: 5000, statement_timeout: 15000 });
pool.on('error', () => console.error(JSON.stringify({ level: 'error', event: 'database_pool_error' })));
export type Tx = PoolClient;
export async function transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
  const tx = await pool.connect();
  try { await tx.query('BEGIN'); const result = await fn(tx); await tx.query('COMMIT'); return result; }
  catch (error) { await tx.query('ROLLBACK'); throw error; }
  finally { tx.release(); }
}
export async function migrate(directory = join(process.cwd(), 'migrations')) {
  await transaction(async tx => {
    await tx.query("SELECT pg_advisory_xact_lock(hashtext('parklink-migrations'))");
    await tx.query('CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())');
    for (const name of (await readdir(directory)).filter(n => n.endsWith('.sql')).sort()) {
      const sql = await readFile(join(directory, name), 'utf8');
      const checksum = createHash('sha256').update(sql).digest('hex');
      const previous = await tx.query('SELECT checksum FROM schema_migrations WHERE name=$1', [name]);
      if (previous.rowCount) { if (previous.rows[0].checksum !== checksum) throw new Error(`Migration modified: ${name}`); continue; }
      await tx.query(sql); await tx.query('INSERT INTO schema_migrations(name,checksum) VALUES($1,$2)', [name, checksum]);
    }
  });
}
export async function commonSchema() {
  await pool.query(`CREATE TABLE IF NOT EXISTS outbox (
    id uuid PRIMARY KEY, exchange text NOT NULL, routing_key text NOT NULL, message jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), published_at timestamptz);
    CREATE INDEX IF NOT EXISTS outbox_pending ON outbox(created_at) WHERE published_at IS NULL;
    CREATE TABLE IF NOT EXISTS inbox (id uuid PRIMARY KEY, processed_at timestamptz NOT NULL DEFAULT now());`);
}

import { Pool } from 'pg';

const connectionString = process.env.SUPABASE_DB_URL ?? process.env.DATABASE_URL;

if (!connectionString) {
  // Allow module import for tests/docs; runtime callers should still supply a DB URL.
  // eslint-disable-next-line no-console
  console.warn('[Sentinel] DATABASE_URL/SUPABASE_DB_URL is not set.');
}

export const pool = new Pool({
  connectionString,
  max: Number(process.env.DB_POOL_MAX ?? 10),
  ssl:
    process.env.DB_SSL === 'disable'
      ? false
      : process.env.NODE_ENV === 'development'
        ? false
        : { rejectUnauthorized: false },
});

export async function query(text, params = []) {
  return pool.query(text, params);
}

export async function withTransaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

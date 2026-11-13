import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Pool, type QueryResultRow } from 'pg';

import { SCHEMA_SQL } from './schema';

export type DataBackend = 'firestore' | 'postgres' | 'disk';

@Injectable()
export class DbService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DbService.name);
  private pool: Pool | null = null;
  private ready = false;

  /** Resolved at boot from DATA_BACKEND (default postgres for local, firestore for shared tests). */
  get backendPreference(): DataBackend {
    const raw = (process.env.DATA_BACKEND ?? 'postgres').toLowerCase();
    if (raw === 'firestore' || raw === 'postgres' || raw === 'disk') return raw;
    return 'postgres';
  }

  get enabled() {
    return this.ready && this.pool != null;
  }

  async onModuleInit() {
    if (this.backendPreference === 'firestore') {
      this.logger.log('DATA_BACKEND=firestore — skipping local PostgreSQL.');
      return;
    }
    if (this.backendPreference === 'disk') {
      this.logger.log('DATA_BACKEND=disk — using JSON file fallbacks only.');
      return;
    }

    const url = process.env.DATABASE_URL?.trim();
    if (!url) {
      this.logger.warn('DATABASE_URL not set — API will use in-memory / JSON fallbacks.');
      return;
    }
    this.pool = new Pool({
      connectionString: url,
      max: 10,
      idleTimeoutMillis: 30_000,
    });
    try {
      await this.pool.query('SELECT 1');
      await this.migrate();
      this.ready = true;
      this.logger.log('PostgreSQL connected and schema ready.');
    } catch (error) {
      this.ready = false;
      this.logger.error(`PostgreSQL unavailable — falling back. ${error}`);
      try {
        await this.pool.end();
      } catch (_) {
        /* ignore */
      }
      this.pool = null;
    }
  }

  async onModuleDestroy() {
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
      this.ready = false;
    }
  }

  private async migrate() {
    if (!this.pool) return;
    await this.pool.query(SCHEMA_SQL);
  }

  async query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params?: unknown[],
  ) {
    if (!this.pool || !this.ready) {
      throw new Error('PostgreSQL is not available');
    }
    return this.pool.query<T>(text, params);
  }

  async health(): Promise<{ ok: boolean; detail?: string }> {
    if (!this.pool || !this.ready) {
      return { ok: false, detail: 'not configured or not connected' };
    }
    try {
      await this.pool.query('SELECT 1');
      return { ok: true };
    } catch (error) {
      return { ok: false, detail: String(error) };
    }
  }
}

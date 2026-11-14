import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';
import type {
  ReconciliationException,
  ReconciliationRun,
  SettlementBatch,
} from './reconciliation.types';

@Injectable()
export class ReconciliationStore implements OnModuleInit {
  private readonly logger = new Logger(ReconciliationStore.name);
  private readonly dataFile = join(process.cwd(), '.data', 'finance-reconciliation.json');
  private readonly batches = new Map<string, SettlementBatch>();
  private readonly exceptions = new Map<string, ReconciliationException>();
  private readonly runs = new Map<string, ReconciliationRun>();

  constructor(
    @Inject(DbService) private readonly db: DbService,
    @Inject(FirestoreService) private readonly fs: FirestoreService,
  ) {}

  async onModuleInit() {
    if (this.fs.enabled) {
      await this.loadFromFirestore();
      return;
    }
    if (this.db.enabled) {
      await this.loadFromDb();
      return;
    }
    this.loadFromDisk();
  }

  listBatches(): SettlementBatch[] {
    return [...this.batches.values()].sort((a, b) => b.importedAt.localeCompare(a.importedAt));
  }

  getBatch(id: string): SettlementBatch | undefined {
    return this.batches.get(id);
  }

  saveBatch(batch: SettlementBatch) {
    this.batches.set(batch.id, batch);
    void this.persist('finance_settlement_batches', batch.id, batch);
  }

  listExceptions(status?: ReconciliationException['status']): ReconciliationException[] {
    const all = [...this.exceptions.values()].sort((a, b) =>
      b.createdAt.localeCompare(a.createdAt),
    );
    return status ? all.filter((e) => e.status === status) : all;
  }

  getException(id: string): ReconciliationException | undefined {
    return this.exceptions.get(id);
  }

  saveException(row: ReconciliationException) {
    this.exceptions.set(row.id, row);
    void this.persist('finance_reconciliation_exceptions', row.id, row);
  }

  listRuns(): ReconciliationRun[] {
    return [...this.runs.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  getRun(id: string): ReconciliationRun | undefined {
    return this.runs.get(id);
  }

  saveRun(run: ReconciliationRun) {
    this.runs.set(run.id, run);
    void this.persist('finance_reconciliation_runs', run.id, run);
  }

  private loadFromDisk() {
    try {
      if (!existsSync(this.dataFile)) return;
      const raw = JSON.parse(readFileSync(this.dataFile, 'utf8')) as {
        batches?: SettlementBatch[];
        exceptions?: ReconciliationException[];
        runs?: ReconciliationRun[];
      };
      for (const b of raw.batches ?? []) this.batches.set(b.id, b);
      for (const e of raw.exceptions ?? []) this.exceptions.set(e.id, e);
      for (const r of raw.runs ?? []) this.runs.set(r.id, r);
      this.logger.log(
        `Loaded reconciliation: ${this.batches.size} batch(es), ${this.exceptions.size} exception(s)`,
      );
    } catch (error) {
      this.logger.warn(`Failed to load reconciliation store: ${error}`);
    }
  }

  private persistDisk() {
    try {
      mkdirSync(dirname(this.dataFile), { recursive: true });
      writeFileSync(
        this.dataFile,
        JSON.stringify(
          {
            batches: [...this.batches.values()],
            exceptions: [...this.exceptions.values()],
            runs: [...this.runs.values()],
          },
          null,
          2,
        ),
        'utf8',
      );
    } catch (error) {
      this.logger.warn(`Failed to persist reconciliation store: ${error}`);
    }
  }

  private async loadFromFirestore() {
    try {
      const batches = await this.fs.list<{ payload: SettlementBatch }>(
        'finance_settlement_batches',
      );
      for (const row of batches) {
        if (row.payload?.id) this.batches.set(row.payload.id, row.payload);
      }
      const exceptions = await this.fs.list<{ payload: ReconciliationException }>(
        'finance_reconciliation_exceptions',
      );
      for (const row of exceptions) {
        if (row.payload?.id) this.exceptions.set(row.payload.id, row.payload);
      }
      const runs = await this.fs.list<{ payload: ReconciliationRun }>(
        'finance_reconciliation_runs',
      );
      for (const row of runs) {
        if (row.payload?.id) this.runs.set(row.payload.id, row.payload);
      }
      this.logger.log(
        `Loaded reconciliation from Firestore: ${this.batches.size} batch(es)`,
      );
    } catch (error) {
      this.logger.warn(`Failed to load reconciliation from Firestore: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      for (const table of [
        'finance_settlement_batches',
        'finance_reconciliation_exceptions',
        'finance_reconciliation_runs',
      ] as const) {
        const result = await this.db.query<{ id: string; payload: unknown }>(
          `SELECT id, payload FROM ${table}`,
        );
        for (const row of result.rows) {
          const payload = row.payload as { id?: string };
          if (!payload?.id) continue;
          if (table === 'finance_settlement_batches') {
            this.batches.set(payload.id, payload as SettlementBatch);
          } else if (table === 'finance_reconciliation_exceptions') {
            this.exceptions.set(payload.id, payload as ReconciliationException);
          } else {
            this.runs.set(payload.id, payload as ReconciliationRun);
          }
        }
      }
    } catch (error) {
      this.logger.warn(`Failed to load reconciliation from Postgres: ${error}`);
    }
  }

  private async persist(collection: string, id: string, payload: unknown) {
    if (this.fs.enabled) {
      try {
        await this.fs.set(collection, id, { payload });
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist ${collection}/${id} to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        await this.db.query(
          `INSERT INTO ${collection} (id, payload, updated_at)
           VALUES ($1, $2::jsonb, NOW())
           ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()`,
          [id, JSON.stringify(payload)],
        );
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist ${collection}/${id} to Postgres: ${error}`);
      }
    }
    this.persistDisk();
  }
}

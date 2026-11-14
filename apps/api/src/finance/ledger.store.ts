import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';
import type { LedgerJournal, Subscription, SubscriptionPlan } from './finance.types';

@Injectable()
export class LedgerStore implements OnModuleInit {
  private readonly logger = new Logger(LedgerStore.name);
  private readonly dataFile = join(process.cwd(), '.data', 'finance-ledger.json');
  private readonly journals: LedgerJournal[] = [];
  private readonly subscriptions = new Map<string, Subscription>();
  /** Intent / reference ids already settled — settlement idempotency. */
  private readonly settledRefs = new Set<string>();

  readonly plans: SubscriptionPlan[] = [
    {
      id: 'listen_plus_monthly_zmw',
      name: 'Listen+ Monthly',
      currency: 'ZMW',
      amountMinor: 49_00,
      interval: 'month',
      markets: ['ZM'],
    },
    {
      id: 'listen_plus_monthly_usd',
      name: 'Listen+ Monthly',
      currency: 'USD',
      amountMinor: 4_99,
      interval: 'month',
      markets: ['US', 'GLOBAL'],
    },
  ];

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

  listJournals(): LedgerJournal[] {
    return [...this.journals];
  }

  hasSettled(referenceType: string, referenceId: string): boolean {
    return this.settledRefs.has(`${referenceType}:${referenceId}`);
  }

  appendJournal(journal: LedgerJournal) {
    this.journals.unshift(journal);
    this.settledRefs.add(`${journal.referenceType}:${journal.referenceId}`);
    void this.persistJournal(journal);
  }

  getPlan(planId: string): SubscriptionPlan | undefined {
    return this.plans.find((p) => p.id === planId);
  }

  listPlans(currency?: string): SubscriptionPlan[] {
    if (!currency) return [...this.plans];
    return this.plans.filter((p) => p.currency === currency);
  }

  getSubscription(id: string): Subscription | undefined {
    return this.subscriptions.get(id);
  }

  getActiveSubscriptionForUser(uid: string): Subscription | undefined {
    const now = Date.now();
    return [...this.subscriptions.values()].find(
      (s) =>
        s.uid === uid &&
        s.status === 'active' &&
        new Date(s.currentPeriodEnd).getTime() > now,
    );
  }

  saveSubscription(sub: Subscription) {
    this.subscriptions.set(sub.id, sub);
    void this.persistSubscription(sub);
  }

  private loadFromDisk() {
    try {
      if (!existsSync(this.dataFile)) return;
      const raw = JSON.parse(readFileSync(this.dataFile, 'utf8')) as {
        journals?: LedgerJournal[];
        subscriptions?: Subscription[];
        settledRefs?: string[];
      };
      for (const j of raw.journals ?? []) this.journals.push(j);
      for (const s of raw.subscriptions ?? []) this.subscriptions.set(s.id, s);
      for (const r of raw.settledRefs ?? []) this.settledRefs.add(r);
      this.logger.log(`Loaded ${this.journals.length} ledger journal(s) from disk`);
    } catch (error) {
      this.logger.warn(`Failed to load finance ledger: ${error}`);
    }
  }

  private persistDisk() {
    try {
      mkdirSync(dirname(this.dataFile), { recursive: true });
      writeFileSync(
        this.dataFile,
        JSON.stringify(
          {
            journals: this.journals,
            subscriptions: [...this.subscriptions.values()],
            settledRefs: [...this.settledRefs],
          },
          null,
          2,
        ),
        'utf8',
      );
    } catch (error) {
      this.logger.warn(`Failed to persist finance ledger: ${error}`);
    }
  }

  private async loadFromFirestore() {
    try {
      const journals = await this.fs.list<{ payload: LedgerJournal }>('finance_journals');
      journals.sort((a, b) => (b.payload?.at ?? '').localeCompare(a.payload?.at ?? ''));
      for (const row of journals) {
        if (row.payload?.id) {
          this.journals.push(row.payload);
          this.settledRefs.add(`${row.payload.referenceType}:${row.payload.referenceId}`);
        }
      }
      const subs = await this.fs.list<{ payload: Subscription }>('finance_subscriptions');
      for (const row of subs) {
        if (row.payload?.id) this.subscriptions.set(row.payload.id, row.payload);
      }
      this.logger.log(`Loaded ${this.journals.length} ledger journal(s) from Firestore`);
    } catch (error) {
      this.logger.warn(`Failed to load finance ledger from Firestore: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      const journals = await this.db.query<{ payload: LedgerJournal }>(
        'SELECT payload FROM finance_journals ORDER BY created_at DESC',
      );
      for (const row of journals.rows) {
        if (row.payload?.id) {
          this.journals.push(row.payload);
          this.settledRefs.add(`${row.payload.referenceType}:${row.payload.referenceId}`);
        }
      }
      const subs = await this.db.query<{ payload: Subscription }>(
        'SELECT payload FROM finance_subscriptions',
      );
      for (const row of subs.rows) {
        if (row.payload?.id) this.subscriptions.set(row.payload.id, row.payload);
      }
      this.logger.log(`Loaded ${this.journals.length} ledger journal(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load finance ledger from Postgres: ${error}`);
    }
  }

  private async persistJournal(journal: LedgerJournal) {
    if (this.fs.enabled) {
      try {
        await this.fs.set('finance_journals', journal.id, { payload: journal });
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist journal to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        await this.db.query(
          `INSERT INTO finance_journals (id, kind, currency, reference_type, reference_id, payload, created_at)
           VALUES ($1, $2, $3, $4, $5, $6::jsonb, NOW())
           ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload`,
          [
            journal.id,
            journal.kind,
            journal.currency,
            journal.referenceType,
            journal.referenceId,
            JSON.stringify(journal),
          ],
        );
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist journal to Postgres: ${error}`);
      }
    }
    this.persistDisk();
  }

  private async persistSubscription(sub: Subscription) {
    if (this.fs.enabled) {
      try {
        await this.fs.set('finance_subscriptions', sub.id, { payload: sub });
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist subscription to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        await this.db.query(
          `INSERT INTO finance_subscriptions (id, uid, plan_id, status, payload, updated_at)
           VALUES ($1, $2, $3, $4, $5::jsonb, NOW())
           ON CONFLICT (id) DO UPDATE SET
             uid = EXCLUDED.uid,
             plan_id = EXCLUDED.plan_id,
             status = EXCLUDED.status,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [sub.id, sub.uid, sub.planId, sub.status, JSON.stringify(sub)],
        );
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist subscription to Postgres: ${error}`);
      }
    }
    this.persistDisk();
  }
}

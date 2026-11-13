import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';

export type PaymentIntentStatus =
  | 'requires_confirmation'
  | 'processing'
  | 'succeeded'
  | 'failed'
  | 'cancelled';

export interface PaymentIntent {
  id: string;
  uid: string;
  titleId: string;
  amountMinor: number;
  currency: string;
  status: PaymentIntentStatus;
  provider: string;
  createdAt: string;
  updatedAt: string;
  providerRef?: string;
  failureReason?: string;
}

@Injectable()
export class PaymentsStore implements OnModuleInit {
  private readonly logger = new Logger(PaymentsStore.name);
  private readonly dataFile = join(process.cwd(), '.data', 'payments.json');
  private readonly intents = new Map<string, PaymentIntent>();
  /** Processed webhook event ids for idempotency. */
  private readonly processedEvents = new Set<string>();

  constructor(
    @Inject(DbService) private readonly db: DbService,
    @Inject(FirestoreService) private readonly fs: FirestoreService,
  ) {}

  async onModuleInit() {
    if (this.fs.enabled) {
      await this.loadFromFirestore();
      if (this.intents.size === 0) {
        this.loadFromDisk();
        if (this.intents.size > 0) await this.persistAllToFirestore();
      }
      return;
    }
    if (this.db.enabled) {
      await this.loadFromDb();
      if (this.intents.size === 0) {
        this.loadFromDisk();
        if (this.intents.size > 0) await this.persistAllToDb();
      }
      return;
    }
    this.loadFromDisk();
  }

  create(input: {
    uid: string;
    titleId: string;
    amountMinor: number;
    currency: string;
  }): PaymentIntent {
    const now = new Date().toISOString();
    const intent: PaymentIntent = {
      id: `pi_${randomUUID().replace(/-/g, '').slice(0, 24)}`,
      uid: input.uid,
      titleId: input.titleId,
      amountMinor: input.amountMinor,
      currency: input.currency || 'ZMW',
      status: 'requires_confirmation',
      provider: 'simulate',
      createdAt: now,
      updatedAt: now,
    };
    this.intents.set(intent.id, intent);
    void this.persistOne(intent);
    return intent;
  }

  get(id: string): PaymentIntent | undefined {
    return this.intents.get(id);
  }

  mark(
    id: string,
    status: PaymentIntentStatus,
    extras?: { providerRef?: string; failureReason?: string },
  ): PaymentIntent | null {
    const intent = this.intents.get(id);
    if (!intent) return null;
    intent.status = status;
    intent.updatedAt = new Date().toISOString();
    if (extras?.providerRef) intent.providerRef = extras.providerRef;
    if (extras?.failureReason) intent.failureReason = extras.failureReason;
    void this.persistOne(intent);
    return intent;
  }

  hasProcessedEvent(eventId: string): boolean {
    return this.processedEvents.has(eventId);
  }

  markEventProcessed(eventId: string) {
    this.processedEvents.add(eventId);
    void this.persistEvent(eventId);
  }

  private loadFromDisk() {
    try {
      if (!existsSync(this.dataFile)) return;
      const raw = JSON.parse(readFileSync(this.dataFile, 'utf8')) as {
        intents?: PaymentIntent[];
        events?: string[];
      };
      for (const intent of raw.intents ?? []) this.intents.set(intent.id, intent);
      for (const eventId of raw.events ?? []) this.processedEvents.add(eventId);
      this.logger.log(`Loaded ${this.intents.size} payment intent(s) from disk`);
    } catch (error) {
      this.logger.warn(`Failed to load payments: ${error}`);
    }
  }

  private persistDisk() {
    try {
      mkdirSync(dirname(this.dataFile), { recursive: true });
      writeFileSync(
        this.dataFile,
        JSON.stringify(
          {
            intents: [...this.intents.values()],
            events: [...this.processedEvents],
          },
          null,
          2,
        ),
        'utf8',
      );
    } catch (error) {
      this.logger.warn(`Failed to persist payments: ${error}`);
    }
  }

  private async loadFromFirestore() {
    try {
      const intents = await this.fs.list<{ payload: PaymentIntent }>('payment_intents');
      for (const row of intents) {
        const intent = row.payload;
        if (intent?.id) this.intents.set(intent.id, intent);
      }
      const events = await this.fs.list<{ eventId?: string }>('payment_webhook_events');
      for (const row of events) this.processedEvents.add(row.eventId ?? row.id);
      this.logger.log(`Loaded ${this.intents.size} payment intent(s) from Firestore`);
    } catch (error) {
      this.logger.warn(`Failed to load payments from Firestore: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      const intents = await this.db.query<{ payload: PaymentIntent }>(
        'SELECT payload FROM payment_intents',
      );
      for (const row of intents.rows) {
        const intent = row.payload;
        if (intent?.id) this.intents.set(intent.id, intent);
      }
      const events = await this.db.query<{ event_id: string }>(
        'SELECT event_id FROM payment_webhook_events',
      );
      for (const row of events.rows) this.processedEvents.add(row.event_id);
      this.logger.log(`Loaded ${this.intents.size} payment intent(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load payments from Postgres: ${error}`);
    }
  }

  private async persistAllToFirestore() {
    for (const intent of this.intents.values()) await this.persistOne(intent);
    for (const eventId of this.processedEvents) await this.persistEvent(eventId);
  }

  private async persistAllToDb() {
    for (const intent of this.intents.values()) await this.persistOne(intent);
    for (const eventId of this.processedEvents) await this.persistEvent(eventId);
  }

  private async persistOne(intent: PaymentIntent) {
    if (this.fs.enabled) {
      try {
        await this.fs.set('payment_intents', intent.id, { payload: intent });
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist payment intent to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        await this.db.query(
          `INSERT INTO payment_intents (id, uid, title_id, status, payload, updated_at)
           VALUES ($1, $2, $3, $4, $5::jsonb, NOW())
           ON CONFLICT (id) DO UPDATE SET
             uid = EXCLUDED.uid,
             title_id = EXCLUDED.title_id,
             status = EXCLUDED.status,
             payload = EXCLUDED.payload,
             updated_at = NOW()`,
          [intent.id, intent.uid, intent.titleId, intent.status, JSON.stringify(intent)],
        );
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist payment intent to Postgres: ${error}`);
      }
    }
    this.persistDisk();
  }

  private async persistEvent(eventId: string) {
    if (this.fs.enabled) {
      try {
        await this.fs.set('payment_webhook_events', eventId, { eventId });
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist webhook event to Firestore: ${error}`);
      }
    }
    if (this.db.enabled) {
      try {
        await this.db.query(
          `INSERT INTO payment_webhook_events (event_id, processed_at)
           VALUES ($1, NOW())
           ON CONFLICT (event_id) DO NOTHING`,
          [eventId],
        );
        return;
      } catch (error) {
        this.logger.warn(`Failed to persist webhook event: ${error}`);
      }
    }
    this.persistDisk();
  }
}

import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';

import { DbService } from '../db/db.service';
import { FirestoreService } from '../db/firestore.service';
import {
  PriceByCurrency,
  SaleRow,
  SalesDashboard,
  StudioChapter,
  StudioDraft,
  StudioDraftStatus,
  StudioEpisode,
  StudioFormat,
} from './studio.types';

@Injectable()
export class StudioStore implements OnModuleInit {
  private readonly logger = new Logger(StudioStore.name);
  private readonly dataFile = join(process.cwd(), '.data', 'studio-drafts.json');
  private readonly salesFile = join(process.cwd(), '.data', 'studio-sales.json');
  private drafts: StudioDraft[] = [];
  private sales: SaleRow[] = [];

  constructor(
    @Inject(DbService) private readonly db: DbService,
    @Inject(FirestoreService) private readonly fs: FirestoreService,
  ) {}

  async onModuleInit() {
    if (this.fs.enabled) {
      await this.loadFromFirestore();
      if (this.drafts.length === 0 && this.sales.length === 0) {
        this.loadFromDisk();
        if (this.drafts.length > 0 || this.sales.length > 0) {
          await this.persistAllToFirestore();
          this.logger.log(
            `Migrated ${this.drafts.length} draft(s) and ${this.sales.length} sale(s) disk → Firestore`,
          );
        }
      }
      return;
    }
    if (this.db.enabled) {
      await this.loadFromDb();
      if (this.drafts.length === 0 && this.sales.length === 0) {
        this.loadFromDisk();
        if (this.drafts.length > 0 || this.sales.length > 0) {
          await this.persistAllToDb();
          this.logger.log(
            `Migrated ${this.drafts.length} draft(s) and ${this.sales.length} sale(s) disk → Postgres`,
          );
        }
      }
      return;
    }
    this.loadFromDisk();
  }

  private loadFromDisk() {
    try {
      if (!existsSync(this.dataFile)) return;
      const raw = JSON.parse(readFileSync(this.dataFile, 'utf8')) as { drafts?: StudioDraft[] };
      if (Array.isArray(raw.drafts)) {
        this.drafts = raw.drafts;
        this.logger.log(`Loaded ${this.drafts.length} studio draft(s) from disk`);
      }
    } catch (error) {
      this.logger.warn(`Failed to load studio drafts: ${error}`);
    }
    try {
      if (!existsSync(this.salesFile)) return;
      const raw = JSON.parse(readFileSync(this.salesFile, 'utf8')) as { sales?: SaleRow[] };
      if (Array.isArray(raw.sales)) {
        this.sales = raw.sales;
        this.logger.log(`Loaded ${this.sales.length} sale row(s) from disk`);
      }
    } catch (error) {
      this.logger.warn(`Failed to load studio sales: ${error}`);
    }
  }

  private async loadFromFirestore() {
    try {
      const drafts = await this.fs.list<{ payload: StudioDraft }>('studio_drafts');
      this.drafts = drafts
        .map((row) => row.payload)
        .filter(Boolean)
        .sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
      this.logger.log(`Loaded ${this.drafts.length} studio draft(s) from Firestore`);
    } catch (error) {
      this.logger.warn(`Failed to load studio drafts from Firestore: ${error}`);
    }
    try {
      const sales = await this.fs.list<{ payload: SaleRow }>('studio_sales');
      this.sales = sales
        .map((row) => row.payload)
        .filter(Boolean)
        .sort((a, b) => (a.at < b.at ? 1 : -1));
      this.logger.log(`Loaded ${this.sales.length} sale row(s) from Firestore`);
    } catch (error) {
      this.logger.warn(`Failed to load studio sales from Firestore: ${error}`);
    }
  }

  private async loadFromDb() {
    try {
      const drafts = await this.db.query<{ payload: StudioDraft }>(
        'SELECT payload FROM studio_drafts ORDER BY updated_at DESC',
      );
      this.drafts = drafts.rows.map((row) => row.payload);
      this.logger.log(`Loaded ${this.drafts.length} studio draft(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load studio drafts from Postgres: ${error}`);
    }
    try {
      const sales = await this.db.query<{ payload: SaleRow }>(
        'SELECT payload FROM studio_sales ORDER BY created_at DESC',
      );
      this.sales = sales.rows.map((row) => row.payload);
      this.logger.log(`Loaded ${this.sales.length} sale row(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load studio sales from Postgres: ${error}`);
    }
  }

  private persistDisk() {
    try {
      mkdirSync(dirname(this.dataFile), { recursive: true });
      writeFileSync(this.dataFile, JSON.stringify({ drafts: this.drafts }, null, 2), 'utf8');
    } catch (error) {
      this.logger.warn(`Failed to persist studio drafts: ${error}`);
    }
  }

  private persistSalesDisk() {
    try {
      mkdirSync(dirname(this.salesFile), { recursive: true });
      writeFileSync(this.salesFile, JSON.stringify({ sales: this.sales }, null, 2), 'utf8');
    } catch (error) {
      this.logger.warn(`Failed to persist studio sales: ${error}`);
    }
  }

  private async upsertDraftFs(draft: StudioDraft) {
    await this.fs.set('studio_drafts', draft.id, { payload: draft });
  }

  private async upsertSaleFs(sale: SaleRow) {
    await this.fs.set('studio_sales', sale.id, { payload: sale });
  }

  private async persistAllToFirestore() {
    for (const draft of this.drafts) await this.upsertDraftFs(draft);
    for (const sale of this.sales) await this.upsertSaleFs(sale);
  }

  private async upsertDraft(draft: StudioDraft) {
    await this.db.query(
      `INSERT INTO studio_drafts (id, payload, updated_at)
       VALUES ($1, $2::jsonb, NOW())
       ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()`,
      [draft.id, JSON.stringify(draft)],
    );
  }

  private async upsertSale(sale: SaleRow) {
    await this.db.query(
      `INSERT INTO studio_sales (id, payload, created_at)
       VALUES ($1, $2::jsonb, $3)
       ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload`,
      [sale.id, JSON.stringify(sale), sale.at],
    );
  }

  private async persistAllToDb() {
    for (const draft of this.drafts) await this.upsertDraft(draft);
    for (const sale of this.sales) await this.upsertSale(sale);
  }

  private persist() {
    if (this.fs.enabled) {
      void Promise.all(this.drafts.map((d) => this.upsertDraftFs(d))).catch((error) =>
        this.logger.warn(`Failed to persist studio drafts to Firestore: ${error}`),
      );
      return;
    }
    if (this.db.enabled) {
      void Promise.all(this.drafts.map((d) => this.upsertDraft(d))).catch((error) =>
        this.logger.warn(`Failed to persist studio drafts to Postgres: ${error}`),
      );
      return;
    }
    this.persistDisk();
  }

  private persistDraft(draft: StudioDraft) {
    if (this.fs.enabled) {
      void this.upsertDraftFs(draft).catch((error) =>
        this.logger.warn(`Failed to persist draft to Firestore: ${error}`),
      );
      return;
    }
    if (this.db.enabled) {
      void this.upsertDraft(draft).catch((error) =>
        this.logger.warn(`Failed to persist draft to Postgres: ${error}`),
      );
      return;
    }
    this.persistDisk();
  }

  private persistDeleteDraft(id: string) {
    if (this.fs.enabled) {
      void this.fs
        .delete('studio_drafts', id)
        .catch((error) => this.logger.warn(`Failed to delete draft in Firestore: ${error}`));
      return;
    }
    if (this.db.enabled) {
      void this.db
        .query('DELETE FROM studio_drafts WHERE id = $1', [id])
        .catch((error) => this.logger.warn(`Failed to delete draft in Postgres: ${error}`));
      return;
    }
    this.persistDisk();
  }

  private persistSales() {
    if (this.fs.enabled) {
      const latest = this.sales[0];
      if (latest) {
        void this.upsertSaleFs(latest).catch((error) =>
          this.logger.warn(`Failed to persist sale to Firestore: ${error}`),
        );
      }
      return;
    }
    if (this.db.enabled) {
      const latest = this.sales[0];
      if (latest) {
        void this.upsertSale(latest).catch((error) =>
          this.logger.warn(`Failed to persist sale to Postgres: ${error}`),
        );
      }
      return;
    }
    this.persistSalesDisk();
  }

  listDrafts(creatorUid: string, email?: string) {
    const normalized = email?.trim().toLowerCase();
    return this.drafts.filter(
      (d) =>
        d.creatorUid === creatorUid ||
        (normalized != null &&
          normalized.length > 0 &&
          d.creatorEmail.toLowerCase() === normalized),
    );
  }

  /** Rebind drafts when /me links a seed/demo uid to the live Firebase uid. */
  rebindCreatorUid(fromUid: string, toUid: string, email?: string) {
    const normalized = email?.trim().toLowerCase();
    let changed = 0;
    for (const draft of this.drafts) {
      const emailMatch =
        normalized != null &&
        normalized.length > 0 &&
        draft.creatorEmail.toLowerCase() === normalized;
      if (draft.creatorUid === fromUid || emailMatch) {
        if (draft.creatorUid !== toUid) {
          draft.creatorUid = toUid;
          changed += 1;
          this.persistDraft(draft);
        }
      }
    }
    return changed;
  }

  listAllDrafts() {
    return this.drafts;
  }

  createDraft(input: {
    creatorUid: string;
    creatorEmail: string;
    creatorDisplayName?: string;
    title: string;
    format: StudioFormat;
    genre?: string;
    prices: PriceByCurrency[];
    monetisationMode?: StudioDraft['monetisationMode'];
    subscriptionEligible?: boolean;
    mediaName?: string;
    mediaKind?: StudioDraft['mediaKind'];
    mediaBytes?: number;
    mediaId?: string;
    coverImageName?: string;
    coverImageBytes?: number;
    chapters?: StudioChapter[];
    episodes?: StudioEpisode[];
    status?: StudioDraftStatus;
  }): StudioDraft {
    const now = new Date().toISOString();
    const draft: StudioDraft = {
      id: `draft-${randomUUID()}`,
      creatorUid: input.creatorUid,
      creatorEmail: input.creatorEmail.trim().toLowerCase(),
      creatorDisplayName: input.creatorDisplayName?.trim() || undefined,
      title: input.title.trim(),
      format: input.format,
      genre: input.genre?.trim() || undefined,
      prices: input.prices.filter((p) => p.amountMinor >= 0),
      monetisationMode:
        input.monetisationMode ??
        (input.format === 'podcast' ? 'free_with_ads' : 'purchase'),
      subscriptionEligible: input.subscriptionEligible ?? input.format !== 'podcast',
      mediaName: input.mediaName,
      mediaKind: input.mediaKind,
      mediaBytes: input.mediaBytes,
      mediaId: input.mediaId,
      coverImageName: input.coverImageName,
      coverImageBytes: input.coverImageBytes,
      chapters: this.normalizeChapters(input.chapters),
      episodes: this.normalizeEpisodes(input.episodes),
      status: input.status ?? 'draft',
      createdAt: now,
      updatedAt: now,
    };
    this.drafts.unshift(draft);
    this.persistDraft(draft);
    this.logger.log(
      `Studio draft ${draft.id} saved (${draft.status}) for ${draft.creatorEmail} · ${draft.title}`,
    );
    return draft;
  }

  removeDraft(id: string): StudioDraft | null {
    const index = this.drafts.findIndex((d) => d.id === id);
    if (index < 0) return null;
    const [removed] = this.drafts.splice(index, 1);
    this.persistDeleteDraft(id);
    return removed;
  }

  submitDraft(id: string, creatorUid: string): StudioDraft | null {
    const draft =
      this.drafts.find((d) => d.id === id && d.creatorUid === creatorUid) ??
      this.drafts.find((d) => d.id === id);
    if (!draft) return null;
    draft.status = 'submitted';
    draft.updatedAt = new Date().toISOString();
    this.persistDraft(draft);
    return draft;
  }

  findByPublishedTitleId(titleId: string): StudioDraft | undefined {
    return this.drafts.find((d) => d.publishedTitleId === titleId);
  }

  findDraft(id: string): StudioDraft | undefined {
    return this.drafts.find((d) => d.id === id);
  }

  listSubmitted(): StudioDraft[] {
    return this.drafts.filter((d) => d.status === 'submitted' || d.status === 'live');
  }

  markLive(id: string, publishedTitleId: string): StudioDraft | null {
    const draft = this.drafts.find((d) => d.id === id);
    if (!draft) return null;
    draft.status = 'live';
    draft.publishedTitleId = publishedTitleId;
    draft.updatedAt = new Date().toISOString();
    this.persistDraft(draft);
    return draft;
  }

  private normalizeChapters(chapters?: StudioChapter[]): StudioChapter[] {
    if (!chapters?.length) return [];
    return chapters
      .map((chapter, index) => ({
        id: chapter.id?.trim() || `ch-${randomUUID().slice(0, 8)}`,
        title: (chapter.title ?? '').trim() || `Chapter ${index + 1}`,
        body: (chapter.body ?? '').trim() || 'Chapter body coming soon.',
        sortOrder: chapter.sortOrder ?? index,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map((chapter, index) => ({ ...chapter, sortOrder: index }));
  }

  private normalizeEpisodes(episodes?: StudioEpisode[]): StudioEpisode[] {
    if (!episodes?.length) return [];
    return episodes
      .map((episode, index) => ({
        id: episode.id?.trim() || `ep-${randomUUID().slice(0, 8)}`,
        title: (episode.title ?? '').trim() || `Episode ${index + 1}`,
        durationSec: Math.max(0, Number(episode.durationSec) || 0),
        mediaName: episode.mediaName?.trim() || undefined,
        mediaId: episode.mediaId?.trim() || undefined,
        showNotes: episode.showNotes?.trim() || undefined,
        body: episode.body?.trim() || undefined,
        sortOrder: episode.sortOrder ?? index,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map((episode, index) => ({ ...episode, sortOrder: index }));
  }

  updateDraft(
    id: string,
    creatorUid: string,
    patch: {
      title?: string;
      format?: StudioFormat;
      genre?: string;
      prices?: PriceByCurrency[];
      monetisationMode?: StudioDraft['monetisationMode'];
      subscriptionEligible?: boolean;
      mediaName?: string;
      mediaKind?: StudioDraft['mediaKind'];
      mediaBytes?: number;
      mediaId?: string;
      coverImageName?: string;
      coverImageBytes?: number;
      chapters?: StudioChapter[];
      episodes?: StudioEpisode[];
      status?: StudioDraftStatus;
      creatorDisplayName?: string;
      creatorEmail?: string;
    },
  ): StudioDraft | null {
    const draft =
      this.drafts.find((d) => d.id === id && d.creatorUid === creatorUid) ??
      this.drafts.find((d) => d.id === id);
    if (!draft) return null;
    if (patch.title?.trim()) draft.title = patch.title.trim();
    if (patch.format) draft.format = patch.format;
    if (patch.genre !== undefined) {
      draft.genre = patch.genre.trim() || undefined;
    }
    if (patch.prices) draft.prices = patch.prices.filter((p) => p.amountMinor >= 0);
    if (patch.monetisationMode !== undefined) draft.monetisationMode = patch.monetisationMode;
    if (patch.subscriptionEligible !== undefined) {
      draft.subscriptionEligible = patch.subscriptionEligible;
    }
    if (patch.mediaName !== undefined) draft.mediaName = patch.mediaName;
    if (patch.mediaKind !== undefined) draft.mediaKind = patch.mediaKind;
    if (patch.mediaBytes !== undefined) draft.mediaBytes = patch.mediaBytes;
    if (patch.mediaId !== undefined) {
      draft.mediaId = patch.mediaId.trim() || undefined;
    }
    if (patch.coverImageName !== undefined) draft.coverImageName = patch.coverImageName;
    if (patch.coverImageBytes !== undefined) draft.coverImageBytes = patch.coverImageBytes;
    if (patch.chapters !== undefined) draft.chapters = this.normalizeChapters(patch.chapters);
    if (patch.episodes !== undefined) draft.episodes = this.normalizeEpisodes(patch.episodes);
    if (patch.status) draft.status = patch.status;
    if (patch.creatorDisplayName?.trim()) draft.creatorDisplayName = patch.creatorDisplayName.trim();
    if (patch.creatorEmail?.trim()) draft.creatorEmail = patch.creatorEmail.trim().toLowerCase();
    // Keep uid current if the same creator rebinds Firebase uid.
    if (creatorUid && draft.creatorUid !== creatorUid) {
      draft.creatorUid = creatorUid;
    }
    draft.updatedAt = new Date().toISOString();
    this.persistDraft(draft);
    return draft;
  }

  deleteDraft(id: string, creatorUid: string): boolean {
    const index = this.drafts.findIndex(
      (d) => d.id === id && (d.creatorUid === creatorUid || d.id.startsWith('local-')),
    );
    if (index < 0) {
      const byId = this.drafts.findIndex((d) => d.id === id);
      if (byId < 0) return false;
      this.drafts.splice(byId, 1);
      this.persistDeleteDraft(id);
      return true;
    }
    this.drafts.splice(index, 1);
    this.persistDeleteDraft(id);
    return true;
  }

  /**
   * Record a creator earning line (prototype ledger).
   * Purchase royalties use 70/30 of net receipts per monetisation policy v1.
   */
  recordEarning(input: {
    creatorUid: string;
    titleId: string;
    titleName: string;
    currency: string;
    grossMinor: number;
    /** Actual processing fee + tax + refunds deducted before split. */
    deductionsMinor?: number;
    market: string;
    stream: SaleRow['stream'];
    format: SaleRow['format'];
    note?: string;
  }): SaleRow {
    const deductions = Math.max(0, input.deductionsMinor ?? 0);
    const net = Math.max(0, input.grossMinor - deductions);
    // purchase 70/30 · advertising 55/45 · subscription pool 60/40 of net pool credits
    const creatorBps =
      input.stream === 'advertising'
        ? 5500
        : input.stream === 'subscription_pool'
          ? 6000
          : 7000;
    const creatorShare = Math.floor((net * creatorBps) / 10000);
    const platformShare = Math.max(0, net - creatorShare);
    const row: SaleRow = {
      id: `sale-${randomUUID()}`,
      creatorUid: input.creatorUid,
      titleId: input.titleId,
      titleName: input.titleName,
      currency: input.currency,
      grossMinor: input.grossMinor,
      netReceiptsMinor: net,
      creatorShareMinor: creatorShare,
      platformShareMinor: platformShare,
      market: input.market,
      at: new Date().toISOString(),
      stream: input.stream,
      format: input.format,
      note: input.note,
    };
    this.sales.unshift(row);
    this.persistSales();
    return row;
  }

  salesFor(creatorUid: string, email?: string): SalesDashboard {
    const normalized = email?.toLowerCase();
    const rows = this.sales.filter(
      (s) =>
        s.creatorUid === creatorUid ||
        (normalized != null &&
          normalized.length > 0 &&
          this.drafts.some(
            (d) =>
              d.creatorUid === s.creatorUid &&
              d.creatorEmail.toLowerCase() === normalized,
          )),
    );
    const primary = rows[0]?.currency ?? 'ZMW';
    const sameCurrency = rows.filter((r) => r.currency === primary);
    const creatorTotal = sameCurrency.reduce((sum, r) => sum + r.creatorShareMinor, 0);
    const byFormat = {
      ebookMinor: 0,
      audiobookMinor: 0,
      podcastMinor: 0,
      advertisingMinor: 0,
    };
    for (const row of sameCurrency) {
      if (row.stream === 'advertising') {
        byFormat.advertisingMinor += row.creatorShareMinor;
        continue;
      }
      if (row.format === 'ebook') byFormat.ebookMinor += row.creatorShareMinor;
      else if (row.format === 'audiobook') byFormat.audiobookMinor += row.creatorShareMinor;
      else byFormat.podcastMinor += row.creatorShareMinor;
    }
    // 30-day hold prototype: ~20% pending until reconciliation.
    const pendingMinor = Math.floor(creatorTotal * 0.2);
    const availableMinor = Math.max(0, creatorTotal - pendingMinor);
    return {
      currency: primary,
      grossSalesMinor: creatorTotal,
      availableMinor,
      pendingMinor,
      paidOutMinor: 0,
      byFormat,
      policy: {
        purchaseCreatorShareBps: 7000,
        purchasePlatformShareBps: 3000,
        subscriptionPoolCreatorBps: 6000,
        subscriptionPoolPlatformBps: 4000,
        advertisingCreatorBps: 5500,
        advertisingPlatformBps: 4500,
        subscriptionFormatWeights: {
          ebookBps: 3000,
          audiobookBps: 4500,
          podcastBps: 2500,
        },
        minPayoutMinor: 20000,
      },
      sales: sameCurrency,
    };
  }
}

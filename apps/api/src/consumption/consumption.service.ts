import { BadRequestException, Inject, Injectable } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { LedgerService } from '../finance/ledger.service';
import { StudioStore } from '../studio/studio.store';

/** Prototype: ZMW credit per qualified listening/reading minute in the sub pool. */
const POOL_PER_MINUTE_MINOR = 8;

@Injectable()
export class ConsumptionService {
  /** listener|title|day -> credited minutes */
  private readonly credited = new Map<string, number>();

  constructor(
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(LedgerService) private readonly ledger: LedgerService,
  ) {}

  /**
   * Credit subscription-pool earnings from verified consumption.
   * Caps prevent spam (max 20 minutes credited per title per listener per day).
   */
  creditQualified(input: {
    listenerUid: string;
    titleId: string;
    minutes: number;
    kind: 'listening' | 'reading';
  }) {
    const minutes = Math.floor(input.minutes);
    if (minutes < 1) {
      throw new BadRequestException('Need at least 1 qualified minute');
    }

    const title = this.catalogue.getTitle(input.titleId);
    if (title.subscriptionEligible === false) {
      throw new BadRequestException('Title is not subscription-pool eligible');
    }
    if (!title.creatorUid) {
      throw new BadRequestException('Title has no creator to credit');
    }

    const day = new Date().toISOString().slice(0, 10);
    const key = `${input.listenerUid}|${title.id}|${day}`;
    const already = this.credited.get(key) ?? 0;
    const remaining = Math.max(0, 20 - already);
    const grant = Math.min(minutes, remaining);
    if (grant <= 0) {
      return { ok: true, creditedMinutes: 0, note: 'Daily cap reached for this title' };
    }
    this.credited.set(key, already + grant);

    const format =
      title.format === 'audiobook' || title.format === 'ebook_audio'
        ? 'audiobook'
        : title.format === 'podcast'
          ? 'podcast'
          : 'ebook';

    const gross = grant * POOL_PER_MINUTE_MINOR;
    const sale = this.studio.recordEarning({
      creatorUid: title.creatorUid,
      titleId: title.id,
      titleName: title.name,
      currency: title.currency || 'ZMW',
      grossMinor: gross,
      deductionsMinor: 0,
      market: 'ZM',
      stream: 'subscription_pool',
      format,
      note: `Qualified ${input.kind} · ${grant} min (pool allocation)`,
    });

    const settled = this.ledger.settleStudioSale({
      saleId: sale.id,
      creatorUid: title.creatorUid,
      titleId: title.id,
      currency: sale.currency,
      creatorShareMinor: sale.creatorShareMinor,
      platformShareMinor: sale.platformShareMinor,
      stream: 'subscription_pool',
      at: sale.at,
      note: sale.note,
    });

    return {
      ok: true,
      creditedMinutes: grant,
      creatorShareMinor: sale.creatorShareMinor,
      currency: sale.currency,
      journalId: settled?.journal.id,
    };
  }
}

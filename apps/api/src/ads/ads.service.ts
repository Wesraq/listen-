import { BadRequestException, Inject, Injectable } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { StudioStore } from '../studio/studio.store';

/**
 * Illustrative gross receipt per verified AdMob reward (ZMW minor units).
 * Replace with payout reconciliation from AdMob reports / Mediation once live.
 */
const AD_GROSS_MINOR = Number(process.env.AD_GROSS_MINOR ?? 50); // ZMW 0.50

@Injectable()
export class AdsService {
  /** listenerKey -> completion timestamps (ms) for hourly caps. */
  private readonly completions = new Map<string, number[]>();
  /** AdMob SSV transaction ids already credited (idempotency). */
  private readonly ssvTransactions = new Set<string>();
  /** Recent credit fingerprints to avoid client+SSV double ledger posts. */
  private readonly recentCredits = new Map<string, number>();

  constructor(
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(StudioStore) private readonly studio: StudioStore,
  ) {}

  complete(input: {
    listenerUid: string;
    titleId: string;
    placement: 'preroll' | 'midroll';
    completedSec: number;
    trackId?: string;
    source?: string;
    rewardEarned?: boolean;
  }) {
    const fromAdMob = (input.source ?? 'admob') === 'admob' && input.rewardEarned === true;
    if (!fromAdMob && input.completedSec < 5) {
      throw new BadRequestException('Ad must play at least 5 seconds to monetise');
    }
    if ((input.source ?? '') === 'admob' && input.rewardEarned !== true) {
      throw new BadRequestException('AdMob completion requires a rewarded callback');
    }

    return this.credit({
      listenerUid: input.listenerUid,
      titleId: input.titleId,
      placement: input.placement,
      noteExtra: fromAdMob
        ? `AdMob rewarded · ${input.placement}`
        : `Verified ${input.placement} · ${input.completedSec}s`,
    });
  }

  /**
   * AdMob Server-Side Verification callback.
   * Configure this URL in the AdMob console (Rewarded interstitial → SSV).
   * Full ECDSA key verification should be enabled before trusting production traffic;
   * for now we accept signed query params when ADMOB_SSV_REQUIRE_SIGNATURE is unset/false.
   */
  ssv(query: Record<string, string | undefined>) {
    const transactionId = query.transaction_id ?? query.transactionId ?? '';
    const customData = query.custom_data ?? query.customData ?? '';
    if (!transactionId) {
      throw new BadRequestException('Missing transaction_id');
    }
    if (this.ssvTransactions.has(transactionId)) {
      return { ok: true, duplicate: true };
    }

    // custom_data is set by the client as titleId|placement|listenerUid
    const [titleId = '', placementRaw = 'preroll', listenerUid = 'ssv'] = customData.split('|');
    const placement = placementRaw === 'midroll' ? 'midroll' : 'preroll';
    if (!titleId) {
      throw new BadRequestException('custom_data must include titleId');
    }

    const result = this.credit({
      listenerUid,
      titleId,
      placement,
      noteExtra: `AdMob SSV · ${transactionId.slice(0, 12)}`,
    });
    this.ssvTransactions.add(transactionId);
    return { ...result, transactionId, duplicate: false };
  }

  private credit(input: {
    listenerUid: string;
    titleId: string;
    placement: 'preroll' | 'midroll';
    noteExtra: string;
  }) {
    const title = this.catalogue.getTitle(input.titleId);
    const mode = title.monetisationMode ?? (title.priceMinor === 0 ? 'free_with_ads' : 'purchase');
    if (mode !== 'free_with_ads') {
      throw new BadRequestException('Advertising is only enabled for free-with-ads titles');
    }
    if (!title.creatorUid) {
      throw new BadRequestException('Title has no creator to credit');
    }

    const key = input.listenerUid;
    const now = Date.now();
    const fingerprint = `${input.listenerUid}:${input.titleId}:${input.placement}`;
    const lastSame = this.recentCredits.get(fingerprint) ?? 0;
    if (now - lastSame < 90_000) {
      return {
        ok: true,
        placement: input.placement,
        creatorShareMinor: 0,
        platformShareMinor: 0,
        currency: title.currency || 'ZMW',
        hourlyCompletions: (this.completions.get(key) ?? []).length,
        hourlyCap: 3,
        duplicate: true,
      };
    }

    const hourAgo = now - 60 * 60 * 1000;
    const recent = (this.completions.get(key) ?? []).filter((t) => t >= hourAgo);
    if (recent.length >= 3) {
      throw new BadRequestException('Hourly ad cap reached (max 3 completed ads)');
    }
    recent.push(now);
    this.completions.set(key, recent);
    this.recentCredits.set(fingerprint, now);

    const format =
      title.format === 'audiobook' || title.format === 'ebook_audio'
        ? 'audiobook'
        : title.format === 'podcast'
          ? 'podcast'
          : 'ebook';

    const sale = this.studio.recordEarning({
      creatorUid: title.creatorUid,
      titleId: title.id,
      titleName: title.name,
      currency: title.currency || 'ZMW',
      grossMinor: AD_GROSS_MINOR,
      deductionsMinor: 0,
      market: 'ZM',
      stream: 'advertising',
      format,
      note: `${input.noteExtra} · listener ${input.listenerUid.slice(0, 8)}`,
    });

    return {
      ok: true,
      placement: input.placement,
      creatorShareMinor: sale.creatorShareMinor,
      platformShareMinor: sale.platformShareMinor,
      currency: sale.currency,
      hourlyCompletions: recent.length,
      hourlyCap: 3,
    };
  }
}

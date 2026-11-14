import { BadRequestException, Inject, Injectable } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { LedgerService } from '../finance/ledger.service';
import { StudioStore } from '../studio/studio.store';

/**
 * Illustrative gross receipt per verified AdMob reward (ZMW minor units).
 * Replace with AdMob Mediation / network reconciliation once live.
 */
const AD_GROSS_MINOR = Number(process.env.AD_GROSS_MINOR ?? 50); // ZMW 0.50

export interface AdCampaign {
  id: string;
  name: string;
  status: 'active' | 'paused' | 'ended';
  /** Who pays Listen+ for the inventory (platform network until advertisers onboard). */
  advertiser: string;
  placements: Array<'preroll' | 'midroll' | 'chapter'>;
  /** Gross credit per verified completion (minor units). */
  grossMinor: number;
  currency: string;
}

@Injectable()
export class AdsService {
  /** listenerKey -> completion timestamps (ms) for hourly caps. */
  private readonly completions = new Map<string, number[]>();
  /** AdMob SSV transaction ids already credited (idempotency). */
  private readonly ssvTransactions = new Set<string>();
  /** Recent credit fingerprints to avoid client+SSV double ledger posts. */
  private readonly recentCredits = new Map<string, number>();

  /** Seed campaigns — advertiser self-serve lands on this same model. */
  private readonly campaigns: AdCampaign[] = [
    {
      id: 'network_default',
      name: 'Listen+ rewarded network',
      status: 'active',
      advertiser: 'Listen+ / AdMob',
      placements: ['preroll', 'midroll', 'chapter'],
      grossMinor: AD_GROSS_MINOR,
      currency: 'ZMW',
    },
  ];

  constructor(
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(LedgerService) private readonly ledger: LedgerService,
  ) {}

  listCampaigns() {
    return {
      items: this.campaigns.filter((c) => c.status === 'active'),
      ssvUrlHint: '/v1/ads/ssv',
      note: 'Advertiser campaign management will create rows here; completions settle on the shared ledger.',
    };
  }

  complete(input: {
    listenerUid: string;
    titleId: string;
    placement: 'preroll' | 'midroll';
    completedSec: number;
    trackId?: string;
    source?: string;
    rewardEarned?: boolean;
    campaignId?: string;
  }) {
    const fromAdMob = (input.source ?? 'admob') === 'admob' && input.rewardEarned === true;
    if (!fromAdMob && input.completedSec < 5) {
      throw new BadRequestException('Ad must play at least 5 seconds to monetise');
    }
    if ((input.source ?? '') === 'admob' && input.rewardEarned !== true) {
      throw new BadRequestException('AdMob completion requires a rewarded callback');
    }

    const minuteBucket = Math.floor(Date.now() / 60_000);
    return this.credit({
      listenerUid: input.listenerUid,
      titleId: input.titleId,
      placement: input.placement,
      campaignId: input.campaignId,
      referenceId: `client:${input.listenerUid}:${input.titleId}:${input.placement}:${minuteBucket}`,
      noteExtra: fromAdMob
        ? `AdMob rewarded · ${input.placement}`
        : `Verified ${input.placement} · ${input.completedSec}s`,
    });
  }

  /**
   * AdMob Server-Side Verification callback.
   * Configure: Rewarded interstitial → SSV URL → https://<api-host>/v1/ads/ssv
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
      referenceId: `ssv:${transactionId}`,
      noteExtra: `AdMob SSV · ${transactionId.slice(0, 12)}`,
    });
    this.ssvTransactions.add(transactionId);
    return { ...result, transactionId, duplicate: false };
  }

  private credit(input: {
    listenerUid: string;
    titleId: string;
    placement: 'preroll' | 'midroll';
    referenceId: string;
    noteExtra: string;
    campaignId?: string;
  }) {
    const title = this.catalogue.getTitle(input.titleId);
    const mode = title.monetisationMode ?? (title.priceMinor === 0 ? 'free_with_ads' : 'purchase');
    if (mode !== 'free_with_ads') {
      throw new BadRequestException('Advertising is only enabled for free-with-ads titles');
    }
    if (!title.creatorUid) {
      throw new BadRequestException('Title has no creator to credit');
    }

    const campaign =
      this.campaigns.find((c) => c.id === (input.campaignId || 'network_default')) ??
      this.campaigns[0];
    if (!campaign || campaign.status !== 'active') {
      throw new BadRequestException('No active ad campaign');
    }

    const key = input.listenerUid;
    const now = Date.now();
    const fingerprint = `${input.listenerUid}:${input.titleId}:${input.placement}`;
    const lastSame = this.recentCredits.get(fingerprint) ?? 0;
    if (now - lastSame < 90_000) {
      return {
        ok: true,
        placement: input.placement,
        campaignId: campaign.id,
        creatorShareMinor: 0,
        platformShareMinor: 0,
        currency: title.currency || campaign.currency,
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

    const currency = title.currency || campaign.currency;
    const settled = this.ledger.settleAdvertising({
      referenceId: input.referenceId,
      customerUid: input.listenerUid,
      creatorUid: title.creatorUid,
      titleId: title.id,
      currency,
      grossMinor: campaign.grossMinor,
      campaignId: campaign.id,
      placement: input.placement,
    });

    const format =
      title.format === 'audiobook' || title.format === 'ebook_audio'
        ? 'audiobook'
        : title.format === 'podcast'
          ? 'podcast'
          : 'ebook';

    if (settled.created) {
      this.studio.recordEarning({
        creatorUid: title.creatorUid,
        titleId: title.id,
        titleName: title.name,
        currency,
        grossMinor: campaign.grossMinor,
        deductionsMinor: 0,
        market: 'ZM',
        stream: 'advertising',
        format,
        note: `${input.noteExtra} · ledger ${settled.journal.id} · listener ${input.listenerUid.slice(0, 8)}`,
      });
    }

    return {
      ok: true,
      placement: input.placement,
      campaignId: campaign.id,
      creatorShareMinor: settled.creatorShareMinor,
      platformShareMinor: settled.platformShareMinor,
      currency,
      journalId: settled.journal.id,
      hourlyCompletions: recent.length,
      hourlyCap: 3,
      duplicate: !settled.created,
    };
  }
}

import {
  BadRequestException,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { LedgerService } from '../finance/ledger.service';
import { StudioStore } from '../studio/studio.store';
import {
  assertFreshSsvTimestamp,
  safeIncludes,
  verifyAdMobSsvQuery,
} from './ssv-verifier';

/**
 * Prototype / simulated gross per SSV callback (ZMW minor units).
 * NOT AdMob network revenue. Must never create cashoutable payables.
 */
const AD_GROSS_MINOR = Number(process.env.AD_GROSS_MINOR ?? 50);

/**
 * - simulate: SSV-verified completions post illustrative journals (cashoutEligible=false)
 * - off: SSV verifies + records receipt only (no creator journal)
 * - reconciled: fixed AD_GROSS forbidden; use admin reconcile with reported amounts
 */
type AdsSettlementMode = 'simulate' | 'off' | 'reconciled';

function adsSettlementMode(): AdsSettlementMode {
  const raw = (process.env.ADS_SETTLEMENT_MODE ?? 'simulate').toLowerCase();
  if (raw === 'off' || raw === 'reconciled') return raw;
  return 'simulate';
}

export interface AdCampaign {
  id: string;
  name: string;
  status: 'active' | 'paused' | 'ended';
  advertiser: string;
  placements: Array<'preroll' | 'midroll' | 'chapter'>;
  /** Simulated gross only — not network settlement. */
  simulatedGrossMinor: number;
  currency: string;
  cashoutEligible: false;
}

@Injectable()
export class AdsService {
  private readonly completions = new Map<string, number[]>();
  /** Persisted via ledger idempotency; in-memory set for fast replay reject. */
  private readonly ssvTransactions = new Set<string>();

  private readonly campaigns: AdCampaign[] = [
    {
      id: 'network_default',
      name: 'Listen+ rewarded network (simulated gross)',
      status: 'active',
      advertiser: 'Listen+ / AdMob',
      placements: ['preroll', 'midroll', 'chapter'],
      simulatedGrossMinor: AD_GROSS_MINOR,
      currency: 'ZMW',
      cashoutEligible: false,
    },
  ];

  constructor(
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(LedgerService) private readonly ledger: LedgerService,
  ) {}

  listCampaigns() {
    const mode = adsSettlementMode();
    return {
      items: this.campaigns.filter((c) => c.status === 'active'),
      ssvUrlHint: '/v1/ads/ssv',
      settlementMode: mode,
      note:
        mode === 'reconciled'
          ? 'Creator advertising payables require reconciled AdMob/network receipts — not client rewards or fixed AD_GROSS.'
          : 'AD_GROSS_MINOR is a SIMULATED prototype amount, not Google revenue. SSV-verified simulate journals are not cashoutable.',
    };
  }

  /**
   * Client telemetry / UX only. Never posts ledger creator payables.
   * `rewardEarned` is untrusted and is ignored for money movement.
   */
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
    const title = this.catalogue.getTitle(input.titleId);
    const mode = title.monetisationMode ?? (title.priceMinor === 0 ? 'free_with_ads' : 'purchase');
    if (mode !== 'free_with_ads') {
      throw new BadRequestException('Advertising is only enabled for free-with-ads titles');
    }

    const key = input.listenerUid;
    const now = Date.now();
    const hourAgo = now - 60 * 60 * 1000;
    const recent = (this.completions.get(key) ?? []).filter((t) => t >= hourAgo);
    if (recent.length >= 3) {
      throw new BadRequestException('Hourly ad cap reached (max 3 completed ads)');
    }
    recent.push(now);
    this.completions.set(key, recent);

    return {
      ok: true,
      credited: false,
      cashoutEligible: false,
      placement: input.placement,
      campaignId: input.campaignId ?? 'network_default',
      creatorShareMinor: 0,
      platformShareMinor: 0,
      currency: title.currency || 'ZMW',
      hourlyCompletions: recent.length,
      hourlyCap: 3,
      note:
        'Client /ads/complete never settles advertising payables. Configure AdMob SSV; only verified SSV (or reconciled receipts) may create journals.',
    };
  }

  /**
   * AdMob Server-Side Verification callback.
   * Requires valid ECDSA signature, fresh timestamp, and unique transaction_id.
   */
  async ssv(input: {
    query: Record<string, string | undefined>;
    rawQuery: string;
  }) {
    const { query, rawQuery } = input;
    if (!rawQuery || !rawQuery.includes('signature=')) {
      throw new BadRequestException('SSV requires the original signed query string');
    }

    const verified = await verifyAdMobSsvQuery(rawQuery);
    if (!verified.ok) {
      throw new UnauthorizedException(verified.reason ?? 'Invalid AdMob SSV signature');
    }

    const fresh = assertFreshSsvTimestamp(query.timestamp);
    if (!fresh.ok) {
      throw new BadRequestException(fresh.reason);
    }

    const transactionId = query.transaction_id ?? query.transactionId ?? '';
    if (!transactionId) {
      throw new BadRequestException('Missing transaction_id');
    }
    if (safeIncludes(this.ssvTransactions, transactionId)) {
      return { ok: true, duplicate: true, credited: false, transactionId };
    }
    // Ledger idempotency is authoritative across instances.
    if (this.ledgerHasAdCompletion(`ssv:${transactionId}`)) {
      this.ssvTransactions.add(transactionId);
      return { ok: true, duplicate: true, credited: false, transactionId };
    }

    const customData = query.custom_data ?? query.customData ?? '';
    const [titleId = '', placementRaw = 'preroll', listenerUid = 'ssv'] = customData.split('|');
    const placement = placementRaw === 'midroll' ? 'midroll' : 'preroll';
    if (!titleId) {
      throw new BadRequestException('custom_data must include titleId');
    }

    const mode = adsSettlementMode();
    if (mode === 'reconciled') {
      this.ssvTransactions.add(transactionId);
      return {
        ok: true,
        credited: false,
        cashoutEligible: false,
        transactionId,
        note: 'SSV verified. ADS_SETTLEMENT_MODE=reconciled — post creator payables only via admin ad reconciliation with reported network amounts.',
      };
    }

    if (mode === 'off') {
      this.ssvTransactions.add(transactionId);
      return {
        ok: true,
        credited: false,
        cashoutEligible: false,
        transactionId,
        note: 'SSV verified. ADS_SETTLEMENT_MODE=off — no ledger journal.',
      };
    }

    // simulate — illustrative only
    const result = this.creditSimulatedSsv({
      listenerUid,
      titleId,
      placement,
      transactionId,
    });
    this.ssvTransactions.add(transactionId);
    return { ...result, transactionId, duplicate: false };
  }

  /**
   * Admin path: attribute creator share from reconciled network receipts
   * (AdMob reporting / mediation), not from fixed AD_GROSS or client flags.
   */
  reconcileReportedEarning(input: {
    referenceId: string;
    listenerUid?: string;
    creatorUid: string;
    titleId: string;
    currency: string;
    /** Actual attributable gross in minor units from reconciliation. */
    reportedGrossMinor: number;
    campaignId?: string;
    placement?: string;
    reportSource: string;
  }) {
    if (input.reportedGrossMinor <= 0) {
      throw new BadRequestException('reportedGrossMinor must be positive');
    }
    const title = this.catalogue.getTitle(input.titleId);
    const creatorUid = input.creatorUid || title.creatorUid;
    if (!creatorUid) throw new BadRequestException('creatorUid required');

    const settled = this.ledger.settleAdvertising({
      referenceId: `reconcile:${input.referenceId}`,
      customerUid: input.listenerUid || 'reconcile',
      creatorUid,
      titleId: input.titleId,
      currency: input.currency || title.currency || 'ZMW',
      grossMinor: input.reportedGrossMinor,
      campaignId: input.campaignId ?? 'network_default',
      placement: input.placement,
      cashoutEligible: true,
      settlementSource: 'ad_reconciled',
    });

    if (settled.created) {
      const format =
        title.format === 'audiobook' || title.format === 'ebook_audio'
          ? 'audiobook'
          : title.format === 'podcast'
            ? 'podcast'
            : 'ebook';
      this.studio.recordEarning({
        creatorUid,
        titleId: title.id,
        titleName: title.name,
        currency: settled.journal.currency,
        grossMinor: input.reportedGrossMinor,
        deductionsMinor: 0,
        market: 'ZM',
        stream: 'advertising',
        format,
        note: `Reconciled ${input.reportSource} · ledger ${settled.journal.id}`,
      });
    }

    return {
      ok: true,
      cashoutEligible: true,
      journalId: settled.journal.id,
      created: settled.created,
      creatorShareMinor: settled.creatorShareMinor,
      platformShareMinor: settled.platformShareMinor,
    };
  }

  private ledgerHasAdCompletion(referenceId: string): boolean {
    return this.ledger
      .recentJournals(5000)
      .some((j) => j.referenceType === 'ad_completion' && j.referenceId === referenceId);
  }

  private creditSimulatedSsv(input: {
    listenerUid: string;
    titleId: string;
    placement: 'preroll' | 'midroll';
    transactionId: string;
  }) {
    const title = this.catalogue.getTitle(input.titleId);
    const mode = title.monetisationMode ?? (title.priceMinor === 0 ? 'free_with_ads' : 'purchase');
    if (mode !== 'free_with_ads') {
      throw new BadRequestException('Advertising is only enabled for free-with-ads titles');
    }
    if (!title.creatorUid) {
      throw new BadRequestException('Title has no creator to credit');
    }

    const campaign = this.campaigns[0];
    const currency = title.currency || campaign.currency;
    const settled = this.ledger.settleAdvertising({
      referenceId: `ssv:${input.transactionId}`,
      customerUid: input.listenerUid,
      creatorUid: title.creatorUid,
      titleId: title.id,
      currency,
      grossMinor: campaign.simulatedGrossMinor,
      campaignId: campaign.id,
      placement: input.placement,
      cashoutEligible: false,
      settlementSource: 'ssv_simulated',
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
        grossMinor: campaign.simulatedGrossMinor,
        deductionsMinor: 0,
        market: 'ZM',
        stream: 'advertising',
        format,
        note: `SIMULATED SSV · ${input.transactionId.slice(0, 12)} · ledger ${settled.journal.id} (not cashoutable)`,
      });
    }

    return {
      ok: true,
      credited: settled.created,
      cashoutEligible: false,
      placement: input.placement,
      campaignId: campaign.id,
      creatorShareMinor: settled.creatorShareMinor,
      platformShareMinor: settled.platformShareMinor,
      currency,
      journalId: settled.journal.id,
      note: 'Simulated AD_GROSS posted for observability only — excluded from cashout balances.',
    };
  }
}

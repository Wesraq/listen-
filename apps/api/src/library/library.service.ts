import { Inject, Injectable, NotFoundException } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import type { ContentFormat } from '../catalogue/catalogue.types';
import { LedgerService } from '../finance/ledger.service';
import { StudioStore } from '../studio/studio.store';
import { LibraryStore } from './library.store';

@Injectable()
export class LibraryService {
  constructor(
    @Inject(LibraryStore) private readonly store: LibraryStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(LedgerService) private readonly ledger: LedgerService,
  ) {}

  getLibrary(uid: string) {
    const ownedIds = this.store.getOwned(uid);
    const savedIds = this.store.getSaved(uid);
    return {
      owned: ownedIds.map((id) => this.catalogue.getTitle(id)),
      saved: savedIds.map((id) => this.catalogue.getTitle(id)),
      ownedIds,
      savedIds,
    };
  }

  entitlement(uid: string, titleId: string) {
    const title = this.catalogue.getTitle(titleId);
    const isFree =
      title.priceMinor === 0 || title.monetisationMode === 'free_with_ads';
    if (this.store.isEntitled(uid, titleId, isFree)) {
      return {
        titleId,
        entitled: true,
        reason: isFree ? 'free' : 'owned',
      };
    }
    const sub = this.ledger.getActiveSubscription(uid);
    const subOk =
      Boolean(sub) &&
      (title.monetisationMode === 'subscription' || title.subscriptionEligible === true);
    return {
      titleId,
      entitled: subOk,
      reason: subOk ? 'subscription' : 'not_owned',
    };
  }

  /**
   * Prototype purchase grant. Real entitlements must come from verified payment
   * webhooks. First paid grant credits the creator ledger (70/30 of net receipts).
   */
  grant(uid: string, titleId: string, options?: { skipEarning?: boolean }) {
    const title = this.catalogue.getTitle(titleId);
    const alreadyOwned = this.store.isEntitled(uid, titleId, false);
    const ownedIds = this.store.grantOwnership(uid, titleId);

    // Preferred path: PaymentsService settles the shared ledger first, then grants
    // with skipEarning. Legacy client grants still record a Studio earnings line.
    if (!options?.skipEarning && !alreadyOwned && title.priceMinor > 0) {
      const draft = this.studio.findByPublishedTitleId(titleId);
      const creatorUid = draft?.creatorUid ?? title.creatorUid;
      if (creatorUid) {
        const deductionsMinor = Math.floor(title.priceMinor * 0.03);
        this.studio.recordEarning({
          creatorUid,
          titleId,
          titleName: title.name,
          currency: title.currency || 'ZMW',
          grossMinor: title.priceMinor,
          deductionsMinor,
          market: 'ZM',
          stream: 'purchase',
          format: this.earningFormat(title.format),
          note: 'Legacy grant · prefer /payments intents for ledger settlement',
        });
      }
    }

    return {
      ownedIds,
      titleId,
    };
  }

  toggleSave(uid: string, titleId: string) {
    try {
      this.catalogue.getTitle(titleId);
    } catch {
      throw new NotFoundException(`Title ${titleId} not found`);
    }
    return this.store.toggleSaved(uid, titleId);
  }

  private earningFormat(format: ContentFormat): 'ebook' | 'audiobook' | 'podcast' {
    if (format === 'audiobook' || format === 'ebook_audio') return 'audiobook';
    if (format === 'podcast') return 'podcast';
    return 'ebook';
  }
}

import { Inject, Injectable, NotFoundException } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import type { ContentFormat } from '../catalogue/catalogue.types';
import { StudioStore } from '../studio/studio.store';
import { LibraryStore } from './library.store';

@Injectable()
export class LibraryService {
  constructor(
    @Inject(LibraryStore) private readonly store: LibraryStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(StudioStore) private readonly studio: StudioStore,
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
    const entitled = this.store.isEntitled(uid, titleId, title.priceMinor === 0);
    return {
      titleId,
      entitled,
      reason: entitled
        ? title.priceMinor === 0
          ? 'free'
          : 'owned'
        : 'not_owned',
    };
  }

  /**
   * Prototype purchase grant. Real entitlements must come from verified payment
   * webhooks. First paid grant credits the creator ledger (70/30 of net receipts).
   */
  grant(uid: string, titleId: string) {
    const title = this.catalogue.getTitle(titleId);
    const alreadyOwned = this.store.isEntitled(uid, titleId, false);
    const ownedIds = this.store.grantOwnership(uid, titleId);

    if (!alreadyOwned && title.priceMinor > 0) {
      const draft = this.studio.findByPublishedTitleId(titleId);
      const creatorUid = draft?.creatorUid ?? title.creatorUid;
      if (creatorUid) {
        // Illustrative payment-processing deduction before the 70/30 split.
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
          note: 'Simulated purchase · net receipts after illustrative 3% processing fee',
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

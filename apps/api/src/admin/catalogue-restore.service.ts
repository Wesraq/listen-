import { Inject, Injectable, Logger, OnModuleInit } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { LibraryStore } from '../library/library.store';
import { StudioStore } from '../studio/studio.store';
import { AdminStore } from './admin.store';

/**
 * Catalogue is in-memory for the prototype. After API restart, republish any
 * Studio drafts already marked live so Home keeps showing approved titles.
 */
@Injectable()
export class CatalogueRestoreService implements OnModuleInit {
  private readonly logger = new Logger(CatalogueRestoreService.name);

  constructor(
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
    @Inject(LibraryStore) private readonly library: LibraryStore,
    @Inject(AdminStore) private readonly profiles: AdminStore,
  ) {}

  onModuleInit() {
    const live = this.studio.listAllDrafts().filter((d) => d.status === 'live');
    // Also keep creators who already published from needing to re-apply after API restarts.
    for (const draft of this.studio.listAllDrafts()) {
      if (!draft.creatorUid && !draft.creatorEmail) continue;
      const profile = this.profiles.ensureConsumer({
        uid: draft.creatorUid,
        email: draft.creatorEmail,
        displayName: draft.creatorDisplayName,
      });
      if (profile.creatorStatus === 'none' || profile.creatorStatus === 'pending') {
        // Live (or submitted) Studio work implies they were already an approved creator.
        if (draft.status === 'live' || draft.status === 'submitted') {
          this.profiles.setCreatorStatus(
            profile.uid,
            'approved',
            'system',
            'Restored from persisted Studio drafts',
          );
        }
      }
    }

    for (const draft of live) {
      const zmw = draft.prices.find((p) => p.currency === 'ZMW') ?? draft.prices[0];
      const author =
        draft.creatorDisplayName?.trim() ||
        this.profiles.findUser(draft.creatorUid, draft.creatorEmail)?.displayName ||
        draft.creatorEmail;
      const published = this.catalogue.publishCreatorTitle({
        draftId: draft.id,
        title: draft.title,
        author,
        format: draft.format,
        priceMinor: zmw?.amountMinor ?? 0,
        currency: zmw?.currency ?? 'ZMW',
        prices: draft.prices,
        category: draft.genre,
        mediaName: draft.mediaName,
        mediaId: draft.mediaId,
        coverImageId: draft.coverImageId,
        monetisationMode: draft.monetisationMode,
        subscriptionEligible: draft.subscriptionEligible,
        creatorUid: draft.creatorUid,
        chapters: draft.chapters,
        episodes: draft.episodes,
      });
      this.studio.markLive(draft.id, published.id);
      const profile = this.profiles.findUser(draft.creatorUid, draft.creatorEmail);
      const ownerUid = profile?.uid ?? draft.creatorUid;
      this.library.grantOwnership(ownerUid, published.id);
      if (ownerUid !== draft.creatorUid) {
        this.library.grantOwnership(draft.creatorUid, published.id);
      }
      this.logger.log(`Restored live title “${published.name}” → ${published.id}`);
    }
  }
}

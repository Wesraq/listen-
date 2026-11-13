import { BadRequestException, Inject, Injectable } from '@nestjs/common';

import { CatalogueService } from '../catalogue/catalogue.service';
import { StudioStore } from '../studio/studio.store';

/** Illustrative gross receipt per completed ad event (ZMW minor units). */
const AD_GROSS_MINOR = 50; // ZMW 0.50

@Injectable()
export class AdsService {
  /** listenerKey -> completion timestamps (ms) for hourly caps. */
  private readonly completions = new Map<string, number[]>();

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
  }) {
    if (input.completedSec < 5) {
      throw new BadRequestException('Ad must play at least 5 seconds to monetise');
    }

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
    const hourAgo = now - 60 * 60 * 1000;
    const recent = (this.completions.get(key) ?? []).filter((t) => t >= hourAgo);
    if (recent.length >= 3) {
      throw new BadRequestException('Hourly ad cap reached (max 3 completed ads)');
    }
    recent.push(now);
    this.completions.set(key, recent);

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
      note: `Verified ${input.placement} · ${input.completedSec}s · listener ${input.listenerUid.slice(0, 8)}`,
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

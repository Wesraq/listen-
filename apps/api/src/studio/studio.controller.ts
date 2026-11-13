import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  NotFoundException,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';

import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthUser } from '../auth/auth.types';
import { CatalogueService } from '../catalogue/catalogue.service';
import { StudioStore } from './studio.store';
import {
  PriceByCurrency,
  StudioChapter,
  StudioEpisode,
  StudioFormat,
} from './studio.types';

@Controller('studio')
@UseGuards(AuthGuard)
export class StudioController {
  constructor(
    @Inject(StudioStore) private readonly studio: StudioStore,
    @Inject(CatalogueService) private readonly catalogue: CatalogueService,
  ) {}

  @Get('drafts')
  drafts(@CurrentUser() user: AuthUser) {
    return {
      items: this.studio.listDrafts(user.uid, user.email),
    };
  }

  @Post('drafts')
  createDraft(
    @CurrentUser() user: AuthUser,
    @Body()
    body: {
      title?: string;
      format?: StudioFormat;
      genre?: string;
      prices?: PriceByCurrency[];
      monetisationMode?: 'purchase' | 'free_with_ads' | 'subscription' | 'premium_purchase';
      subscriptionEligible?: boolean;
      mediaName?: string;
      mediaKind?: 'epub' | 'audio' | 'other';
      mediaBytes?: number;
      mediaId?: string;
      coverImageName?: string;
      coverImageBytes?: number;
      chapters?: StudioChapter[];
      episodes?: StudioEpisode[];
      submit?: boolean;
      email?: string;
      displayName?: string;
    },
  ) {
    const title = body.title?.trim();
    if (!title) throw new BadRequestException('Title is required');
    const creatorEmail =
      body.email?.trim() || user.email?.trim() || `${user.uid}@listeners.listen.plus`;
    const format = body.format ?? 'ebook';
    const isPodcast = format === 'podcast';
    const draft = this.studio.createDraft({
      creatorUid: user.uid,
      creatorEmail,
      creatorDisplayName: body.displayName?.trim() || user.displayName,
      title,
      format,
      genre: body.genre,
      prices: body.prices?.length
        ? body.prices
        : isPodcast
          ? [
              { currency: 'ZMW', amountMinor: 0 },
              { currency: 'USD', amountMinor: 0 },
              { currency: 'ZAR', amountMinor: 0 },
            ]
          : [{ currency: 'ZMW', amountMinor: 8500 }],
      monetisationMode: body.monetisationMode,
      subscriptionEligible: body.subscriptionEligible,
      mediaName: body.mediaName,
      mediaKind: body.mediaKind,
      mediaBytes: body.mediaBytes,
      mediaId: body.mediaId,
      coverImageName: body.coverImageName,
      coverImageBytes: body.coverImageBytes,
      chapters: body.chapters,
      episodes: body.episodes,
      status: body.submit ? 'submitted' : 'draft',
    });
    return draft;
  }

  @Post('drafts/:id/submit')
  submit(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    const draft = this.studio.submitDraft(id, user.uid);
    if (!draft) throw new NotFoundException('Draft not found');
    return draft;
  }

  @Patch('drafts/:id')
  updateDraft(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Body()
    body: {
      title?: string;
      format?: StudioFormat;
      genre?: string;
      prices?: PriceByCurrency[];
      monetisationMode?: 'purchase' | 'free_with_ads' | 'subscription' | 'premium_purchase';
      subscriptionEligible?: boolean;
      mediaName?: string;
      mediaKind?: 'epub' | 'audio' | 'other';
      mediaBytes?: number;
      mediaId?: string;
      coverImageName?: string;
      coverImageBytes?: number;
      chapters?: StudioChapter[];
      episodes?: StudioEpisode[];
      submit?: boolean;
      email?: string;
      displayName?: string;
    },
  ) {
    const draft = this.studio.updateDraft(id, user.uid, {
      title: body.title,
      format: body.format,
      genre: body.genre,
      prices: body.prices,
      monetisationMode: body.monetisationMode,
      subscriptionEligible: body.subscriptionEligible,
      mediaName: body.mediaName,
      mediaKind: body.mediaKind,
      mediaBytes: body.mediaBytes,
      mediaId: body.mediaId,
      coverImageName: body.coverImageName,
      coverImageBytes: body.coverImageBytes,
      chapters: body.chapters,
      episodes: body.episodes,
      status: body.submit ? 'submitted' : body.submit === false ? 'draft' : undefined,
      creatorEmail: body.email?.trim() || user.email,
      creatorDisplayName: body.displayName?.trim() || user.displayName,
    });
    if (!draft) throw new NotFoundException('Draft not found');
    this.syncLiveCatalogue(draft);
    return draft;
  }

  @Delete('drafts/:id')
  deleteDraft(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    if (!this.studio.deleteDraft(id, user.uid)) {
      throw new NotFoundException('Draft not found');
    }
    return { ok: true };
  }

  @Get('sales')
  sales(@CurrentUser() user: AuthUser) {
    return this.studio.salesFor(user.uid, user.email);
  }

  /** Keep live catalogue chapters/episodes in sync when the creator edits parts. */
  private syncLiveCatalogue(draft: {
    status: string;
    publishedTitleId?: string;
    format: StudioFormat;
    title: string;
    creatorDisplayName?: string;
    creatorEmail: string;
    creatorUid?: string;
    genre?: string;
    prices: PriceByCurrency[];
    mediaName?: string;
    mediaId?: string;
    monetisationMode?: 'purchase' | 'free_with_ads' | 'subscription' | 'premium_purchase';
    subscriptionEligible?: boolean;
    chapters?: StudioChapter[];
    episodes?: StudioEpisode[];
    id: string;
  }) {
    if (draft.status !== 'live' || !draft.publishedTitleId) return;
    const zmw = draft.prices.find((p) => p.currency === 'ZMW') ?? draft.prices[0];
    this.catalogue.publishCreatorTitle({
      draftId: draft.id,
      title: draft.title,
      author: draft.creatorDisplayName?.trim() || draft.creatorEmail,
      format: draft.format,
      priceMinor: zmw?.amountMinor ?? 0,
      currency: zmw?.currency ?? 'ZMW',
      prices: draft.prices,
      category: draft.genre,
      mediaName: draft.mediaName,
      mediaId: draft.mediaId,
      monetisationMode: draft.monetisationMode,
      subscriptionEligible: draft.subscriptionEligible,
      creatorUid: draft.creatorUid,
      chapters: draft.chapters,
      episodes: draft.episodes,
    });
  }
}

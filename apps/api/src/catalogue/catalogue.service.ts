import { Inject, Injectable } from '@nestjs/common';

import { CatalogueStore } from './catalogue.store';
import {
  AudioTrackDto,
  CategoryDto,
  ChapterDto,
  CollectionDto,
  ContentFormat,
  TitleDto,
} from './catalogue.types';

@Injectable()
export class CatalogueService {
  constructor(@Inject(CatalogueStore) private readonly store: CatalogueStore) {}

  listTitles(format?: ContentFormat, category?: string): TitleDto[] {
    return this.store.listTitles(format, category);
  }

  getTitle(id: string): TitleDto {
    return this.store.getTitle(id);
  }

  listCategories(): CategoryDto[] {
    return this.store.listCategories();
  }

  listCollections(): CollectionDto[] {
    return this.store.listCollections();
  }

  getCollection(id: string): CollectionDto & { items: TitleDto[] } {
    return this.store.getCollection(id);
  }

  getChapters(titleId: string): ChapterDto[] {
    return this.store.getChapters(titleId);
  }

  getTracks(titleId: string): AudioTrackDto[] {
    return this.store.getTracks(titleId);
  }

  publishCreatorTitle(input: {
    draftId: string;
    title: string;
    author: string;
    format: ContentFormat;
    priceMinor: number;
    currency?: string;
    prices?: { currency: string; amountMinor: number }[];
    description?: string;
    mediaName?: string;
    mediaId?: string;
    category?: string;
    monetisationMode?: TitleDto['monetisationMode'];
    subscriptionEligible?: boolean;
    creatorUid?: string;
    chapters?: { id: string; title: string; body: string; sortOrder?: number }[];
    episodes?: {
      id: string;
      title: string;
      durationSec: number;
      mediaName?: string;
      mediaId?: string;
      sortOrder?: number;
      showNotes?: string;
    }[];
  }): TitleDto {
    return this.store.publishCreatorTitle(input);
  }

  applyCreatorParts(
    titleId: string,
    input: {
      format: ContentFormat;
      chapters?: { id: string; title: string; body: string; sortOrder?: number }[];
      episodes?: {
        id: string;
        title: string;
        durationSec: number;
        mediaName?: string;
        sortOrder?: number;
        showNotes?: string;
      }[];
    },
  ) {
    this.store.applyCreatorParts(titleId, input);
  }

  removeTitle(id: string): boolean {
    return this.store.removeTitle(id);
  }
}

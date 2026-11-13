import { Inject, Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';

import { DbService } from '../db/db.service';
import {
  categories as seedCategories,
  chaptersByTitle as seedChapters,
  collections as seedCollections,
  titles as seedTitles,
  tracksByTitle as seedTracks,
} from './catalogue.seed';
import {
  AudioTrackDto,
  CategoryDto,
  ChapterDto,
  CollectionDto,
  ContentFormat,
  TitleDto,
} from './catalogue.types';

@Injectable()
export class CatalogueStore implements OnModuleInit {
  private readonly logger = new Logger(CatalogueStore.name);
  private readonly titles: TitleDto[] = seedTitles.map((t) => ({ ...t }));
  private readonly chaptersByTitle: Record<string, ChapterDto[]> = {
    ...Object.fromEntries(
      Object.entries(seedChapters).map(([id, chapters]) => [id, chapters.map((c) => ({ ...c }))]),
    ),
  };
  private readonly tracksByTitle: Record<string, AudioTrackDto[]> = {
    ...Object.fromEntries(
      Object.entries(seedTracks).map(([id, tracks]) => [id, tracks.map((t) => ({ ...t }))]),
    ),
  };
  private readonly categories: CategoryDto[] = seedCategories.map((c) => ({ ...c }));
  private readonly collections: CollectionDto[] = seedCollections.map((c) => ({
    ...c,
    titleIds: [...c.titleIds],
  }));

  constructor(@Inject(DbService) private readonly db: DbService) {}

  async onModuleInit() {
    if (!this.db.enabled) return;
    try {
      const titles = await this.db.query<{ id: string; payload: TitleDto; sort_order: number }>(
        'SELECT id, payload, sort_order FROM catalogue_titles ORDER BY sort_order ASC, updated_at DESC',
      );
      for (const row of titles.rows) {
        const title = row.payload;
        const existingIndex = this.titles.findIndex((t) => t.id === title.id);
        if (existingIndex >= 0) this.titles[existingIndex] = title;
        else this.titles.unshift(title);

        const spotlight = this.collections.find((c) => c.id === 'editors');
        if (spotlight && !spotlight.titleIds.includes(title.id)) {
          spotlight.titleIds.unshift(title.id);
        }
      }

      const chapters = await this.db.query<{
        title_id: string;
        id: string;
        title: string;
        body: string;
        sort_order: number;
      }>(
        'SELECT title_id, id, title, body, sort_order FROM catalogue_chapters ORDER BY sort_order ASC',
      );
      const chapterTitles = new Set<string>();
      for (const row of chapters.rows) {
        if (!chapterTitles.has(row.title_id)) {
          this.chaptersByTitle[row.title_id] = [];
          chapterTitles.add(row.title_id);
        }
        this.chaptersByTitle[row.title_id].push({
          id: row.id,
          title: row.title,
          body: row.body,
        });
      }

      const tracks = await this.db.query<{
        title_id: string;
        id: string;
        title: string;
        duration_sec: number;
        media_url: string | null;
        media_name: string | null;
        sort_order: number;
      }>(
        `SELECT title_id, id, title, duration_sec, media_url, media_name, sort_order
         FROM catalogue_tracks ORDER BY sort_order ASC`,
      );
      const trackTitles = new Set<string>();
      for (const row of tracks.rows) {
        if (!trackTitles.has(row.title_id)) {
          this.tracksByTitle[row.title_id] = [];
          trackTitles.add(row.title_id);
        }
        this.tracksByTitle[row.title_id].push({
          id: row.id,
          title: row.title,
          durationSec: row.duration_sec,
          mediaUrl: row.media_url ?? undefined,
          mediaName: row.media_name ?? undefined,
        });
      }

      this.logger.log(`Loaded ${titles.rows.length} persisted catalogue title(s) from Postgres`);
    } catch (error) {
      this.logger.warn(`Failed to load catalogue from Postgres: ${error}`);
    }
  }

  private async persistTitle(title: TitleDto, sortOrder = 0) {
    if (!this.db.enabled) return;
    try {
      await this.db.query(
        `INSERT INTO catalogue_titles (id, payload, sort_order, updated_at)
         VALUES ($1, $2::jsonb, $3, NOW())
         ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, sort_order = EXCLUDED.sort_order, updated_at = NOW()`,
        [title.id, JSON.stringify(title), sortOrder],
      );
    } catch (error) {
      this.logger.warn(`Failed to persist catalogue title ${title.id}: ${error}`);
    }
  }

  private async persistParts(titleId: string) {
    if (!this.db.enabled) return;
    try {
      await this.db.query('DELETE FROM catalogue_chapters WHERE title_id = $1', [titleId]);
      await this.db.query('DELETE FROM catalogue_tracks WHERE title_id = $1', [titleId]);

      const chapters = this.chaptersByTitle[titleId] ?? [];
      for (let i = 0; i < chapters.length; i += 1) {
        const chapter = chapters[i];
        await this.db.query(
          `INSERT INTO catalogue_chapters (title_id, id, title, body, sort_order)
           VALUES ($1, $2, $3, $4, $5)`,
          [titleId, chapter.id, chapter.title, chapter.body, i],
        );
      }

      const tracks = this.tracksByTitle[titleId] ?? [];
      for (let i = 0; i < tracks.length; i += 1) {
        const track = tracks[i];
        await this.db.query(
          `INSERT INTO catalogue_tracks (title_id, id, title, duration_sec, media_url, media_name, sort_order)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            titleId,
            track.id,
            track.title,
            track.durationSec,
            track.mediaUrl ?? null,
            track.mediaName ?? null,
            i,
          ],
        );
      }
    } catch (error) {
      this.logger.warn(`Failed to persist catalogue parts for ${titleId}: ${error}`);
    }
  }

  private async deletePersistedTitle(id: string) {
    if (!this.db.enabled) return;
    try {
      await this.db.query('DELETE FROM catalogue_chapters WHERE title_id = $1', [id]);
      await this.db.query('DELETE FROM catalogue_tracks WHERE title_id = $1', [id]);
      await this.db.query('DELETE FROM catalogue_titles WHERE id = $1', [id]);
    } catch (error) {
      this.logger.warn(`Failed to delete catalogue title ${id} from Postgres: ${error}`);
    }
  }

  listTitles(format?: ContentFormat, category?: string): TitleDto[] {
    return this.titles.filter((title) => {
      if (format && title.format !== format) return false;
      if (category && title.category !== category) return false;
      return true;
    });
  }

  getTitle(id: string): TitleDto {
    const title = this.titles.find((item) => item.id === id);
    if (!title) throw new NotFoundException(`Title ${id} not found`);
    return title;
  }

  listCategories(): CategoryDto[] {
    return this.categories;
  }

  listCollections(): CollectionDto[] {
    return this.collections;
  }

  getCollection(id: string): CollectionDto & { items: TitleDto[] } {
    const collection = this.collections.find((item) => item.id === id);
    if (!collection) throw new NotFoundException(`Collection ${id} not found`);
    return {
      ...collection,
      items: collection.titleIds.map((titleId) => this.getTitle(titleId)),
    };
  }

  getChapters(titleId: string): ChapterDto[] {
    this.getTitle(titleId);
    return this.chaptersByTitle[titleId] ?? [];
  }

  getTracks(titleId: string): AudioTrackDto[] {
    this.getTitle(titleId);
    return this.tracksByTitle[titleId] ?? [];
  }

  /**
   * Publish or refresh a creator draft in the consumer catalogue after admin approval.
   * Always overwrites title/author/price from the current Studio draft.
   */
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
    const id = `creator-${input.draftId.replace(/^draft-/, '').slice(0, 12)}`;
    // Only ship assets that exist in apps/mobile/assets/images/.
    const imageAsset =
      input.format === 'ebook' || input.format === 'ebook_audio'
        ? 'assets/images/jacaranda.jpg'
        : input.format === 'podcast'
          ? 'assets/images/zambezi.jpg'
          : 'assets/images/quiet.jpg';

    const chapterCount = input.chapters?.length ?? 0;
    const episodeCount = input.episodes?.length ?? 0;
    const lengthLabel =
      input.format === 'ebook_audio'
        ? [
            chapterCount > 0
              ? `${chapterCount} chapter${chapterCount === 1 ? '' : 's'}`
              : null,
            episodeCount > 0
              ? `${episodeCount} episode${episodeCount === 1 ? '' : 's'}`
              : null,
          ]
            .filter(Boolean)
            .join(' · ') || 'Ebook + audio'
        : input.format === 'ebook'
          ? chapterCount > 0
            ? `${chapterCount} chapter${chapterCount === 1 ? '' : 's'}`
            : 'Ebook'
          : episodeCount > 0
            ? `${episodeCount} episode${episodeCount === 1 ? '' : 's'}`
            : 'Audio';

    const partCount = chapterCount + episodeCount;
    const description =
      input.description?.trim() ||
      (partCount > 0
        ? `${partCount} part${partCount === 1 ? '' : 's'} available on Listen+.`
        : 'Available on Listen+.');

    const existing = this.titles.find((t) => t.id === id);
    let title: TitleDto;
    const monetisationMode =
      input.monetisationMode ??
      (input.format === 'podcast'
        ? input.priceMinor > 0
          ? 'premium_purchase'
          : 'free_with_ads'
        : 'purchase');
    const subscriptionEligible =
      input.subscriptionEligible ??
      (monetisationMode === 'subscription' || monetisationMode === 'purchase');

    const category =
      input.category?.trim() ||
      (input.format === 'podcast' ? 'Podcasts' : 'Fiction');

    if (existing) {
      existing.name = input.title;
      existing.author = input.author;
      existing.format = input.format;
      existing.priceMinor = input.priceMinor;
      existing.currency = input.currency ?? 'ZMW';
      existing.prices = input.prices?.map((p) => ({ ...p }));
      existing.category = category;
      existing.description = description;
      existing.length = lengthLabel;
      existing.imageAsset = imageAsset;
      existing.monetisationMode = monetisationMode;
      existing.subscriptionEligible = subscriptionEligible;
      existing.creatorUid = input.creatorUid ?? existing.creatorUid;
      existing.mediaName = input.mediaName ?? existing.mediaName;
      existing.mediaUrl = input.mediaId
        ? `/v1/media/${input.mediaId}`
        : existing.mediaUrl;
      title = existing;
    } else {
      title = {
        id,
        name: input.title,
        author: input.author,
        category,
        format: input.format,
        priceMinor: input.priceMinor,
        currency: input.currency ?? 'ZMW',
        prices: input.prices?.map((p) => ({ ...p })),
        imageAsset,
        rating: 'New',
        length: lengthLabel,
        description,
        monetisationMode,
        subscriptionEligible,
        creatorUid: input.creatorUid,
        mediaName: input.mediaName,
        mediaUrl: input.mediaId ? `/v1/media/${input.mediaId}` : undefined,
      };
      this.titles.unshift(title);
    }

    this.applyCreatorParts(id, input);

    const spotlight = this.collections.find((c) => c.id === 'editors');
    if (spotlight && !spotlight.titleIds.includes(id)) {
      spotlight.titleIds.unshift(id);
    }

    void this.persistTitle(title).then(() => this.persistParts(id));

    return title;
  }

  /** Replace catalogue chapters/tracks from Studio draft parts (or stubs). */
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
        mediaId?: string;
        sortOrder?: number;
        showNotes?: string;
        body?: string;
      }[];
    },
  ) {
    const wantsChapters =
      input.format === 'ebook' || input.format === 'ebook_audio';
    const wantsTracks =
      input.format === 'audiobook' ||
      input.format === 'podcast' ||
      input.format === 'ebook_audio';

    if (wantsChapters) {
      const chapters = [...(input.chapters ?? [])].sort(
        (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0),
      );
      this.chaptersByTitle[titleId] = chapters.length
        ? chapters.map((chapter, index) => ({
            id: chapter.id || `${titleId}-ch${index + 1}`,
            title: chapter.title,
            body: chapter.body,
          }))
        : [
            {
              id: `${titleId}-ch1`,
              title: 'Opening',
              body:
                'This chapter was published from a creator upload on Listen+. Full EPUB parsing arrives with storage-backed media.',
            },
            {
              id: `${titleId}-ch2`,
              title: 'Continuation',
              body:
                'Readers can bookmark, download offline, and leave notes while this title lives in the shared catalogue.',
            },
          ];
    } else {
      delete this.chaptersByTitle[titleId];
    }

    if (wantsTracks) {
      const episodes = [...(input.episodes ?? [])].sort(
        (a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0),
      );
      this.tracksByTitle[titleId] = episodes.length
        ? episodes.map((episode, index) => ({
            id: episode.id || `${titleId}-t${index + 1}`,
            title: episode.title,
            durationSec: episode.durationSec || 180,
            mediaName: episode.mediaName,
            mediaUrl: episode.mediaId ? `/v1/media/${episode.mediaId}` : undefined,
          }))
        : [
            { id: `${titleId}-t1`, title: 'Episode 1', durationSec: 180 },
            { id: `${titleId}-t2`, title: 'Episode 2', durationSec: 240 },
          ];
    } else {
      delete this.tracksByTitle[titleId];
    }
  }

  removeTitle(id: string): boolean {
    const index = this.titles.findIndex((t) => t.id === id);
    if (index < 0) return false;
    this.titles.splice(index, 1);
    delete this.chaptersByTitle[id];
    delete this.tracksByTitle[id];
    for (const collection of this.collections) {
      collection.titleIds = collection.titleIds.filter((titleId) => titleId !== id);
    }
    void this.deletePersistedTitle(id);
    return true;
  }
}

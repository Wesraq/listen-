export type ContentFormat = 'ebook' | 'audiobook' | 'podcast' | 'ebook_audio';

export interface TitlePriceDto {
  currency: string;
  amountMinor: number;
}

export type TitleMonetisationMode =
  | 'purchase'
  | 'free_with_ads'
  | 'subscription'
  | 'premium_purchase';

export interface TitleDto {
  id: string;
  name: string;
  author: string;
  category: string;
  format: ContentFormat;
  priceMinor: number;
  currency: string;
  /** Optional multi-currency list from Creator Studio. */
  prices?: TitlePriceDto[];
  imageAsset: string;
  rating: string;
  length: string;
  description: string;
  /** Creator earning model from Studio (hybrid policy). */
  monetisationMode?: TitleMonetisationMode;
  subscriptionEligible?: boolean;
  creatorUid?: string;
  /** Original uploaded manuscript file name (ebook PDF/EPUB/etc). */
  mediaName?: string;
  /** API-relative URL for the uploaded ebook file (`/v1/media/...`). */
  mediaUrl?: string;
}

export interface CategoryDto {
  name: string;
  description: string;
}

export interface CollectionDto {
  id: string;
  name: string;
  description: string;
  imageAsset: string;
  titleIds: string[];
}

export interface ChapterDto {
  id: string;
  title: string;
  body: string;
}

export interface AudioTrackDto {
  id: string;
  title: string;
  durationSec: number;
  /** Absolute or API-relative URL for the uploaded episode audio. */
  mediaUrl?: string;
  mediaName?: string;
}

export type StudioFormat = 'ebook' | 'audiobook' | 'podcast' | 'ebook_audio';

export type StudioDraftStatus = 'draft' | 'submitted' | 'live';

/** How a creator credit was earned (Listen+ hybrid monetisation policy v1). */
export type CreatorEarningStream =
  | 'purchase'
  | 'subscription_pool'
  | 'advertising'
  | 'creator_membership';

export interface PriceByCurrency {
  currency: string;
  amountMinor: number;
}

/** Ebook chapter authored in Creator Studio. */
export interface StudioChapter {
  id: string;
  title: string;
  body: string;
  sortOrder: number;
  /** When true, this chapter is offered on “Read sample” before purchase. */
  isSample?: boolean;
}

/** Audiobook track / podcast episode authored in Creator Studio. */
export interface StudioEpisode {
  id: string;
  title: string;
  durationSec: number;
  /** Audio file name for this episode/track. */
  mediaName?: string;
  /** Uploaded media id from POST /v1/media (prototype disk store). */
  mediaId?: string;
  sortOrder: number;
  /** Listener-facing show notes. */
  showNotes?: string;
  /** Script / episode body text the creator attaches as content. */
  body?: string;
  /** When true, this part is offered on “Listen to sample” before purchase. */
  isSample?: boolean;
}

/** How the title is meant to earn (hybrid monetisation policy). */
export type StudioMonetisationMode =
  | 'purchase'
  | 'free_with_ads'
  | 'subscription'
  | 'premium_purchase';

export interface StudioDraft {
  id: string;
  creatorUid: string;
  creatorEmail: string;
  creatorDisplayName?: string;
  title: string;
  format: StudioFormat;
  /** Catalogue genre / browse category. */
  genre?: string;
  prices: PriceByCurrency[];
  /**
   * purchase — buy the title (ebook/audiobook default)
   * free_with_ads — free catalogue + ads (podcast default)
   * subscription — eligible / exclusive via Listen+ sub
   * premium_purchase — paid premium podcast series/episodes
   */
  monetisationMode?: StudioMonetisationMode;
  /** Eligible for the subscription creator pool. */
  subscriptionEligible?: boolean;
  mediaName?: string;
  mediaKind?: 'epub' | 'audio' | 'other';
  mediaBytes?: number;
  /** Uploaded primary media id (ebook file / single audio). */
  mediaId?: string;
  /** Cover / profile image metadata. */
  coverImageName?: string;
  coverImageBytes?: number;
  /** Uploaded cover media id (durable; replaces device-local paths). */
  coverImageId?: string;
  chapters?: StudioChapter[];
  episodes?: StudioEpisode[];
  status: StudioDraftStatus;
  createdAt: string;
  updatedAt: string;
  /** Set when moderation publishes the draft to the consumer catalogue. */
  publishedTitleId?: string;
}

export interface SaleRow {
  id: string;
  creatorUid: string;
  titleId: string;
  titleName: string;
  currency: string;
  /** Gross customer payment collected (before deductions). */
  grossMinor: number;
  /** Net receipts after tax/fees/refunds (royalty base). */
  netReceiptsMinor: number;
  creatorShareMinor: number;
  platformShareMinor: number;
  market: string;
  at: string;
  stream: CreatorEarningStream;
  format: 'ebook' | 'audiobook' | 'podcast';
  /** Human-readable note for statements (e.g. processing fee). */
  note?: string;
}

export interface EarningsByFormat {
  ebookMinor: number;
  audiobookMinor: number;
  podcastMinor: number;
  advertisingMinor: number;
}

export interface SalesDashboard {
  currency: string;
  /** Sum of creator royalties this period (all streams). */
  grossSalesMinor: number;
  availableMinor: number;
  pendingMinor: number;
  paidOutMinor: number;
  byFormat: EarningsByFormat;
  /** Proposed policy rates shown in Studio (not binding until commercial sign-off). */
  policy: {
    purchaseCreatorShareBps: number;
    purchasePlatformShareBps: number;
    subscriptionPoolCreatorBps: number;
    subscriptionPoolPlatformBps: number;
    advertisingCreatorBps: number;
    advertisingPlatformBps: number;
    subscriptionFormatWeights: {
      ebookBps: number;
      audiobookBps: number;
      podcastBps: number;
    };
    minPayoutMinor: number;
  };
  sales: SaleRow[];
}

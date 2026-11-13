import {
  AudioTrackDto,
  CategoryDto,
  ChapterDto,
  CollectionDto,
  TitleDto,
} from './catalogue.types';

/** Clean prototype catalogue — no seeded titles. */
export const titles: TitleDto[] = [];

export const categories: CategoryDto[] = [
  { name: 'Fiction', description: 'Stories, novels, and imaginative reading.' },
  { name: 'Personal growth', description: 'Self-development, habits, and wellbeing.' },
  { name: 'Business', description: 'Work, entrepreneurship, and money skills.' },
  { name: 'Culture', description: 'Arts, society, and contemporary life.' },
  { name: 'Biography', description: 'Lives and memoirs.' },
  { name: 'Education', description: 'Learning, study, and practical skills.' },
  { name: 'Faith & inspiration', description: 'Spiritual and uplifting titles.' },
  { name: 'History', description: 'Past events, places, and people.' },
  { name: 'Podcasts', description: 'Shows and episodic audio.' },
  { name: 'Independent voices', description: 'Creator Studio titles and indie releases.' },
];

export const collections: CollectionDto[] = [
  {
    id: 'editors',
    name: 'From creators',
    description: 'Approved titles from Listen+ Creator Studio.',
    imageAsset: 'assets/images/quiet.jpg',
    titleIds: [],
  },
];

export const chaptersByTitle: Record<string, ChapterDto[]> = {};

export const tracksByTitle: Record<string, AudioTrackDto[]> = {};

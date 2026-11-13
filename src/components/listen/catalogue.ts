import quiet from '@/assets/quiet.jpg';

export type Title = { id: string; name: string; author: string; category: string; format: 'Ebook' | 'Audiobook' | 'Podcast'; price: number; image: string; rating: string; length: string; description: string };
export const titles: Title[] = [];
export const money = (minor: number) => `ZMW ${(minor / 100).toFixed(2)}`;
export const sampleText = 'Upload a title in Creator Studio to see content here.';
export const placeholderCover = quiet;

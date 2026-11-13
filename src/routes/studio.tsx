import { createFileRoute } from '@tanstack/react-router';
import { StudioPage } from '@/components/listen/prototype';
import { pageHead } from '@/components/listen/metadata';
export const Route = createFileRoute('/studio')({ head: () => pageHead('Creator Studio', 'Listen+ studio: your world of books, audio and creative possibilities.'), component: StudioPage });

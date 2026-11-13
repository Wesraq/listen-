import { createFileRoute } from '@tanstack/react-router';
import { LibraryPage } from '@/components/listen/prototype';
import { pageHead } from '@/components/listen/metadata';
export const Route = createFileRoute('/library')({ head: () => pageHead('Your personal library', 'Listen+ library: your world of books, audio and creative possibilities.'), component: LibraryPage });

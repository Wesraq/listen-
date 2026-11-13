import { createFileRoute } from '@tanstack/react-router';
import { SearchPage } from '@/components/listen/prototype';
import { pageHead } from '@/components/listen/metadata';
export const Route = createFileRoute('/search')({ head: () => pageHead('Find your next story', 'Listen+ search: your world of books, audio and creative possibilities.'), component: SearchPage });

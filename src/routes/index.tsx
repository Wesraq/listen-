import { createFileRoute } from '@tanstack/react-router';
import { HomePage } from '@/components/listen/prototype';
import { pageHead } from '@/components/listen/metadata';
export const Route = createFileRoute('/')({ head: () => pageHead('Discover your next story', 'Explore books, audiobooks and fresh voices. Read and listen with Listen+, starting in Zambia.'), component: HomePage });

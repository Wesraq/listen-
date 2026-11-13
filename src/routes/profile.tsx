import { createFileRoute } from '@tanstack/react-router';
import { ProfilePage } from '@/components/listen/prototype';
import { pageHead } from '@/components/listen/metadata';
export const Route = createFileRoute('/profile')({ head: () => pageHead('Your profile', 'Listen+ profile: your world of books, audio and creative possibilities.'), component: ProfilePage });

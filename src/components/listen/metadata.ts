export const pageHead = (title: string, description: string) => ({ meta: [
  { title: `${title} | Listen+` }, { name: 'description', content: description },
  { property: 'og:title', content: `${title} | Listen+` }, { property: 'og:description', content: description },
  { property: 'og:type', content: 'website' }, { name: 'twitter:card', content: 'summary_large_image' },
] });
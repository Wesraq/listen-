/// Shared Listen+ catalogue genres (Studio picker + browse categories).
class ListenGenres {
  const ListenGenres._();

  static const options = <String>[
    'Fiction',
    'Personal growth',
    'Business',
    'Culture',
    'Biography',
    'Education',
    'Faith & inspiration',
    'History',
    'Podcasts',
    'Independent voices',
  ];

  static String defaultForFormat(String format) {
    final lower = format.toLowerCase();
    if (lower.contains('podcast')) return 'Podcasts';
    return 'Fiction';
  }

  static bool isKnown(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return options.any((g) => g.toLowerCase() == value.trim().toLowerCase());
  }
}

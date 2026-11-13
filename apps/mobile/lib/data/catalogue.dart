enum ContentFormat { ebook, audiobook, podcast, ebookAudio }

class TitleItem {
  const TitleItem({
    required this.id,
    required this.name,
    required this.author,
    required this.category,
    required this.format,
    required this.priceMinor,
    required this.imageAsset,
    required this.rating,
    required this.length,
    required this.description,
    this.currency = 'ZMW',
    this.prices = const [],
    this.monetisationMode,
    this.subscriptionEligible,
    this.creatorUid,
    this.mediaName,
    this.mediaUrl,
  });

  final String id;
  final String name;
  final String author;
  final String category;
  final ContentFormat format;
  final int priceMinor;
  final String currency;
  final List<({String currency, int amountMinor})> prices;
  final String imageAsset;
  final String rating;
  final String length;
  final String description;
  /// purchase | free_with_ads | subscription | premium_purchase
  final String? monetisationMode;
  final bool? subscriptionEligible;
  final String? creatorUid;
  /// Uploaded ebook manuscript file name (PDF/EPUB/etc).
  final String? mediaName;
  /// API media URL for the uploaded ebook file.
  final String? mediaUrl;

  String get resolvedMonetisationMode {
    if (monetisationMode != null && monetisationMode!.isNotEmpty) {
      return monetisationMode!;
    }
    if (format == ContentFormat.podcast) {
      return priceMinor > 0 ? 'premium_purchase' : 'free_with_ads';
    }
    return priceMinor == 0 ? 'free_with_ads' : 'purchase';
  }

  bool get showsAds => resolvedMonetisationMode == 'free_with_ads';


  String get priceLabel {
    if (showsAds) return 'Free · with ads';
    if (resolvedMonetisationMode == 'subscription' && priceMinor == 0) {
      return 'Listen+ subscription';
    }
    if (prices.isNotEmpty) {
      return prices
          .map((p) => money(p.amountMinor, currency: p.currency))
          .join(' · ');
    }
    return isFree ? 'Free' : money(priceMinor, currency: currency);
  }

  /// Compact price for tight cards — prefer the listener's market currency.
  String priceLabelFor(String preferredCurrency) {
    if (showsAds) return 'Free · ads';
    if (resolvedMonetisationMode == 'subscription' && priceMinor == 0) {
      return 'Subscription';
    }
    if (isFree) return 'Free';
    if (prices.isNotEmpty) {
      for (final quote in prices) {
        if (quote.currency == preferredCurrency) {
          return money(quote.amountMinor, currency: quote.currency);
        }
      }
      final first = prices.first;
      return money(first.amountMinor, currency: first.currency);
    }
    return money(priceMinor, currency: currency);
  }

  String get formatLabel => switch (format) {
        ContentFormat.ebook => 'Ebook',
        ContentFormat.audiobook => 'Audiobook',
        ContentFormat.podcast => 'Podcast',
        ContentFormat.ebookAudio => 'Ebook + Audiobook',
      };

  bool get isFree =>
      priceMinor == 0 ||
      showsAds ||
      (resolvedMonetisationMode == 'subscription' && priceMinor == 0);
  bool get isEbook =>
      format == ContentFormat.ebook || format == ContentFormat.ebookAudio;
  bool get isAudio =>
      format == ContentFormat.audiobook ||
      format == ContentFormat.podcast ||
      format == ContentFormat.ebookAudio;
  bool get isDualFormat => format == ContentFormat.ebookAudio;

  bool get isPdfEbook {
    final name = (mediaName ?? '').toLowerCase();
    if (name.endsWith('.pdf')) return true;
    final url = (mediaUrl ?? '').toLowerCase();
    return url.contains('.pdf');
  }

  factory TitleItem.fromJson(Map<String, dynamic> json) {
    final formatRaw = '${json['format'] ?? 'ebook'}';
    final prices = () {
      final raw = json['prices'];
      if (raw is! List) return const <({String currency, int amountMinor})>[];
      return raw
          .whereType<Map>()
          .map(
            (item) => (
              currency: '${item['currency'] ?? 'ZMW'}',
              amountMinor: (item['amountMinor'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    }();
    final priceMinor = (json['priceMinor'] as num?)?.toInt() ?? 0;
    final modeRaw = json['monetisationMode'] == null ? null : '${json['monetisationMode']}';
    final inferredMode = (modeRaw != null && modeRaw.isNotEmpty)
        ? modeRaw
        : (formatRaw == 'podcast'
            ? (prices.any((p) => p.amountMinor > 0) || priceMinor > 0
                ? 'premium_purchase'
                : 'free_with_ads')
            : (priceMinor == 0 ? 'free_with_ads' : 'purchase'));
    return TitleItem(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      author: '${json['author'] ?? ''}',
      category: '${json['category'] ?? ''}',
      format: switch (formatRaw) {
        'audiobook' => ContentFormat.audiobook,
        'podcast' => ContentFormat.podcast,
        'ebook_audio' => ContentFormat.ebookAudio,
        _ => ContentFormat.ebook,
      },
      priceMinor: priceMinor,
      currency: '${json['currency'] ?? 'ZMW'}',
      prices: prices,
      imageAsset: _resolvedImageAsset('${json['imageAsset'] ?? ''}'),
      rating: '${json['rating'] ?? 'New'}',
      length: '${json['length'] ?? ''}',
      description: '${json['description'] ?? ''}',
      monetisationMode: inferredMode,
      subscriptionEligible: json['subscriptionEligible'] as bool?,
      creatorUid: json['creatorUid'] == null ? null : '${json['creatorUid']}',
      mediaName: json['mediaName'] == null ? null : '${json['mediaName']}',
      mediaUrl: json['mediaUrl'] == null ? null : '${json['mediaUrl']}',
    );
  }
}

String money(int amountMinor, {String currency = 'ZMW'}) =>
    '$currency ${(amountMinor / 100).toStringAsFixed(2)}';

String _resolvedImageAsset(String raw) {
  const fallbacks = <String>[
    'assets/images/quiet.jpg',
    'assets/images/river.jpg',
    'assets/images/zambezi.jpg',
    'assets/images/jacaranda.jpg',
  ];
  if (raw.startsWith('assets/images/') && raw.endsWith('.jpg')) {
    return raw;
  }
  if (raw.contains('quiet')) return 'assets/images/quiet.jpg';
  if (raw.contains('river')) return 'assets/images/river.jpg';
  if (raw.contains('zambezi') || raw.contains('voices')) {
    return 'assets/images/zambezi.jpg';
  }
  if (raw.contains('jacaranda') || raw.contains('ebook')) {
    return 'assets/images/jacaranda.jpg';
  }
  return fallbacks.first;
}

class CategoryInfo {
  const CategoryInfo({required this.name, required this.description});

  final String name;
  final String description;
}

class CollectionInfo {
  const CollectionInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.imageAsset,
    required this.titleIds,
  });

  final String id;
  final String name;
  final String description;
  final String imageAsset;
  final List<String> titleIds;

  List<TitleItem> get items => titleIds
      .map(titleById)
      .whereType<TitleItem>()
      .toList();
}

class CreatorProfile {
  const CreatorProfile({
    required this.name,
    required this.bio,
    required this.titleIds,
  });

  final String name;
  final String bio;
  final List<String> titleIds;

  List<TitleItem> get works => titleIds
      .map(titleById)
      .whereType<TitleItem>()
      .toList();
}

CreatorProfile? creatorByName(String authorName) {
  final needle = authorName.trim().toLowerCase();
  for (final creator in creators) {
    if (creator.name.trim().toLowerCase() == needle) return creator;
  }
  final authored = titles.where((t) => t.author.trim().toLowerCase() == needle).toList();
  if (authored.isEmpty) return null;
  return CreatorProfile(
    name: authored.first.author,
    bio: 'Creator on Listen+.',
    titleIds: authored.map((t) => t.id).toList(),
  );
}

class SampleChapter {
  const SampleChapter({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

class SampleAudioTrack {
  const SampleAudioTrack({
    required this.id,
    required this.title,
    required this.durationSec,
    this.mediaUrl,
    this.mediaName,
  });

  final String id;
  final String title;
  final int durationSec;
  /// API-relative (`/v1/media/...`) or absolute URL for uploaded audio.
  final String? mediaUrl;
  final String? mediaName;

  String get durationLabel {
    final minutes = durationSec ~/ 60;
    final seconds = durationSec % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

const categories = <CategoryInfo>[
  CategoryInfo(name: 'Fiction', description: 'Stories, novels, and imaginative reading.'),
  CategoryInfo(name: 'Personal growth', description: 'Self-development, habits, and wellbeing.'),
  CategoryInfo(name: 'Business', description: 'Work, entrepreneurship, and money skills.'),
  CategoryInfo(name: 'Culture', description: 'Arts, society, and contemporary life.'),
  CategoryInfo(name: 'Biography', description: 'Lives and memoirs.'),
  CategoryInfo(name: 'Education', description: 'Learning, study, and practical skills.'),
  CategoryInfo(name: 'Faith & inspiration', description: 'Spiritual and uplifting titles.'),
  CategoryInfo(name: 'History', description: 'Past events, places, and people.'),
  CategoryInfo(name: 'Podcasts', description: 'Shows and episodic audio.'),
  CategoryInfo(name: 'Independent voices', description: 'Creator Studio titles and indie releases.'),
];

const collections = <CollectionInfo>[
  CollectionInfo(
    id: 'editors',
    name: 'From creators',
    description: 'Approved titles from Listen+ Creator Studio.',
    imageAsset: 'assets/images/quiet.jpg',
    titleIds: [],
  ),
];

List<TitleItem> titlesInCategory(String category) =>
    titles.where((title) => title.category == category).toList();

TitleItem? titleById(String id) {
  for (final title in titles) {
    if (title.id == id) return title;
  }
  return null;
}

const _placeholderBody = 'Content will appear here after a creator upload is approved.';

/// Sample ebook chapters keyed by title id.
const sampleChapters = <String, List<SampleChapter>>{};

/// Sample audio tracks keyed by title id.
const sampleTracks = <String, List<SampleAudioTrack>>{};

/// Runtime overlays from the Listen+ API (creator-published parts).
final Map<String, List<SampleChapter>> remoteChapters = {};
final Map<String, List<SampleAudioTrack>> remoteTracks = {};

void putRemoteChapters(String titleId, List<SampleChapter> chapters) {
  remoteChapters[titleId] = List<SampleChapter>.from(chapters);
}

void putRemoteTracks(String titleId, List<SampleAudioTrack> tracks) {
  remoteTracks[titleId] = List<SampleAudioTrack>.from(tracks);
}

List<SampleChapter> chaptersFor(String titleId) =>
    remoteChapters[titleId] ??
    sampleChapters[titleId] ??
    const [
      SampleChapter(id: 'sample-1', title: 'Chapter one', body: _placeholderBody),
      SampleChapter(id: 'sample-2', title: 'Chapter two', body: _placeholderBody),
    ];

List<SampleAudioTrack> tracksFor(String titleId) =>
    remoteTracks[titleId] ??
    sampleTracks[titleId] ??
    const [
      SampleAudioTrack(id: 'track-1', title: 'Part one', durationSec: 15 * 60),
      SampleAudioTrack(id: 'track-2', title: 'Part two', durationSec: 15 * 60),
    ];

const creators = <CreatorProfile>[];

/// Clean local catalogue — filled from API after approval.
const sampleTitles = <TitleItem>[];

/// Active catalogue — seeded locally, replaced when the API responds.
List<TitleItem> titles = List<TitleItem>.from(sampleTitles);

bool catalogueFromApi = false;

void replaceCatalogue(List<TitleItem> next, {required bool fromApi}) {
  titles = List<TitleItem>.from(next);
  catalogueFromApi = fromApi;
}

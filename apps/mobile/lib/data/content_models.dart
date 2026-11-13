import 'catalogue.dart';

class PriceQuote {
  const PriceQuote({required this.currency, required this.amountMinor});

  final String currency;
  final int amountMinor;

  String get label {
    final major = amountMinor / 100;
    return '$currency ${major.toStringAsFixed(2)}';
  }

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'amountMinor': amountMinor,
      };

  factory PriceQuote.fromJson(Map<String, dynamic> json) => PriceQuote(
        currency: '${json['currency'] ?? 'ZMW'}',
        amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
      );
}

class ContentChapter {
  const ContentChapter({
    required this.id,
    required this.title,
    required this.body,
    required this.sortOrder,
  });

  final String id;
  final String title;
  final String body;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'sortOrder': sortOrder,
      };

  factory ContentChapter.fromJson(Map<String, dynamic> json) => ContentChapter(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        body: '${json['body'] ?? ''}',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  ContentChapter copyWith({
    String? title,
    String? body,
    int? sortOrder,
  }) =>
      ContentChapter(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class ContentEpisode {
  const ContentEpisode({
    required this.id,
    required this.title,
    required this.durationSec,
    required this.sortOrder,
    this.mediaName,
    this.mediaPath,
    this.mediaId,
    this.showNotes,
    this.body,
  });

  final String id;
  final String title;
  final int durationSec;
  final int sortOrder;
  final String? mediaName;
  /// Local audio file for this episode.
  final String? mediaPath;
  /// Uploaded media id from the Listen+ API (`POST /media`).
  final String? mediaId;
  final String? showNotes;
  /// Script / episode text content.
  final String? body;

  bool get hasContent =>
      (mediaName != null && mediaName!.trim().isNotEmpty) ||
      (mediaId != null && mediaId!.trim().isNotEmpty) ||
      (body != null && body!.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'durationSec': durationSec,
        'sortOrder': sortOrder,
        'mediaName': mediaName,
        'mediaPath': mediaPath,
        'mediaId': mediaId,
        'showNotes': showNotes,
        'body': body,
      };

  factory ContentEpisode.fromJson(Map<String, dynamic> json) => ContentEpisode(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        mediaName: json['mediaName'] == null ? null : '${json['mediaName']}',
        mediaPath: json['mediaPath'] == null ? null : '${json['mediaPath']}',
        mediaId: json['mediaId'] == null ? null : '${json['mediaId']}',
        showNotes: json['showNotes'] == null ? null : '${json['showNotes']}',
        body: json['body'] == null ? null : '${json['body']}',
      );

  ContentEpisode copyWith({
    String? title,
    int? durationSec,
    int? sortOrder,
    String? mediaName,
    String? mediaPath,
    String? mediaId,
    String? showNotes,
    String? body,
    bool clearMedia = false,
  }) =>
      ContentEpisode(
        id: id,
        title: title ?? this.title,
        durationSec: durationSec ?? this.durationSec,
        sortOrder: sortOrder ?? this.sortOrder,
        mediaName: clearMedia ? null : (mediaName ?? this.mediaName),
        mediaPath: clearMedia ? null : (mediaPath ?? this.mediaPath),
        mediaId: clearMedia ? null : (mediaId ?? this.mediaId),
        showNotes: showNotes ?? this.showNotes,
        body: body ?? this.body,
      );
}

class CreatorDraft {
  const CreatorDraft({
    required this.id,
    required this.title,
    required this.format,
    required this.prices,
    required this.status,
    required this.createdAtMs,
    this.genre,
    this.monetisationMode,
    this.subscriptionEligible = true,
    this.mediaName,
    this.mediaPath,
    this.mediaKind,
    this.mediaBytes,
    this.mediaId,
    this.coverImageName,
    this.coverImagePath,
    this.coverImageBytes,
    this.coverImageId,
    this.chapters = const [],
    this.episodes = const [],
    this.publishedTitleId,
  });

  final String id;
  final String title;
  /// Ebook | Audiobook | Podcast | Ebook + Audiobook
  final String format;
  /// Catalogue genre / browse category.
  final String? genre;
  final List<PriceQuote> prices;
  /// purchase | free_with_ads | subscription | premium_purchase
  final String? monetisationMode;
  final bool subscriptionEligible;
  final String status; // draft | submitted | live
  final int createdAtMs;
  final String? mediaName;
  final String? mediaPath;
  final String? mediaKind; // epub | audio | other
  final int? mediaBytes;
  final String? mediaId;
  final String? coverImageName;
  final String? coverImagePath;
  final int? coverImageBytes;
  /// Durable uploaded cover media id.
  final String? coverImageId;
  final List<ContentChapter> chapters;
  final List<ContentEpisode> episodes;
  final String? publishedTitleId;

  String get priceSummary {
    final mode = monetisationMode ?? (format == 'Podcast' ? 'free_with_ads' : 'purchase');
    switch (mode) {
      case 'free_with_ads':
        return 'Free · ads';
      case 'subscription':
        return 'Subscription';
      case 'premium_purchase':
        return prices.isEmpty ? 'Premium' : prices.map((p) => p.label).join(' · ');
      default:
        if (prices.isEmpty) return 'No price';
        if (prices.every((p) => p.amountMinor == 0)) return 'Free';
        return prices.map((p) => p.label).join(' · ');
    }
  }

  bool get isDualFormat =>
      format == 'Ebook + Audiobook' || format.toLowerCase() == 'ebook_audio';

  bool get isEbook =>
      format.toLowerCase() == 'ebook' || isDualFormat;

  bool get isAudioFormat =>
      format.toLowerCase() == 'audiobook' ||
      format.toLowerCase() == 'podcast' ||
      isDualFormat;

  int get partCount =>
      (isEbook ? chapters.length : 0) + (isAudioFormat ? episodes.length : 0);

  String get partsSummary {
    final bits = <String>[];
    if (isEbook) {
      bits.add(
        chapters.isEmpty
            ? 'No chapters yet'
            : '${chapters.length} chapter${chapters.length == 1 ? '' : 's'}',
      );
    }
    if (isAudioFormat) {
      final isPodcast = format.toLowerCase() == 'podcast';
      final noun = isPodcast ? 'episode' : 'track';
      bits.add(
        episodes.isEmpty
            ? 'No ${noun}s yet'
            : '${episodes.length} $noun${episodes.length == 1 ? '' : 's'}',
      );
    }
    return bits.join(' · ');
  }

  ContentFormat get catalogueFormat {
    final key = format.trim().toLowerCase();
    if (key.contains('ebook') && key.contains('audio')) return ContentFormat.ebookAudio;
    if (key == 'audiobook') return ContentFormat.audiobook;
    if (key == 'podcast') return ContentFormat.podcast;
    return ContentFormat.ebook;
  }

  /// Deterministic catalogue id matching the API publish formula.
  String get inferredPublishedTitleId {
    final explicit = publishedTitleId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final raw = id
        .replaceFirst(RegExp(r'^draft-'), '')
        .replaceFirst(RegExp(r'^local-from-creator-'), '')
        .replaceFirst(RegExp(r'^local-from-'), '')
        .replaceFirst(RegExp(r'^local-'), '');
    final slice = raw.length <= 12 ? raw : raw.substring(0, 12);
    return 'creator-$slice';
  }

  /// Build a catalogue card when the API catalogue is missing this live title.
  TitleItem toCatalogueTitle({required String author}) {
    final quote = prices.isEmpty ? null : prices.first;
    final lengthBits = <String>[];
    if (isEbook && chapters.isNotEmpty) {
      lengthBits.add('${chapters.length} chapter${chapters.length == 1 ? '' : 's'}');
    }
    if (isAudioFormat && episodes.isNotEmpty) {
      final isPodcast = format.toLowerCase() == 'podcast';
      final noun = isPodcast ? 'episode' : 'track';
      lengthBits.add('${episodes.length} $noun${episodes.length == 1 ? '' : 's'}');
    }
    return TitleItem(
      id: inferredPublishedTitleId,
      name: title,
      author: author,
      category: genre?.trim().isNotEmpty == true ? genre!.trim() : 'Fiction',
      format: catalogueFormat,
      priceMinor: quote?.amountMinor ?? 0,
      currency: quote?.currency ?? 'ZMW',
      prices: prices
          .map((p) => (currency: p.currency, amountMinor: p.amountMinor))
          .toList(),
      imageAsset: switch (catalogueFormat) {
        ContentFormat.podcast => 'assets/images/zambezi.jpg',
        ContentFormat.audiobook => 'assets/images/quiet.jpg',
        _ => 'assets/images/jacaranda.jpg',
      },
      rating: 'New',
      length: lengthBits.isEmpty ? format : lengthBits.join(' · '),
      description: 'Available on Listen+.',
      monetisationMode: monetisationMode,
      subscriptionEligible: subscriptionEligible,
      mediaName: mediaName,
      coverImageId: coverImageId,
      coverUrl: coverImageId == null || coverImageId!.isEmpty
          ? null
          : '/v1/media/$coverImageId',
    );
  }

  bool get canEdit => status == 'draft' || status == 'submitted' || status == 'live';

  bool get isLive => status == 'live';

  CreatorDraft copyWith({
    String? title,
    String? format,
    String? genre,
    List<PriceQuote>? prices,
    String? monetisationMode,
    bool? subscriptionEligible,
    String? status,
    String? mediaName,
    String? mediaPath,
    String? mediaKind,
    int? mediaBytes,
    String? mediaId,
    String? coverImageName,
    String? coverImagePath,
    int? coverImageBytes,
    String? coverImageId,
    List<ContentChapter>? chapters,
    List<ContentEpisode>? episodes,
    String? publishedTitleId,
    bool clearMedia = false,
    bool clearCover = false,
  }) =>
      CreatorDraft(
        id: id,
        title: title ?? this.title,
        format: format ?? this.format,
        genre: genre ?? this.genre,
        prices: prices ?? this.prices,
        monetisationMode: monetisationMode ?? this.monetisationMode,
        subscriptionEligible: subscriptionEligible ?? this.subscriptionEligible,
        status: status ?? this.status,
        createdAtMs: createdAtMs,
        mediaName: clearMedia ? null : (mediaName ?? this.mediaName),
        mediaPath: clearMedia ? null : (mediaPath ?? this.mediaPath),
        mediaKind: clearMedia ? null : (mediaKind ?? this.mediaKind),
        mediaBytes: clearMedia ? null : (mediaBytes ?? this.mediaBytes),
        mediaId: clearMedia ? null : (mediaId ?? this.mediaId),
        coverImageName: clearCover ? null : (coverImageName ?? this.coverImageName),
        coverImagePath: clearCover ? null : (coverImagePath ?? this.coverImagePath),
        coverImageBytes: clearCover ? null : (coverImageBytes ?? this.coverImageBytes),
        coverImageId: clearCover ? null : (coverImageId ?? this.coverImageId),
        chapters: chapters ?? this.chapters,
        episodes: episodes ?? this.episodes,
        publishedTitleId: publishedTitleId ?? this.publishedTitleId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'format': format,
        'genre': genre,
        'prices': prices.map((p) => p.toJson()).toList(),
        'monetisationMode': monetisationMode,
        'subscriptionEligible': subscriptionEligible,
        'status': status,
        'createdAtMs': createdAtMs,
        'mediaName': mediaName,
        'mediaPath': mediaPath,
        'mediaKind': mediaKind,
        'mediaBytes': mediaBytes,
        'mediaId': mediaId,
        'coverImageName': coverImageName,
        'coverImagePath': coverImagePath,
        'coverImageBytes': coverImageBytes,
        'coverImageId': coverImageId,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'publishedTitleId': publishedTitleId,
      };

  factory CreatorDraft.fromJson(Map<String, dynamic> json) {
    final pricesRaw = json['prices'];
    final prices = <PriceQuote>[];
    if (pricesRaw is List) {
      for (final item in pricesRaw) {
        if (item is Map<String, dynamic>) {
          prices.add(PriceQuote.fromJson(item));
        } else if (item is Map) {
          prices.add(PriceQuote.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    List<ContentChapter> parseChapters() {
      final raw = json['chapters'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => ContentChapter.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    List<ContentEpisode> parseEpisodes() {
      final raw = json['episodes'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => ContentEpisode.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    final format = '${json['format'] ?? 'Ebook'}';
    final modeRaw = json['monetisationMode'] == null ? null : '${json['monetisationMode']}';
    final inferredMode = modeRaw ??
        (format == 'Podcast'
            ? (prices.any((p) => p.amountMinor > 0) ? 'premium_purchase' : 'free_with_ads')
            : 'purchase');
    return CreatorDraft(
      id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
      title: '${json['title'] ?? ''}',
      format: format,
      genre: json['genre'] == null ? null : '${json['genre']}',
      prices: prices,
      monetisationMode: inferredMode,
      subscriptionEligible: json['subscriptionEligible'] as bool? ?? format != 'Podcast',
      status: '${json['status'] ?? 'draft'}',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      mediaName: json['mediaName'] == null ? null : '${json['mediaName']}',
      mediaPath: json['mediaPath'] == null ? null : '${json['mediaPath']}',
      mediaKind: json['mediaKind'] == null ? null : '${json['mediaKind']}',
      mediaBytes: (json['mediaBytes'] as num?)?.toInt(),
      mediaId: json['mediaId'] == null ? null : '${json['mediaId']}',
      coverImageName: json['coverImageName'] == null ? null : '${json['coverImageName']}',
      coverImagePath: json['coverImagePath'] == null ? null : '${json['coverImagePath']}',
      coverImageBytes: (json['coverImageBytes'] as num?)?.toInt(),
      coverImageId: json['coverImageId'] == null ? null : '${json['coverImageId']}',
      chapters: parseChapters(),
      episodes: parseEpisodes(),
      publishedTitleId:
          json['publishedTitleId'] == null ? null : '${json['publishedTitleId']}',
    );
  }

  factory CreatorDraft.fromLegacyLabel(String label) {
    final parts = label.split(' · ');
    return CreatorDraft(
      id: 'legacy-${label.hashCode}',
      title: parts.isNotEmpty ? parts.first : label,
      format: parts.length > 1 ? parts[1] : 'Ebook',
      prices: const [PriceQuote(currency: 'ZMW', amountMinor: 8500)],
      status: 'draft',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class EarningsByFormat {
  const EarningsByFormat({
    this.ebookMinor = 0,
    this.audiobookMinor = 0,
    this.podcastMinor = 0,
    this.advertisingMinor = 0,
  });

  final int ebookMinor;
  final int audiobookMinor;
  final int podcastMinor;
  final int advertisingMinor;

  factory EarningsByFormat.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EarningsByFormat();
    return EarningsByFormat(
      ebookMinor: (json['ebookMinor'] as num?)?.toInt() ?? 0,
      audiobookMinor: (json['audiobookMinor'] as num?)?.toInt() ?? 0,
      podcastMinor: (json['podcastMinor'] as num?)?.toInt() ?? 0,
      advertisingMinor: (json['advertisingMinor'] as num?)?.toInt() ?? 0,
    );
  }
}

class MonetisationPolicy {
  const MonetisationPolicy({
    this.purchaseCreatorShareBps = 7000,
    this.subscriptionPoolCreatorBps = 6000,
    this.advertisingCreatorBps = 5500,
    this.minPayoutMinor = 20000,
  });

  final int purchaseCreatorShareBps;
  final int subscriptionPoolCreatorBps;
  final int advertisingCreatorBps;
  final int minPayoutMinor;

  factory MonetisationPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MonetisationPolicy();
    return MonetisationPolicy(
      purchaseCreatorShareBps: (json['purchaseCreatorShareBps'] as num?)?.toInt() ?? 7000,
      subscriptionPoolCreatorBps:
          (json['subscriptionPoolCreatorBps'] as num?)?.toInt() ?? 6000,
      advertisingCreatorBps: (json['advertisingCreatorBps'] as num?)?.toInt() ?? 5500,
      minPayoutMinor: (json['minPayoutMinor'] as num?)?.toInt() ?? 20000,
    );
  }

  String get purchaseSplitLabel =>
      '${purchaseCreatorShareBps ~/ 100}/${100 - purchaseCreatorShareBps ~/ 100}';
  String get subscriptionSplitLabel =>
      '${subscriptionPoolCreatorBps ~/ 100}/${100 - subscriptionPoolCreatorBps ~/ 100}';
  String get advertisingSplitLabel =>
      '${advertisingCreatorBps ~/ 100}/${100 - advertisingCreatorBps ~/ 100}';
}

class SalesDashboard {
  const SalesDashboard({
    required this.currency,
    required this.grossSalesMinor,
    required this.availableMinor,
    required this.pendingMinor,
    required this.sales,
    this.paidOutMinor = 0,
    this.byFormat = const EarningsByFormat(),
    this.policy = const MonetisationPolicy(),
  });

  final String currency;
  final int grossSalesMinor;
  final int availableMinor;
  final int pendingMinor;
  final int paidOutMinor;
  final EarningsByFormat byFormat;
  final MonetisationPolicy policy;
  final List<SaleLine> sales;

  String money(int minor) => '$currency ${(minor / 100).toStringAsFixed(2)}';

  factory SalesDashboard.empty() => const SalesDashboard(
        currency: 'ZMW',
        grossSalesMinor: 0,
        availableMinor: 0,
        pendingMinor: 0,
        sales: [],
      );

  factory SalesDashboard.fromJson(Map<String, dynamic> json) {
    final salesRaw = json['sales'];
    final sales = <SaleLine>[];
    if (salesRaw is List) {
      for (final item in salesRaw) {
        if (item is Map<String, dynamic>) {
          sales.add(SaleLine.fromJson(item));
        } else if (item is Map) {
          sales.add(SaleLine.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final byFormatRaw = json['byFormat'];
    final policyRaw = json['policy'];
    return SalesDashboard(
      currency: '${json['currency'] ?? 'ZMW'}',
      grossSalesMinor: (json['grossSalesMinor'] as num?)?.toInt() ?? 0,
      availableMinor: (json['availableMinor'] as num?)?.toInt() ?? 0,
      pendingMinor: (json['pendingMinor'] as num?)?.toInt() ?? 0,
      paidOutMinor: (json['paidOutMinor'] as num?)?.toInt() ?? 0,
      byFormat: EarningsByFormat.fromJson(
        byFormatRaw is Map ? Map<String, dynamic>.from(byFormatRaw) : null,
      ),
      policy: MonetisationPolicy.fromJson(
        policyRaw is Map ? Map<String, dynamic>.from(policyRaw) : null,
      ),
      sales: sales,
    );
  }
}

class SaleLine {
  const SaleLine({
    required this.id,
    required this.titleName,
    required this.currency,
    required this.grossMinor,
    required this.creatorShareMinor,
    required this.at,
    this.stream = 'purchase',
    this.format = 'ebook',
    this.netReceiptsMinor,
    this.note,
  });

  final String id;
  final String titleName;
  final String currency;
  final int grossMinor;
  final int creatorShareMinor;
  final String at;
  final String stream;
  final String format;
  final int? netReceiptsMinor;
  final String? note;

  String get streamLabel => switch (stream) {
        'subscription_pool' => 'Subscription pool',
        'advertising' => 'Advertising',
        'creator_membership' => 'Membership',
        _ => 'Purchase',
      };

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
        id: '${json['id'] ?? ''}',
        titleName: '${json['titleName'] ?? ''}',
        currency: '${json['currency'] ?? 'ZMW'}',
        grossMinor: (json['grossMinor'] as num?)?.toInt() ?? 0,
        creatorShareMinor: (json['creatorShareMinor'] as num?)?.toInt() ?? 0,
        at: '${json['at'] ?? ''}',
        stream: '${json['stream'] ?? 'purchase'}',
        format: '${json['format'] ?? 'ebook'}',
        netReceiptsMinor: (json['netReceiptsMinor'] as num?)?.toInt(),
        note: json['note'] == null ? null : '${json['note']}',
      );
}

class ContentNote {
  const ContentNote({
    required this.id,
    required this.titleId,
    required this.kind,
    required this.anchor,
    required this.locationId,
    required this.position,
    required this.createdAtMs,
    this.text,
    this.voicePath,
    this.voiceDurationSec,
  });

  final String id;
  final String titleId;
  final String kind; // text | voice
  final String anchor; // chapter | audio
  final String locationId;
  final double position;
  final int createdAtMs;
  final String? text;
  final String? voicePath;
  final double? voiceDurationSec;

  String get anchorLabel {
    if (anchor == 'audio') {
      final m = position.floor() ~/ 60;
      final s = position.floor() % 60;
      return 'At $m:${s.toString().padLeft(2, '0')}';
    }
    final pct = (position * 100).round().clamp(0, 100);
    return 'About $pct% through the chapter';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titleId': titleId,
        'kind': kind,
        'anchor': anchor,
        'locationId': locationId,
        'position': position,
        'createdAtMs': createdAtMs,
        'text': text,
        'voicePath': voicePath,
        'voiceDurationSec': voiceDurationSec,
      };

  factory ContentNote.fromJson(Map<String, dynamic> json) => ContentNote(
        id: '${json['id'] ?? ''}',
        titleId: '${json['titleId'] ?? ''}',
        kind: '${json['kind'] ?? 'text'}',
        anchor: '${json['anchor'] ?? 'chapter'}',
        locationId: '${json['locationId'] ?? ''}',
        position: (json['position'] as num?)?.toDouble() ?? 0,
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ??
            DateTime.tryParse('${json['createdAt'] ?? ''}')?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        text: json['text'] == null ? null : '${json['text']}',
        voicePath: json['voicePath'] == null && json['voiceRef'] == null
            ? null
            : '${json['voicePath'] ?? json['voiceRef']}',
        voiceDurationSec: (json['voiceDurationSec'] as num?)?.toDouble(),
      );
}

class OfflineDownload {
  const OfflineDownload({
    required this.titleId,
    required this.format,
    required this.cachedAtMs,
    required this.bytes,
    this.localPath,
  });

  final String titleId;
  final String format;
  final int cachedAtMs;
  final int bytes;
  final String? localPath;

  Map<String, dynamic> toJson() => {
        'titleId': titleId,
        'format': format,
        'cachedAtMs': cachedAtMs,
        'bytes': bytes,
        'localPath': localPath,
      };

  factory OfflineDownload.fromJson(Map<String, dynamic> json) => OfflineDownload(
        titleId: '${json['titleId'] ?? ''}',
        format: '${json['format'] ?? 'Ebook'}',
        cachedAtMs: (json['cachedAtMs'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        localPath: json['localPath'] == null ? null : '${json['localPath']}',
      );
}

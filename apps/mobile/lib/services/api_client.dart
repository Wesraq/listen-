import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/catalogue.dart';
import '../data/content_models.dart';
import 'api_config.dart';

class LibraryRemote {
  const LibraryRemote({
    required this.ownedIds,
    required this.savedIds,
  });

  final List<String> ownedIds;
  final List<String> savedIds;
}

class ProfileRemote {
  const ProfileRemote({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.creatorStatus,
    required this.role,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String creatorStatus;
  final String role;
}

class ListenApiClient {
  ListenApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized').replace(queryParameters: query);
  }

  Future<bool> health() async {
    try {
      final response = await _client.get(_uri('/health')).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<TitleItem>?> fetchTitles() async {
    try {
      final response = await _client.get(_uri('/catalogue/titles')).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final items = decoded['items'];
      if (items is! List) return null;
      return items.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        final mediaUrl = map['mediaUrl'];
        if (mediaUrl is String && mediaUrl.isNotEmpty) {
          map['mediaUrl'] = absoluteMediaUrl(mediaUrl);
        }
        return TitleItem.fromJson(map);
      }).toList();
    } catch (_) {
      return null;
    }
  }

  /// Download media bytes to [destinationPath] (ebook PDFs, etc).
  Future<String?> downloadMediaFile(
    String mediaUrl, {
    required String destinationPath,
  }) async {
    try {
      final absolute = absoluteMediaUrl(mediaUrl);
      if (absolute.isEmpty) return null;
      final response = await _client
          .get(Uri.parse(absolute))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final file = File(destinationPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<LibraryRemote?> fetchLibrary(String bearerToken) async {
    try {
      final response = await _client
          .get(
            _uri('/library'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final owned = (decoded['ownedIds'] as List<dynamic>? ?? const []).map((e) => '$e').toList();
      final saved = (decoded['savedIds'] as List<dynamic>? ?? const []).map((e) => '$e').toList();
      return LibraryRemote(ownedIds: owned, savedIds: saved);
    } catch (_) {
      return null;
    }
  }

  Future<bool> grantOwnership(String bearerToken, String titleId) async {
    try {
      final response = await _client
          .post(
            _uri('/library/owned/$titleId'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleSaved(String bearerToken, String titleId) async {
    try {
      final response = await _client
          .post(
            _uri('/library/saved/$titleId'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<ProfileRemote?> fetchMe(String bearerToken) async {
    try {
      final response = await _client
          .get(
            _uri('/me'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return ProfileRemote(
        uid: '${decoded['uid'] ?? ''}',
        email: decoded['email'] == null ? null : '${decoded['email']}',
        displayName: decoded['displayName'] == null ? null : '${decoded['displayName']}',
        creatorStatus: '${decoded['creatorStatus'] ?? 'none'}',
        role: '${decoded['role'] ?? 'listener'}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<ProfileRemote?> applyCreator(String bearerToken, {String? displayName}) async {
    try {
      final response = await _client
          .post(
            _uri('/me/creator-application'),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'displayName': displayName}),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return ProfileRemote(
        uid: '${decoded['uid'] ?? ''}',
        email: decoded['email'] == null ? null : '${decoded['email']}',
        displayName: decoded['displayName'] == null ? null : '${decoded['displayName']}',
        creatorStatus: '${decoded['creatorStatus'] ?? 'pending'}',
        role: '${decoded['role'] ?? 'creator'}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> checkEntitlement(String bearerToken, String titleId) async {
    try {
      final response = await _client
          .get(
            _uri('/library/entitlements/$titleId'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      return decoded['entitled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<SalesDashboard?> fetchSales(String bearerToken) async {
    try {
      final response = await _client
          .get(
            _uri('/studio/sales'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return SalesDashboard.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  CreatorDraft? _draftFromApiMap(Map<String, dynamic> map, {String? fallbackFormat}) {
    final formatRaw = '${map['format'] ?? fallbackFormat ?? 'ebook'}'.toLowerCase();
    final format = switch (formatRaw) {
      'audiobook' => 'Audiobook',
      'podcast' => 'Podcast',
      'ebook_audio' => 'Ebook + Audiobook',
      'ebook' => 'Ebook',
      _ when fallbackFormat != null => fallbackFormat,
      _ => 'Ebook',
    };
    final pricesRaw = map['prices'];
    final prices = <PriceQuote>[];
    if (pricesRaw is List) {
      for (final price in pricesRaw) {
        if (price is Map) {
          prices.add(PriceQuote.fromJson(Map<String, dynamic>.from(price)));
        }
      }
    }
    final chapters = <ContentChapter>[];
    final chaptersRaw = map['chapters'];
    if (chaptersRaw is List) {
      for (final item in chaptersRaw) {
        if (item is Map) {
          chapters.add(ContentChapter.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      chapters.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    final episodes = <ContentEpisode>[];
    final episodesRaw = map['episodes'];
    if (episodesRaw is List) {
      for (final item in episodesRaw) {
        if (item is Map) {
          episodes.add(ContentEpisode.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      episodes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    final modeRaw = map['monetisationMode'] == null ? null : '${map['monetisationMode']}';
    final inferredMode = modeRaw ??
        (format == 'Podcast'
            ? (prices.any((p) => p.amountMinor > 0) ? 'premium_purchase' : 'free_with_ads')
            : 'purchase');
    return CreatorDraft(
      id: '${map['id'] ?? ''}',
      title: '${map['title'] ?? ''}',
      format: format,
      genre: map['genre'] == null ? null : '${map['genre']}',
      prices: prices,
      monetisationMode: inferredMode,
      subscriptionEligible: map['subscriptionEligible'] as bool? ?? format != 'Podcast',
      status: '${map['status'] ?? 'draft'}',
      createdAtMs: DateTime.tryParse('${map['createdAt'] ?? ''}')?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      mediaName: map['mediaName'] == null ? null : '${map['mediaName']}',
      mediaKind: map['mediaKind'] == null ? null : '${map['mediaKind']}',
      mediaBytes: (map['mediaBytes'] as num?)?.toInt(),
      mediaId: map['mediaId'] == null ? null : '${map['mediaId']}',
      coverImageName: map['coverImageName'] == null ? null : '${map['coverImageName']}',
      coverImageBytes: (map['coverImageBytes'] as num?)?.toInt(),
      chapters: chapters,
      episodes: episodes,
      publishedTitleId:
          map['publishedTitleId'] == null ? null : '${map['publishedTitleId']}',
    );
  }

  String absoluteMediaUrl(String? relativeOrAbsolute) {
    if (relativeOrAbsolute == null || relativeOrAbsolute.isEmpty) return '';
    if (relativeOrAbsolute.startsWith('http://') ||
        relativeOrAbsolute.startsWith('https://')) {
      return relativeOrAbsolute;
    }
    final origin = _baseUrl.replaceFirst(RegExp(r'/v1/?$'), '');
    if (relativeOrAbsolute.startsWith('/')) return '$origin$relativeOrAbsolute';
    return '$origin/$relativeOrAbsolute';
  }

  Future<String?> uploadMedia(
    String bearerToken, {
    required String filePath,
    String? filename,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final uri = _uri('/media');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $bearerToken';
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: filename ?? file.uri.pathSegments.last,
        ),
      );
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final id = decoded['id'];
      return id == null ? null : '$id';
    } catch (_) {
      return null;
    }
  }

  /// Returns null when the request fails (keep local drafts). Empty list means none on API.
  Future<List<CreatorDraft>?> fetchStudioDrafts(String bearerToken) async {
    try {
      final response = await _client
          .get(
            _uri('/studio/drafts'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final items = decoded['items'];
      if (items is! List) return null;
      return items
          .whereType<Object>()
          .map((item) {
            if (item is! Map) return null;
            return _draftFromApiMap(Map<String, dynamic>.from(item));
          })
          .whereType<CreatorDraft>()
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<CreatorDraft?> createStudioDraft(
    String bearerToken, {
    required String title,
    required String format,
    required List<PriceQuote> prices,
    String? genre,
    String? monetisationMode,
    bool? subscriptionEligible,
    String? mediaName,
    String? mediaKind,
    int? mediaBytes,
    String? mediaId,
    String? coverImageName,
    int? coverImageBytes,
    List<ContentChapter> chapters = const [],
    List<ContentEpisode> episodes = const [],
    bool submit = false,
    String? email,
    String? displayName,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('/studio/drafts'),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'title': title,
              'format': switch (format.toLowerCase()) {
                'audiobook' => 'audiobook',
                'podcast' => 'podcast',
                'ebook + audiobook' => 'ebook_audio',
                'ebook_audio' => 'ebook_audio',
                _ => 'ebook',
              },
              'genre': genre,
              'prices': prices.map((p) => p.toJson()).toList(),
              'monetisationMode': monetisationMode,
              'subscriptionEligible': subscriptionEligible,
              'mediaName': mediaName,
              'mediaKind': mediaKind,
              'mediaBytes': mediaBytes,
              'mediaId': mediaId,
              'coverImageName': coverImageName,
              'coverImageBytes': coverImageBytes,
              'chapters': chapters.map((c) => c.toJson()).toList(),
              'episodes': episodes
                  .map(
                    (e) => {
                      'id': e.id,
                      'title': e.title,
                      'durationSec': e.durationSec,
                      'sortOrder': e.sortOrder,
                      'mediaName': e.mediaName,
                      'mediaId': e.mediaId,
                      'showNotes': e.showNotes,
                      'body': e.body,
                    },
                  )
                  .toList(),
              'submit': submit,
              'email': email,
              'displayName': displayName,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return _draftFromApiMap(decoded, fallbackFormat: format)?.copyWith(
            mediaName: mediaName,
            mediaKind: mediaKind,
            mediaBytes: mediaBytes,
            mediaId: mediaId,
            coverImageName: coverImageName,
            coverImageBytes: coverImageBytes,
            chapters: chapters,
            episodes: episodes,
          );
    } catch (_) {
      return null;
    }
  }

  Future<CreatorDraft?> updateStudioDraft(
    String bearerToken, {
    required String id,
    required String title,
    required String format,
    required List<PriceQuote> prices,
    String? genre,
    String? monetisationMode,
    bool? subscriptionEligible,
    String? mediaName,
    String? mediaKind,
    int? mediaBytes,
    String? mediaId,
    String? coverImageName,
    int? coverImageBytes,
    List<ContentChapter>? chapters,
    List<ContentEpisode>? episodes,
    bool? submit,
    String? email,
    String? displayName,
  }) async {
    try {
      final body = <String, dynamic>{
        'title': title,
        'format': switch (format.toLowerCase()) {
          'audiobook' => 'audiobook',
          'podcast' => 'podcast',
          'ebook + audiobook' => 'ebook_audio',
          'ebook_audio' => 'ebook_audio',
          _ => 'ebook',
        },
        'genre': genre,
        'prices': prices.map((p) => p.toJson()).toList(),
        'monetisationMode': monetisationMode,
        'subscriptionEligible': subscriptionEligible,
        'mediaName': mediaName,
        'mediaKind': mediaKind,
        'mediaBytes': mediaBytes,
        'mediaId': mediaId,
        'coverImageName': coverImageName,
        'coverImageBytes': coverImageBytes,
        'email': email,
        'displayName': displayName,
      };
      if (submit != null) body['submit'] = submit;
      if (chapters != null) {
        body['chapters'] = chapters.map((c) => c.toJson()).toList();
      }
      if (episodes != null) {
        body['episodes'] = episodes
            .map(
              (e) => {
                'id': e.id,
                'title': e.title,
                'durationSec': e.durationSec,
                'sortOrder': e.sortOrder,
                'mediaName': e.mediaName,
                'mediaId': e.mediaId,
                'showNotes': e.showNotes,
                'body': e.body,
              },
            )
            .toList();
      }
      final response = await _client
          .patch(
            _uri('/studio/drafts/$id'),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return _draftFromApiMap(decoded, fallbackFormat: format);
    } catch (_) {
      return null;
    }
  }

  Future<List<SampleChapter>?> fetchChapters(String titleId) async {
    try {
      final response =
          await _client.get(_uri('/catalogue/titles/$titleId/chapters')).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final items = decoded['items'];
      if (items is! List) return null;
      return items
          .whereType<Map>()
          .map(
            (item) => SampleChapter(
              id: '${item['id'] ?? ''}',
              title: '${item['title'] ?? ''}',
              body: '${item['body'] ?? ''}',
            ),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<SampleAudioTrack>?> fetchTracks(String titleId) async {
    try {
      final response =
          await _client.get(_uri('/catalogue/titles/$titleId/tracks')).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final items = decoded['items'];
      if (items is! List) return null;
      return items
          .whereType<Map>()
          .map(
            (item) => SampleAudioTrack(
              id: '${item['id'] ?? ''}',
              title: '${item['title'] ?? ''}',
              durationSec: (item['durationSec'] as num?)?.toInt() ?? 0,
              mediaName: item['mediaName'] == null ? null : '${item['mediaName']}',
              mediaUrl: item['mediaUrl'] == null
                  ? null
                  : absoluteMediaUrl('${item['mediaUrl']}'),
            ),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteStudioDraft(String bearerToken, String id) async {
    try {
      final response = await _client
          .delete(
            _uri('/studio/drafts/$id'),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<ContentNote>> fetchNotes(String bearerToken, {String? titleId}) async {
    try {
      final response = await _client
          .get(
            _uri('/notes', titleId == null ? null : {'titleId': titleId}),
            headers: {'Authorization': 'Bearer $bearerToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      return items
          .whereType<Object>()
          .map((item) {
            if (item is Map<String, dynamic>) return ContentNote.fromJson(item);
            if (item is Map) return ContentNote.fromJson(Map<String, dynamic>.from(item));
            return null;
          })
          .whereType<ContentNote>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<ContentNote?> createNote(
    String bearerToken, {
    required ContentNote note,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('/notes'),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'titleId': note.titleId,
              'kind': note.kind,
              'anchor': note.anchor,
              'locationId': note.locationId,
              'position': note.position,
              'text': note.text,
              'voiceDurationSec': note.voiceDurationSec,
              'voiceRef': note.voicePath,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return ContentNote.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Verified completed ad event → creator advertising ledger (55/45).
  Future<bool> completeAd(
    String bearerToken, {
    required String titleId,
    required String placement,
    required int completedSec,
    String? trackId,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('/ads/complete'),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'titleId': titleId,
              'placement': placement,
              'completedSec': completedSec,
              if (trackId != null) 'trackId': trackId,
            }),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Qualified listening/reading minutes → subscription pool credit (60/40).
  Future<bool> creditQualifiedConsumption(
    String bearerToken, {
    required String titleId,
    required int minutes,
    required String kind,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('/consumption/qualified'),
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'titleId': titleId,
              'minutes': minutes,
              'kind': kind,
            }),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

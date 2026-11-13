import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'content_models.dart';

enum ReaderThemeMode { day, sepia, night }

class ReaderPrefs {
  const ReaderPrefs({
    this.fontScale = 1,
    this.theme = ReaderThemeMode.day,
  });

  final double fontScale;
  final ReaderThemeMode theme;

  ReaderPrefs copyWith({double? fontScale, ReaderThemeMode? theme}) => ReaderPrefs(
        fontScale: fontScale ?? this.fontScale,
        theme: theme ?? this.theme,
      );

  Map<String, dynamic> toJson() => {
        'fontScale': fontScale,
        'theme': theme.name,
      };

  factory ReaderPrefs.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReaderPrefs();
    final themeName = '${json['theme'] ?? 'day'}';
    return ReaderPrefs(
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1,
      theme: switch (themeName) {
        'sepia' => ReaderThemeMode.sepia,
        'night' => ReaderThemeMode.night,
        _ => ReaderThemeMode.day,
      },
    );
  }
}

class TitleProgress {
  const TitleProgress({
    required this.titleId,
    required this.locationId,
    required this.position,
    required this.updatedAtMs,
    this.bookmarks = const [],
  });

  final String titleId;
  /// Chapter id for ebooks, track id for audio.
  final String locationId;
  /// Ebook: 0–1 scroll fraction in chapter. Audio: seconds into track.
  final double position;
  final int updatedAtMs;
  final List<String> bookmarks;

  TitleProgress copyWith({
    String? locationId,
    double? position,
    int? updatedAtMs,
    List<String>? bookmarks,
  }) =>
      TitleProgress(
        titleId: titleId,
        locationId: locationId ?? this.locationId,
        position: position ?? this.position,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        bookmarks: bookmarks ?? this.bookmarks,
      );

  Map<String, dynamic> toJson() => {
        'titleId': titleId,
        'locationId': locationId,
        'position': position,
        'updatedAtMs': updatedAtMs,
        'bookmarks': bookmarks,
      };

  factory TitleProgress.fromJson(Map<String, dynamic> json) {
    return TitleProgress(
      titleId: '${json['titleId'] ?? ''}',
      locationId: '${json['locationId'] ?? ''}',
      position: (json['position'] as num?)?.toDouble() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      bookmarks: (json['bookmarks'] as List<dynamic>? ?? const [])
          .map((item) => '$item')
          .toList(),
    );
  }
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.onboardingComplete,
    required this.isSignedIn,
    required this.displayName,
    required this.contact,
    required this.marketCode,
    required this.marketLabel,
    required this.currencyCode,
    required this.language,
    required this.notificationsEnabled,
    required this.interests,
    required this.owned,
    required this.saved,
    required this.creatorState,
    required this.drafts,
    this.progress = const {},
    this.readerPrefs = const ReaderPrefs(),
    this.playbackSpeed = 1,
    this.notes = const [],
    this.downloads = const [],
  });

  final bool onboardingComplete;
  final bool isSignedIn;
  final String displayName;
  final String contact;
  final String marketCode;
  final String marketLabel;
  final String currencyCode;
  final String language;
  final bool notificationsEnabled;
  final List<String> interests;
  final List<String> owned;
  final List<String> saved;
  final String creatorState;
  final List<CreatorDraft> drafts;
  final Map<String, TitleProgress> progress;
  final ReaderPrefs readerPrefs;
  final double playbackSpeed;
  final List<ContentNote> notes;
  final List<OfflineDownload> downloads;

  Map<String, dynamic> toJson() => {
        'onboardingComplete': onboardingComplete,
        'isSignedIn': isSignedIn,
        'displayName': displayName,
        'contact': contact,
        'marketCode': marketCode,
        'marketLabel': marketLabel,
        'currencyCode': currencyCode,
        'language': language,
        'notificationsEnabled': notificationsEnabled,
        'interests': interests,
        'owned': owned,
        'saved': saved,
        'creatorState': creatorState,
        'drafts': drafts.map((d) => d.toJson()).toList(),
        'progress': progress.map((key, value) => MapEntry(key, value.toJson())),
        'readerPrefs': readerPrefs.toJson(),
        'playbackSpeed': playbackSpeed,
        'notes': notes.map((n) => n.toJson()).toList(),
        'downloads': downloads.map((d) => d.toJson()).toList(),
      };

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>? ?? const []).map((item) => '$item').toList();

    final progressRaw = json['progress'];
    final progress = <String, TitleProgress>{};
    if (progressRaw is Map) {
      progressRaw.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          progress['$key'] = TitleProgress.fromJson(value);
        } else if (value is Map) {
          progress['$key'] = TitleProgress.fromJson(Map<String, dynamic>.from(value));
        }
      });
    }

    return SessionSnapshot(
      onboardingComplete: json['onboardingComplete'] == true,
      isSignedIn: json['isSignedIn'] == true,
      displayName: '${json['displayName'] ?? ''}',
      contact: '${json['contact'] ?? ''}',
      marketCode: '${json['marketCode'] ?? 'ZM'}',
      marketLabel: '${json['marketLabel'] ?? 'Zambia'}',
      currencyCode: '${json['currencyCode'] ?? 'ZMW'}',
      language: '${json['language'] ?? 'English'}',
      notificationsEnabled: json['notificationsEnabled'] != false,
      interests: strings('interests'),
      owned: strings('owned'),
      saved: strings('saved'),
      creatorState: '${json['creatorState'] ?? 'newApplicant'}',
      drafts: _parseDrafts(json['drafts']),
      progress: progress,
      readerPrefs: ReaderPrefs.fromJson(
        json['readerPrefs'] is Map<String, dynamic>
            ? json['readerPrefs'] as Map<String, dynamic>
            : json['readerPrefs'] is Map
                ? Map<String, dynamic>.from(json['readerPrefs'] as Map)
                : null,
      ),
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1,
      notes: _parseNotes(json['notes']),
      downloads: _parseDownloads(json['downloads']),
    );
  }

  static List<CreatorDraft> _parseDrafts(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((item) {
      if (item is String) return CreatorDraft.fromLegacyLabel(item);
      if (item is Map<String, dynamic>) return CreatorDraft.fromJson(item);
      if (item is Map) return CreatorDraft.fromJson(Map<String, dynamic>.from(item));
      return CreatorDraft.fromLegacyLabel('$item');
    }).toList();
  }

  static List<ContentNote> _parseNotes(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Object>()
        .map((item) {
          if (item is Map<String, dynamic>) return ContentNote.fromJson(item);
          if (item is Map) return ContentNote.fromJson(Map<String, dynamic>.from(item));
          return null;
        })
        .whereType<ContentNote>()
        .toList();
  }

  static List<OfflineDownload> _parseDownloads(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Object>()
        .map((item) {
          if (item is Map<String, dynamic>) return OfflineDownload.fromJson(item);
          if (item is Map) return OfflineDownload.fromJson(Map<String, dynamic>.from(item));
          return null;
        })
        .whereType<OfflineDownload>()
        .toList();
  }
}

class SessionStore {
  static const _key = 'listen_plus.session.v1';

  Future<SessionSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SessionSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SessionSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/catalogue.dart';
import '../data/content_models.dart';
import '../data/session_store.dart';
import '../services/api_client.dart';
import '../services/audio_playback_service.dart';
import '../services/auth_service.dart';
import '../services/offline_cache_service.dart';

enum CreatorApplicationState { newApplicant, pending, approved }

enum CheckoutState { review, pending, success, failed }

enum AuthMode { guest, signedIn }

class SessionState extends ChangeNotifier {
  SessionState({
    SessionStore? store,
    AuthService? authService,
    ListenApiClient? apiClient,
  })  : _store = store ?? SessionStore(),
        _auth = authService ?? createDefaultAuthService(),
        _api = apiClient ?? ListenApiClient();

  final SessionStore _store;
  final AuthService _auth;
  final ListenApiClient _api;
  final AudioPlaybackService _audio = AudioPlaybackService();
  final OfflineCacheService _offline = OfflineCacheService();
  StreamSubscription<AuthUser?>? _authSub;
  StreamSubscription<Duration>? _audioPositionSub;
  Timer? _playbackTicker;
  Timer? _sleepTimer;
  Timer? _syncRetryTimer;

  bool ready = false;
  bool apiReachable = false;
  bool librarySyncedFromApi = false;
  /// Title ids that need entitlement/saved sync once the API is back.
  final Set<String> _pendingOwnedSync = {};
  final Set<String> _pendingSavedSync = {};
  bool _pendingDraftFlush = false;
  AuthMode authMode = AuthMode.guest;
  bool onboardingComplete = false;
  String? uid;

  String displayName = '';
  String contact = '';
  String marketCode = 'ZM';
  String marketLabel = 'Zambia';
  String currencyCode = 'ZMW';
  String language = 'English';
  bool notificationsEnabled = true;
  final Set<String> interests = {};

  final Set<String> owned = {};
  final Set<String> saved = {};
  CreatorApplicationState creatorState = CreatorApplicationState.newApplicant;
  final List<CreatorDraft> drafts = [];
  SalesDashboard sales = SalesDashboard.empty();

  final Map<String, TitleProgress> progress = {};
  ReaderPrefs readerPrefs = const ReaderPrefs();
  final List<ContentNote> notes = [];
  final List<OfflineDownload> downloads = [];

  TitleItem? nowPlaying;
  SampleAudioTrack? nowPlayingTrack;
  bool playing = false;
  double playbackPositionSec = 0;
  double playbackSpeed = 1;
  int? sleepTimerMinutesRemaining;
  bool usingRealAudio = false;
  bool usingSampleAsset = false;
  String notice = '';

  /// Strategic ad break state (free-with-ads titles only).
  bool adBreakActive = false;
  String? adBreakPlacement; // preroll | midroll | chapter
  int adBreakElapsedSec = 0;
  bool adBreakSkippable = false;
  Timer? _adBreakTicker;
  final Set<String> _prerollShownForSession = {};
  final Set<String> _midrollShownForTrack = {};
  final List<int> _adCompletionTimesMs = [];
  double _qualifiedListenAccumSec = 0;
  final Map<String, int> _readerMinutesCredited = {};

  bool get isSignedIn => authMode == AuthMode.signedIn;
  bool get isGuest => authMode == AuthMode.guest;
  bool get firebaseAuthAvailable => _auth.isAvailable;
  String get marketChip => '$marketLabel · $currencyCode';
  String get avatarLetters {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'LP';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  bool isOwned(String id) => owned.contains(id);
  bool isSaved(String id) => saved.contains(id);

  TitleProgress? progressFor(String titleId) => progress[titleId];

  List<TitleItem> continueTitles({int limit = 6}) {
    final ordered = progress.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    final items = <TitleItem>[];
    for (final entry in ordered) {
      final title = titleById(entry.titleId);
      if (title == null) continue;
      if (!isOwned(title.id) && !title.isFree) continue;
      items.add(title);
      if (items.length >= limit) break;
    }
    return items;
  }

  String continueSubtitle(TitleItem title) {
    final entry = progress[title.id];
    if (entry == null) {
      return title.isAudio ? 'Ready to listen' : 'Ready to read';
    }
    if (title.isAudio) {
      final tracks = tracksFor(title.id);
      SampleAudioTrack? track;
      for (final item in tracks) {
        if (item.id == entry.locationId) {
          track = item;
          break;
        }
      }
      track ??= tracks.isEmpty ? null : tracks.first;
      final label = track?.title ?? 'Track';
      final duration = track?.durationSec ?? 1;
      final pct = (entry.position / duration * 100).clamp(0, 99).round();
      return '$label · $pct%';
    }
    final chapters = chaptersFor(title.id);
    SampleChapter? chapter;
    for (final item in chapters) {
      if (item.id == entry.locationId) {
        chapter = item;
        break;
      }
    }
    chapter ??= chapters.isEmpty ? null : chapters.first;
    final label = chapter?.title ?? 'Chapter';
    final pct = (entry.position * 100).clamp(0, 99).round();
    return '$label · $pct%';
  }

  Future<void> hydrate() async {
    final snapshot = await _store.load();
    if (snapshot != null) {
      _applySnapshot(snapshot);
    }

    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      _applyFirebaseUser(firebaseUser, markOnboardingComplete: snapshot?.onboardingComplete == true);
    } else if (snapshot?.isSignedIn == true) {
      authMode = AuthMode.guest;
      uid = null;
      if (displayName.trim().isEmpty) displayName = 'Guest';
    }

    _authSub?.cancel();
    _authSub = _auth.authStateChanges().listen((user) async {
      if (user == null) {
        if (authMode == AuthMode.signedIn) {
          authMode = AuthMode.guest;
          uid = null;
          librarySyncedFromApi = false;
          if (displayName.trim().isEmpty) displayName = 'Guest';
          contact = '';
          await _persist();
          notifyListeners();
        }
        return;
      }
      _applyFirebaseUser(user, markOnboardingComplete: onboardingComplete);
      // /me first: rebinds Studio drafts and grants creators their live titles.
      await _syncProfileFromApi();
      await _syncLibraryFromApi();
      await _syncSalesFromApi();
      await _syncDraftsFromApi();
      await _syncNotesFromApi();
      await _persist();
      notifyListeners();
    });

    await _syncCatalogueFromApi();
    if (isSignedIn) {
      await _syncProfileFromApi();
      await _syncLibraryFromApi();
      await _syncSalesFromApi();
      await _syncDraftsFromApi();
      await _syncNotesFromApi();
    }

    ready = true;
    notifyListeners();
    await _persist();
    _ensureSyncRetry();
  }

  String? _devBearer() {
    if (!isSignedIn || uid == null || uid!.isEmpty) return null;
    final email = contact.trim();
    final name = displayName.trim();
    if (email.isNotEmpty && name.isNotEmpty) return '$uid|$email|$name';
    if (email.isNotEmpty) return '$uid|$email';
    return uid;
  }

  Future<void> _syncCatalogueFromApi() async {
    apiReachable = await _api.health();
    if (!apiReachable) {
      replaceCatalogue(sampleTitles, fromApi: false);
      return;
    }
    final remote = await _api.fetchTitles();
    if (remote != null) {
      replaceCatalogue(remote, fromApi: true);
      await _syncCatalogueParts(remote);
    } else {
      replaceCatalogue(sampleTitles, fromApi: false);
    }
  }

  Future<void> _syncCatalogueParts(List<TitleItem> remoteTitles) async {
    for (final title in remoteTitles) {
      await refreshTitleParts(title.id, notify: false);
    }
  }

  /// Push Studio draft chapters/episodes into the in-memory catalogue overlay.
  void overlayDraftParts(CreatorDraft draft) {
    final titleId = draft.publishedTitleId;
    if (titleId == null || titleId.isEmpty) return;
    if (draft.isEbook && draft.chapters.isNotEmpty) {
      putRemoteChapters(
        titleId,
        draft.chapters
            .map(
              (chapter) => SampleChapter(
                id: chapter.id,
                title: chapter.title,
                body: chapter.body,
              ),
            )
            .toList(),
      );
    }
    if (draft.isAudioFormat && draft.episodes.isNotEmpty) {
      putRemoteTracks(
        titleId,
        draft.episodes
            .map(
              (episode) => SampleAudioTrack(
                id: episode.id,
                title: episode.title,
                durationSec: episode.durationSec <= 0 ? 180 : episode.durationSec,
                mediaName: episode.mediaName,
                mediaUrl: episode.mediaId == null || episode.mediaId!.isEmpty
                    ? null
                    : _api.absoluteMediaUrl('/v1/media/${episode.mediaId}'),
              ),
            )
            .toList(),
      );
    }
  }

  /// Fetch latest chapters/tracks from API (and merge any live Studio draft).
  Future<void> refreshTitleParts(String titleId, {bool notify = true}) async {
    final title = titleById(titleId);
    final wantsAudio = title?.isAudio ?? true;
    final wantsEbook = title?.isEbook ?? !(title?.isAudio ?? false);
    if (wantsAudio) {
      final tracks = await _api.fetchTracks(titleId);
      if (tracks != null && tracks.isNotEmpty) {
        putRemoteTracks(titleId, tracks);
      }
    }
    if (wantsEbook) {
      final chapters = await _api.fetchChapters(titleId);
      if (chapters != null && chapters.isNotEmpty) {
        putRemoteChapters(titleId, chapters);
      }
    }
    for (final draft in drafts) {
      if (draft.publishedTitleId == titleId) {
        // Local Studio edits win until the next successful API pull overwrites them.
        overlayDraftParts(draft);
      }
    }
    if (notify) notifyListeners();
  }

  Future<CreatorDraft?> saveCreatorParts({
    required String draftId,
    List<ContentChapter>? chapters,
    List<ContentEpisode>? episodes,
  }) async {
    final index = drafts.indexWhere((d) => d.id == draftId);
    if (index < 0) return null;
    final draft = drafts[index];
    final saved = await saveCreatorDraft(
      existingId: draft.id,
      title: draft.title,
      format: draft.format,
      prices: draft.prices,
      genre: draft.genre,
      mediaName: draft.mediaName,
      mediaPath: draft.mediaPath,
      mediaKind: draft.mediaKind,
      mediaBytes: draft.mediaBytes,
      coverImageName: draft.coverImageName,
      coverImagePath: draft.coverImagePath,
      coverImageBytes: draft.coverImageBytes,
      chapters: chapters ?? draft.chapters,
      episodes: episodes ?? draft.episodes,
      submit: null,
    );
    // Drop stale offline cache so Library/reader don't keep old chapter bodies.
    downloads.removeWhere((d) => d.titleId == saved.publishedTitleId);
    overlayDraftParts(saved);
    if (saved.publishedTitleId != null) {
      await refreshTitleParts(saved.publishedTitleId!);
    }
    return saved;
  }

  Future<void> _syncLibraryFromApi() async {
    final bearer = _devBearer();
    if (bearer == null) {
      librarySyncedFromApi = false;
      return;
    }
    final remote = await _api.fetchLibrary(bearer);
    if (remote == null) {
      librarySyncedFromApi = false;
      return;
    }
    owned
      ..clear()
      ..addAll(remote.ownedIds);
    saved
      ..clear()
      ..addAll(remote.savedIds);
    librarySyncedFromApi = true;
  }

  CreatorApplicationState _creatorStateFromApi(String status) {
    return switch (status) {
      'pending' => CreatorApplicationState.pending,
      'approved' => CreatorApplicationState.approved,
      _ => CreatorApplicationState.newApplicant,
    };
  }

  Future<void> _syncProfileFromApi() async {
    final bearer = _devBearer();
    if (bearer == null) return;
    final profile = await _api.fetchMe(bearer);
    if (profile == null) return;
    final remoteState = _creatorStateFromApi(profile.creatorStatus);
    // Don't wipe a locally approved Studio session if the API briefly returns
    // a blank profile (e.g. mid-restart before disk hydrate). Prefer upgrade.
    final rank = (CreatorApplicationState s) => switch (s) {
          CreatorApplicationState.approved => 3,
          CreatorApplicationState.pending => 2,
          CreatorApplicationState.newApplicant => 0,
        };
    if (rank(remoteState) >= rank(creatorState) || remoteState == CreatorApplicationState.approved) {
      creatorState = remoteState;
    }
    if (profile.displayName != null && profile.displayName!.trim().isNotEmpty) {
      displayName = profile.displayName!.trim();
    }
  }

  void _applySnapshot(SessionSnapshot snapshot) {
    onboardingComplete = snapshot.onboardingComplete;
    authMode = snapshot.isSignedIn ? AuthMode.signedIn : AuthMode.guest;
    displayName = snapshot.displayName;
    contact = snapshot.contact;
    marketCode = snapshot.marketCode;
    marketLabel = snapshot.marketLabel;
    currencyCode = snapshot.currencyCode;
    language = snapshot.language;
    notificationsEnabled = snapshot.notificationsEnabled;
    interests
      ..clear()
      ..addAll(snapshot.interests);
    owned
      ..clear()
      ..addAll(snapshot.owned);
    saved
      ..clear()
      ..addAll(snapshot.saved);
    creatorState = switch (snapshot.creatorState) {
      'pending' => CreatorApplicationState.pending,
      'approved' => CreatorApplicationState.approved,
      _ => CreatorApplicationState.newApplicant,
    };
    drafts
      ..clear()
      ..addAll(snapshot.drafts);
    notes
      ..clear()
      ..addAll(snapshot.notes);
    downloads
      ..clear()
      ..addAll(snapshot.downloads);
    progress
      ..clear()
      ..addAll(snapshot.progress);
    readerPrefs = snapshot.readerPrefs;
    playbackSpeed = snapshot.playbackSpeed;
  }

  void _applyFirebaseUser(AuthUser user, {required bool markOnboardingComplete}) {
    authMode = AuthMode.signedIn;
    uid = user.uid;
    contact = user.email ?? contact;
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      displayName = user.displayName!.trim();
    } else if (displayName.trim().isEmpty || displayName == 'Guest') {
      displayName = (user.email ?? 'Listener').split('@').first;
    }
    if (markOnboardingComplete) {
      onboardingComplete = true;
    }
  }

  Future<void> _persist() async {
    if (!ready) return;
    await _store.save(
      SessionSnapshot(
        onboardingComplete: onboardingComplete,
        isSignedIn: isSignedIn,
        displayName: displayName,
        contact: contact,
        marketCode: marketCode,
        marketLabel: marketLabel,
        currencyCode: currencyCode,
        language: language,
        notificationsEnabled: notificationsEnabled,
        interests: interests.toList(),
        owned: owned.toList(),
        saved: saved.toList(),
        creatorState: creatorState.name,
        drafts: List<CreatorDraft>.from(drafts),
        progress: Map<String, TitleProgress>.from(progress),
        readerPrefs: readerPrefs,
        playbackSpeed: playbackSpeed,
        notes: List<ContentNote>.from(notes),
        downloads: List<OfflineDownload>.from(downloads),
      ),
    );
  }

  void continueAsGuest() {
    authMode = AuthMode.guest;
    uid = null;
    displayName = 'Guest';
    contact = '';
    notifyListeners();
    _persist();
  }

  Future<void> createAccountWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final user = await _auth.createAccount(
      email: email,
      password: password,
      displayName: name,
    );
    _applyFirebaseUser(user, markOnboardingComplete: false);
    displayName = name.trim();
    // Full sync so Studio drafts / creator status land immediately after signup.
    await refreshFromApi();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final user = await _auth.signIn(email: email, password: password);
    _applyFirebaseUser(user, markOnboardingComplete: false);
    // Full sync: profile (creator approval) + Studio drafts + library.
    // Without this, Studio can look empty until a manual pull-to-refresh.
    await refreshFromApi();
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordReset(email);

  void setMarket({
    required String code,
    required String label,
    required String currency,
  }) {
    marketCode = code;
    marketLabel = label;
    currencyCode = currency;
    notifyListeners();
    _persist();
  }

  void setLanguage(String value) {
    language = value;
    notifyListeners();
    _persist();
  }

  void setNotificationsEnabled(bool value) {
    notificationsEnabled = value;
    notifyListeners();
    _persist();
  }

  void setInterests(Iterable<String> values) {
    interests
      ..clear()
      ..addAll(values);
    notifyListeners();
    _persist();
  }

  void completeOnboarding() {
    onboardingComplete = true;
    notifyListeners();
    _persist();
  }

  Future<void> resetOnboardingForDemo() async {
    onboardingComplete = false;
    if (isSignedIn) {
      await signOut(showMessage: false);
    } else {
      authMode = AuthMode.guest;
      displayName = '';
      contact = '';
      uid = null;
    }
    interests.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> signOut({bool showMessage = true}) async {
    await _auth.signOut();
    authMode = AuthMode.guest;
    uid = null;
    displayName = 'Guest';
    contact = '';
    creatorState = CreatorApplicationState.newApplicant;
    drafts.clear();
    notifyListeners();
    await _persist();
    if (showMessage) {
      showNotice('Signed out.');
    }
  }

  Future<void> updateProfile({
    required String name,
    required String languageValue,
    required bool notifications,
  }) async {
    final nextName = name.trim().isEmpty ? displayName : name.trim();
    displayName = nextName;
    language = languageValue;
    notificationsEnabled = notifications;
    if (isSignedIn && firebaseAuthAvailable) {
      try {
        await _auth.updateDisplayName(nextName);
      } catch (_) {
        // Local profile still updates even if Firebase profile sync fails.
      }
    }
    notifyListeners();
    await _persist();
    showNotice('Preferences updated.');
  }

  Future<void> toggleSave(String id) async {
    final nowSaved = !saved.contains(id);
    if (!saved.add(id)) saved.remove(id);
    notifyListeners();
    await _persist();
    final bearer = _devBearer();
    if (bearer == null) return;
    final ok = await _api.toggleSaved(bearer, id);
    if (!ok) {
      if (nowSaved) {
        _pendingSavedSync.add(id);
      } else {
        _pendingSavedSync.remove(id);
      }
      _ensureSyncRetry();
      showNotice('Saved on this device. Syncing when Listen+ is reachable…');
    } else {
      _pendingSavedSync.remove(id);
    }
  }

  Future<void> grantOwnership(String id) async {
    owned.add(id);
    notifyListeners();
    await _persist();
    final bearer = _devBearer();
    if (bearer == null) {
      _pendingOwnedSync.add(id);
      _ensureSyncRetry();
      showNotice('Added to your library. Sign in to sync across devices.');
      return;
    }
    final ok = await _api.grantOwnership(bearer, id);
    if (ok) {
      librarySyncedFromApi = true;
      _pendingOwnedSync.remove(id);
      showNotice('Added to your library.');
    } else {
      _pendingOwnedSync.add(id);
      _ensureSyncRetry();
      showNotice('Added to your library on this device. Syncing when Listen+ is reachable…');
    }
  }

  void _ensureSyncRetry() {
    _syncRetryTimer?.cancel();
    _syncRetryTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_flushPendingApiSync());
    });
  }

  Future<void> _flushPendingApiSync() async {
    final healthy = await _api.health();
    apiReachable = healthy;
    if (!healthy) return;

    final bearer = _devBearer();
    if (bearer == null) {
      if (_pendingOwnedSync.isEmpty && _pendingSavedSync.isEmpty && !_pendingDraftFlush) {
        _syncRetryTimer?.cancel();
        _syncRetryTimer = null;
      }
      return;
    }

    var progressed = false;
    for (final id in [..._pendingOwnedSync]) {
      final ok = await _api.grantOwnership(bearer, id);
      if (ok) {
        _pendingOwnedSync.remove(id);
        librarySyncedFromApi = true;
        progressed = true;
      }
    }
    for (final id in [..._pendingSavedSync]) {
      if (!saved.contains(id)) {
        _pendingSavedSync.remove(id);
        continue;
      }
      final ok = await _api.toggleSaved(bearer, id);
      if (ok) {
        _pendingSavedSync.remove(id);
        progressed = true;
      }
    }

    if (_pendingDraftFlush || drafts.any((d) => d.id.startsWith('local-'))) {
      _pendingDraftFlush = false;
      await _syncDraftsFromApi();
      // Re-save local-only drafts once the API is back.
      final locals = drafts.where((d) => d.id.startsWith('local-')).toList();
      for (final draft in locals) {
        final remote = await _api.createStudioDraft(
          bearer,
          title: draft.title,
          format: draft.format,
          prices: draft.prices,
          genre: draft.genre,
          monetisationMode: draft.monetisationMode,
          subscriptionEligible: draft.subscriptionEligible,
          mediaName: draft.mediaName,
          mediaKind: draft.mediaKind,
          mediaBytes: draft.mediaBytes,
          mediaId: draft.mediaId,
          coverImageName: draft.coverImageName,
          coverImageBytes: draft.coverImageBytes,
          chapters: draft.chapters,
          episodes: draft.episodes,
          submit: draft.status == 'submitted',
          email: contact.trim().isEmpty ? null : contact.trim(),
          displayName: displayName.trim().isEmpty ? null : displayName.trim(),
        );
        if (remote != null) {
          final index = drafts.indexWhere((d) => d.id == draft.id);
          if (index >= 0) {
            drafts[index] = CreatorDraft(
              id: remote.id,
              title: draft.title,
              format: draft.format,
              genre: draft.genre,
              prices: draft.prices,
              monetisationMode: draft.monetisationMode,
              subscriptionEligible: draft.subscriptionEligible,
              status: remote.status,
              createdAtMs: draft.createdAtMs,
              mediaName: draft.mediaName,
              mediaPath: draft.mediaPath,
              mediaKind: draft.mediaKind,
              mediaBytes: draft.mediaBytes,
              mediaId: draft.mediaId ?? remote.mediaId,
              coverImageName: draft.coverImageName,
              coverImagePath: draft.coverImagePath,
              coverImageBytes: draft.coverImageBytes,
              chapters: draft.chapters,
              episodes: draft.episodes,
              publishedTitleId: remote.publishedTitleId ?? draft.publishedTitleId,
            );
            progressed = true;
          }
        }
      }
      if (locals.isNotEmpty) await _persist();
    }

    if (progressed) {
      await _syncLibraryFromApi();
      notifyListeners();
    }

    if (_pendingOwnedSync.isEmpty &&
        _pendingSavedSync.isEmpty &&
        !drafts.any((d) => d.id.startsWith('local-'))) {
      _syncRetryTimer?.cancel();
      _syncRetryTimer = null;
    }
  }

  Future<void> refreshFromApi() async {
    await _syncCatalogueFromApi();
    if (isSignedIn) {
      // Profile (/me) before library so creator entitlement grants are visible.
      await _syncProfileFromApi();
      await _syncLibraryFromApi();
      await _syncSalesFromApi();
      await _syncDraftsFromApi();
      await _syncNotesFromApi();
      // If drafts API was unreachable, still surface your live creator titles.
      _hydrateStudioDraftsFromCatalogue();
      await _backfillDraftPartsFromCatalogue();
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _syncSalesFromApi() async {
    final bearer = _devBearer();
    if (bearer == null) return;
    final remote = await _api.fetchSales(bearer);
    if (remote != null) sales = remote;
  }

  Future<void> _syncDraftsFromApi() async {
    final bearer = _devBearer();
    if (bearer == null) return;
    final remote = await _api.fetchStudioDrafts(bearer);
    if (remote == null) return;
    // API is source of truth for non-local rows. Keep only unsynced local-* drafts
    // that do not already exist remotely under the same title.
    final byLocalKey = <String, CreatorDraft>{
      for (final draft in drafts) draft.id: draft,
      for (final draft in drafts) 'title:${draft.title.trim().toLowerCase()}': draft,
    };
    final remoteTitles = {
      for (final draft in remote) draft.title.trim().toLowerCase(),
    };
    final localOnly = drafts
        .where(
          (d) =>
              d.id.startsWith('local-') &&
              !remoteTitles.contains(d.title.trim().toLowerCase()),
        )
        .toList();
    final merged = <CreatorDraft>[];
    for (final draft in remote) {
      final local = byLocalKey[draft.id] ??
          byLocalKey['title:${draft.title.trim().toLowerCase()}'];
      merged.add(
        draft.copyWith(
          genre: draft.genre ?? local?.genre,
          mediaPath: local?.mediaPath,
          mediaId: draft.mediaId ?? local?.mediaId,
          mediaName: draft.mediaName ?? local?.mediaName,
          mediaKind: draft.mediaKind ?? local?.mediaKind,
          mediaBytes: draft.mediaBytes ?? local?.mediaBytes,
          coverImageName: draft.coverImageName ?? local?.coverImageName,
          coverImagePath: local?.coverImagePath,
          coverImageBytes: draft.coverImageBytes ?? local?.coverImageBytes,
          chapters: draft.chapters.isNotEmpty ? draft.chapters : local?.chapters,
          episodes: _mergeEpisodeLocalPaths(
            draft.episodes.isNotEmpty ? draft.episodes : (local?.episodes ?? const []),
            local?.episodes,
          ),
        ),
      );
    }
    merged.addAll(localOnly);
    drafts
      ..clear()
      ..addAll(merged);
    _hydrateStudioDraftsFromCatalogue();
    await _backfillDraftPartsFromCatalogue();
  }

  /// Offline / sync-gap fallback: show live creator catalogue titles you authored.
  void _hydrateStudioDraftsFromCatalogue() {
    if (creatorState != CreatorApplicationState.approved) return;
    if (drafts.isNotEmpty) return;
    final author = displayName.trim().toLowerCase();
    if (author.isEmpty) return;
    for (final title in titles) {
      if (!title.id.startsWith('creator-')) continue;
      if (title.author.trim().toLowerCase() != author) continue;
      drafts.add(
        CreatorDraft(
          id: 'local-from-${title.id}',
          title: title.name,
          format: title.formatLabel,
          genre: title.category,
          prices: title.prices
              .map((p) => PriceQuote(currency: p.currency, amountMinor: p.amountMinor))
              .toList(),
          status: 'live',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          publishedTitleId: title.id,
          monetisationMode: title.monetisationMode,
          subscriptionEligible:
              title.subscriptionEligible ?? title.format != ContentFormat.podcast,
        ),
      );
    }
  }

  /// Fill missing Studio parts from the live catalogue so edit flows are not blank.
  Future<void> _backfillDraftPartsFromCatalogue() async {
    var changed = false;
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      final titleId = draft.publishedTitleId;
      if (titleId == null || titleId.isEmpty) continue;
      final needsAudio = draft.isAudioFormat && draft.episodes.isEmpty;
      final needsEbook = draft.isEbook && draft.chapters.isEmpty;
      if (!needsAudio && !needsEbook) continue;
      await refreshTitleParts(titleId, notify: false);
      final nextEpisodes = needsAudio
          ? tracksFor(titleId)
              .asMap()
              .entries
              .map(
                (entry) => ContentEpisode(
                  id: entry.value.id,
                  title: entry.value.title,
                  durationSec: entry.value.durationSec,
                  sortOrder: entry.key,
                  mediaName: entry.value.mediaName,
                  mediaId: _mediaIdFromUrl(entry.value.mediaUrl),
                ),
              )
              .toList()
          : draft.episodes;
      final nextChapters = needsEbook
          ? chaptersFor(titleId)
              .asMap()
              .entries
              .map(
                (entry) => ContentChapter(
                  id: entry.value.id,
                  title: entry.value.title,
                  body: entry.value.body,
                  sortOrder: entry.key,
                ),
              )
              .toList()
          : draft.chapters;
      if (nextEpisodes.isEmpty && nextChapters.isEmpty) continue;
      drafts[i] = draft.copyWith(
        episodes: nextEpisodes.isNotEmpty ? nextEpisodes : draft.episodes,
        chapters: nextChapters.isNotEmpty ? nextChapters : draft.chapters,
      );
      changed = true;
    }
    if (changed) await _persist();
  }

  String? _mediaIdFromUrl(String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;
    const marker = '/media/';
    final index = mediaUrl.indexOf(marker);
    if (index < 0) return null;
    final id = mediaUrl.substring(index + marker.length).split('?').first;
    return id.isEmpty ? null : id;
  }

  /// Latest draft snapshot for Studio edit, with catalogue parts filled in.
  Future<CreatorDraft> draftForEdit(CreatorDraft draft) async {
    await _syncDraftsFromApi();
    CreatorDraft? latest;
    for (final candidate in drafts) {
      if (candidate.id == draft.id ||
          (draft.publishedTitleId != null &&
              candidate.publishedTitleId == draft.publishedTitleId) ||
          candidate.title.trim().toLowerCase() == draft.title.trim().toLowerCase()) {
        latest = candidate;
        break;
      }
    }
    latest ??= draft;
    final titleId = latest.publishedTitleId;
    if (titleId != null &&
        ((latest.isAudioFormat && latest.episodes.isEmpty) ||
            (latest.isEbook && latest.chapters.isEmpty))) {
      await refreshTitleParts(titleId, notify: false);
      await _backfillDraftPartsFromCatalogue();
      for (final candidate in drafts) {
        if (candidate.id == latest.id) return candidate;
      }
    }
    return latest;
  }

  Future<void> _syncNotesFromApi() async {
    final bearer = _devBearer();
    if (bearer == null) return;
    final remote = await _api.fetchNotes(bearer);
    if (remote.isEmpty) return;
    final byId = {for (final note in notes) note.id: note};
    for (final note in remote) {
      byId[note.id] = note;
    }
    notes
      ..clear()
      ..addAll(byId.values);
  }

  void setCreatorState(CreatorApplicationState state) {
    creatorState = state;
    notifyListeners();
    _persist();
  }

  Future<bool> applyAsCreator({required String displayName}) async {
    final bearer = _devBearer();
    if (bearer == null) {
      creatorState = CreatorApplicationState.pending;
      notifyListeners();
      await _persist();
      showNotice('Sign in to submit your creator application.');
      return false;
    }

    final remote = await _api.applyCreator(bearer, displayName: displayName);
    if (remote == null) {
      creatorState = CreatorApplicationState.pending;
      notifyListeners();
      await _persist();
      _ensureSyncRetry();
      showNotice('Application saved. We’ll sync it when Listen+ is reachable.');
      return false;
    }

    creatorState = _creatorStateFromApi(remote.creatorStatus);
    if (remote.displayName != null && remote.displayName!.trim().isNotEmpty) {
      this.displayName = remote.displayName!.trim();
    }
    notifyListeners();
    await _persist();
    showNotice(
      creatorState == CreatorApplicationState.approved
          ? 'Creator access is already approved.'
          : 'Creator application submitted for review.',
    );
    return true;
  }

  Future<CreatorDraft> saveCreatorDraft({
    String? existingId,
    required String title,
    required String format,
    required List<PriceQuote> prices,
    String? genre,
    String? monetisationMode,
    bool? subscriptionEligible,
    String? mediaName,
    String? mediaPath,
    String? mediaKind,
    int? mediaBytes,
    String? coverImageName,
    String? coverImagePath,
    int? coverImageBytes,
    List<ContentChapter>? chapters,
    List<ContentEpisode>? episodes,
    bool? submit,
  }) async {
    final existingIndex =
        existingId == null ? -1 : drafts.indexWhere((d) => d.id == existingId);
    final existing = existingIndex >= 0 ? drafts[existingIndex] : null;
    final nextChapters = chapters ?? existing?.chapters ?? const <ContentChapter>[];
    final nextEpisodes = episodes ?? existing?.episodes ?? const <ContentEpisode>[];
    final wantsSubmit = submit == true;
    final localStatus = wantsSubmit
        ? 'submitted'
        : (existing?.status == 'live' ? 'live' : (submit == false ? 'draft' : (existing?.status ?? 'draft')));

    var preparedEpisodes = nextEpisodes;
    var preparedMediaId = existing?.mediaId;
    final bearer = _devBearer();
    if (bearer != null) {
      // Upload any local audio that is not yet on the API before draft sync.
      final uploaded = <ContentEpisode>[];
      for (final episode in nextEpisodes) {
        if ((episode.mediaId != null && episode.mediaId!.isNotEmpty) ||
            episode.mediaPath == null ||
            !File(episode.mediaPath!).existsSync()) {
          uploaded.add(episode);
          continue;
        }
        final id = await _api.uploadMedia(
          bearer,
          filePath: episode.mediaPath!,
          filename: episode.mediaName,
        );
        uploaded.add(id == null ? episode : episode.copyWith(mediaId: id));
      }
      preparedEpisodes = uploaded;
      if (mediaPath != null && File(mediaPath).existsSync()) {
        final pathChanged = existing?.mediaPath != mediaPath;
        if (preparedMediaId == null || preparedMediaId.isEmpty || pathChanged) {
          preparedMediaId = await _api.uploadMedia(
            bearer,
            filePath: mediaPath,
            filename: mediaName,
          );
        }
      }
      // Podcast/audiobook: also promote first episode media to draft root when needed.
      if (preparedMediaId == null || preparedMediaId.isEmpty) {
        for (final episode in preparedEpisodes) {
          final id = episode.mediaId;
          if (id != null && id.isNotEmpty) {
            preparedMediaId = id;
            break;
          }
        }
      }
    }

    final local = CreatorDraft(
      id: existing?.id ?? 'local-${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      format: format,
      genre: genre ?? existing?.genre,
      prices: prices,
      monetisationMode: monetisationMode ??
          existing?.monetisationMode ??
          (format == 'Podcast' ? 'free_with_ads' : 'purchase'),
      subscriptionEligible:
          subscriptionEligible ?? existing?.subscriptionEligible ?? format != 'Podcast',
      status: localStatus,
      createdAtMs: existing?.createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      mediaName: mediaName,
      mediaPath: mediaPath,
      mediaKind: mediaKind,
      mediaBytes: mediaBytes,
      mediaId: preparedMediaId,
      coverImageName: coverImageName,
      coverImagePath: coverImagePath,
      coverImageBytes: coverImageBytes,
      chapters: nextChapters,
      episodes: preparedEpisodes,
      publishedTitleId: existing?.publishedTitleId,
    );

    CreatorDraft saved = local.copyWith(
      status: wantsSubmit ? 'draft' : local.status,
    );
    // Never mark as submitted unless the API confirms — otherwise admin never sees it.
    if (bearer == null) {
      if (existingIndex >= 0) {
        drafts[existingIndex] = local.copyWith(status: 'draft');
      } else {
        drafts.insert(0, local.copyWith(status: 'draft'));
      }
      notifyListeners();
      await _persist();
      _pendingDraftFlush = true;
      _ensureSyncRetry();
      showNotice(
        wantsSubmit
            ? 'Saved on this device. Sign in to submit for review.'
            : 'Draft saved on this device.',
      );
      return drafts.first;
    }

    final email = contact.trim().isEmpty ? null : contact.trim();
    final name = displayName.trim().isEmpty ? null : displayName.trim();
    // null = keep current API status (important for live + part edits).
    final bool? submitFlag = existing?.status == 'live'
        ? (wantsSubmit ? true : null)
        : submit;
    CreatorDraft? remote;
    if (existingId != null && !existingId.startsWith('local-')) {
      remote = await _api.updateStudioDraft(
        bearer,
        id: existingId,
        title: title,
        format: format,
        prices: prices,
        genre: local.genre,
        monetisationMode: local.monetisationMode,
        subscriptionEligible: local.subscriptionEligible,
        mediaName: mediaName,
        mediaKind: mediaKind,
        mediaBytes: mediaBytes,
        mediaId: local.mediaId,
        coverImageName: coverImageName,
        coverImageBytes: coverImageBytes,
        chapters: nextChapters,
        episodes: preparedEpisodes,
        submit: submitFlag,
        email: email,
        displayName: name,
      );
      // Stale draft ids (API restart before disk persist) → create a fresh API row.
      remote ??= await _api.createStudioDraft(
        bearer,
        title: title,
        format: format,
        prices: prices,
        genre: local.genre,
        monetisationMode: local.monetisationMode,
        subscriptionEligible: local.subscriptionEligible,
        mediaName: mediaName,
        mediaKind: mediaKind,
        mediaBytes: mediaBytes,
        mediaId: local.mediaId,
        coverImageName: coverImageName,
        coverImageBytes: coverImageBytes,
        chapters: nextChapters,
        episodes: preparedEpisodes,
        submit: wantsSubmit,
        email: email,
        displayName: name,
      );
    } else {
      remote = await _api.createStudioDraft(
        bearer,
        title: title,
        format: format,
        prices: prices,
        genre: local.genre,
        monetisationMode: local.monetisationMode,
        subscriptionEligible: local.subscriptionEligible,
        mediaName: mediaName,
        mediaKind: mediaKind,
        mediaBytes: mediaBytes,
        mediaId: local.mediaId,
        coverImageName: coverImageName,
        coverImageBytes: coverImageBytes,
        chapters: nextChapters,
        episodes: preparedEpisodes,
        submit: wantsSubmit,
        email: email,
        displayName: name,
      );
    }

    if (remote == null) {
      final offline = local.copyWith(status: 'draft');
      if (existingIndex >= 0) {
        drafts[existingIndex] = offline;
      } else {
        drafts.insert(0, offline);
      }
      apiReachable = await _api.health();
      notifyListeners();
      await _persist();
      _pendingDraftFlush = true;
      _ensureSyncRetry();
      showNotice(
        wantsSubmit
            ? 'Saved on this device. Will submit for review when Listen+ is reachable.'
            : 'Draft saved on this device. Syncing when Listen+ is reachable…',
      );
      return offline;
    }

    saved = CreatorDraft(
      id: remote.id,
      title: remote.title,
      format: format,
      genre: local.genre ?? remote.genre,
      prices: prices,
      monetisationMode: local.monetisationMode ?? remote.monetisationMode,
      subscriptionEligible: local.subscriptionEligible,
      status: remote.status,
      createdAtMs: existing?.createdAtMs ?? remote.createdAtMs,
      mediaName: mediaName,
      mediaPath: mediaPath,
      mediaKind: mediaKind,
      mediaBytes: mediaBytes,
      mediaId: local.mediaId ?? remote.mediaId,
      coverImageName: coverImageName ?? remote.coverImageName,
      coverImagePath: coverImagePath,
      coverImageBytes: coverImageBytes ?? remote.coverImageBytes,
      chapters: remote.chapters.isNotEmpty ? remote.chapters : nextChapters,
      episodes: _mergeEpisodeLocalPaths(
        remote.episodes.isNotEmpty ? remote.episodes : preparedEpisodes,
        preparedEpisodes,
      ),
      publishedTitleId: remote.publishedTitleId ?? existing?.publishedTitleId,
    );

    if (existingIndex >= 0) {
      drafts[existingIndex] = saved;
    } else {
      // Drop any previous local-only copy of the same title.
      drafts.removeWhere((d) => d.id.startsWith('local-') && d.title == saved.title);
      drafts.insert(0, saved);
    }
    await _syncSalesFromApi();
    await _syncDraftsFromApi();
    overlayDraftParts(saved);
    if (saved.publishedTitleId != null) {
      downloads.removeWhere((d) => d.titleId == saved.publishedTitleId);
      await refreshTitleParts(saved.publishedTitleId!);
    }
    notifyListeners();
    await _persist();
    showNotice(
      saved.status == 'submitted'
          ? 'Submitted for review. It appears on Home after approval.'
          : saved.status == 'live'
              ? 'Live on Listen+ · ${saved.priceSummary}'
              : 'Draft saved · ${saved.priceSummary}',
    );
    return saved;
  }

  Future<void> deleteCreatorDraft(String id) async {
    drafts.removeWhere((d) => d.id == id);
    final bearer = _devBearer();
    if (bearer != null && !id.startsWith('local-')) {
      await _api.deleteStudioDraft(bearer, id);
    }
    notifyListeners();
    await _persist();
    showNotice('Draft deleted.');
  }

  Future<void> refreshSales() async {
    await _syncSalesFromApi();
    notifyListeners();
  }

  bool isDownloaded(String titleId) => downloads.any((d) => d.titleId == titleId);

  Future<void> downloadForOffline(TitleItem title) async {
    final path = title.isAudio
        ? await _offline.cacheAudioMarker(title)
        : await _offline.cacheEbook(title, chaptersFor(title.id));
    downloads.removeWhere((d) => d.titleId == title.id);
    downloads.insert(
      0,
      OfflineDownload(
        titleId: title.id,
        format: title.isAudio ? title.formatLabel : 'EPUB',
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        bytes: title.isAudio ? 360000 : chaptersFor(title.id).fold<int>(0, (sum, c) => sum + c.body.length),
        localPath: path,
      ),
    );
    notifyListeners();
    await _persist();
    showNotice('${title.name} ready offline.');
  }

  Future<void> removeDownload(String titleId) async {
    await _offline.remove(titleId);
    downloads.removeWhere((d) => d.titleId == titleId);
    notifyListeners();
    await _persist();
  }

  List<ContentNote> notesFor(String titleId) =>
      notes.where((n) => n.titleId == titleId).toList();

  Future<void> addContentNote(ContentNote note) async {
    var saved = note;
    final bearer = _devBearer();
    if (bearer != null) {
      final remote = await _api.createNote(bearer, note: note);
      if (remote != null) saved = remote;
    }
    notes.insert(0, saved);
    notifyListeners();
    await _persist();
    showNotice(note.kind == 'voice' ? 'Voice note pinned.' : 'Note pinned.');
  }

  void removeContentNote(String id) {
    notes.removeWhere((n) => n.id == id);
    notifyListeners();
    _persist();
  }

  void setReaderPrefs({double? fontScale, ReaderThemeMode? theme}) {
    readerPrefs = readerPrefs.copyWith(fontScale: fontScale, theme: theme);
    notifyListeners();
    _persist();
  }

  void updateReadingProgress({
    required String titleId,
    required String chapterId,
    required double scrollFraction,
    List<String>? bookmarks,
    bool persist = true,
  }) {
    final existing = progress[titleId];
    progress[titleId] = TitleProgress(
      titleId: titleId,
      locationId: chapterId,
      position: scrollFraction.clamp(0, 1),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      bookmarks: bookmarks ?? existing?.bookmarks ?? const [],
    );
    notifyListeners();
    if (persist) _persist();
  }

  void toggleChapterBookmark({
    required String titleId,
    required String chapterId,
    double? scrollFraction,
  }) {
    final existing = progress[titleId];
    final bookmarks = List<String>.from(existing?.bookmarks ?? const []);
    final position = (scrollFraction ?? existing?.position ?? 0).clamp(0.0, 1.0);
    final token = '$chapterId@${position.toStringAsFixed(3)}';
    final existingIndex = bookmarks.indexWhere(
      (item) => item == chapterId || item.startsWith('$chapterId@'),
    );
    if (existingIndex >= 0) {
      bookmarks.removeAt(existingIndex);
    } else {
      bookmarks.add(token);
    }
    progress[titleId] = TitleProgress(
      titleId: titleId,
      locationId: existing?.locationId ?? chapterId,
      position: existing?.position ?? position,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      bookmarks: bookmarks,
    );
    notifyListeners();
    _persist();
  }

  bool isChapterBookmarked(String titleId, String chapterId) {
    final bookmarks = progress[titleId]?.bookmarks ?? const [];
    return bookmarks.any((item) => item == chapterId || item.startsWith('$chapterId@'));
  }

  static String bookmarkChapterId(String token) => token.split('@').first;

  static double? bookmarkScrollFraction(String token) {
    final parts = token.split('@');
    if (parts.length < 2) return null;
    return double.tryParse(parts[1]);
  }

  Future<void> play(
    TitleItem title, {
    String? trackId,
    double? positionSec,
    bool autoplay = true,
  }) async {
    await refreshTitleParts(title.id);
    final tracks = tracksFor(title.id);
    if (tracks.isEmpty) return;

    final saved = progress[title.id];
    final preferredId = trackId ?? saved?.locationId ?? tracks.first.id;
    final track = tracks.firstWhere(
      (item) => item.id == preferredId,
      orElse: () => tracks.first,
    );
    final start = positionSec ??
        (saved != null && saved.locationId == track.id ? saved.position : 0.0);

    nowPlaying = title;
    nowPlayingTrack = track;
    playbackPositionSec = start.clamp(0, track.durationSec.toDouble());
    _qualifiedListenAccumSec = 0;

    final needsPreroll = title.showsAds &&
        !_prerollShownForSession.contains('${title.id}:${track.id}') &&
        _hourlyAdSlotsRemaining > 0;
    if (needsPreroll && autoplay) {
      playing = false;
      await _engageAudioEngine(startAt: playbackPositionSec, autoplay: false);
      _syncAudioProgress(persist: true);
      _startAdBreak(placement: 'preroll');
      return;
    }

    playing = autoplay;
    await _engageAudioEngine(startAt: playbackPositionSec, autoplay: autoplay);
    _syncAudioProgress(persist: true);
    notifyListeners();
  }

  Future<void> selectTrack(SampleAudioTrack track, {bool autoplay = true}) async {
    if (nowPlaying == null) return;
    nowPlayingTrack = track;
    playbackPositionSec = 0;
    playing = autoplay;
    await _engageAudioEngine(startAt: 0, autoplay: autoplay);
    _syncAudioProgress(persist: true);
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (nowPlaying == null || nowPlayingTrack == null) return;
    playing = !playing;
    if (usingRealAudio) {
      if (playing) {
        await _audio.play();
      } else {
        await _audio.pause();
      }
      _stopTicker();
    } else {
      _restartTicker();
    }
    _syncAudioProgress(persist: true);
    notifyListeners();
  }

  Future<void> seekTo(double seconds) async {
    final track = nowPlayingTrack;
    if (track == null) return;
    playbackPositionSec = seconds.clamp(0, track.durationSec.toDouble());
    if (usingRealAudio) {
      await _audio.seek(Duration(milliseconds: (playbackPositionSec * 1000).round()));
    }
    _syncAudioProgress(persist: true);
    notifyListeners();
  }

  Future<void> skipBy(int seconds) async {
    await seekTo(playbackPositionSec + seconds);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    if (usingRealAudio) {
      await _audio.setSpeed(speed);
    } else {
      _restartTicker();
    }
    notifyListeners();
    await _persist();
  }

  void setSleepTimerMinutes(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerMinutesRemaining = minutes;
    if (minutes == null || minutes <= 0) {
      notifyListeners();
      return;
    }
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      playing = false;
      sleepTimerMinutesRemaining = null;
      _stopTicker();
      if (usingRealAudio) await _audio.pause();
      _syncAudioProgress(persist: true);
      showNotice('Sleep timer ended playback.');
    });
    notifyListeners();
  }

  Future<void> stopPlayback() async {
    _syncAudioProgress(persist: true);
    _stopTicker();
    _stopAdBreakTicker();
    adBreakActive = false;
    adBreakPlacement = null;
    adBreakElapsedSec = 0;
    adBreakSkippable = false;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerMinutesRemaining = null;
    await _audioPositionSub?.cancel();
    _audioPositionSub = null;
    await _audio.stop();
    usingRealAudio = false;
    usingSampleAsset = false;
    nowPlaying = null;
    nowPlayingTrack = null;
    playing = false;
    playbackPositionSec = 0;
    notifyListeners();
  }

  int get _hourlyAdSlotsRemaining {
    final hourAgo = DateTime.now().millisecondsSinceEpoch - 60 * 60 * 1000;
    _adCompletionTimesMs.removeWhere((t) => t < hourAgo);
    return (3 - _adCompletionTimesMs.length).clamp(0, 3);
  }

  void _stopAdBreakTicker() {
    _adBreakTicker?.cancel();
    _adBreakTicker = null;
  }

  void _startAdBreak({required String placement}) {
    _stopAdBreakTicker();
    adBreakActive = true;
    adBreakPlacement = placement;
    adBreakElapsedSec = 0;
    adBreakSkippable = false;
    playing = false;
    if (usingRealAudio) {
      _audio.pause();
    } else {
      _stopTicker();
    }
    notifyListeners();
    _adBreakTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!adBreakActive) return;
      adBreakElapsedSec += 1;
      if (adBreakElapsedSec >= 5) adBreakSkippable = true;
      // Soft cap at 15s prototype spot; auto-complete.
      if (adBreakElapsedSec >= 15) {
        completeAdBreak(skipped: false);
        return;
      }
      notifyListeners();
    });
  }

  Future<void> completeAdBreak({required bool skipped}) async {
    if (!adBreakActive) return;
    final title = nowPlaying;
    final track = nowPlayingTrack;
    final placement = adBreakPlacement ?? 'preroll';
    final watched = adBreakElapsedSec;
    _stopAdBreakTicker();
    adBreakActive = false;
    adBreakPlacement = null;
    adBreakSkippable = false;
    adBreakElapsedSec = 0;

    if (title != null && track != null) {
      if (placement == 'preroll') {
        _prerollShownForSession.add('${title.id}:${track.id}');
      } else if (placement == 'midroll') {
        _midrollShownForTrack.add('${title.id}:${track.id}');
      }
    }

    final bearer = _devBearer();
    if (!skipped &&
        watched >= 5 &&
        title != null &&
        title.showsAds &&
        bearer != null &&
        _hourlyAdSlotsRemaining > 0) {
      final ok = await _api.completeAd(
        bearer,
        titleId: title.id,
        placement: placement == 'chapter' ? 'midroll' : placement,
        completedSec: watched,
        trackId: track?.id,
      );
      if (ok) {
        _adCompletionTimesMs.add(DateTime.now().millisecondsSinceEpoch);
        await refreshSales();
      }
    }

    // Chapter interstitial is reader-only — don't start the audio engine.
    if (placement == 'chapter' || nowPlayingTrack == null) {
      playing = false;
      notifyListeners();
      return;
    }

    playing = true;
    if (usingRealAudio) {
      await _audio.play();
    } else {
      _restartTicker();
    }
    notifyListeners();
  }

  Future<void> skipAdBreak() async {
    if (!adBreakActive || !adBreakSkippable) return;
    // Still monetise if they watched the minimum 5s before skip.
    await completeAdBreak(skipped: adBreakElapsedSec < 5);
  }

  /// Reader interstitial between chapters for free-with-ads ebooks (max 1/session).
  Future<void> maybeShowChapterAd(TitleItem title) async {
    if (!title.showsAds) return;
    if (_prerollShownForSession.contains('chapter:${title.id}')) return;
    if (_hourlyAdSlotsRemaining <= 0) return;
    nowPlaying = title;
    nowPlayingTrack = null;
    _startAdBreak(placement: 'chapter');
    _prerollShownForSession.add('chapter:${title.id}');
  }

  Future<void> reportQualifiedReading(TitleItem title, {required int minutes}) async {
    if (minutes < 1) return;
    if (title.subscriptionEligible == false &&
        title.resolvedMonetisationMode != 'subscription' &&
        title.resolvedMonetisationMode != 'purchase') {
      return;
    }
    final bearer = _devBearer();
    if (bearer == null) return;
    final dayKey = '${title.id}:${DateTime.now().toIso8601String().substring(0, 10)}';
    final already = _readerMinutesCredited[dayKey] ?? 0;
    final grant = minutes.clamp(0, 20 - already);
    if (grant <= 0) return;
    final ok = await _api.creditQualifiedConsumption(
      bearer,
      titleId: title.id,
      minutes: grant,
      kind: 'reading',
    );
    if (ok) {
      _readerMinutesCredited[dayKey] = already + grant;
      await refreshSales();
    }
  }

  Future<void> _maybeCreditListeningMinute() async {
    final title = nowPlaying;
    if (title == null || !playing || adBreakActive) return;
    if (title.subscriptionEligible == false &&
        title.resolvedMonetisationMode != 'subscription' &&
        title.resolvedMonetisationMode != 'purchase') {
      return;
    }
    _qualifiedListenAccumSec += 0.25 * playbackSpeed;
    if (_qualifiedListenAccumSec < 60) return;
    final minutes = (_qualifiedListenAccumSec / 60).floor();
    _qualifiedListenAccumSec -= minutes * 60;
    final bearer = _devBearer();
    if (bearer == null) return;
    final ok = await _api.creditQualifiedConsumption(
      bearer,
      titleId: title.id,
      minutes: minutes,
      kind: 'listening',
    );
    if (ok) await refreshSales();
  }

  void _maybeTriggerMidroll() {
    final title = nowPlaying;
    final track = nowPlayingTrack;
    if (title == null || track == null || adBreakActive || !playing) return;
    if (!title.showsAds) return;
    if (track.durationSec < 12 * 60) return; // only longer episodes
    if (_midrollShownForTrack.contains('${title.id}:${track.id}')) return;
    if (_hourlyAdSlotsRemaining <= 0) return;
    final threshold = track.durationSec * 0.4;
    if (playbackPositionSec < threshold) return;
    _startAdBreak(placement: 'midroll');
  }

  List<ContentEpisode> _mergeEpisodeLocalPaths(
    List<ContentEpisode> remote,
    List<ContentEpisode>? local,
  ) {
    if (local == null || local.isEmpty) return remote;
    final byId = {for (final episode in local) episode.id: episode};
    final byOrder = [...local]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return remote.asMap().entries.map((entry) {
      final index = entry.key;
      final episode = entry.value;
      final prior = byId[episode.id] ??
          (index < byOrder.length ? byOrder[index] : null);
      if (prior == null) return episode;
      return episode.copyWith(
        mediaPath: prior.mediaPath,
        mediaId: episode.mediaId ?? prior.mediaId,
        mediaName: episode.mediaName ?? prior.mediaName,
        body: episode.body ?? prior.body,
        showNotes: episode.showNotes ?? prior.showNotes,
      );
    }).toList();
  }

  bool _fileExists(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  Future<String?> _findLocalMediaByName(String? mediaName) async {
    if (mediaName == null || mediaName.isEmpty) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      for (final folder in ['episodes', 'media']) {
        final dir = Directory('${docs.path}/$folder');
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync()) {
          if (entity is! File) continue;
          if (entity.path.endsWith('_$mediaName') ||
              entity.path.endsWith('/$mediaName') ||
              entity.uri.pathSegments.last.contains(mediaName)) {
            return entity.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _looksLikePdf(String? pathOrName) {
    final value = (pathOrName ?? '').toLowerCase();
    return value.endsWith('.pdf');
  }

  bool _chaptersSuggestPdf(TitleItem title) {
    if (title.isPdfEbook) return true;
    for (final chapter in chaptersFor(title.id)) {
      final body = chapter.body.toLowerCase();
      if (body.contains('.pdf') || body.contains('image-based or encrypted')) {
        return true;
      }
    }
    return false;
  }

  /// Resolve a local PDF path for ebook reading (draft file or downloaded media).
  Future<String?> resolveEbookPdfFile(TitleItem title) async {
    if (!title.isEbook) return null;
    final preferPdf = _chaptersSuggestPdf(title);

    for (final draft in drafts) {
      if (draft.publishedTitleId != title.id && draft.id != title.id) continue;
      if (_fileExists(draft.mediaPath) &&
          (_looksLikePdf(draft.mediaPath) || preferPdf)) {
        if (_looksLikePdf(draft.mediaPath) || await _fileIsPdf(draft.mediaPath!)) {
          return draft.mediaPath;
        }
      }
      if (_looksLikePdf(draft.mediaName) || preferPdf) {
        final byName = await _findLocalMediaByName(draft.mediaName);
        if (byName != null && (_looksLikePdf(byName) || await _fileIsPdf(byName))) {
          return byName;
        }
      }
      final mediaId = draft.mediaId;
      if (mediaId != null &&
          mediaId.isNotEmpty &&
          (_looksLikePdf(draft.mediaName) || preferPdf || title.isPdfEbook)) {
        final name = draft.mediaName ?? title.mediaName ?? '${title.id}.pdf';
        final safeName = _looksLikePdf(name) ? name : '$name.pdf';
        final cached = await _cacheRemoteEbookPdf(
          titleId: title.id,
          mediaUrl: _api.absoluteMediaUrl('/v1/media/$mediaId'),
          mediaName: safeName,
        );
        if (cached != null && await _fileIsPdf(cached)) return cached;
      }
    }

    if (_looksLikePdf(title.mediaName)) {
      final byName = await _findLocalMediaByName(title.mediaName);
      if (byName != null) return byName;
    }

    final remote = title.mediaUrl;
    if (remote != null && remote.isNotEmpty && (title.isPdfEbook || preferPdf)) {
      final name = title.mediaName ?? '${title.id}.pdf';
      final cached = await _cacheRemoteEbookPdf(
        titleId: title.id,
        mediaUrl: remote,
        mediaName: _looksLikePdf(name) ? name : '$name.pdf',
      );
      if (cached != null && await _fileIsPdf(cached)) return cached;
    }
    return null;
  }

  Future<bool> _fileIsPdf(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      if (_looksLikePdf(path)) return true;
      final raf = await file.open();
      final header = await raf.read(5);
      await raf.close();
      return String.fromCharCodes(header) == '%PDF-';
    } catch (_) {
      return false;
    }
  }

  Future<String?> _cacheRemoteEbookPdf({
    required String titleId,
    required String mediaUrl,
    required String mediaName,
  }) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final safeName = mediaName.split(Platform.pathSeparator).last;
      final dest = '${docs.path}/media/pdf_${titleId}_$safeName';
      if (_fileExists(dest) && File(dest).lengthSync() > 0) return dest;
      return await _api.downloadMediaFile(mediaUrl, destinationPath: dest);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _mediaPathForPlayingTitle() async {
    final title = nowPlaying;
    if (title == null) return null;
    final trackId = nowPlayingTrack?.id;
    final trackIndex = trackId == null
        ? -1
        : tracksFor(title.id).indexWhere((t) => t.id == trackId);

    for (final draft in drafts) {
      if (draft.publishedTitleId != title.id && draft.id != title.id) continue;
      final episodes = [...draft.episodes]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      ContentEpisode? matched;
      if (trackId != null) {
        for (final episode in episodes) {
          if (episode.id == trackId) {
            matched = episode;
            break;
          }
        }
      }
      matched ??= (trackIndex >= 0 && trackIndex < episodes.length)
          ? episodes[trackIndex]
          : null;
      matched ??= episodes.isNotEmpty ? episodes.first : null;

      if (matched != null) {
        if (_fileExists(matched.mediaPath)) return matched.mediaPath;
        final byName = await _findLocalMediaByName(matched.mediaName);
        if (byName != null) return byName;
      }

      if (_fileExists(draft.mediaPath)) return draft.mediaPath;
      final draftByName = await _findLocalMediaByName(draft.mediaName);
      if (draftByName != null) return draftByName;
    }
    return null;
  }

  String? _mediaUrlForPlayingTitle() {
    final track = nowPlayingTrack;
    if (track?.mediaUrl != null && track!.mediaUrl!.isNotEmpty) {
      return track.mediaUrl;
    }
    final title = nowPlaying;
    if (title == null || track == null) return null;
    for (final draft in drafts) {
      if (draft.publishedTitleId != title.id) continue;
      final episodes = [...draft.episodes]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      ContentEpisode? matched;
      for (final episode in episodes) {
        if (episode.id == track.id) {
          matched = episode;
          break;
        }
      }
      final index = tracksFor(title.id).indexWhere((t) => t.id == track.id);
      matched ??= (index >= 0 && index < episodes.length) ? episodes[index] : null;
      final mediaId = matched?.mediaId ?? draft.mediaId;
      if (mediaId != null && mediaId.isNotEmpty) {
        return _api.absoluteMediaUrl('/v1/media/$mediaId');
      }
    }
    return null;
  }

  Future<void> _engageAudioEngine({required double startAt, required bool autoplay}) async {
    await _audioPositionSub?.cancel();
    _audioPositionSub = null;
    _stopTicker();

    final localPath = await _mediaPathForPlayingTitle();
    final mediaUrl = _mediaUrlForPlayingTitle();
    final ok = await _audio.load(
      duration: Duration(seconds: nowPlayingTrack?.durationSec ?? 8),
      filePath: localPath,
      mediaUrl: mediaUrl,
    );
    usingRealAudio = ok;
    usingSampleAsset = ok && _audio.usingSampleAsset;
    if (!ok) {
      if (autoplay) _restartTicker();
      return;
    }

    // Upload local-only audio in the background so future plays (and other devices) use the API URL.
    if (localPath != null && mediaUrl == null) {
      unawaited(_ensurePlayingMediaUploaded(localPath));
    }

    await _audio.setSpeed(playbackSpeed);
    await _audio.seek(Duration(milliseconds: (startAt * 1000).round()));
    _audioPositionSub = _audio.positionStream.listen((pos) {
      final track = nowPlayingTrack;
      if (track == null || adBreakActive) return;
      final posSec = pos.inMilliseconds / 1000.0;
      if (_audio.usingSampleAsset) {
        // Loop short bundled sample across long chapter durations.
        const sampleSec = 8.0;
        final logical = startAt + posSec;
        playbackPositionSec = logical.clamp(0, track.durationSec.toDouble());
        if (playbackPositionSec >= track.durationSec) {
          _advanceTrack();
          return;
        }
        if (posSec >= sampleSec - 0.05 && playing) {
          _audio.seek(Duration.zero);
        }
      } else {
        final total = (_audio.duration?.inMilliseconds ?? (track.durationSec * 1000)) / 1000.0;
        playbackPositionSec = posSec.clamp(0, total);
        if (playbackPositionSec >= total - 0.25) {
          _advanceTrack();
          return;
        }
      }
      _syncAudioProgress(persist: false);
      _maybeTriggerMidroll();
      _maybeCreditListeningMinute();
      notifyListeners();
    });
    if (autoplay) {
      await _audio.play();
    }
  }

  Future<void> _ensurePlayingMediaUploaded(String localPath) async {
    final bearer = _devBearer();
    final title = nowPlaying;
    final track = nowPlayingTrack;
    if (bearer == null || title == null) return;
    final mediaId = await _api.uploadMedia(
      bearer,
      filePath: localPath,
      filename: track?.mediaName,
    );
    if (mediaId == null) return;

    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      if (draft.publishedTitleId != title.id) continue;
      final episodes = draft.episodes.map((episode) {
        if (track != null && episode.id == track.id) {
          return episode.copyWith(mediaId: mediaId, mediaPath: localPath);
        }
        return episode;
      }).toList();
      // If ids drifted, attach to first episode / draft root.
      final nextEpisodes = episodes.any((e) => e.mediaId == mediaId)
          ? episodes
          : [
              for (var j = 0; j < episodes.length; j++)
                j == 0
                    ? episodes[j].copyWith(mediaId: mediaId, mediaPath: localPath)
                    : episodes[j],
            ];
      drafts[i] = draft.copyWith(
        mediaId: draft.mediaId ?? mediaId,
        mediaPath: draft.mediaPath ?? localPath,
        episodes: nextEpisodes.isEmpty
            ? [
                ContentEpisode(
                  id: track?.id ?? 'ep-1',
                  title: track?.title ?? 'Episode 1',
                  durationSec: track?.durationSec ?? 0,
                  sortOrder: 0,
                  mediaName: track?.mediaName,
                  mediaPath: localPath,
                  mediaId: mediaId,
                ),
              ]
            : nextEpisodes,
      );
      // Persist mediaId onto the live Studio draft so catalogue tracks get mediaUrl.
      await _api.updateStudioDraft(
        bearer,
        id: drafts[i].id,
        title: drafts[i].title,
        format: drafts[i].format,
        prices: drafts[i].prices,
        genre: drafts[i].genre,
        monetisationMode: drafts[i].monetisationMode,
        subscriptionEligible: drafts[i].subscriptionEligible,
        mediaName: drafts[i].mediaName,
        mediaKind: drafts[i].mediaKind,
        mediaBytes: drafts[i].mediaBytes,
        mediaId: drafts[i].mediaId,
        coverImageName: drafts[i].coverImageName,
        coverImageBytes: drafts[i].coverImageBytes,
        chapters: drafts[i].chapters,
        episodes: drafts[i].episodes,
      );
      if (drafts[i].publishedTitleId != null) {
        await refreshTitleParts(drafts[i].publishedTitleId!);
      }
      await _persist();
      break;
    }
  }

  void _stopTicker() {
    _playbackTicker?.cancel();
    _playbackTicker = null;
  }

  void _restartTicker() {
    _stopTicker();
    if (!playing || nowPlayingTrack == null || usingRealAudio) return;
    _playbackTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final track = nowPlayingTrack;
      if (!playing || track == null || adBreakActive) return;
      playbackPositionSec =
          (playbackPositionSec + 0.25 * playbackSpeed).clamp(0, track.durationSec.toDouble());
      if (playbackPositionSec >= track.durationSec) {
        _advanceTrack();
      } else {
        _syncAudioProgress(persist: false);
        _maybeTriggerMidroll();
        _maybeCreditListeningMinute();
        notifyListeners();
      }
    });
  }

  void _advanceTrack() {
    final title = nowPlaying;
    final track = nowPlayingTrack;
    if (title == null || track == null) return;
    final tracks = tracksFor(title.id);
    final index = tracks.indexWhere((item) => item.id == track.id);
    if (index >= 0 && index < tracks.length - 1) {
      selectTrack(tracks[index + 1], autoplay: true);
      return;
    }
    playing = false;
    playbackPositionSec = track.durationSec.toDouble();
    _syncAudioProgress(persist: true);
    _stopTicker();
    _audio.pause();
    notifyListeners();
  }

  void _syncAudioProgress({required bool persist}) {
    final title = nowPlaying;
    final track = nowPlayingTrack;
    if (title == null || track == null) return;
    progress[title.id] = TitleProgress(
      titleId: title.id,
      locationId: track.id,
      position: playbackPositionSec,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      bookmarks: progress[title.id]?.bookmarks ?? const [],
    );
    if (persist) _persist();
  }

  void showNotice(String text) {
    notice = text;
    notifyListeners();
  }

  void clearNotice() {
    notice = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _playbackTicker?.cancel();
    _adBreakTicker?.cancel();
    _sleepTimer?.cancel();
    _syncRetryTimer?.cancel();
    _audioPositionSub?.cancel();
    _authSub?.cancel();
    _audio.dispose();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/distribution.dart';

/// Whether this build updates itself from GitHub Releases: Android builds
/// installed from the APK (the Play build updates through the store).
bool get selfUpdates =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    !isPlayDistribution;

enum UpdateStatus { idle, checking, available, downloading, installing, error }

/// The newest GitHub release that has an installable APK.
@immutable
class ReleaseInfo {
  final String version;
  final String downloadUrl;

  const ReleaseInfo({required this.version, required this.downloadUrl});
}

@immutable
class UpdateState {
  final UpdateStatus status;
  final ReleaseInfo? release;

  /// 0–1 while downloading.
  final double progress;
  final String? error;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.progress = 0,
    this.error,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    ReleaseInfo? release,
    double? progress,
    String? error,
  }) => UpdateState(
    status: status ?? this.status,
    release: release ?? this.release,
    progress: progress ?? this.progress,
    error: error,
  );
}

/// Parses GitHub's `releases/latest` JSON; null without a version tag or APK.
@visibleForTesting
ReleaseInfo? parseRelease(Map<String, dynamic> data) {
  final tag = data['tag_name'];
  if (tag is! String) return null;
  final m = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch(tag);
  if (m == null) return null;
  for (final asset in data['assets'] as List<dynamic>? ?? const []) {
    if (asset is! Map) continue;
    final name = asset['name'];
    final url = asset['browser_download_url'];
    if (name is String && name.endsWith('.apk') && url is String) {
      return ReleaseInfo(version: m.group(1)!, downloadUrl: url);
    }
  }
  return null;
}

/// Whether [remote] (YYYY.MMDD.N) is newer than [current].
@visibleForTesting
bool isNewerVersion(String remote, String current) {
  List<int> parts(String v) {
    final p = v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (p.length < 3) {
      p.add(0);
    }
    return p;
  }

  final r = parts(remote);
  final c = parts(current);
  for (var i = 0; i < 3; i++) {
    if (r[i] != c[i]) return r[i] > c[i];
  }
  return false;
}

/// Checks GitHub Releases for a newer APK and downloads and installs it.
class UpdateNotifier extends Notifier<UpdateState> {
  static const _latestUrl =
      'https://api.github.com/repos/dz0ny/prometnik/releases/latest';

  StreamSubscription<OtaEvent>? _download;

  @override
  UpdateState build() {
    ref.onDispose(() => _download?.cancel());
    return const UpdateState();
  }

  /// Looks for a newer release; quiet on failure (it runs on every start).
  void check() {
    if (!selfUpdates) return;
    if (state.status != UpdateStatus.idle &&
        state.status != UpdateStatus.error) {
      return;
    }
    unawaited(
      _check().catchError((Object e, StackTrace s) {
        debugPrint('UpdateNotifier.check: $e');
        if (ref.mounted) state = const UpdateState();
      }),
    );
  }

  Future<void> _check() async {
    state = const UpdateState(status: UpdateStatus.checking);
    final info = await PackageInfo.fromPlatform();
    final res = await http
        .get(
          Uri.parse(_latestUrl),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (!ref.mounted) return;
    final release = res.statusCode == 200
        ? parseRelease(json.decode(res.body) as Map<String, dynamic>)
        : null;
    state = release != null && isNewerVersion(release.version, info.version)
        ? UpdateState(status: UpdateStatus.available, release: release)
        : const UpdateState();
  }

  /// Downloads the APK and hands it to the system installer.
  void install() {
    final release = state.release;
    if (!selfUpdates || release == null) return;
    if (state.status == UpdateStatus.downloading) return;
    state = UpdateState(status: UpdateStatus.downloading, release: release);
    unawaited(_download?.cancel());
    try {
      _download = OtaUpdate()
          .execute(
            release.downloadUrl,
            destinationFilename: 'prometnik-${release.version}.apk',
          )
          .listen(_onEvent, onError: (Object e) => _fail('$e'));
    } on Exception catch (e) {
      _fail('$e');
    }
  }

  void _onEvent(OtaEvent event) {
    if (!ref.mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        state = state.copyWith(
          progress: (double.tryParse(event.value ?? '') ?? 0) / 100,
        );
      case OtaStatus.INSTALLING:
        state = state.copyWith(status: UpdateStatus.installing, progress: 1);
      case OtaStatus.INSTALLATION_DONE:
        state = const UpdateState();
      case OtaStatus.CANCELED:
        state = state.copyWith(status: UpdateStatus.available, progress: 0);
      case OtaStatus.ALREADY_RUNNING_ERROR:
        _fail('Prenos že poteka.');
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail('Dovoljenje za namestitev je zavrnjeno.');
      case OtaStatus.CHECKSUM_ERROR:
        _fail('Preverjanje datoteke ni uspelo.');
      case OtaStatus.DOWNLOAD_ERROR:
        _fail('Prenos ni uspel.');
      case OtaStatus.INSTALLATION_ERROR:
        _fail('Namestitev ni uspela.');
      case OtaStatus.INTERNAL_ERROR:
        _fail('Posodobitev ni uspela.');
    }
  }

  void _fail(String message) {
    debugPrint('UpdateNotifier: $message');
    if (!ref.mounted) return;
    state = state.copyWith(status: UpdateStatus.error, error: message);
  }

  /// Hides the banner until the next start.
  void dismiss() => state = const UpdateState();
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);

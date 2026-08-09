import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'logger.dart';

const _tag = 'update';

// Update this if the repo ever moves.
const _releasesApiUrl = 'https://api.github.com/repos/klion-gh/stillhere/releases/latest';

class ReleaseInfo {
  final String version;
  final String htmlUrl;
  final String? windowsAssetUrl;
  final String? androidAssetUrl;

  const ReleaseInfo({
    required this.version,
    required this.htmlUrl,
    this.windowsAssetUrl,
    this.androidAssetUrl,
  });
}

class UpdateInfo {
  final String currentVersion;
  final ReleaseInfo latest;

  const UpdateInfo({required this.currentVersion, required this.latest});

  /// The right download link for the platform this build is running on,
  /// falling back to the release page if we don't have a direct asset.
  String get downloadUrl {
    if (Platform.isWindows && latest.windowsAssetUrl != null) return latest.windowsAssetUrl!;
    if (Platform.isAndroid && latest.androidAssetUrl != null) return latest.androidAssetUrl!;
    return latest.htmlUrl;
  }
}

/// Compares two dotted version strings (e.g. "0.2.0" vs "0.1.3", "v" prefix
/// already stripped). Returns true if [latest] is strictly newer.
bool isNewerVersion(String latest, String current) {
  final l = latest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final c = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final len = l.length > c.length ? l.length : c.length;
  for (var i = 0; i < len; i++) {
    final lv = i < l.length ? l[i] : 0;
    final cv = i < c.length ? c[i] : 0;
    if (lv != cv) return lv > cv;
  }
  return false;
}

Future<UpdateInfo?> checkForUpdate() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersion = packageInfo.version;

  final dio = Dio();
  final res = await dio.get<Map<String, dynamic>>(
    _releasesApiUrl,
    options: Options(headers: {'Accept': 'application/vnd.github+json'}),
  );
  final data = res.data!;
  final tag = (data['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
  final assets = (data['assets'] as List).cast<Map<String, dynamic>>();

  String? findAsset(String suffix) {
    for (final a in assets) {
      final name = (a['name'] as String).toLowerCase();
      if (name.endsWith(suffix)) return a['browser_download_url'] as String;
    }
    return null;
  }

  final latest = ReleaseInfo(
    version: tag,
    htmlUrl: data['html_url'] as String,
    windowsAssetUrl: findAsset('.exe'),
    androidAssetUrl: findAsset('.apk'),
  );

  AppLogger.info(_tag, 'current=$currentVersion latest=$tag');
  if (!isNewerVersion(tag, currentVersion)) return null;
  return UpdateInfo(currentVersion: currentVersion, latest: latest);
}

/// Checked once when first watched (typically right after login). A failed
/// check (offline, rate-limited, repo moved) just means no update badge —
/// never blocks or errors the UI.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    return await checkForUpdate();
  } catch (e, st) {
    AppLogger.error(_tag, 'update check failed', e, st);
    return null;
  }
});

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final String version;
  final String currentVersion;
  final String rawTag;
  final String releaseName;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSizeBytes;
  final DateTime publishedAt;

  AppUpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.rawTag,
    required this.releaseName,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
    required this.publishedAt,
  });
}

class UpdateService {
  static const String currentVersion = '1.0.13';
  static const String repoOwner = 'hebimind-boop';
  static const String repoName = 'private-agent-pro';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Resolves the installed version dynamically from Android PackageInfo, falling back to currentVersion
  static Future<String> getInstalledVersion() async {
    try {
      const channel = MethodChannel('com.privateagent/accessibility');
      final ver = await channel.invokeMethod<String>('getAppVersion');
      if (ver != null && ver.isNotEmpty) return ver;
    } catch (_) {}
    return currentVersion;
  }

  /// Clean version string (e.g., 'v1.0.9-pro' -> '1.0.9')
  static String _cleanVersion(String v) {
    String clean = v.trim();
    if (clean.toLowerCase().startsWith('v')) {
      clean = clean.substring(1);
    }
    final dashIndex = clean.indexOf('-');
    if (dashIndex != -1) {
      clean = clean.substring(0, dashIndex);
    }
    return clean;
  }

  /// Returns true if remote is strictly newer than local
  static bool _isVersionNewer(String remoteTag, String localVersion) {
    try {
      final remoteClean = _cleanVersion(remoteTag);
      final localClean = _cleanVersion(localVersion);

      final rParts = remoteClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = localClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (rParts.length < 3) {
        rParts.add(0);
      }
      while (lParts.length < 3) {
        lParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (rParts[i] > lParts[i]) return true;
        if (rParts[i] < lParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fetch latest release from GitHub API
  static Future<AppUpdateInfo?> fetchLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse(latestReleaseUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'BoopAgent-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final releaseNotes = data['body'] as String? ?? 'No release notes provided.';
      final publishedAtStr = data['published_at'] as String? ?? '';
      final publishedAt = DateTime.tryParse(publishedAtStr) ?? DateTime.now();

      // Find exact release APK asset:
      // Prioritize BoopAgent-*pro*.apk, PrivateAgent-*pro*.apk, or matching release APKs
      // and explicitly ignore split architecture APKs (arm64-v8a, armeabi-v7a, x86_64).
      String downloadUrl = '';
      int apkSize = 0;
      final assets = data['assets'] as List<dynamic>? ?? [];

      // Pass 1: exact BoopAgent-*pro*.apk or PrivateAgent-*pro*.apk match
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') &&
            (name.contains('boopagent') || name.contains('privateagent')) &&
            name.contains('pro')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          apkSize = asset['size'] as int? ?? 0;
          debugPrint('Selected Pass 1 Pro APK: ${asset['name']} ($apkSize bytes)');
          break;
        }
      }

      // Pass 2: any asset named BoopAgent-*.apk or PrivateAgent-*.apk
      if (downloadUrl.isEmpty) {
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk') &&
              (name.startsWith('boopagent') || name.startsWith('privateagent'))) {
            downloadUrl = asset['browser_download_url'] as String? ?? '';
            apkSize = asset['size'] as int? ?? 0;
            debugPrint('Selected Pass 2 BoopAgent APK: ${asset['name']} ($apkSize bytes)');
            break;
          }
        }
      }

      // Pass 3: any non-split release APK (avoiding v8a, v7a, x86_64 partial architecture builds)
      if (downloadUrl.isEmpty) {
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk') &&
              !name.contains('v8a') &&
              !name.contains('v7a') &&
              !name.contains('x86')) {
            downloadUrl = asset['browser_download_url'] as String? ?? '';
            apkSize = asset['size'] as int? ?? 0;
            debugPrint('Selected Pass 3 Full APK: ${asset['name']} ($apkSize bytes)');
            break;
          }
        }
      }

      // Fallback direct URL if asset not found in metadata
      if (downloadUrl.isEmpty && tagName.isNotEmpty) {
        downloadUrl =
            'https://github.com/$repoOwner/$repoName/releases/download/$tagName/BoopAgent-$tagName-pro.apk';
      }

      if (downloadUrl.isEmpty) {
        return null;
      }

      final remoteVersion = _cleanVersion(tagName);
      final localVersion = await getInstalledVersion();
      if (_isVersionNewer(tagName, localVersion)) {
        return AppUpdateInfo(
          version: remoteVersion,
          currentVersion: localVersion,
          rawTag: tagName,
          releaseName: releaseName,
          releaseNotes: releaseNotes,
          apkDownloadUrl: downloadUrl,
          apkSizeBytes: apkSize,
          publishedAt: publishedAt,
        );
      }
      return null;
    } catch (e) {
      debugPrint('UpdateService check error: $e');
      return null;
    }
  }

  /// Silently check for updates on startup (non-blocking)
  static Future<void> checkSilently(BuildContext context) async {
    try {
      final updateInfo = await fetchLatestRelease();
      if (updateInfo != null && context.mounted) {
        showUpdateDialog(context, updateInfo);
      }
    } catch (_) {}
  }

  /// Manual check from Settings screen
  static Future<void> checkManually(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Checking for updates...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF333333), width: 1),
        ),
      ),
    );

    try {
      final localVersion = await getInstalledVersion();
      final updateInfo = await fetchLatestRelease();
      if (!context.mounted) return;

      if (updateInfo != null) {
        showUpdateDialog(context, updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You are using the latest version (v$localVersion).',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF333333), width: 1),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to check for updates: $e',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFF7F1D1D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFB91C1C), width: 1),
            ),
          ),
        );
      }
    }
  }

  /// Show sleek OLED monochrome update dialog
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _UpdateDialog(info: info),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141414) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? const Color(0xFF262626) : Colors.grey[300]!,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header icon + tag
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update Available',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'v${info.currentVersion} → v${info.version}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Release title
            Text(
              info.releaseName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Release Notes snippet box
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18181A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Later',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final uri = Uri.parse(info.apkDownloadUrl);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black87,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Update Now',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

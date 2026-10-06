import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class AppUpdateInfo {
  final String version;
  final String rawTag;
  final String releaseName;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSizeBytes;
  final DateTime publishedAt;

  AppUpdateInfo({
    required this.version,
    required this.rawTag,
    required this.releaseName,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
    required this.publishedAt,
  });
}

class UpdateService {
  static const String currentVersion = '1.0.2';
  static const String repoOwner = 'hebimind-boop';
  static const String repoName = 'private-agent-pro';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Clean version string (e.g., 'v1.0.3-pro' -> '1.0.3')
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
          'User-Agent': 'PrivateAgent-App',
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

      // Find APK asset
      String downloadUrl = '';
      int apkSize = 0;
      final assets = data['assets'] as List<dynamic>? ?? [];

      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String? ?? '';
          apkSize = asset['size'] as int? ?? 0;
          break;
        }
      }

      // Fallback direct URL if asset not in list
      if (downloadUrl.isEmpty && tagName.isNotEmpty) {
        downloadUrl =
            'https://github.com/$repoOwner/$repoName/releases/download/$tagName/PrivateAgent-$tagName.apk';
      }

      if (downloadUrl.isEmpty) {
        return null;
      }

      final remoteVersion = _cleanVersion(tagName);
      if (_isVersionNewer(tagName, currentVersion)) {
        return AppUpdateInfo(
          version: remoteVersion,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Checking for updates...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      ),
    );

    try {
      final updateInfo = await fetchLatestRelease();
      if (!context.mounted) return;

      if (updateInfo != null) {
        showUpdateDialog(context, updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are using the latest version (v$currentVersion).'),
            backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.black87,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check for updates: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Show sleek OLED monochrome update dialog
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _UpdateDialog(info: info),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Connecting...';
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.info.apkDownloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? widget.info.apkSizeBytes;
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/PrivateAgent-${widget.info.version}.apk');
      final sink = file.openWrite();

      int receivedBytes = 0;
      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0 && mounted) {
          setState(() {
            _downloadProgress = receivedBytes / contentLength;
            final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
            _downloadStatus = '$mbReceived MB / $mbTotal MB (${(_downloadProgress * 100).toInt()}%)';
          });
        }
      }).asFuture();

      await sink.close();
      client.close();

      if (mounted) {
        setState(() {
          _downloadStatus = 'Launching package installer...';
        });
      }

      // Launch APK installer
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint('OpenFilex install result: ${result.message}');

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = 'Download failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[300]!,
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
                        'v${UpdateService.currentVersion} → v${widget.info.version}',
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
              widget.info.releaseName,
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
                  widget.info.releaseNotes,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Download Progress indicator (if active)
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white : Colors.black87,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _downloadStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading)
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
                  onPressed: _isDownloading ? null : _startDownloadAndInstall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black87,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    elevation: 0,
                  ),
                  child: Text(
                    _isDownloading ? 'Downloading...' : 'Update Now',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'shizuku_service.dart';

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
  static const String currentVersion = '1.0.3';
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
      final updateInfo = await fetchLatestRelease();
      if (!context.mounted) return;

      if (updateInfo != null) {
        showUpdateDialog(context, updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You are using the latest version (v$currentVersion).',
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

  /// Resolves the optimal destination for the APK:
  /// Primary: Public Downloads Directory (/storage/emulated/0/Download/PrivateAgent-$version.apk)
  /// Fallbacks: getExternalStorageDirectory(), external cache, or temporary directory.
  static Future<File> getApkDestinationFile(String version) async {
    final fileName = 'PrivateAgent-$version.apk';

    // 1. Primary: Public Downloads directory
    try {
      final publicDownloadDir = Directory('/storage/emulated/0/Download');
      if (await publicDownloadDir.exists()) {
        final targetFile = File('${publicDownloadDir.path}/$fileName');
        final testFile = File('${publicDownloadDir.path}/.test_perm');
        await testFile.writeAsString('ok');
        await testFile.delete();
        debugPrint('Using public Downloads directory for update: ${targetFile.path}');
        return targetFile;
      }
    } catch (e) {
      debugPrint('Direct write to /storage/emulated/0/Download not permitted: $e');
    }

    // 2. Fallback: External Storage Directory (app-specific external folder)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final downloadSubdir = Directory('${extDir.path}/Download');
        if (!await downloadSubdir.exists()) {
          await downloadSubdir.create(recursive: true);
        }
        final targetFile = File('${downloadSubdir.path}/$fileName');
        debugPrint('Using external storage fallback for update: ${targetFile.path}');
        return targetFile;
      }
    } catch (e) {
      debugPrint('External storage fallback error: $e');
    }

    // 3. Fallback: External Cache
    try {
      final extCacheDirs = await getExternalCacheDirectories();
      if (extCacheDirs != null && extCacheDirs.isNotEmpty) {
        final targetFile = File('${extCacheDirs.first.path}/$fileName');
        debugPrint('Using external cache fallback for update: ${targetFile.path}');
        return targetFile;
      }
    } catch (_) {}

    // 4. Final Fallback: Temporary directory
    final tempDir = await getTemporaryDirectory();
    final targetFile = File('${tempDir.path}/$fileName');
    debugPrint('Using temporary directory fallback for update: ${targetFile.path}');
    return targetFile;
  }

  /// Telegram-Style Multi-Mode Installation Pipeline
  /// Mode 1: Privileged Shizuku Install (100% Silent with auto-restart)
  /// Mode 2: Standard PackageInstaller Fallback with FileProvider
  static Future<bool> installApkFile(
    File file,
    String version, {
    Function(String)? onStatusUpdate,
  }) async {
    // Mode 1: Privileged Shizuku Install (100% Silent)
    try {
      final shizuku = ShizukuService();
      final isShizukuAvailable = await shizuku.checkAvailability();
      if (isShizukuAvailable) {
        onStatusUpdate?.call('Installing silently via Shizuku...');
        debugPrint('Shizuku is running. Attempting silent privileged install: ${file.path}');
        final output = await shizuku.runCommand('pm install -r -d "${file.path}"');
        debugPrint('Shizuku pm install output: $output');

        if (output.toLowerCase().contains('success')) {
          onStatusUpdate?.call('Installed! Restarting PrivateAgent...');
          await Future.delayed(const Duration(milliseconds: 600));
          // Gracefully restart application
          await shizuku.runCommand('am start -n com.orailnoor.privateagent/.MainActivity');
          return true;
        } else {
          debugPrint('Shizuku pm install non-success output: $output');
        }
      }
    } catch (e) {
      debugPrint('Shizuku privileged install error: $e');
    }

    // Mode 2: Standard PackageInstaller Fallback with FileProvider
    onStatusUpdate?.call('Launching package installer...');
    try {
      debugPrint('Triggering native FileProvider installer MethodChannel...');
      const channel = MethodChannel('com.privateagent/accessibility');
      final result = await channel.invokeMethod<bool>('installApk', {
        'filePath': file.path,
      });
      if (result == true) {
        return true;
      }
    } catch (e) {
      debugPrint('Native installApk MethodChannel failed: $e, trying AndroidIntent');
    }

    // Fallback: AndroidIntent with FileProvider content URI
    try {
      final relativePath = file.path.startsWith('/storage/emulated/0/')
          ? file.path.replaceFirst('/storage/emulated/0/', '')
          : file.path.split('/').last;
      final contentUri = 'content://com.orailnoor.privateagent.fileprovider/external_files/$relativePath';

      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: contentUri,
        type: 'application/vnd.android.package-archive',
        flags: <int>[
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_GRANT_READ_URI_PERMISSION,
        ],
      );
      await intent.launch();
      return true;
    } catch (e) {
      debugPrint('AndroidIntent launch failed: $e, falling back to OpenFilex');
    }

    // Fallback: OpenFilex
    final openResult = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    return openResult.type == ResultType.done;
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
      final file = await UpdateService.getApkDestinationFile(widget.info.version);
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
          _downloadStatus = 'Installing update...';
        });
      }

      await UpdateService.installApkFile(
        file,
        widget.info.version,
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              _downloadStatus = status;
            });
          }
        },
      );

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

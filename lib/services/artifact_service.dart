import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:path_provider/path_provider.dart';

class ArtifactItem {
  final String id;
  final String fileName;
  final String filePath;
  final String fileType; // 'image', 'pdf', 'text', 'code'
  final DateTime timestamp;
  final String source; // 'user_upload' or 'ai_generated'
  final int fileSize;

  ArtifactItem({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.timestamp,
    required this.source,
    this.fileSize = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'filePath': filePath,
    'fileType': fileType,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'fileSize': fileSize,
  };

  factory ArtifactItem.fromJson(Map<String, dynamic> json) => ArtifactItem(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    filePath: json['filePath'] as String,
    fileType: json['fileType'] as String? ?? 'text',
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    source: json['source'] as String? ?? 'user_upload',
    fileSize: json['fileSize'] as int? ?? 0,
  );
}

class ArtifactService {
  static const String _artifactsDirName = 'artifacts';
  static const String _manifestFileName = 'artifacts_manifest.json';

  static Future<Directory> _getArtifactsDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final artifactsDir = Directory('${appDocDir.path}/$_artifactsDirName');
    if (!await artifactsDir.exists()) {
      await artifactsDir.create(recursive: true);
    }
    return artifactsDir;
  }

  static Future<File> _getManifestFile() async {
    final dir = await _getArtifactsDirectory();
    return File('${dir.path}/$_manifestFileName');
  }

  static Future<List<ArtifactItem>> listArtifacts({String? filterType}) async {
    try {
      final manifestFile = await _getManifestFile();
      if (!await manifestFile.exists()) {
        return [];
      }
      final content = await manifestFile.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
      var items = decoded
          .map(
            (item) =>
                ArtifactItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();

      if (filterType != null &&
          filterType.isNotEmpty &&
          filterType.toLowerCase() != 'all') {
        items = items
            .where((i) => i.fileType.toLowerCase() == filterType.toLowerCase())
            .toList();
      }

      // Sort newest first
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (e) {
      developer.log(
        'Error reading artifacts manifest: $e',
        name: 'ArtifactService',
      );
      return [];
    }
  }

  static Future<ArtifactItem> saveArtifact({
    required String fileName,
    required Uint8List bytes,
    required String source,
    String? customType,
  }) async {
    final dir = await _getArtifactsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final safeFileName =
        '${id}_${fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final targetFile = File('${dir.path}/$safeFileName');
    await targetFile.writeAsBytes(bytes);

    final detectedType = customType ?? detectFileType(fileName);
    final newItem = ArtifactItem(
      id: id,
      fileName: fileName,
      filePath: targetFile.path,
      fileType: detectedType,
      timestamp: DateTime.now(),
      source: source,
      fileSize: bytes.length,
    );

    await _appendToManifest(newItem);
    return newItem;
  }

  static Future<ArtifactItem> saveTextArtifact({
    required String fileName,
    required String textContent,
    String source = 'ai_generated',
    String? customType,
  }) async {
    final bytes = utf8.encode(textContent);
    return saveArtifact(
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      source: source,
      customType: customType ?? detectFileType(fileName),
    );
  }

  static Future<bool> deleteArtifact(String id) async {
    try {
      final manifestFile = await _getManifestFile();
      if (!await manifestFile.exists()) return false;

      final items = await listArtifacts();
      final itemToDelete = items.firstWhere(
        (i) => i.id == id,
        orElse: () => ArtifactItem(
          id: '',
          fileName: '',
          filePath: '',
          fileType: '',
          timestamp: DateTime.now(),
          source: '',
        ),
      );

      if (itemToDelete.id.isEmpty) return false;

      // Delete physical file
      final file = File(itemToDelete.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Update manifest
      final updated = items.where((i) => i.id != id).toList();
      await manifestFile.writeAsString(
        jsonEncode(updated.map((i) => i.toJson()).toList()),
      );
      return true;
    } catch (e) {
      developer.log('Error deleting artifact $id: $e', name: 'ArtifactService');
      return false;
    }
  }

  static Future<String?> readArtifactContent(ArtifactItem item) async {
    try {
      final file = File(item.filePath);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  static String detectFileType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'bmp':
        return 'image';
      case 'pdf':
        return 'pdf';
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'html':
      case 'css':
      case 'json':
      case 'yaml':
      case 'yml':
      case 'sh':
      case 'kt':
      case 'java':
      case 'cpp':
      case 'c':
      case 'sql':
        return 'code';
      default:
        return 'text';
    }
  }

  static Future<void> _appendToManifest(ArtifactItem item) async {
    final manifestFile = await _getManifestFile();
    final items = await listArtifacts();
    items.insert(0, item);
    await manifestFile.writeAsString(
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:neko/object_box/object_box.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/util/path_util.dart';
import 'package:neko/util/file_util.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String _status = '';
  bool _importing = false;

  Future<void> _importFolder() async {
    final path = await getDirectoryPath();
    if (path == null) return;
    setState(() {
      _importing = true;
      _status = '正在分析...';
    });
    await _processImport(path);
  }

  Future<void> _importZip() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(extensions: ['zip']),
    ]);
    if (file == null) return;
    setState(() {
      _importing = true;
      _status = '正在解压...';
    });

    try {
      final bytes = await File(file.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final tempDir = Directory.systemTemp.createTempSync('neko_import_');
      try {
        for (final entry in archive) {
          if (entry.isFile) {
            final f = File(p.join(tempDir.path, entry.name));
            await f.create(recursive: true);
            await f.writeAsBytes(entry.content as List<int>);
          }
        }
        setState(() => _status = '正在分析...');
        await _processImport(tempDir.path);
      } finally {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      setState(() {
        _status = '解压失败: $e';
        _importing = false;
      });
    }
  }

  Future<void> _processImport(String sourcePath) async {
    final storageRoot = await getStoragePath();
    final comicId = const Uuid().v4();
    final comicDir = p.join(storageRoot, comicId);

    try {
      final result = await _analyzeSource(sourcePath);
      if (result == null) {
        setState(() {
          _status = '未找到可识别的漫画文件';
          _importing = false;
        });
        return;
      }

      setState(() => _status = '正在导入...');
      await _copyDir(Directory(sourcePath), Directory(comicDir));

      final coverPath = await _findCover(result, comicDir);

      final comic = Comic(
        comicId: comicId,
        title: result.title,
        author: result.author,
        description: result.description,
        coverPath: coverPath,
        pageCount: result.totalPages,
        storagePath: comicDir,
        importedAt: DateTime.now(),
        displayOrder: objectbox.comicBox.count() + 1,
      );
      comic.chapters = result.chapters;

      objectbox.comicBox.put(comic);

      if (!mounted) return;
      setState(() {
        _status = '导入成功: ${result.title}';
        _importing = false;
      });

      final nav = Navigator.of(context);
      Future.delayed(const Duration(milliseconds: 800), () {
        nav.pop(true);
      });
    } catch (e) {
      // Clean up partial copy on failure
      try {
        final dir = Directory(comicDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _status = '导入失败: $e';
        _importing = false;
      });
    }
  }

  Future<_ImportResult?> _analyzeSource(String sourcePath) async {
    final originalInfo = File(p.join(sourcePath, 'original_comic_info.json'));
    final processedInfo = File(p.join(sourcePath, 'processed_comic_info.json'));

    Map<String, dynamic>? metadata;
    if (await originalInfo.exists()) {
      try {
        metadata = jsonDecode(await originalInfo.readAsString());
      } catch (_) {}
    }
    if (metadata == null && await processedInfo.exists()) {
      try {
        metadata = jsonDecode(await processedInfo.readAsString());
      } catch (_) {}
    }

    if (metadata != null) {
      return _parseBreezeFormat(sourcePath, metadata);
    }

    return _parseGenericFormat(sourcePath);
  }

  _ImportResult _parseBreezeFormat(
    String sourcePath,
    Map<String, dynamic> metadata,
  ) {
    final title =
        metadata['title']?.toString() ??
        metadata['name']?.toString() ??
        p.basename(sourcePath);
    final author = metadata['author']?.toString() ?? '';
    final description = metadata['description']?.toString() ?? '';

    final extern =
        metadata['extern'] as Map<String, dynamic>? ??
        metadata['extension'] as Map<String, dynamic>? ??
        {};

    // Try downloadChapters first (processed_comic_info format)
    final downloadChapters = extern['downloadChapters'] as List?;

    if (downloadChapters != null && downloadChapters.isNotEmpty) {
      final result = _ImportResult(
        title: title,
        author: author,
        description: description,
        chapters: [],
        totalPages: 0,
      );
      for (final ch in downloadChapters) {
        if (ch is! Map) continue;
        final chapterName = ch['name']?.toString() ?? '';
        final order = int.tryParse(ch['order']?.toString() ?? '') ?? result.chapters.length + 1;

        // Find matching directory in source
        final subDirs = Directory(sourcePath)
            .listSync()
            .whereType<Directory>()
            .where((d) => p.basename(d.path) == chapterName)
            .toList();

        final imageFiles = <String>[];
        if (subDirs.isNotEmpty) {
          imageFiles.addAll(
            subDirs.first
                .listSync()
                .whereType<File>()
                .where((f) => isImageFile(f.path))
                .map((f) => p.basename(f.path))
                .toList()
              ..sort(),
          );
        }

        result.chapters.add(ComicChapter(
          name: chapterName,
          order: order,
          folderName: chapterName,
          pageCount: imageFiles.length,
          imageFiles: imageFiles,
        ));
        result.totalPages += imageFiles.length;
      }
      // Only use the parsed result if at least one chapter has images;
      // otherwise fall back to scanning directories.
      if (result.totalPages > 0) return result;
    }

    // Try eps from metadata
    final eps = metadata['eps'] as List?;
    if (eps != null && eps.isNotEmpty) {
      // Scan actual directories for images — eps metadata may not match folder names exactly
      return _scanChapterDirs(sourcePath, fallbackTitle: title, fallbackAuthor: author, fallbackDescription: description);
    }

    // Fallback: scan actual directory structure
    return _scanChapterDirs(sourcePath, fallbackTitle: title, fallbackAuthor: author, fallbackDescription: description);
  }

  _ImportResult _parseGenericFormat(String sourcePath) {
    return _scanChapterDirs(sourcePath);
  }

  _ImportResult _scanChapterDirs(
    String sourcePath, {
    String? fallbackTitle,
    String? fallbackAuthor,
    String? fallbackDescription,
  }) {
    final chapters = <ComicChapter>[];
    int totalPages = 0;
    final dir = Directory(sourcePath);

    final skipNames = {
      'original_comic_info.json',
      'processed_comic_info.json',
      'cover.jpg',
      'cover.png',
    };

    final subDirs = dir
        .listSync()
        .whereType<Directory>()
        .where((d) => !skipNames.contains(p.basename(d.path)))
        .toList();

    if (subDirs.isEmpty) {
      // Single chapter — all images in root
      final images = dir
          .listSync()
          .whereType<File>()
          .where((f) => isImageFile(f.path) && !skipNames.contains(p.basename(f.path)))
          .map((f) => p.basename(f.path))
          .toList()
        ..sort();
      totalPages = images.length;
      chapters.add(ComicChapter(
        name: '第1话',
        order: 1,
        folderName: '',
        pageCount: totalPages,
        imageFiles: images,
      ));
    } else {
      int order = 1;
      for (final subDir in subDirs) {
        final images = subDir
            .listSync()
            .whereType<File>()
            .where((f) => isImageFile(f.path))
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();
        if (images.isEmpty) continue;
        totalPages += images.length;
        chapters.add(ComicChapter(
          name: p.basename(subDir.path),
          order: order++,
          folderName: p.basename(subDir.path),
          pageCount: images.length,
          imageFiles: images,
        ));
      }
    }

    return _ImportResult(
      title: fallbackTitle ?? p.basename(sourcePath),
      author: fallbackAuthor ?? '',
      description: fallbackDescription ?? '',
      chapters: chapters,
      totalPages: totalPages,
    );
  }

  Future<String> _findCover(_ImportResult result, String comicDir) async {
    final coverJpg = File(p.join(comicDir, 'cover.jpg'));
    final coverPng = File(p.join(comicDir, 'cover.png'));

    if (await coverJpg.exists()) return coverJpg.path;
    if (await coverPng.exists()) return coverPng.path;

    if (result.chapters.isNotEmpty) {
      final firstChapter = result.chapters.first;
      if (firstChapter.imageFiles.isNotEmpty) {
        final firstImage = firstChapter.imageFiles.first;
        final imagePath = firstChapter.folderName.isNotEmpty
            ? p.join(comicDir, firstChapter.folderName, firstImage)
            : p.join(comicDir, firstImage);
        if (await File(imagePath).exists()) {
          return imagePath;
        }
      }
    }

    return '';
  }

  Future<void> _copyDir(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      if (entity is File) {
        await entity.copy(p.join(target.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDir(
          entity,
          Directory(p.join(target.path, p.basename(entity.path))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入漫画')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_importing)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                    ],
                  ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                if (!_importing) ...[
                  _buildImportCard(
                    icon: Icons.folder_open,
                    title: '导入文件夹',
                    subtitle: '选择包含漫画文件的文件夹\n支持 Breeze 导出格式或图片文件夹',
                    onTap: _importFolder,
                  ),
                  const SizedBox(height: 16),
                  _buildImportCard(
                    icon: Icons.archive,
                    title: '导入 ZIP 压缩包',
                    subtitle: '选择 ZIP 格式的漫画压缩包\n支持 Breeze 导出格式或图片压缩包',
                    onTap: _importZip,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 48),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportResult {
  final String title;
  final String author;
  final String description;
  final List<ComicChapter> chapters;
  int totalPages;

  _ImportResult({
    required this.title,
    required this.author,
    required this.description,
    required this.chapters,
    required this.totalPages,
  });
}

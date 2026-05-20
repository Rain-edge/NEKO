import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/util/file_util.dart';

class ReaderPage extends StatefulWidget {
  final String comicId;
  final int chapterIndex;

  const ReaderPage({
    super.key,
    required this.comicId,
    this.chapterIndex = 0,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late Comic _comic;
  late List<ComicChapter> _chapters;
  late int _chapterIndex;
  int _pageIndex = 0;
  bool _showUI = true;
  bool _loadingPages = false;
  PageController _pageController = PageController();
  List<String> _pagePaths = [];
  final Map<int, TransformationController> _transformControllers = {};

  @override
  void initState() {
    super.initState();
    _comic = _loadComic();
    _chapters = _comic.chapters;
    _chapterIndex = widget.chapterIndex.clamp(0, _chapters.length - 1);
    _loadPagePathsAsync();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Comic _loadComic() {
    final query = objectbox.comicBox
        .query(Comic_.comicId.equals(widget.comicId))
        .build();
    final comic = query.findFirst();
    query.close();
    if (comic == null) throw StateError('漫画不存在');
    return comic;
  }

  ComicChapter get _currentChapter => _chapters[_chapterIndex];

  Future<void> _loadPagePathsAsync() async {
    setState(() => _loadingPages = true);
    final paths = await Future(() {
      final chapter = _currentChapter;
      final chapterDir = chapter.folderName.isNotEmpty
          ? p.join(_comic.storagePath, chapter.folderName)
          : _comic.storagePath;

      if (chapter.imageFiles.isNotEmpty) {
        return chapter.imageFiles
            .map((f) => p.join(chapterDir, f))
            .where((path) => File(path).existsSync())
            .toList();
      }

      try {
        final dir = Directory(chapterDir);
        if (dir.existsSync()) {
          return dir
              .listSync()
              .whereType<File>()
              .where((f) => isImageFile(f.path))
              .map((f) => f.path)
              .toList()
            ..sort();
        }
      } catch (_) {}
      return <String>[];
    });
    if (!mounted) return;
    setState(() {
      _pagePaths = paths;
      _loadingPages = false;
    });
  }

  TransformationController _controllerFor(int index) {
    return _transformControllers.putIfAbsent(
      index,
      () => TransformationController(),
    );
  }

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    _transformControllers.clear();
    _pageController.dispose();
    _pageController = PageController();

    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _pagePaths = [];
    });
    _loadPagePathsAsync();
  }

  void _nextChapter() {
    if (_chapterIndex < _chapters.length - 1) {
      _goToChapter(_chapterIndex + 1);
    }
  }

  void _prevChapter() {
    if (_chapterIndex > 0) {
      _goToChapter(_chapterIndex - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Stack(
        children: [
          // Page viewer
          GestureDetector(
            onTap: _toggleUI,
            child: _loadingPages
                ? const Center(child: CircularProgressIndicator())
                : _pagePaths.isEmpty
                    ? const Center(
                        child: Text('没有图片',
                            style: TextStyle(color: Colors.white54)),
                      )
                    : PageView.builder(
                        key: ValueKey('chapter_$_chapterIndex'),
                        controller: _pageController,
                        itemCount: _pagePaths.length,
                        scrollDirection: Axis.horizontal,
                        onPageChanged: (index) {
                          setState(() => _pageIndex = index);
                        },
                        itemBuilder: (context, index) {
                          return InteractiveViewer(
                            transformationController: _controllerFor(index),
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.file(
                                File(_pagePaths[index]),
                                fit: BoxFit.contain,
                                errorBuilder: (_, e, s) => const Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // UI overlay
          if (_showUI) ...[
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _comic.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _currentChapter.name.isNotEmpty
                                    ? _currentChapter.name
                                    : '第${_chapterIndex + 1}话',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_chapters.length > 1)
                          IconButton(
                            icon: const Icon(Icons.list,
                                color: Colors.white),
                            onPressed: () => _showChapterPicker(context),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_pageIndex + 1} / ${_pagePaths.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Chapter navigation arrows
            if (_chapters.length > 1) ...[
              if (_chapterIndex > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left,
                          color: Colors.white54, size: 48),
                      onPressed: _prevChapter,
                    ),
                  ),
                ),
              if (_chapterIndex < _chapters.length - 1)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right,
                          color: Colors.white54, size: 48),
                      onPressed: _nextChapter,
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  void _showChapterPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('章节列表', style: TextStyle(fontSize: 18)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) {
                    final ch = _chapters[index];
                    return ListTile(
                      title: Text(
                        ch.name.isNotEmpty ? ch.name : '第${index + 1}话',
                      ),
                      subtitle: Text('${ch.pageCount} 页'),
                      leading: index == _chapterIndex
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _goToChapter(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

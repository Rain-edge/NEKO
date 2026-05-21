import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/util/file_util.dart';

class ReaderPage extends StatefulWidget {
  final String comicId;
  final int chapterIndex;
  final int pageIndex;

  const ReaderPage({
    super.key,
    required this.comicId,
    this.chapterIndex = 0,
    this.pageIndex = 0,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _ReaderMode { scroll, page }

class _ReaderPageState extends State<ReaderPage> {
  late Comic _comic;
  late List<ComicChapter> _chapters;
  late int _chapterIndex;
  int _pageIndex = 0;
  bool _showUI = true;
  bool _loadingPages = false;
  List<String> _pagePaths = [];
  _ReaderMode _mode = _ReaderMode.scroll;
  PageController? _pageController;
  final Map<int, TransformationController> _transformControllers = {};
  final ScrollController _scrollController = ScrollController();
  double _screenHeight = 0;
  Timer? _saveTimer;
  int _lastSavedChapter = -1;
  int _lastSavedPage = -1;
  bool _autoAdvancing = false;

  @override
  void initState() {
    super.initState();
    _comic = _loadComic();
    _chapters = _comic.chapters;

    // Guard: empty chapters
    if (_chapters.isEmpty) {
      _chapterIndex = 0;
      _pageIndex = 0;
    } else {
      _chapterIndex = widget.chapterIndex.clamp(0, _chapters.length - 1);
      final maxPage = _chapters[_chapterIndex].pageCount;
      _pageIndex = widget.pageIndex.clamp(0, maxPage > 0 ? maxPage - 1 : 0);
    }

    _loadPagePathsAsync();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenHeight = MediaQuery.of(context).size.height;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController?.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    _saveTimer?.cancel();
    _saveProgressNow();
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

  ComicChapter get _currentChapter {
    if (_chapters.isEmpty || _chapterIndex >= _chapters.length) {
      return const ComicChapter(name: '', order: 0, folderName: '');
    }
    return _chapters[_chapterIndex];
  }

  Future<void> _loadPagePathsAsync() async {
    setState(() => _loadingPages = true);

    // Run file I/O off the UI thread using compute / Isolate
    final paths = await _computePagePaths();

    if (!mounted) return;
    setState(() {
      _pagePaths = paths;
      _loadingPages = false;
    });

    if (_mode == _ReaderMode.scroll && _pageIndex > 0 && _pagePaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPage(_pageIndex.clamp(0, _pagePaths.length - 1));
      });
    }
    _debouncedSave();
  }

  Future<List<String>> _computePagePaths() async {
    // Capture what we need before running on another zone
    final chapter = _currentChapter;
    final storagePath = _comic.storagePath;
    final chapterDir = chapter.folderName.isNotEmpty
        ? p.join(storagePath, chapter.folderName)
        : storagePath;
    final imageFiles = List<String>.from(chapter.imageFiles);

    return Isolate.run(() {
      if (imageFiles.isNotEmpty) {
        return imageFiles
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
  }

  void _scrollToPage(int index) {
    if (!_scrollController.hasClients) return;
    if (_screenHeight <= 0) return;
    final targetOffset = index * _screenHeight;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (targetOffset <= maxExtent) {
      _scrollController.jumpTo(targetOffset);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _mode != _ReaderMode.scroll) return;
    if (_screenHeight <= 0) return;
    final page = (_scrollController.offset / _screenHeight).round();
    if (page != _pageIndex && page >= 0 && page < _pagePaths.length) {
      setState(() => _pageIndex = page);
      _debouncedSave();
    }

    if (_autoAdvancing || _pagePaths.isEmpty) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentOffset = _scrollController.offset;

    // Near the bottom → advance to next chapter
    if (maxScroll > 0 && currentOffset >= maxScroll - _screenHeight * 0.8) {
      _advanceToNextChapter();
      return;
    }

    // Near the top → go back to previous chapter
    if (_chapterIndex > 0 && currentOffset <= _screenHeight * 0.2) {
      _goToPrevChapter();
    }
  }

  void _advanceToNextChapter() {
    if (_chapterIndex >= _chapters.length - 1) return;
    _autoAdvancing = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在加载: ${_chapters[_chapterIndex + 1].name.isNotEmpty ? _chapters[_chapterIndex + 1].name : '第${_chapterIndex + 2}话'}'),
        duration: const Duration(milliseconds: 800),
      ),
    );
    _goToChapter(_chapterIndex + 1);
    Future.delayed(const Duration(milliseconds: 500), () {
      _autoAdvancing = false;
    });
  }

  void _goToPrevChapter() {
    if (_chapterIndex <= 0) return;
    _autoAdvancing = true;
    final prev = _chapters[_chapterIndex - 1];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在加载: ${prev.name.isNotEmpty ? prev.name : '第$_chapterIndex 话'}'),
        duration: const Duration(milliseconds: 800),
      ),
    );
    // Go to the last page of the previous chapter
    final prevPageCount = prev.pageCount;
    _pageIndex = prevPageCount > 0 ? prevPageCount - 1 : 0;
    _goToChapter(_chapterIndex - 1);
    Future.delayed(const Duration(milliseconds: 500), () {
      _autoAdvancing = false;
    });
  }

  void _debouncedSave() {
    if (_pageIndex == _lastSavedPage && _chapterIndex == _lastSavedChapter) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveProgressNow);
  }

  void _saveProgressNow() {
    if (_pageIndex == _lastSavedPage && _chapterIndex == _lastSavedChapter) return;
    _lastSavedChapter = _chapterIndex;
    _lastSavedPage = _pageIndex;
    _comic.lastReadChapterIndex = _chapterIndex;
    _comic.lastReadPageIndex = _pageIndex;
    objectbox.comicBox.put(_comic);
  }

  TransformationController _controllerFor(int index) {
    return _transformControllers.putIfAbsent(index, () => TransformationController());
  }

  void _toggleUI() => setState(() => _showUI = !_showUI);

  void _toggleMode() {
    setState(() {
      _mode = _mode == _ReaderMode.scroll ? _ReaderMode.page : _ReaderMode.scroll;
    });
    if (_mode == _ReaderMode.page) {
      _pageController?.dispose();
      _pageController = PageController(initialPage: _pageIndex);
    } else {
      _pageController?.dispose();
      _pageController = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPage(_pageIndex);
      });
    }
  }

  void _goToChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    _transformControllers.clear();
    _pageController?.dispose();
    _pageController = null;

    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _pagePaths = [];
    });
    _loadPagePathsAsync();
    _debouncedSave();
  }

  void _tryExitEditMode() {
    // If in edit mode, exit it; otherwise go back
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: Stack(
          children: [
            GestureDetector(
              onTap: _toggleUI,
              child: _loadingPages
                  ? const Center(child: CircularProgressIndicator())
                  : _pagePaths.isEmpty
                      ? const Center(
                          child: Text('没有图片',
                              style: TextStyle(color: Colors.white54)),
                        )
                      : _mode == _ReaderMode.scroll
                          ? _buildScrollViewer()
                          : _buildPageViewer(),
            ),
            if (_showUI) ...[
              _buildTopBar(),
              _buildBottomBar(),
              if (_chapters.length > 1) ...[
                if (_chapterIndex > 0) _buildChapterArrow(isLeft: true),
                if (_chapterIndex < _chapters.length - 1)
                  _buildChapterArrow(isLeft: false),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        color: Colors.black54,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _tryExitEditMode,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_comic.title,
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        _currentChapter.name.isNotEmpty
                            ? _currentChapter.name
                            : '第${_chapterIndex + 1}话',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _mode == _ReaderMode.scroll ? Icons.auto_stories : Icons.swipe,
                      color: Colors.white),
                  tooltip: _mode == _ReaderMode.scroll ? '切换分页' : '切换滚动',
                  onPressed: _toggleMode,
                ),
                if (_chapters.length > 1)
                  IconButton(
                    icon: const Icon(Icons.list, color: Colors.white),
                    onPressed: () => _showChapterPicker(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        color: Colors.black54,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${_pageIndex + 1} / ${_pagePaths.length}',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChapterArrow({required bool isLeft}) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0, bottom: 0,
      child: Center(
        child: IconButton(
          icon: Icon(isLeft ? Icons.chevron_left : Icons.chevron_right,
              color: Colors.white54, size: 48),
          onPressed: isLeft ? _prevChapter : _nextChapter,
        ),
      ),
    );
  }

  void _nextChapter() {
    if (_chapterIndex < _chapters.length - 1) _goToChapter(_chapterIndex + 1);
  }

  void _prevChapter() {
    if (_chapterIndex > 0) _goToChapter(_chapterIndex - 1);
  }

  Widget _buildScrollViewer() {
    final sh = _screenHeight;
    return ListView.builder(
      controller: _scrollController,
      itemCount: _pagePaths.length,
      itemExtent: sh,
      cacheExtent: sh * 2,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        return InteractiveViewer(
          transformationController: _controllerFor(index),
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              File(_pagePaths[index]),
              fit: BoxFit.contain,
              width: double.infinity,
              height: sh,
              cacheWidth: (sh * MediaQuery.of(context).devicePixelRatio).round(),
              errorBuilder: (_, e, s) =>
                  const Icon(Icons.broken_image, size: 64, color: Colors.white54),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageViewer() {
    final sh = _screenHeight;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (_autoAdvancing) return false;
        // At last page → next chapter
        if (_pageIndex == _pagePaths.length - 1 &&
            _chapterIndex < _chapters.length - 1) {
          _advanceToNextChapter();
        }
        // At first page → previous chapter
        if (_pageIndex == 0 && _chapterIndex > 0) {
          _goToPrevChapter();
        }
        return false;
      },
      child: PageView.builder(
        key: ValueKey('page_$_chapterIndex'),
        controller: _pageController,
        itemCount: _pagePaths.length,
        scrollDirection: Axis.horizontal,
        onPageChanged: (index) {
          setState(() => _pageIndex = index);
          _debouncedSave();
          if (_autoAdvancing) return;
          // Auto-advance to next chapter when on last page
          if (index == _pagePaths.length - 1 &&
              _chapterIndex < _chapters.length - 1) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (_pageIndex == _pagePaths.length - 1 &&
                  _chapterIndex < _chapters.length - 1) {
                _advanceToNextChapter();
              }
            });
          }
          // Auto-return to previous chapter when on first page
          if (index == 0 && _chapterIndex > 0) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (_pageIndex == 0 && _chapterIndex > 0) {
                _goToPrevChapter();
              }
            });
          }
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
                cacheWidth: (sh * MediaQuery.of(context).devicePixelRatio).round(),
                errorBuilder: (_, e, s) =>
                    const Icon(Icons.broken_image, size: 64, color: Colors.white54),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showChapterPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
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
                    title: Text(ch.name.isNotEmpty ? ch.name : '第${index + 1}话'),
                    subtitle: Text('${ch.pageCount} 页'),
                    leading: index == _chapterIndex ? const Icon(Icons.check) : null,
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
      ),
    );
  }
}

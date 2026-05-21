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

class _ChapterSegment {
  final int chapterIndex;
  final String name;
  final List<String> pagePaths;
  const _ChapterSegment({
    required this.chapterIndex,
    required this.name,
    required this.pagePaths,
  });
}

class _ReaderPageState extends State<ReaderPage> {
  late Comic _comic;
  late List<ComicChapter> _chapters;
  int _currentChapterIdx = 0;

  // Combined segments for seamless scrolling
  List<_ChapterSegment> _segments = [];
  List<dynamic> _displayItems = []; // String (image path) or _Sep (separator)
  bool _loadingPages = true;
  bool _showUI = true;
  double _screenHeight = 0;

  final ScrollController _scrollController = ScrollController();
  final Map<int, TransformationController> _transformControllers = {};
  Timer? _saveTimer;
  int _lastSavedChapter = -1;
  int _lastSavedPage = -1;

  // Track the current global page index (across all loaded segments)
  int _globalPage = 0;

  @override
  void initState() {
    super.initState();
    _comic = _loadComic();
    _chapters = _comic.chapters;

    if (_chapters.isEmpty) {
      _currentChapterIdx = 0;
    } else {
      _currentChapterIdx = widget.chapterIndex.clamp(0, _chapters.length - 1);
    }

    _loadInitialSegments();
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

  // ── Segment loading ──

  Future<void> _loadInitialSegments() async {
    setState(() => _loadingPages = true);

    // Load current, next, and previous chapters in parallel
    final futures = <Future<_ChapterSegment>>[];
    if (_currentChapterIdx > 0) {
      futures.add(_buildSegment(_currentChapterIdx - 1));
    }
    futures.add(_buildSegment(_currentChapterIdx));
    if (_currentChapterIdx < _chapters.length - 1) {
      futures.add(_buildSegment(_currentChapterIdx + 1));
    }

    _segments = await Future.wait(futures);
    _rebuildDisplayItems();

    if (!mounted) return;

    // Scroll to the right page after layout
    if (_screenHeight > 0) {
      final targetGlobal = _globalPageForChapter(_currentChapterIdx) +
          widget.pageIndex.clamp(0,
              _chapters[_currentChapterIdx].pageCount.clamp(1, 999999) - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToGlobalPage(targetGlobal);
      });
    }

    setState(() => _loadingPages = false);
    _debouncedSave();
  }

  Future<_ChapterSegment> _buildSegment(int chIdx) async {
    final ch = _chapters[chIdx];
    final chapterDir = ch.folderName.isNotEmpty
        ? p.join(_comic.storagePath, ch.folderName)
        : _comic.storagePath;
    final imageFiles = List<String>.from(ch.imageFiles);

    final paths = await Future(() {
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

    return _ChapterSegment(
      chapterIndex: chIdx,
      name: ch.name.isNotEmpty ? ch.name : '第${chIdx + 1}话',
      pagePaths: paths,
    );
  }

  /// Separator marker class
  static const _sep = '__SEP__';

  void _rebuildDisplayItems() {
    final items = <dynamic>[];
    for (int i = 0; i < _segments.length; i++) {
      if (i > 0) items.add(_sep);
      items.addAll(_segments[i].pagePaths);
    }
    _displayItems = items;
  }

  /// Find which chapter a global item index belongs to.
  int _chapterIdxForGlobal(int globalIndex) {
    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      final segLen = _segments[i].pagePaths.length;
      final segEnd = offset + segLen;
      if (globalIndex < segEnd) return _segments[i].chapterIndex;
      offset = segEnd + 1; // +1 for separator
    }
    return _segments.last.chapterIndex;
  }

  /// Find the first global page index for a chapter.
  int _globalPageForChapter(int chIdx) {
    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i].chapterIndex == chIdx) return offset;
      offset += _segments[i].pagePaths.length + 1; // +1 for separator
    }
    return 0;
  }

  /// Get the local page index within a chapter.
  int _localPageForGlobal(int globalIndex) {
    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      final segLen = _segments[i].pagePaths.length;
      if (globalIndex < offset + segLen) {
        return globalIndex - offset;
      }
      offset += segLen + 1; // +1 for separator
    }
    return 0;
  }

  // ── Scroll handling ──

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_screenHeight <= 0) return;
    final page = (_scrollController.offset / _screenHeight).round();
    if (page != _globalPage && page >= 0 && page < _displayItems.length) {
      final item = _displayItems[page];
      if (item is String && item != _sep) {
        _globalPage = page;
        final chIdx = _chapterIdxForGlobal(page);
        if (chIdx != _currentChapterIdx) {
          _currentChapterIdx = chIdx;
          _updateChapterLabel();
        }
        _debouncedSave();
      }
    }

    // Preload more chapters when near boundaries
    _checkPreload();
  }

  void _updateChapterLabel() {
    // Trigger rebuild to update the top bar chapter name
    setState(() {});
  }

  void _checkPreload() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;

    // Near the end → load next chapter if available
    if (maxScroll > 0 && offset >= maxScroll - _screenHeight * 2) {
      _loadNextSegmentIfNeeded();
    }

    // Near the beginning → load previous chapter if available
    if (offset <= _screenHeight * 2) {
      _loadPrevSegmentIfNeeded();
    }
  }

  bool _loadingSegment = false;

  Future<void> _loadNextSegmentIfNeeded() async {
    if (_loadingSegment) return;
    final lastSeg = _segments.last;
    final nextCh = lastSeg.chapterIndex + 1;
    if (nextCh >= _chapters.length) return;

    _loadingSegment = true;
    final newSeg = await _buildSegment(nextCh);
    if (!mounted) { _loadingSegment = false; return; }

    // Remove oldest segment if we have too many
    if (_segments.length > 3) {
      final removedFirst = _segments.removeAt(0);
      for (final c in _transformControllers.keys.toList()) {
        if (c >= _displayItems.length) _transformControllers.remove(c);
      }
    }

    _segments.add(newSeg);
    _rebuildDisplayItems();
    setState(() {});
    _loadingSegment = false;
  }

  Future<void> _loadPrevSegmentIfNeeded() async {
    if (_loadingSegment) return;
    final firstSeg = _segments.first;
    final prevCh = firstSeg.chapterIndex - 1;
    if (prevCh < 0) return;

    _loadingSegment = true;
    final newSeg = await _buildSegment(prevCh);
    if (!mounted) { _loadingSegment = false; return; }

    // Remove last segment if too many
    if (_segments.length > 3) {
      _segments.removeLast();
    }

    final oldFirstGlobal = _globalPageForChapter(firstSeg.chapterIndex);
    _segments.insert(0, newSeg);
    _rebuildDisplayItems();
    final newFirstGlobal = _globalPageForChapter(firstSeg.chapterIndex);
    final delta = newFirstGlobal - oldFirstGlobal;

    // Adjust scroll position to compensate for prepended content
    if (_scrollController.hasClients && delta > 0) {
      final newOffset = _scrollController.offset + delta * _screenHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(newOffset.clamp(
            0, _scrollController.position.maxScrollExtent,
          ));
        }
      });
    }
    setState(() {});
    _loadingSegment = false;
  }

  void _scrollToGlobalPage(int page) {
    if (!_scrollController.hasClients) return;
    if (_screenHeight <= 0) return;
    final target = page * _screenHeight;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (target <= maxExtent) {
      _scrollController.jumpTo(target);
    }
  }

  // ── Chapter info for UI ──

  int get _currentLocalPage => _localPageForGlobal(_globalPage);
  int get _currentChapterPageCount => _chapters[_currentChapterIdx].pageCount;
  String get _currentChapterName {
    if (_currentChapterIdx >= 0 && _currentChapterIdx < _chapters.length) {
      final ch = _chapters[_currentChapterIdx];
      return ch.name.isNotEmpty ? ch.name : '第${_currentChapterIdx + 1}话';
    }
    return '';
  }

  // ── Save progress ──

  void _debouncedSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveProgressNow);
  }

  void _saveProgressNow() {
    final chIdx = _currentChapterIdx;
    final page = _currentLocalPage;
    if (page == _lastSavedPage && chIdx == _lastSavedChapter) return;
    _lastSavedChapter = chIdx;
    _lastSavedPage = page;
    _comic.lastReadChapterIndex = chIdx;
    _comic.lastReadPageIndex = page;
    objectbox.comicBox.put(_comic);
  }

  TransformationController _controllerFor(int index) {
    return _transformControllers.putIfAbsent(index, () => TransformationController());
  }

  void _toggleUI() => setState(() => _showUI = !_showUI);

  // ── Build ──

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
                  : _displayItems.isEmpty
                      ? const Center(
                          child: Text('没有图片',
                              style: TextStyle(color: Colors.white54)),
                        )
                      : _buildScrollViewer(),
            ),
            if (_showUI) ...[
              _buildTopBar(),
              _buildBottomBar(),
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
                  onPressed: () => Navigator.pop(context),
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
                        _currentChapterName,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
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
                Text('${_currentLocalPage + 1} / $_currentChapterPageCount',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollViewer() {
    final sh = _screenHeight;
    return ListView.builder(
      controller: _scrollController,
      itemCount: _displayItems.length,
      itemExtent: sh,
      cacheExtent: sh * 2,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final item = _displayItems[index];
        if (item == _sep) return _buildSeparator(sh);

        return InteractiveViewer(
          transformationController: _controllerFor(index),
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              File(item as String),
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

  Widget _buildSeparator(double screenHeight) {
    // Find which chapter comes after this separator
    return Container(
      width: double.infinity,
      height: screenHeight,
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text('— 下一章 —',
                style: TextStyle(color: Colors.white38, fontSize: 18)),
          ],
        ),
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
                    leading: index == _currentChapterIdx
                        ? const Icon(Icons.check) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _jumpToChapter(index);
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

  Future<void> _jumpToChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    _currentChapterIdx = index;
    _segments.clear();
    _displayItems.clear();
    _globalPage = 0;

    for (final c in _transformControllers.values) {
      c.dispose();
    }
    _transformControllers.clear();

    await _loadInitialSegments();
  }
}

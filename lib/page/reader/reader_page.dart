import 'dart:async';
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

  List<_ChapterSegment> _segments = [];
  List<String> _displayItems = [];
  bool _loadingPages = true;
  bool _showUI = true;
  double _screenHeight = 0;

  final ScrollController _scrollController = ScrollController();
  final Map<int, TransformationController> _transformControllers = {};
  Timer? _saveTimer;
  int _lastSavedChapter = -1;
  int _lastSavedPage = -1;
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

    if (_screenHeight > 0) {
      final maxPage = _chapters[_currentChapterIdx].pageCount;
      final targetGlobal = _globalPageForChapter(_currentChapterIdx) +
          widget.pageIndex.clamp(0, maxPage > 0 ? maxPage - 1 : 0);
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

  // ── Display list ──

  void _rebuildDisplayItems() {
    final items = <String>[];
    for (final seg in _segments) {
      items.addAll(seg.pagePaths);
    }
    _displayItems = items;
  }

  int _chapterIdxForGlobal(int globalIndex) {
    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      final segLen = _segments[i].pagePaths.length;
      if (globalIndex < offset + segLen) return _segments[i].chapterIndex;
      offset += segLen;
    }
    return _segments.last.chapterIndex;
  }

  int _globalPageForChapter(int chIdx) {
    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i].chapterIndex == chIdx) return offset;
      offset += _segments[i].pagePaths.length;
    }
    return 0;
  }

  int _localPageForGlobal(int globalIndex) {
    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      final segLen = _segments[i].pagePaths.length;
      if (globalIndex < offset + segLen) return globalIndex - offset;
      offset += segLen;
    }
    return 0;
  }

  // ── Scroll ──

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_screenHeight <= 0) return;
    final page = (_scrollController.offset / _screenHeight).round();
    if (page != _globalPage && page >= 0 && page < _displayItems.length) {
      _globalPage = page;
      final chIdx = _chapterIdxForGlobal(page);
      if (chIdx != _currentChapterIdx) {
        _currentChapterIdx = chIdx;
        setState(() {});
      }
      _debouncedSave();
    }
    _checkPreload();
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

  // ── Preload ──

  bool _loadingSegment = false;

  void _checkPreload() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;

    if (maxScroll > 0 && offset >= maxScroll - _screenHeight * 2) {
      _loadNextSegmentIfNeeded();
    }
    if (offset <= _screenHeight * 2) {
      _loadPrevSegmentIfNeeded();
    }
  }

  Future<void> _loadNextSegmentIfNeeded() async {
    if (_loadingSegment) return;
    final lastSeg = _segments.last;
    final nextCh = lastSeg.chapterIndex + 1;
    if (nextCh >= _chapters.length) return;

    _loadingSegment = true;
    final newSeg = await _buildSegment(nextCh);
    if (!mounted) { _loadingSegment = false; return; }

    if (_segments.length > 3) _segments.removeAt(0);
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

    final oldFirstGlobal = _globalPageForChapter(firstSeg.chapterIndex);
    if (_segments.length > 3) _segments.removeLast();
    _segments.insert(0, newSeg);
    _rebuildDisplayItems();
    final newFirstGlobal = _globalPageForChapter(firstSeg.chapterIndex);
    final delta = newFirstGlobal - oldFirstGlobal;

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

  // ── Chapter info ──

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
        return InteractiveViewer(
          transformationController: _controllerFor(index),
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              File(_displayItems[index]),
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';

class ComicDetailPage extends StatefulWidget {
  final String comicId;

  const ComicDetailPage({super.key, required this.comicId});

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  late Comic _comic;
  late List<ComicChapter> _chapters;

  @override
  void initState() {
    super.initState();
    _comic = _loadComic();
    _chapters = _comic.chapters;
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

  void _startReading({int? chapterIndex, int? pageIndex}) {
    final ch = chapterIndex ?? _comic.lastReadChapterIndex.clamp(0, _chapters.length - 1);
    final pg = pageIndex ?? (chapterIndex != null ? 0 : _comic.lastReadPageIndex);
    Navigator.pushNamed(
      context,
      '/reader',
      arguments: {
        'comicId': _comic.comicId,
        'chapterIndex': ch,
        'pageIndex': pg,
      },
    ).then((_) {
      if (mounted) {
        final updated = _loadComic();
        _comic = updated;
        _chapters = updated.chapters;
        setState(() {});
      }
    });
  }

  String _progressText() {
    final label = _comic.progressLabel;
    if (label == null) return '尚未阅读';
    return '上次阅读: $label';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_comic.title),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cover
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 200,
                height: 280,
                child: _comic.coverPath.isNotEmpty &&
                        File(_comic.coverPath).existsSync()
                    ? Image.file(
                        File(_comic.coverPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _placeholderCover(context),
                      )
                    : _placeholderCover(context),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            _comic.title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (_comic.author.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _comic.author,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),

          // Progress
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _progressText(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Start / Continue reading button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () => _startReading(),
              icon: Icon(
                _comic.lastReadPageIndex > 0
                    ? Icons.play_circle
                    : Icons.play_arrow,
              ),
              label: Text(
                _comic.lastReadPageIndex > 0 ? '继续阅读' : '开始阅读',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Chapter list
          Text(
            '章节目录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_chapters.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('暂无章节信息')),
              ),
            )
          else
            ...List.generate(_chapters.length, (i) {
              final ch = _chapters[i];
              final isLastRead = i == _comic.lastReadChapterIndex &&
                  _comic.lastReadPageIndex > 0;
              return Card(
                child: ListTile(
                  title: Text(
                    ch.name.isNotEmpty ? ch.name : '第${i + 1}话',
                    style: TextStyle(
                      fontWeight: isLastRead ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text('${ch.pageCount} 页'),
                  trailing: isLastRead
                      ? const Icon(Icons.bookmark, size: 18)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _startReading(chapterIndex: i, pageIndex: 0),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _placeholderCover(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

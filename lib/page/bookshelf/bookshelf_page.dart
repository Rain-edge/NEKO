import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/page/bookshelf/widgets/comic_card.dart';

class BookshelfPage extends StatefulWidget {
  final VoidCallback? onComicsChanged;

  const BookshelfPage({super.key, this.onComicsChanged});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  List<Comic> _comics = [];
  Comic? _draggedComic;
  bool _overDeleteZone = false;

  @override
  void initState() {
    super.initState();
    _loadComics();
  }

  void _loadComics() {
    final query = objectbox.comicBox
        .query(Comic_.deleted.equals(false))
        .order(Comic_.displayOrder)
        .build();
    _comics = query.find();
    query.close();
    if (mounted) setState(() {});
  }

  void _openComic(Comic comic) {
    if (_draggedComic != null) return;
    Navigator.pushNamed(
      context,
      '/comic_detail',
      arguments: {'comicId': comic.comicId},
    ).then((_) {
      if (mounted) _loadComics();
    });
  }

  void _swapComics(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    setState(() {
      final item = _comics.removeAt(fromIndex);
      _comics.insert(toIndex, item);
      // Save display orders
      final changed = <Comic>[];
      for (int i = 0; i < _comics.length; i++) {
        if (_comics[i].displayOrder != i) {
          _comics[i].displayOrder = i;
          changed.add(_comics[i]);
        }
      }
      if (changed.isNotEmpty) {
        objectbox.comicBox.putMany(changed);
      }
    });
  }

  void _onDragStarted(Comic comic) {
    setState(() => _draggedComic = comic);
  }

  void _onDragEnded() {
    setState(() {
      _draggedComic = null;
      _overDeleteZone = false;
    });
  }

  void _onDeleteAccept(Comic comic) {
    setState(() {
      _draggedComic = null;
      _overDeleteZone = false;
    });
    _deleteComic(comic);
  }

  Future<void> _deleteComic(Comic comic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除漫画'),
        content: Text('确定要删除「${comic.title}」吗？\n\n这将同时删除所有文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final dir = Directory(comic.storagePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}

    comic.deleted = true;
    objectbox.comicBox.put(comic);

    final entries = objectbox.entryBox
        .query(CollectionEntry_.comicId.equals(comic.comicId))
        .build()
        .find();
    objectbox.entryBox.removeMany(entries.map((e) => e.id).toList());

    _loadComics();
    widget.onComicsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _draggedComic != null;

    return Stack(
      children: [
        _comics.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.library_books_outlined, size: 64, color: Colors.white54),
                    SizedBox(height: 16),
                    Text('还没有漫画', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('点击右上角菜单导入漫画', style: TextStyle(color: Colors.white60)),
                  ],
                ),
              )
            : _buildDraggableGrid(),

        // Delete zone — shown during drag
        if (isDragging)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: DragTarget<Comic>(
              onWillAcceptWithDetails: (_) {
                if (!_overDeleteZone) setState(() => _overDeleteZone = true);
                return true;
              },
              onLeave: (_) => setState(() => _overDeleteZone = false),
              onAcceptWithDetails: (details) => _onDeleteAccept(details.data),
              builder: (context, candidates, rejected) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 72,
                  color: _overDeleteZone ? Colors.red.shade800 : Colors.red.shade400,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete, color: Colors.white,
                          size: _overDeleteZone ? 36 : 28),
                      const SizedBox(width: 8),
                      Text(
                        _overDeleteZone ? '松开删除' : '拖到此处删除',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDraggableGrid() {
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: _comics.length,
        itemBuilder: (context, index) {
          final comic = _comics[index];
          final isDragged = _draggedComic?.comicId == comic.comicId;

          final card = ComicCardWidget(
            key: ValueKey('card_${comic.comicId}'),
            comic: comic,
            onTap: () => _openComic(comic),
            isDragged: isDragged,
          );

          return LongPressDraggable<Comic>(
            key: ValueKey('drag_${comic.comicId}'),
            data: comic,
            delay: const Duration(milliseconds: 300),
            hapticFeedbackOnStart: true,
            onDragStarted: () => _onDragStarted(comic),
            onDragEnd: (_) => _onDragEnded(),
            onDraggableCanceled: (_, __) => _onDragEnded(),
            feedback: SizedBox(
              width: 120,
              height: 167,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: card,
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: card),
            child: DragTarget<Comic>(
              onWillAcceptWithDetails: (details) {
                // Accept if different comic
                return details.data.comicId != comic.comicId;
              },
              onAcceptWithDetails: (details) {
                final fromIndex = _comics.indexOf(details.data);
                final toIndex = index;
                _swapComics(fromIndex, toIndex);
              },
              builder: (context, candidates, rejected) {
                return candidates.isNotEmpty
                    ? Card(
                        clipBehavior: Clip.antiAlias,
                        color: Theme.of(context).colorScheme.primary.withAlpha(40),
                        child: const Center(child: Icon(Icons.swap_horiz, size: 32)),
                      )
                    : card;
              },
            ),
          );
        },
      ),
    );
  }
}

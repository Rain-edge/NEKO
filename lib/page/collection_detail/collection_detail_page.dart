import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/page/bookshelf/widgets/comic_card.dart';

class CollectionDetailPage extends StatefulWidget {
  final FavoriteCollection collection;

  const CollectionDetailPage({super.key, required this.collection});

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  List<Comic> _comics = [];
  Comic? _draggedComic;
  bool _overDeleteZone = false;
  FavoriteCollection get _col => widget.collection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final entries = objectbox.entryBox
        .query(CollectionEntry_.collectionId.equals(_col.collectionId))
        .order(CollectionEntry_.displayOrder)
        .build()
        .find();

    final comicIds = entries.map((e) => e.comicId).toList();
    _comics = [];

    if (comicIds.isNotEmpty) {
      final idSet = comicIds.toSet();
      final allComics = objectbox.comicBox.getAll();
      for (final c in allComics) {
        if (!c.deleted && idSet.contains(c.comicId)) {
          _comics.add(c);
        }
      }
      _comics.sort((a, b) =>
          comicIds.indexOf(a.comicId).compareTo(comicIds.indexOf(b.comicId)));
    }

    _updateCollectionCover();
    if (mounted) setState(() {});
  }

  void _updateCollectionCover() {
    if (_comics.isNotEmpty && _comics.first.coverPath.isNotEmpty) {
      if (_col.coverPath != _comics.first.coverPath) {
        _col.coverPath = _comics.first.coverPath;
        objectbox.collectionBox.put(_col);
      }
    }
  }

  void _openComic(Comic comic) {
    if (_draggedComic != null) return;
    Navigator.pushNamed(
      context,
      '/comic_detail',
      arguments: {'comicId': comic.comicId},
    ).then((_) => _load());
  }

  void _swapComics(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    setState(() {
      final item = _comics.removeAt(fromIndex);
      _comics.insert(toIndex, item);

      final entries = objectbox.entryBox
          .query(CollectionEntry_.collectionId.equals(_col.collectionId))
          .order(CollectionEntry_.displayOrder)
          .build()
          .find();

      for (int i = 0; i < _comics.length; i++) {
        for (final e in entries) {
          if (e.comicId == _comics[i].comicId && e.displayOrder != i) {
            e.displayOrder = i;
            objectbox.entryBox.put(e);
            break;
          }
        }
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

  Future<void> _removeFromCollection(Comic comic) async {
    final q = objectbox.entryBox.query(
      CollectionEntry_.collectionId
          .equals(_col.collectionId)
          .and(CollectionEntry_.comicId.equals(comic.comicId)),
    );
    final built = q.build();
    final entries = built.find();
    built.close();
    objectbox.entryBox.removeMany(entries.map((e) => e.id).toList());
    _load();
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

    final allEntries = objectbox.entryBox
        .query(CollectionEntry_.comicId.equals(comic.comicId))
        .build()
        .find();
    objectbox.entryBox.removeMany(allEntries.map((e) => e.id).toList());

    _load();
  }

  void _showAddComicDialog() {
    final allComics = objectbox.comicBox
        .query(Comic_.deleted.equals(false))
        .order(Comic_.displayOrder)
        .build()
        .find();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加漫画到收藏'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allComics.length,
            itemBuilder: (_, i) {
              final c = allComics[i];
              return ListTile(
                title: Text(c.title),
                leading: c.coverPath.isNotEmpty
                    ? Image.file(File(c.coverPath),
                        width: 40, height: 56, fit: BoxFit.cover, cacheWidth: 80)
                    : null,
                onTap: () {
                  final eq = objectbox.entryBox.query(
                    CollectionEntry_.collectionId
                        .equals(_col.collectionId)
                        .and(CollectionEntry_.comicId.equals(c.comicId)),
                  );
                  final built = eq.build();
                  final existing = built.count();
                  built.close();
                  if (existing == 0) {
                    objectbox.entryBox.put(CollectionEntry(
                      collectionId: _col.collectionId,
                      comicId: c.comicId,
                      displayOrder: objectbox.entryBox
                          .query(CollectionEntry_.collectionId
                              .equals(_col.collectionId))
                          .build()
                          .count(),
                    ));
                  }
                  Navigator.pop(ctx);
                  _load();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showComicOptions(Comic comic) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('从收藏中移除'),
              onTap: () {
                Navigator.pop(ctx);
                _removeFromCollection(comic);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除漫画', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteComic(comic);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _draggedComic != null;

    return Scaffold(
      appBar: AppBar(title: Text(_col.name), centerTitle: true),
      body: Stack(
        children: [
          _comics.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.collections_bookmark, size: 64,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('收藏夹是空的',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                )
              : _buildDraggableGrid(),

          // Delete zone
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
                        Text(_overDeleteZone ? '松开删除' : '拖到此处删除',
                            style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: isDragging
          ? null
          : FloatingActionButton(
              onPressed: _showAddComicDialog,
              child: const Icon(Icons.add),
            ),
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
            onLongPress: isDragged ? null : () {},
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
              width: 120, height: 167,
              child: Material(elevation: 8, borderRadius: BorderRadius.circular(8), child: card),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: card),
            child: DragTarget<Comic>(
              onWillAcceptWithDetails: (details) {
                return details.data.comicId != comic.comicId;
              },
              onAcceptWithDetails: (details) {
                final fromIndex = _comics.indexOf(details.data);
                _swapComics(fromIndex, index);
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

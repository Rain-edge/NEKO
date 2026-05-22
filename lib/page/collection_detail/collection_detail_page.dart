import 'dart:io';
import 'dart:math' as math;
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

class _CollectionDetailPageState extends State<CollectionDetailPage>
    with SingleTickerProviderStateMixin {
  List<Comic> _comics = [];
  Comic? _draggedComic;
  bool _overDeleteZone = false;
  bool _overRemoveZone = false;
  int? _hoveredIndex;
  FavoriteCollection get _col => widget.collection;

  late AnimationController _wobbleCtrl;
  late Animation<double> _wobbleAnim;

  @override
  void initState() {
    super.initState();
    _load();
    _wobbleCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _wobbleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.06), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.04), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.04, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _wobbleCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _wobbleCtrl.dispose();
    super.dispose();
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
    _wobbleCtrl.forward(from: 0);
    setState(() {
      _draggedComic = comic;
      _hoveredIndex = _comics.indexOf(comic);
    });
  }

  void _onDragEnded() {
    _wobbleCtrl.reset();
    setState(() {
      _draggedComic = null;
      _overDeleteZone = false;
      _overRemoveZone = false;
      _hoveredIndex = null;
    });
  }

  void _onDeleteAccept(Comic comic) {
    _wobbleCtrl.reset();
    setState(() {
      _draggedComic = null;
      _overDeleteZone = false;
      _overRemoveZone = false;
      _hoveredIndex = null;
    });
    _deleteComic(comic);
  }

  void _onRemoveAccept(Comic comic) {
    _wobbleCtrl.reset();
    setState(() {
      _draggedComic = null;
      _overDeleteZone = false;
      _overRemoveZone = false;
      _hoveredIndex = null;
    });
    _removeFromCollection(comic);
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

          if (isDragging)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Row(
                children: [
                  Expanded(
                    child: DragTarget<Comic>(
                      onWillAcceptWithDetails: (_) {
                        if (!_overRemoveZone) setState(() => _overRemoveZone = true);
                        return true;
                      },
                      onLeave: (_) => setState(() => _overRemoveZone = false),
                      onAcceptWithDetails: (details) => _onRemoveAccept(details.data),
                      builder: (context, candidates, rejected) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 72,
                          color: _overRemoveZone ? Colors.orange.shade800 : Colors.orange.shade400,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.remove_circle_outline, color: Colors.white,
                                  size: _overRemoveZone ? 36 : 28),
                              const SizedBox(width: 4),
                              Text(_overRemoveZone ? '松开移出' : '移出收藏',
                                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
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
                              const SizedBox(width: 4),
                              Text(_overDeleteZone ? '松开删除' : '删除漫画',
                                  style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
      child: AnimatedBuilder(
        animation: _wobbleAnim,
        builder: (context, child) {
          return GridView.builder(
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
              final isHovered = _hoveredIndex == index && !isDragged;

              final card = ComicCardWidget(
                comic: comic,
                onTap: () => _openComic(comic),
                onLongPress: isDragged ? null : () {},
                isDragged: isDragged,
              );

              Widget content = isDragged
                  ? Transform.rotate(angle: _wobbleAnim.value, child: card)
                  : card;

              if (isHovered) {
                content = Transform.translate(
                  offset: Offset(math.sin(_wobbleAnim.value * 20) * 8, 0),
                  child: content,
                );
              }

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
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    child: Transform.rotate(angle: 0.05, child: card),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.2, child: card),
                child: DragTarget<Comic>(
                  onWillAcceptWithDetails: (details) {
                    if (details.data.comicId == comic.comicId) return false;
                    setState(() => _hoveredIndex = index);
                    return true;
                  },
                  onLeave: (_) {},
                  onAcceptWithDetails: (details) {
                    final fromIndex = _comics.indexOf(details.data);
                    _swapComics(fromIndex, index);
                    _onDragEnded();
                  },
                  builder: (context, candidates, rejected) {
                    final hasCandidate = candidates.isNotEmpty;
                    return AnimatedScale(
                      duration: const Duration(milliseconds: 150),
                      scale: hasCandidate ? 1.08 : 1.0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: hasCandidate
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              )
                            : null,
                        child: content,
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

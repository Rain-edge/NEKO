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
  bool _editMode = false;
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
      _comics.sort((a, b) => comicIds.indexOf(a.comicId).compareTo(comicIds.indexOf(b.comicId)));
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
    if (_editMode) return;
    Navigator.pushNamed(
      context,
      '/comic_detail',
      arguments: {'comicId': comic.comicId},
    ).then((_) => _load());
  }

  void _startEditMode(Comic comic) {
    setState(() => _editMode = true);
  }

  void _endEditMode() {
    if (!_editMode) return;
    setState(() => _editMode = false);
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

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _comics.removeAt(oldIndex);
    _comics.insert(newIndex, item);

    // Rebuild all CollectionEntry display orders
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
    setState(() {});
  }

  Future<void> _deleteComic(Comic comic) async {
    _endEditMode();
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_col.name),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          _comics.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.collections_bookmark,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('收藏夹是空的',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                )
              : _editMode
                  ? _buildEditGrid()
                  : _buildNormalGrid(),
          // Edit mode header
          if (_editMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _endEditMode,
                      ),
                      const Expanded(
                        child: Text(
                          '编辑模式 — 长按拖拽排序，点击 X 移除',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _editMode
          ? null
          : FloatingActionButton(
              onPressed: _showAddComicDialog,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildNormalGrid() {
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
        return ComicCardWidget(
          key: ValueKey(_comics[index].comicId),
          comic: _comics[index],
          onTap: () => _openComic(_comics[index]),
          onLongPress: () => _showComicOptions(_comics[index]),
        );
      },
    );
  }

  Widget _buildEditGrid() {
    return SafeArea(
      child: ReorderableListView.builder(
        padding: const EdgeInsets.all(8),
        buildDefaultDragHandles: true,
        onReorder: _onReorder,
        itemCount: _comics.length,
        itemBuilder: (context, index) {
          final comic = _comics[index];
          return Card(
            key: ValueKey('edit_${comic.comicId}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 48,
                  height: 68,
                  child: comic.coverPath.isNotEmpty
                      ? Image.file(
                          File(comic.coverPath),
                          fit: BoxFit.cover,
                          cacheWidth: 96,
                          errorBuilder: (_, __, ___) => _placeholderIcon(),
                        )
                      : _placeholderIcon(),
                ),
              ),
              title: Text(comic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${comic.pageCount} 页'),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.orange),
                onPressed: () => _removeFromCollection(comic),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.menu_book, size: 24, color: Colors.grey),
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
              leading: const Icon(Icons.reorder),
              title: const Text('编辑排序'),
              onTap: () {
                Navigator.pop(ctx);
                _startEditMode(comic);
              },
            ),
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
}

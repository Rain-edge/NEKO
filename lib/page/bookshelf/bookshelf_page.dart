import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/page/bookshelf/widgets/comic_card.dart';

class BookshelfPage extends StatefulWidget {
  final VoidCallback? onComicsChanged;

  const BookshelfPage({
    super.key,
    this.onComicsChanged,
  });

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  List<Comic> _comics = [];
  bool _editMode = false;

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
    if (_editMode) return;
    Navigator.pushNamed(
      context,
      '/comic_detail',
      arguments: {'comicId': comic.comicId},
    ).then((_) {
      if (mounted) _loadComics();
    });
  }

  void _startEditMode(Comic comic) {
    setState(() => _editMode = true);
  }

  void _endEditMode() {
    if (!_editMode) return;
    setState(() => _editMode = false);
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

    _endEditMode();

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

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _comics.removeAt(oldIndex);
    _comics.insert(newIndex, item);

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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Content
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
            : _editMode
                ? _buildEditGrid()
                : _buildNormalGrid(),

        // Edit mode controls
        if (_editMode) ...[
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
                        '编辑模式 — 长按拖拽排序，点击 X 删除',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Normal grid — simple tap/long-press to enter edit mode.
  Widget _buildNormalGrid() {
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
          return ComicCardWidget(
            key: ValueKey(comic.comicId),
            comic: comic,
            onTap: () => _openComic(comic),
            onLongPress: () => _startEditMode(comic),
          );
        },
      ),
    );
  }

  /// Edit mode — simple ListTile-style items, guaranteed to render.
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
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteComic(comic),
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

}

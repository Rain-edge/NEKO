import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/page/collection_detail/collection_detail_page.dart';

class CollectionsPage extends StatefulWidget {
  final VoidCallback? onCollectionChanged;

  const CollectionsPage({super.key, this.onCollectionChanged});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  List<FavoriteCollection> _collections = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final query = objectbox.collectionBox
        .query()
        .order(FavoriteCollection_.displayOrder)
        .build();
    _collections = query.find();
    query.close();
    if (mounted) setState(() {});
  }

  void _openCollection(FavoriteCollection collection) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectionDetailPage(collection: collection),
      ),
    ).then((_) {
      _load();
      widget.onCollectionChanged?.call();
    });
  }

  Future<void> _deleteCollection(FavoriteCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text('确定要删除收藏「${collection.name}」吗？\n\n其中的漫画不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final entries = objectbox.entryBox
        .query(CollectionEntry_.collectionId.equals(collection.collectionId))
        .build()
        .find();
    objectbox.entryBox.removeMany(entries.map((e) => e.id).toList());
    objectbox.collectionBox.remove(collection.id);
    _load();
    widget.onCollectionChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_collections.isEmpty) {
      return SafeArea(
        child: Center(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_outline,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('还没有收藏',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            Text('点击右上角菜单新建收藏',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        ),
      );
    }

    return SafeArea(
      child: GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _collections.length,
      itemBuilder: (context, index) {
        final col = _collections[index];
        return GestureDetector(
          onTap: () => _openCollection(col),
          onLongPress: () => _deleteCollection(col),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(child: _buildCover(col)),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(col.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
        );
      },
    ),
    );
  }

  Widget _buildCover(FavoriteCollection col) {
    if (col.coverPath.isNotEmpty) {
      return Image.file(
        File(col.coverPath),
        fit: BoxFit.cover,
        cacheWidth: 320,
        errorBuilder: (_, __, ___) => _placeholderIcon(),
      );
    }
    return _placeholderIcon();
  }

  Widget _placeholderIcon() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.folder, size: 40,
            color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

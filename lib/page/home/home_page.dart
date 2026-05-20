import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/object_box/objectbox.g.dart';
import 'package:neko/page/home/widgets/comic_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Comic> _comics = [];

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

  Future<void> _navigateToImport() async {
    if (!mounted) return;
    final result = await Navigator.pushNamed(context, '/import');
    if (!mounted) return;
    if (result == true) {
      _loadComics();
    }
  }

  void _openReader(Comic comic) {
    Navigator.pushNamed(
      context,
      '/reader',
      arguments: {'comicId': comic.comicId, 'chapterIndex': 0},
    ).then((_) {
      if (mounted) _loadComics();
    });
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
    _loadComics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEKO'),
        centerTitle: true,
      ),
      body: _comics.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.library_books_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有漫画',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右下角按钮导入漫画',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: _comics.length,
              itemBuilder: (context, index) {
                return ComicCard(
                  comic: _comics[index],
                  onTap: () => _openReader(_comics[index]),
                  onLongPress: () => _deleteComic(_comics[index]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToImport,
        child: const Icon(Icons.add),
      ),
    );
  }
}

import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:neko/model/comic.dart';
import 'package:neko/object_box/object_box.dart';
import 'package:neko/util/path_util.dart';
import 'package:neko/page/bookshelf/bookshelf_page.dart';
import 'package:neko/page/collections/collections_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _tabIndex = 0;
  String? _wallpaperPath;
  int _refreshCounter = 0;

  static const _wallpaperKey = 'wallpaper_path';

  @override
  void initState() {
    super.initState();
    _loadWallpaper();
  }

  Future<void> _loadWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_wallpaperKey);
    if (path != null && await File(path).exists()) {
      if (mounted) setState(() => _wallpaperPath = path);
    } else {
      if (path != null) {
        // File no longer exists, clear preference
        await prefs.remove(_wallpaperKey);
      }
    }
  }

  Future<void> _changeWallpaper() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(extensions: ['jpg', 'jpeg', 'png', 'webp']),
    ]);
    if (file == null) return;

    final wallpaperFile = File(file.path);
    if (!await wallpaperFile.exists()) return;

    // Copy to app storage so the wallpaper persists
    final appDir = await _getWallpaperDir();
    await appDir.create(recursive: true);
    final destPath = '${appDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}${_extension(file.path)}';
    await wallpaperFile.copy(destPath);
    await wallpaperFile.copy(destPath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperKey, destPath);

    if (mounted) setState(() => _wallpaperPath = destPath);

    // Clear old wallpaper files to avoid filling storage
    _cleanOldWallpapers(appDir, destPath);
  }

  Future<Directory> _getWallpaperDir() async {
    // Store wallpaper in app storage using the same base as comics
    final appDir = await getAppDir();
    final dir = Directory(p.join(appDir, 'neko_wallpaper'));
    await dir.create(recursive: true);
    return dir;
  }

  String _extension(String path) {
    final idx = path.lastIndexOf('.');
    return idx >= 0 ? path.substring(idx) : '.jpg';
  }

  Future<void> _cleanOldWallpapers(Directory dir, String keepPath) async {
    try {
      await for (final f in dir.list()) {
        if (f is File && f.path != keepPath) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> _createCollection() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建收藏'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '收藏名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final collection = FavoriteCollection(
      collectionId: const Uuid().v4(),
      name: name,
      displayOrder: objectbox.collectionBox.count(),
    );
    objectbox.collectionBox.put(collection);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏「$name」已创建'), duration: const Duration(seconds: 2)),
      );
      setState(() => _refreshCounter++);
      if (_tabIndex != 1) {
        setState(() => _tabIndex = 1);
      }
    }
  }

  Future<void> _navigateToImport() async {
    if (!mounted) return;
    final result = await Navigator.pushNamed(context, '/import');
    if (!mounted) return;
    if (result == true) {
      setState(() => _refreshCounter++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('NEKO'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              switch (value) {
                case 'wallpaper':
                  _changeWallpaper();
                  break;
                case 'create_collection':
                  _createCollection();
                  break;
                case 'import':
                  _navigateToImport();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'wallpaper',
                child: ListTile(
                  leading: Icon(Icons.wallpaper),
                  title: Text('更换壁纸'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'create_collection',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder),
                  title: Text('新建收藏'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.add),
                  title: Text('导入漫画'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Default background (visible when no wallpaper or wallpaper fails)
          Positioned.fill(
            child: Container(color: Theme.of(context).colorScheme.surface),
          ),
          // Shared wallpaper background for both tabs
          if (_wallpaperPath != null)
            Positioned.fill(
              child: Image.file(
                File(_wallpaperPath!),
                fit: BoxFit.cover,
                cacheWidth: 720,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          // Dark overlay over wallpaper
          if (_wallpaperPath != null)
            Positioned.fill(
              child: Container(color: Colors.black.withAlpha(100)),
            ),
          // Tab content
          IndexedStack(
            index: _tabIndex,
            children: [
              BookshelfPage(
                key: ValueKey('bookshelf_$_refreshCounter'),
                onComicsChanged: () => setState(() {}),
              ),
              CollectionsPage(
                key: ValueKey('collections_$_refreshCounter'),
                onCollectionChanged: () => setState(() {}),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: '收藏',
          ),
        ],
      ),
    );
  }
}

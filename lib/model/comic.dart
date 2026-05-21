import 'dart:convert';
import 'package:objectbox/objectbox.dart';

@Entity()
class Comic {
  @Id()
  int id;

  @Unique()
  String comicId;

  String title;
  String author;
  String description;
  String coverPath;
  int pageCount;
  String storagePath;
  String chaptersJson;

  @Property(type: PropertyType.date)
  DateTime importedAt;

  int displayOrder;

  bool deleted;

  // Reading progress
  int lastReadChapterIndex;
  int lastReadPageIndex;

  Comic({
    this.id = 0,
    required this.comicId,
    required this.title,
    this.author = '',
    this.description = '',
    this.coverPath = '',
    this.pageCount = 0,
    required this.storagePath,
    this.chaptersJson = '[]',
    required this.importedAt,
    this.displayOrder = 0,
    this.deleted = false,
    this.lastReadChapterIndex = 0,
    this.lastReadPageIndex = 0,
  });

  // ── Cached getters (avoid repeated jsonDecode) ──

  List<ComicChapter>? _cachedChapters;
  String? _cachedChaptersJson;

  List<ComicChapter> get chapters {
    if (_cachedChapters != null && _cachedChaptersJson == chaptersJson) {
      return _cachedChapters!;
    }
    if (chaptersJson.isEmpty) {
      _cachedChapters = [];
      _cachedChaptersJson = chaptersJson;
      return [];
    }
    try {
      final list = jsonDecode(chaptersJson) as List;
      _cachedChapters = list
          .map((e) => ComicChapter.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _cachedChaptersJson = chaptersJson;
      return _cachedChapters!;
    } catch (_) {
      return [];
    }
  }

  set chapters(List<ComicChapter> value) {
    _cachedChapters = value;
    final encoded = jsonEncode(value.map((e) => e.toJson()).toList());
    _cachedChaptersJson = encoded;
    chaptersJson = encoded;
  }

  /// Returns a human-readable reading progress string, or null if never read.
  /// Uses cached chapters to avoid jsonDecode on every call.
  String? get progressLabel {
    if (lastReadPageIndex <= 0) return null;
    final chs = chapters;
    if (chs.isEmpty) return null;
    final idx = lastReadChapterIndex.clamp(0, chs.length - 1);
    final ch = chs[idx];
    final chapterName = ch.name.isNotEmpty ? ch.name : '第${idx + 1}话';
    final pageInfo = ch.pageCount > 0
        ? '$lastReadPageIndex / ${ch.pageCount} 页'
        : '$lastReadPageIndex 页';
    return '$chapterName $pageInfo';
  }

  /// Whether the cover file exists (computed once, call after import).
  bool get coverExists => coverPath.isNotEmpty;
}

class ComicChapter {
  final String name;
  final int order;
  final String folderName;
  final int pageCount;
  final List<String> imageFiles;

  const ComicChapter({
    required this.name,
    required this.order,
    required this.folderName,
    this.pageCount = 0,
    this.imageFiles = const [],
  });

  factory ComicChapter.fromJson(Map<String, dynamic> json) {
    return ComicChapter(
      name: json['name']?.toString() ?? '',
      order: int.tryParse(json['order']?.toString() ?? '') ?? 0,
      folderName: json['folderName']?.toString() ?? '',
      pageCount: int.tryParse(json['pageCount']?.toString() ?? '') ?? 0,
      imageFiles: (json['imageFiles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'order': order,
        'folderName': folderName,
        'pageCount': pageCount,
        'imageFiles': imageFiles,
      };
}

// ── Collections ──

@Entity()
class FavoriteCollection {
  @Id()
  int id;

  @Unique()
  String collectionId;

  String name;
  int displayOrder;

  /// Path to the cover image (first comic's cover) or empty.
  String coverPath;

  FavoriteCollection({
    this.id = 0,
    required this.collectionId,
    required this.name,
    this.displayOrder = 0,
    this.coverPath = '',
  });
}

/// Many-to-many link between collections and comics.
@Entity()
class CollectionEntry {
  @Id()
  int id;

  /// UUID of the [FavoriteCollection].
  String collectionId;

  /// UUID of the [Comic].
  String comicId;

  /// Order within the collection.
  int displayOrder;

  CollectionEntry({
    this.id = 0,
    required this.collectionId,
    required this.comicId,
    this.displayOrder = 0,
  });
}

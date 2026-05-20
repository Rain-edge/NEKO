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
  });

  List<ComicChapter> get chapters {
    if (chaptersJson.isEmpty) return [];
    try {
      final list = jsonDecode(chaptersJson) as List;
      return list
          .map((e) => ComicChapter.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  set chapters(List<ComicChapter> value) {
    chaptersJson = jsonEncode(value.map((e) => e.toJson()).toList());
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'comicId': comicId,
    'title': title,
    'author': author,
    'description': description,
    'coverPath': coverPath,
    'pageCount': pageCount,
    'storagePath': storagePath,
    'chaptersJson': chaptersJson,
    'importedAt': importedAt.toIso8601String(),
    'displayOrder': displayOrder,
    'deleted': deleted,
  };
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
      imageFiles:
          (json['imageFiles'] as List?)
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

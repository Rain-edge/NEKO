import 'package:neko/model/comic.dart';
import 'package:neko/util/path_util.dart';
import 'objectbox.g.dart';

late final ObjectBox objectbox;

class ObjectBox {
  late final Store store;
  late final Box<Comic> comicBox;
  late final Box<FavoriteCollection> collectionBox;
  late final Box<CollectionEntry> entryBox;

  ObjectBox._create(this.store) {
    comicBox = store.box<Comic>();
    collectionBox = store.box<FavoriteCollection>();
    entryBox = store.box<CollectionEntry>();
  }

  static Future<ObjectBox> create() async {
    final dbPath = await getDbPath();
    final store = await openStore(directory: dbPath);
    return ObjectBox._create(store);
  }
}

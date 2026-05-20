import 'package:flutter/material.dart';
import 'package:neko/app.dart';
import 'package:neko/object_box/object_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  objectbox = await ObjectBox.create();
  runApp(const NekoApp());
}

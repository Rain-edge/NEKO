import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:neko/app.dart';
import 'package:neko/object_box/object_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handler: catches async errors that would crash the app
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // Don't crash — log and continue
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true; // true = handled, don't crash
  };

  objectbox = await ObjectBox.create();
  runApp(const NekoApp());
}

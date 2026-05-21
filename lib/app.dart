import 'package:flutter/material.dart';
import 'package:neko/page/main/main_page.dart';
import 'package:neko/page/import/import_page.dart';
import 'package:neko/page/comic_detail/comic_detail_page.dart';
import 'package:neko/page/reader/reader_page.dart';

class NekoApp extends StatelessWidget {
  const NekoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEKO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE91E63),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE91E63),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainPage(),
      routes: {
        '/import': (context) => const ImportPage(),
      },
      onGenerateRoute: (settings) {
        final args = settings.arguments as Map<String, dynamic>? ?? {};

        if (settings.name == '/comic_detail') {
          return MaterialPageRoute(
            builder: (context) => ComicDetailPage(
              comicId: args['comicId'] as String,
            ),
          );
        }

        if (settings.name == '/reader') {
          return MaterialPageRoute(
            builder: (context) => ReaderPage(
              comicId: args['comicId'] as String,
              chapterIndex: args['chapterIndex'] as int? ?? 0,
              pageIndex: args['pageIndex'] as int? ?? 0,
            ),
          );
        }

        return null;
      },
    );
  }
}

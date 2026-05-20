import 'package:flutter/material.dart';
import 'package:neko/page/home/home_page.dart';
import 'package:neko/page/import/import_page.dart';
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
      home: const HomePage(),
      routes: {
        '/import': (context) => const ImportPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/reader') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ReaderPage(
              comicId: args['comicId'] as String,
              chapterIndex: args['chapterIndex'] as int? ?? 0,
            ),
          );
        }
        return null;
      },
    );
  }
}

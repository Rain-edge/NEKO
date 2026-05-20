import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';

class ComicCard extends StatelessWidget {
  final Comic comic;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ComicCard({
    super.key,
    required this.comic,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child:
                  comic.coverPath.isNotEmpty && File(comic.coverPath).existsSync()
                      ? Image.file(
                        File(comic.coverPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, s) => _placeholder(context),
                      )
                      : _placeholder(context),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                comic.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book,
          size: 32,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neko/model/comic.dart';

class ComicCardWidget extends StatelessWidget {
  final Comic comic;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isDragged;

  const ComicCardWidget({
    super.key,
    required this.comic,
    this.onTap,
    this.onLongPress,
    this.isDragged = false,
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
            Expanded(child: _buildCover(context)),
            Padding(
              padding: const EdgeInsets.all(6),
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

  Widget _buildCover(BuildContext context) {
    if (comic.coverPath.isEmpty) {
      return _placeholder(context);
    }

    final progress = comic.progressLabel;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(comic.coverPath),
          fit: BoxFit.cover,
          cacheWidth: 320,
          frameBuilder: (context, child, frame, _) {
            if (frame == null) return _placeholder(context);
            return child;
          },
          errorBuilder: (_, __, ___) => _placeholder(context),
        ),
        if (progress != null)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Text(progress,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(BuildContext context) {
    final progress = comic.progressLabel;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(Icons.menu_book, size: 40,
                color: Theme.of(context).colorScheme.outline),
          ),
          if (progress != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Text(progress,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}

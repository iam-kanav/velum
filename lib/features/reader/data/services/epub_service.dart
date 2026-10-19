import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A parsed book: chapter text is loaded up front, images are read from the
/// archive only when a chapter needs them.
class OpenedBook {
  /// Title, author and chapters (with HTML). Content/images are not loaded.
  final EpubBook book;
  final List<String> imageNames;
  final List<int>? Function(String imageName) readImage;

  const OpenedBook(this.book, this.imageNames, this.readImage);
}

class EpubService {
  const EpubService();

  /// Open an EPUB from the asset bundle (path starts with 'assets/') or a file.
  Future<OpenedBook> parseEpub(String path) async {
    final Uint8List bytes;
    try {
      if (path.startsWith('assets/')) {
        bytes = (await rootBundle.load(path)).buffer.asUint8List();
      } else {
        final file = File(path);
        if (!await file.exists()) throw Exception('File not found: $path');
        bytes = await file.readAsBytes();
      }

      // Chapter HTML is read in a background isolate while the archive index
      // (cheap: no decompression) is opened here for on-demand image reads.
      // Images, fonts, CSS and the decoded cover are never loaded up front.
      final chaptersFuture = compute(_readChaptersIsolate, bytes);
      final bookRef = await EpubReader.openBook(bytes);
      final book = await chaptersFuture;

      final images = bookRef.Content?.Images ?? const {};
      List<int>? readImage(String name) {
        try {
          return images[name]?.getContentFileEntry().content as List<int>?;
        } catch (_) {
          return null;
        }
      }

      return OpenedBook(book, images.keys.toList(), readImage);
    } catch (e) {
      throw Exception('Failed to parse EPUB: $e');
    }
  }
}

/// Top-level so it can run in an isolate: title, author and chapter HTML only.
Future<EpubBook> _readChaptersIsolate(Uint8List bytes) async {
  final bookRef = await EpubReader.openBook(bytes);
  return EpubBook()
    ..Title = bookRef.Title
    ..Author = bookRef.Author
    ..AuthorList = bookRef.AuthorList
    ..Chapters = flattenChapters(
        await EpubReader.readChapters(await bookRef.getChapters()));
}

/// The reader works on a flat chapter list, but many EPUBs nest chapters
/// under parts ("Book 1" > "Chapter 1", ...). Flatten them in reading order.
/// A parent that only points at its first child's file (no content of its
/// own) is dropped so that chapter isn't listed and read twice.
@visibleForTesting
List<EpubChapter> flattenChapters(List<EpubChapter> chapters) {
  final flat = <EpubChapter>[];
  for (final chapter in chapters) {
    final children = chapter.SubChapters ?? const <EpubChapter>[];
    final sameAsFirstChild = children.isNotEmpty &&
        children.first.ContentFileName == chapter.ContentFileName &&
        children.first.Anchor == chapter.Anchor;
    if (!sameAsFirstChild) flat.add(chapter);
    flat.addAll(flattenChapters(children));
    chapter.SubChapters = [];
  }
  return flat;
}

import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'chapter_processor.dart';

/// A parsed book: chapter text is loaded up front, images are read from the
/// archive only when a chapter needs them.
class OpenedBook {
  /// Title and chapters (with HTML). Content/images are not loaded.
  final EpubBook book;
  final List<String> imageNames;
  final List<int>? Function(String imageName) readImage;

  const OpenedBook(this.book, this.imageNames, this.readImage);
}

class EpubService {
  const EpubService();

  /// Open the EPUB file at [path].
  Future<OpenedBook> parseEpub(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) throw Exception('File not found: $path');
      final bytes = await file.readAsBytes();

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

/// Top-level so it can run in an isolate: title and chapter HTML only.
Future<EpubBook> _readChaptersIsolate(Uint8List bytes) async {
  final bookRef = await EpubReader.openBook(bytes);

  // Each file is read once, however many contents entries point into it
  // and whether or not it is also in the reading order.
  final texts = <String?, String>{};
  Future<String> read(String? file, Future<String> Function() load) async =>
      texts[file] ??= await load();

  final chapters = flattenChapters(
    await _readChapters(await bookRef.getChapters(), read),
  );

  // The reading order (spine) as HTML file names, with each file's HTML.
  final htmlRefs = {
    for (final e in (bookRef.Content?.Html ?? const {}).entries)
      _decode(e.key): e.value,
  };
  final manifest = {
    for (final item in bookRef.Schema?.Package?.Manifest?.Items ?? const [])
      item.Id: item.Href,
  };
  final spine = <String>[];
  final html = <String, String>{};
  // Every spine item counts: epubx reads the linear attribute backwards.
  for (final item in bookRef.Schema?.Package?.Spine?.Items ?? const []) {
    final href = manifest[item.IdRef];
    if (href == null) continue;
    final name = _decode(href);
    final ref = htmlRefs[name];
    if (ref == null || html.containsKey(name)) continue;
    try {
      html[name] = await read(ref.FileName, ref.readContentAsText);
      spine.add(name);
    } catch (_) {}
  }

  return EpubBook()
    ..Title = bookRef.Title
    ..Chapters = chapters.isEmpty
        ? chaptersFromSpine(spine, html)
        : followReadingOrder(chapters, spine, html);
}

/// The contents entries [refs] as chapters with their HTML, like epubx's
/// `EpubReader.readChapters` but reading each file through [read].
Future<List<EpubChapter>> _readChapters(
  List<EpubChapterRef> refs,
  Future<String> Function(String? file, Future<String> Function() load) read,
) async {
  final chapters = <EpubChapter>[];
  for (final ref in refs) {
    chapters.add(
      EpubChapter()
        ..Title = ref.Title
        ..ContentFileName = ref.ContentFileName
        ..Anchor = ref.Anchor
        ..HtmlContent = await read(
          ref.epubTextContentFileRef!.FileName,
          ref.readHtmlContent,
        )
        ..SubChapters = await _readChapters(ref.SubChapters ?? const [], read),
    );
  }
  return chapters;
}

/// A book with no table of contents is read file by file, in its reading
/// order ([spine], with each file's HTML in [html]).
@visibleForTesting
List<EpubChapter> chaptersFromSpine(
  List<String> spine,
  Map<String, String> html,
) => [
  for (var i = 0; i < spine.length; i++)
    EpubChapter()
      ..Title = 'Chapter ${i + 1}'
      ..ContentFileName = spine[i]
      ..HtmlContent = html[spine[i]]
      ..SubChapters = [],
];

String _decode(String path) {
  try {
    return Uri.decodeFull(path);
  } catch (_) {
    return path;
  }
}

/// A place in the reading order: a spine file, and the element (in document
/// order) a chapter starts at there, or -1 for the top of the file.
typedef _Position = (int file, int element);

int _compare(_Position a, _Position b) =>
    a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2;

/// Make each chapter run from where its table-of-contents entry points to
/// where the next entry starts, in the book's reading order ([spine], with
/// each file's HTML in [html]).
///
/// Chapters come from the table of contents, which often skips files (a
/// chapter split over several files lists only the first) and can point
/// into the middle of a file (`chapter.xhtml#scene2`). Taking each entry's
/// whole file then drops the unlisted files and repeats the shared ones.
/// A chapter that is exactly one whole file keeps its HTML untouched;
/// spine files before the first entry stay out, as before.
@visibleForTesting
List<EpubChapter> followReadingOrder(
  List<EpubChapter> chapters,
  List<String> spine,
  Map<String, String> html,
) {
  final fileIndex = {for (var i = 0; i < spine.length; i++) spine[i]: i};
  final bodies = <int, dom.Element?>{};
  dom.Element? body(int file) => bodies.putIfAbsent(
    file,
    () => html_parser
        .parse(ChapterProcessor.expandSelfClosing(html[spine[file]] ?? ''))
        .body,
  );
  final elementOrders = <int, Map<String, int>>{};
  int elementOrder(int file, String id) {
    final ids = elementOrders.putIfAbsent(file, () {
      final all = body(file)?.querySelectorAll('*') ?? const [];
      final order = <String, int>{};
      for (var i = 0; i < all.length; i++) {
        if (all[i].id.isNotEmpty) order[all[i].id] = i;
      }
      // Older books mark places with <a name="x"> instead of an id.
      for (var i = 0; i < all.length; i++) {
        final name = all[i].localName == 'a' ? all[i].attributes['name'] : null;
        if (name != null && name.isNotEmpty) order.putIfAbsent(name, () => i);
      }
      return order;
    });
    return ids[id] ?? -1;
  }

  _Position? positionOf(EpubChapter chapter) {
    final file = fileIndex[_decode(chapter.ContentFileName ?? '')];
    if (file == null) return null;
    final anchor = chapter.Anchor;
    return (
      file,
      anchor == null || anchor.isEmpty ? -1 : elementOrder(file, anchor),
    );
  }

  final positions = chapters.map(positionOf).toList();
  final starts = positions.whereType<_Position>().toSet().toList()
    ..sort(_compare);
  final end = (spine.length, -1);

  return [
    for (var i = 0; i < chapters.length; i++)
      if (positions[i] case final start?)
        _withHtml(
          chapters[i],
          _slice(
            start,
            starts.firstWhere((p) => _compare(p, start) > 0, orElse: () => end),
            spine,
            html,
            body,
          ),
        )
      else
        chapters[i],
  ];
}

EpubChapter _withHtml(EpubChapter chapter, String? html) {
  if (html != null) chapter.HtmlContent = html;
  return chapter;
}

/// The HTML from [start] up to (not including) [end], or null when that is
/// one whole file, whose HTML is then used as it is.
String? _slice(
  _Position start,
  _Position end,
  List<String> spine,
  Map<String, String> html,
  dom.Element? Function(int file) body,
) {
  final wholeFile =
      start.$2 == -1 &&
      (end.$1 == start.$1 + 1 && end.$2 == -1 ||
          end.$1 == spine.length && start.$1 == spine.length - 1);
  if (wholeFile) return null;

  final parts = StringBuffer();
  final lastFile = end.$2 == -1 ? end.$1 - 1 : end.$1;
  for (var file = start.$1; file <= lastFile && file < spine.length; file++) {
    final original = body(file);
    if (original == null) continue;
    final piece = original.clone(true);
    final all = piece.querySelectorAll('*');
    if (file == lastFile && file == end.$1 && end.$2 >= 0) {
      _cutFrom(all[end.$2], piece);
    }
    if (file == start.$1 && start.$2 >= 0) _cutBefore(all[start.$2], piece);
    parts.write(piece.innerHtml);
  }
  return '<html><head></head><body>$parts</body></html>';
}

/// Remove everything before [element] in document order, keeping the
/// elements around it.
void _cutBefore(dom.Element element, dom.Element root) {
  dom.Node node = element;
  while (node != root && node.parentNode != null) {
    final parent = node.parentNode!;
    parent.nodes.removeRange(0, parent.nodes.indexOf(node));
    node = parent;
  }
}

/// Remove [element] and everything after it in document order.
void _cutFrom(dom.Element element, dom.Element root) {
  dom.Node node = element;
  var first = true;
  while (node != root && node.parentNode != null) {
    final parent = node.parentNode!;
    final index = parent.nodes.indexOf(node);
    parent.nodes.removeRange(first ? index : index + 1, parent.nodes.length);
    first = false;
    node = parent;
  }
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
    final sameAsFirstChild =
        children.isNotEmpty &&
        children.first.ContentFileName == chapter.ContentFileName &&
        children.first.Anchor == chapter.Anchor;
    if (!sameAsFirstChild) flat.add(chapter);
    flat.addAll(flattenChapters(children));
    chapter.SubChapters = [];
  }
  return flat;
}

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:uuid/uuid.dart';

/// A text the user typed or pasted into Velum ("New File").
class Note {
  final String title;
  final String html;

  const Note(this.title, this.html);
}

/// Stores notes so they can be read and listened to like any book.
///
/// Each note is two files in `<documents>/notes/`: `<id>.epub`, a one-chapter
/// EPUB the reader opens like any other book, and `<id>.json`, the editable
/// source (title + HTML) used when the note is edited again.
class NoteService {
  const NoteService();

  /// Whether [path] is a note created in Velum (and so can be edited).
  static bool isNote(String path) =>
      p.basename(p.dirname(path)) == 'notes' && path.endsWith('.epub');

  Future<Directory> _dir() async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'notes'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _sourcePath(String epubPath) =>
      p.setExtension(epubPath, '.json');

  /// The editable source of the note at [epubPath], if it has one.
  Future<Note?> load(String epubPath) async {
    try {
      final json = jsonDecode(await File(_sourcePath(epubPath)).readAsString())
          as Map<String, dynamic>;
      return Note(json['title'] as String, json['html'] as String);
    } catch (_) {
      return null;
    }
  }

  /// Save [note], replacing the note at [epubPath] if given. Returns the
  /// path of the note's EPUB.
  Future<String> save(Note note, {String? epubPath}) async {
    epubPath ??= p.join((await _dir()).path, '${const Uuid().v4()}.epub');
    await File(epubPath).writeAsBytes(buildEpub(note), flush: true);
    await File(_sourcePath(epubPath)).writeAsString(
      jsonEncode({'title': note.title, 'html': note.html}),
      flush: true,
    );
    return epubPath;
  }

  Future<void> delete(String epubPath) async {
    for (final path in [epubPath, _sourcePath(epubPath)]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// A minimal EPUB 2 book: one chapter holding the note's HTML.
  @visibleForTesting
  static List<int> buildEpub(Note note) {
    final title = _xml(note.title);
    final id = const Uuid().v4();
    final body = html_parser.parseFragment(note.html).outerHtml
        // XHTML needs void elements closed.
        .replaceAllMapped(
          RegExp(r'<(br|hr)(\s[^>]*)?>', caseSensitive: false),
          (m) => '<${m[1]}${m[2] ?? ''}/>',
        );

    final files = <String, String>{
      'META-INF/container.xml': '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
      'OEBPS/content.opf': '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>Your file</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">urn:uuid:$id</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="text" href="text.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="text"/>
  </spine>
</package>''',
      'OEBPS/toc.ncx': '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:$id"/></head>
  <docTitle><text>$title</text></docTitle>
  <navMap>
    <navPoint id="text" playOrder="1">
      <navLabel><text>$title</text></navLabel>
      <content src="text.xhtml"/>
    </navPoint>
  </navMap>
</ncx>''',
      'OEBPS/text.xhtml': '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title></head>
<body>
$body
</body>
</html>''',
    };

    final archive = Archive();
    // The mimetype entry must come first and be stored uncompressed.
    final mimetype = utf8.encode('application/epub+zip');
    archive.addFile(
      ArchiveFile('mimetype', mimetype.length, mimetype)..compress = false,
    );
    files.forEach((name, text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return ZipEncoder().encode(archive)!;
  }

  static String _xml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

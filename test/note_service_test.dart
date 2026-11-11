import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velum/features/notes/data/note_service.dart';
import 'package:velum/features/reader/data/services/chapter_processor.dart';

void main() {
  test('a note becomes a one-chapter EPUB the reader can open', () async {
    const note = Note(
      'Notes & <Ideas>',
      '<h1>Plan</h1><p>First line.<br>Second line.</p>'
          '<ul><li>Apples</li><li>Pears</li></ul><hr>',
    );
    final book = await EpubReader.openBook(NoteService.buildEpub(note));
    final chapters = await book.getChapters();

    expect(book.Title, 'Notes & <Ideas>');
    expect(chapters, hasLength(1));
    final html = await chapters.single.readHtmlContent();
    expect(html, contains('<h1>Plan</h1>'));
    expect(html, contains('<li>Apples</li>'));
    expect(html, contains('<br/>'));

    final (_, paragraphs) = ChapterProcessor.process(html);
    expect(paragraphs.map((p) => p.text), [
      'Plan',
      'First line. Second line.',
      'Apples',
      'Pears',
    ]);
  });

  test('saving replaces a note in place and leaves no temporary files',
      () async {
    final dir = await Directory.systemTemp.createTemp('velum_note_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/abc.epub';
    const notes = NoteService();

    await notes.save(const Note('First', '<p>One</p>'), epubPath: path);
    await notes.save(const Note('Second', '<p>Two</p>'), epubPath: path);

    expect((await notes.load(path))?.title, 'Second');
    expect((await EpubReader.openBook(File(path).readAsBytesSync())).Title,
        'Second');
    expect(
      dir.listSync().map((f) => f.uri.pathSegments.last).toSet(),
      {'abc.epub', 'abc.json'},
    );
  });

  test('notes are recognised by their folder', () {
    expect(NoteService.isNote('/data/app/notes/abc.epub'), isTrue);
    expect(NoteService.isNote('/storage/Download/book.epub'), isFalse);
    expect(NoteService.isNote('/data/app/notes/abc.json'), isFalse);
  });
}

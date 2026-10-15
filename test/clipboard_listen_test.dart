import 'package:flutter_test/flutter_test.dart';
import 'package:velum/features/notes/data/clipboard_listen.dart';

void main() {
  test('copied text becomes a note: a paragraph per line, titled by the first',
      () {
    final note = ClipboardListen.noteFromText(
      '  Chapter One  \r\n\r\nIt was a <dark> & stormy night.\nThe end.\n',
    );
    expect(note.title, 'Chapter One');
    expect(
      note.html,
      '<p>Chapter One</p>\n'
      '<p>It was a &lt;dark&gt; &amp; stormy night.</p>\n'
      '<p>The end.</p>',
    );
  });

  test('a long first line is cut at a word for the title', () {
    final note = ClipboardListen.noteFromText(
      'The quick brown fox jumps over the lazy dog and keeps on running '
      'far past the edge of the field.',
    );
    expect(note.title, 'The quick brown fox jumps over the lazy dog and keeps on…');
    expect(note.title.length, lessThanOrEqualTo(61));
  });
}

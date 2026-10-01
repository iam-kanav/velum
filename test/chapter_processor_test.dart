import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:velum/features/reader/data/services/chapter_processor.dart';
import 'package:velum/features/tts/data/models/tts_chunk.dart';
import 'package:velum/features/tts/data/models/tts_settings.dart';

/// Process [html] and check the core invariant: every paragraph/sentence the
/// voice will speak is exactly the text of the element the page highlights.
List<TtsParagraph> processAndCheck(String html) {
  final (output, paragraphs) = ChapterProcessor.process(html);
  final body = html_parser.parse(output).body!;

  expect(
    body.querySelectorAll('.tts-sent .tts-sent'),
    isEmpty,
    reason:
        'sentence spans must never nest (nested spans make text be read twice)',
  );

  final paraEls = body.querySelectorAll('.tts-para');
  expect(
    paraEls.length,
    paragraphs.length,
    reason: 'one element per paragraph',
  );

  String norm(String t) => t.replaceAll(RegExp(r'\s+'), ' ').trim();

  for (var i = 0; i < paragraphs.length; i++) {
    final el = paraEls[i];
    expect(el.attributes['data-para'], '$i');
    expect(el.text.trim(), paragraphs[i].text);

    final sentences = paragraphs[i].sentences;
    if (sentences.isEmpty) {
      expect(el.querySelectorAll('[data-sent]'), isEmpty);
      continue;
    }
    // Every sentence's pieces on the page spell exactly its spoken text.
    for (final s in sentences) {
      final pieces = el.querySelectorAll('[data-sent="${s.index}"]');
      expect(pieces, isNotEmpty, reason: 'spans for sentence ${s.index}');
      expect(pieces.every((p) => p.attributes['data-para'] == '$i'), isTrue);
      expect(norm(pieces.map((p) => p.text).join()), norm(s.text));
    }
    // The sentences together are the paragraph: nothing missing, nothing twice.
    expect(
      norm(sentences.map((s) => s.text).join(' ')),
      norm(paragraphs[i].text),
    );
  }
  return paragraphs;
}

List<String> sentenceTexts(TtsParagraph p) =>
    p.sentences.map((s) => s.text).toList();

void main() {
  group('sentence alignment', () {
    test('sentences across inline tags stay aligned', () {
      final paras = processAndCheck(
        '<p>Hello there. How are <i>you</i>? <b>Fine.</b> Thanks!</p>',
      );
      expect(sentenceTexts(paras.single), [
        'Hello there.',
        'How are you?',
        'Fine.',
        'Thanks!',
      ]);
    });

    test('sentence breaks inside an inline tag stay aligned', () {
      final paras = processAndCheck(
        '<p><i>One thing. Another thing.</i> A third thing.</p>',
      );
      expect(sentenceTexts(paras.single), [
        'One thing.',
        'Another thing.',
        'A third thing.',
      ]);
    });

    test('a sentence break inside formatting is not read twice', () {
      // Real case from Pride and Prejudice that made the voice read the whole
      // paragraph and then repeat part of it.
      final paras = processAndCheck(
        '<p class="r">\u201C<span class="smcap">Edw. Gardiner</span>.\u201D<br/></p>',
      );
      expect(sentenceTexts(paras.single), ['\u201CEdw.', 'Gardiner.\u201D']);
    });

    test('a sentence crossing formatting is marked in several pieces', () {
      final paras = processAndCheck(
        '<p>He said <i>no. Then he</i> left quietly. Done.</p>',
      );
      expect(sentenceTexts(paras.single), [
        'He said no.',
        'Then he left quietly.',
        'Done.',
      ]);
    });

    test('punctuation inside tag attributes does not split', () {
      final paras = processAndCheck(
        '<p>Visit <a href="https://www.gutenberg.org/a.b.html">www.gutenberg.org</a>. '
        'If you are not located in the United States, check the laws.</p>',
      );
      expect(sentenceTexts(paras.single), [
        'Visit www.gutenberg.org.',
        'If you are not located in the United States, check the laws.',
      ]);
    });

    test('closing quotes stay with their sentence', () {
      final paras = processAndCheck(
        '<p>“Curiouser and curiouser!” cried Alice. She stared.</p>',
      );
      expect(sentenceTexts(paras.single), [
        '“Curiouser and curiouser!”',
        'cried Alice.',
        'She stared.',
      ]);
    });

    test('common abbreviations do not end a sentence', () {
      final paras = processAndCheck(
        '<p>Mr. Darcy met Mrs. Bennet and Dr. Jones. They talked.</p>',
      );
      expect(sentenceTexts(paras.single), [
        'Mr. Darcy met Mrs. Bennet and Dr. Jones.',
        'They talked.',
      ]);
    });

    test('a one-sentence paragraph has no sentence spans', () {
      final paras = processAndCheck('<p>Just one line.</p><h2>Title</h2>');
      expect(paras.map((p) => p.text), ['Just one line.', 'Title']);
      expect(paras.every((p) => p.sentences.isEmpty), isTrue);
    });
  });

  group('paragraph detection', () {
    test('wrapper divs are not read as an extra paragraph', () {
      final paras = processAndCheck(
        '<div class="chapter"><div><p>First.</p><p>Second.</p></div></div>',
      );
      expect(paras.map((p) => p.text), ['First.', 'Second.']);
    });

    test('loose text next to paragraphs is read, in order', () {
      final paras = processAndCheck(
        '<div>Intro <em>text</em><p>Middle.</p>Outro text</div>',
      );
      expect(paras.map((p) => p.text), ['Intro text', 'Middle.', 'Outro text']);
    });

    test('loose text directly in the body is read', () {
      final paras = processAndCheck('Before<p>Inside.</p>After');
      expect(paras.map((p) => p.text), ['Before', 'Inside.', 'After']);
    });

    test('table cells are read', () {
      final paras = processAndCheck(
        '<table><tr><td>Cell one.</td><td>Cell two.</td></tr></table>',
      );
      expect(paras.map((p) => p.text), ['Cell one.', 'Cell two.']);
    });

    test('document head is never read', () {
      final paras = processAndCheck(
        '<html><head><title>Book title</title></head>'
        '<body><p>Body text.</p></body></html>',
      );
      expect(paras.map((p) => p.text), ['Body text.']);
    });

    test('whitespace-only blocks are skipped', () {
      final paras = processAndCheck('<p>   </p><p>Real.</p><div>\n</div>');
      expect(paras.map((p) => p.text), ['Real.']);
    });
  });

  group('chunking', () {
    final (_, paragraphs) = ChapterProcessor.process(
      '<h1>Chapter One</h1><p>A first. A second.</p><p>Alone.</p>',
    );

    test('sentence mode speaks each sentence with its page position', () {
      final chunks = chunkParagraphs(paragraphs, TtsHighlightMode.sentence);
      expect(chunks.map((c) => (c.text, c.paragraphIndex, c.sentenceIndex)), [
        ('Chapter One', 0, null),
        ('A first.', 1, 0),
        ('A second.', 1, 1),
        ('Alone.', 2, null),
      ]);
    });

    test('paragraph mode speaks whole paragraphs', () {
      final chunks = chunkParagraphs(paragraphs, TtsHighlightMode.paragraph);
      expect(chunks.map((c) => (c.text, c.paragraphIndex, c.sentenceIndex)), [
        ('Chapter One', 0, null),
        ('A first. A second.', 1, null),
        ('Alone.', 2, null),
      ]);
    });
  });
}

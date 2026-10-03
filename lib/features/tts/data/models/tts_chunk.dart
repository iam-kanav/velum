import 'tts_settings.dart';

/// A sentence inside a paragraph. [index] matches the `data-sent` attribute
/// of the span the reader page renders for it.
typedef TtsSentence = ({int index, String text});

/// One readable block of a chapter. Its position in the list matches the
/// `data-para` attribute in the rendered page, and [sentences] is empty when
/// the paragraph wasn't split into sentence spans.
class TtsParagraph {
  final String text;
  final List<TtsSentence> sentences;

  const TtsParagraph(this.text, [this.sentences = const []]);
}

/// A piece of text spoken in one go, with the page position it highlights.
class TtsChunk {
  final String text;
  final int paragraphIndex;
  final int? sentenceIndex; // null when the whole paragraph is one chunk

  const TtsChunk({
    required this.text,
    required this.paragraphIndex,
    this.sentenceIndex,
  });
}

/// Split paragraphs into speakable chunks for the given highlight mode.
List<TtsChunk> chunkParagraphs(
  List<TtsParagraph> paragraphs,
  TtsHighlightMode mode,
) {
  final chunks = <TtsChunk>[];
  for (int p = 0; p < paragraphs.length; p++) {
    final para = paragraphs[p];
    if (mode == TtsHighlightMode.paragraph || para.sentences.isEmpty) {
      chunks.add(TtsChunk(text: para.text, paragraphIndex: p));
    } else {
      for (final s in para.sentences) {
        chunks.add(
          TtsChunk(text: s.text, paragraphIndex: p, sentenceIndex: s.index),
        );
      }
    }
  }
  return chunks;
}

/// The book being read aloud. Reading carries on into its next chapters
/// even after the reader screen is closed, so it needs its own way to get
/// each chapter's text.
class ReadAloudBook {
  final String path;
  final String title;
  final List<String> chapterTitles;

  /// Paragraphs of a chapter, indexed like the reader page's `data-para`.
  final List<TtsParagraph> Function(int chapter) paragraphsFor;

  /// Called when reading moves on to a chapter by itself, so the book
  /// reopens there.
  final void Function(int chapter) onChapterStarted;

  const ReadAloudBook({
    required this.path,
    required this.title,
    required this.chapterTitles,
    required this.paragraphsFor,
    required this.onChapterStarted,
  });
}

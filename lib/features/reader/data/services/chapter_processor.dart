import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../../../tts/data/models/tts_chunk.dart';

/// Prepares chapter HTML for read-aloud: wraps each sentence in a span and
/// returns the matching spoken text, built in the same pass so the voice and
/// the highlight always refer to the same sentence.
class ChapterProcessor {
  const ChapterProcessor._();

  /// Elements whose text is read aloud as one paragraph.
  static const blockSelector =
      'p, div, h1, h2, h3, h4, h5, h6, li, blockquote, '
      'td, th, dt, dd, figcaption, pre';

  /// Returns the processed body HTML and its paragraphs. Paragraph i matches
  /// `data-para="i"`; sentence s of it matches `data-sent="s"`.
  static (String, List<TtsParagraph>) process(String htmlContent) {
    final body = html_parser.parse(htmlContent).body;
    if (body == null) return (htmlContent, const []);

    _wrapLooseText(body);

    final paragraphs = <TtsParagraph>[];
    for (final p in leafBlocks(body)) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      final paraIndex = paragraphs.length;

      final sentences = splitHtmlIntoSentences(p.innerHtml);
      final spoken = <TtsSentence>[];
      if (sentences.length > 1) {
        final newInnerHtml = StringBuffer();
        for (int sIdx = 0; sIdx < sentences.length; sIdx++) {
          final sentence = sentences[sIdx];
          if (sentence.trim().isEmpty) continue;
          newInnerHtml.write(
            '<span class="tts-sent" data-para="$paraIndex" data-sent="$sIdx">$sentence</span>',
          );
          if (sIdx < sentences.length - 1) newInnerHtml.write(' ');
        }
        p.innerHtml = newInnerHtml.toString();
        // Read the sentences back from the parsed spans: that's exactly the
        // text the page shows for each data-sent index.
        final seen = <int>{};
        for (final span in p.querySelectorAll('span.tts-sent')) {
          final idx = int.tryParse(span.attributes['data-sent'] ?? '');
          final spanText = span.text.trim();
          if (idx != null && spanText.isNotEmpty && seen.add(idx)) {
            spoken.add((index: idx, text: spanText));
          }
        }
      }
      p.attributes['data-para'] = paraIndex.toString();
      p.classes.add('tts-para');
      paragraphs.add(TtsParagraph(text, spoken));
    }

    return (body.innerHtml, paragraphs);
  }

  /// Block elements that contain no other matched block, so wrapper divs
  /// aren't read as one giant paragraph. Linear in elements × depth.
  static List<dom.Element> leafBlocks(dom.Element root) {
    final elements = root.querySelectorAll(blockSelector);
    final hasBlockChild = _blockAncestors(elements, root);
    return elements.where((el) => !hasBlockChild.contains(el)).toList();
  }

  /// Every element from [root] down that contains one of [elements].
  static Set<dom.Element> _blockAncestors(
    List<dom.Element> elements,
    dom.Element root,
  ) {
    final stop = root.parent;
    final ancestors = <dom.Element>{};
    for (final el in elements) {
      for (var node = el.parent;
          node != null && !identical(node, stop);
          node = node.parent) {
        if (!ancestors.add(node)) break;
      }
    }
    return ancestors;
  }

  /// Text sitting directly next to block elements (e.g. `<div>Intro<p>…</p>
  /// More</div>`) belongs to no leaf block and would never be read. Wrap each
  /// such run of inline content in its own div, which the browser lays out
  /// the same way (as an anonymous block).
  static void _wrapLooseText(dom.Element body) {
    final blocks = body.querySelectorAll(blockSelector);
    if (blocks.isEmpty) return;
    final containers = _blockAncestors(blocks, body);
    final structural = {...blocks, ...containers};

    for (final container in containers) {
      final run = <dom.Node>[];
      void flush() {
        if (run.any((n) => (n.text ?? '').trim().isNotEmpty)) {
          final wrapper = dom.Element.tag('div')..classes.add('tts-loose');
          container.insertBefore(wrapper, run.first);
          for (final n in run) {
            wrapper.append(n.remove());
          }
        }
        run.clear();
      }

      for (final node in container.nodes.toList()) {
        final isInline = node is dom.Text ||
            (node is dom.Element && !structural.contains(node));
        if (isInline) {
          run.add(node);
        } else {
          flush();
        }
      }
      flush();
    }
  }

  static const _closers = {'"', "'", '”', '’', ')', ']'};
  static const _abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr', 'prof', 'mt', 'vs', 'etc',
  };

  static final _letter = RegExp(r'[A-Za-z]');

  static bool _isSpace(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '\r';

  /// Split an HTML string into sentences, preserving inner tags.
  /// A sentence ends at . ! or ? (plus any closing quotes, brackets or tags)
  /// followed by whitespace, outside of tags and not after a common
  /// abbreviation.
  static List<String> splitHtmlIntoSentences(String html) {
    final sentences = <String>[];
    final current = StringBuffer();
    bool inTag = false;

    int i = 0;
    while (i < html.length) {
      final char = html[i];
      current.write(char);

      if (char == '<') {
        inTag = true;
      } else if (char == '>') {
        inTag = false;
      } else if (!inTag &&
          (char == '.' || char == '!' || char == '?') &&
          !(char == '.' && _followsAbbreviation(html, i))) {
        // Keep closing quotes/brackets and closing tags (e.g. `.</i>`) with
        // the sentence they end.
        var end = i + 1;
        while (end < html.length) {
          if (_closers.contains(html[end])) {
            end++;
          } else if (html.startsWith('</', end) && html.indexOf('>', end) != -1) {
            end = html.indexOf('>', end) + 1;
          } else {
            break;
          }
        }
        if (end < html.length && _isSpace(html[end])) {
          current.write(html.substring(i + 1, end));
          sentences.add(current.toString());
          current.clear();
          i = end;
          while (i < html.length && _isSpace(html[i])) {
            i++;
          }
          continue;
        }
      }
      i++;
    }

    if (current.isNotEmpty) sentences.add(current.toString());
    return sentences;
  }

  /// True when the '.' at [dot] ends a word like "Mr" or "etc".
  static bool _followsAbbreviation(String html, int dot) {
    var start = dot;
    while (start > 0 && _letter.hasMatch(html[start - 1])) {
      start--;
    }
    if (start == dot) return false;
    return _abbreviations.contains(html.substring(start, dot).toLowerCase());
  }
}

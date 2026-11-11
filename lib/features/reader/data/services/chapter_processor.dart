import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../../../tts/data/models/tts_chunk.dart';

/// Prepares chapter HTML for read-aloud: marks each sentence on the page and
/// returns the matching spoken text, built in the same pass so the voice and
/// the highlight always refer to the same sentence.
///
/// Sentences are marked by splitting text nodes, never by cutting HTML apart,
/// so markup is untouched and spans can never nest. A sentence that crosses
/// inline formatting (`Mr. <i>Darcy. He</i> left.`) gets one span per piece,
/// all sharing the same data-sent index.
class ChapterProcessor {
  const ChapterProcessor._();

  /// Elements whose text is read aloud as one paragraph.
  static const blockSelector =
      'p, div, h1, h2, h3, h4, h5, h6, li, blockquote, '
      'td, th, dt, dd, figcaption, pre';

  /// Returns the processed body HTML and its paragraphs. Paragraph i matches
  /// `data-para="i"`; sentence s of it matches `data-sent="s"`.
  static (String, List<TtsParagraph>) process(String htmlContent) {
    final body = html_parser.parse(expandSelfClosing(htmlContent)).body;
    if (body == null) return (htmlContent, const []);

    _removeScripts(body);
    _wrapLooseText(body);

    final paragraphs = <TtsParagraph>[];
    for (final p in leafBlocks(body)) {
      final (plain, nodes, starts) = _blockText(p);
      final text = plain.trim();
      if (text.isEmpty) continue;
      final paraIndex = paragraphs.length;

      final spoken = _wrapSentences(plain, nodes, starts, paraIndex);
      p.attributes['data-para'] = paraIndex.toString();
      p.classes.add('tts-para');
      paragraphs.add(TtsParagraph(text, spoken));
    }

    return (body.innerHtml, paragraphs);
  }

  /// Elements that never have content, so `<br/>` already means `<br>`.
  static const _voidElements = {
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link',
    'meta', 'param', 'source', 'track', 'wbr',
  };

  /// A tag closed with `/>`: its name, then its attributes (quoted values
  /// may hold any character).
  static final _selfClosed = RegExp(
    r"""<([A-Za-z][\w:.-]*)((?:[^<>"'/]|"[^"]*"|'[^']*'|/(?!>))*)/>""",
  );

  /// EPUB chapters are XHTML, where `<a id="x"/>` or `<title/>` is a whole
  /// element. The HTML parser reads those as opening tags, which wraps the
  /// rest of the chapter in a link or swallows it into the title. Write them
  /// out as `<a id="x"></a>` before parsing.
  static String expandSelfClosing(String xhtml) {
    if (!xhtml.contains('/>')) return xhtml;
    return xhtml.replaceAllMapped(_selfClosed, (m) {
      final name = m[1]!;
      if (_voidElements.contains(name.toLowerCase())) return m[0]!;
      return '<$name${m[2]}></$name>';
    });
  }

  /// The page a book is shown in can talk to the app, so nothing from the
  /// book may run there: drop scripts, inline event handlers and
  /// `javascript:` links. Scripts would otherwise be read aloud as well.
  static void _removeScripts(dom.Element body) {
    for (final el in body.querySelectorAll('*')) {
      if (el.localName == 'script') {
        el.remove();
        continue;
      }
      el.attributes.removeWhere((name, value) {
        final key = name is dom.AttributeName ? name.name : name as String;
        return key.toLowerCase().startsWith('on') || _isScriptUrl(value);
      });
    }
  }

  /// True for a `javascript:` URL as a browser reads it: any case, with
  /// whitespace and control characters skipped.
  static bool _isScriptUrl(String value) {
    const scheme = 'javascript:';
    var matched = 0;
    for (var i = 0; i < value.length && matched < scheme.length; i++) {
      final c = value.codeUnitAt(i);
      if (c <= 0x20) continue;
      if ((c | 0x20) != scheme.codeUnitAt(matched)) return false;
      matched++;
    }
    return matched == scheme.length;
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
  /// More</div>`), or in a body with no blocks at all (a note typed as one
  /// line), belongs to no leaf block and would never be read. Wrap each such
  /// run of inline content in its own div, which the browser lays out the
  /// same way (as an anonymous block).
  static void _wrapLooseText(dom.Element body) {
    final blocks = body.querySelectorAll(blockSelector);
    final containers =
        blocks.isEmpty ? {body} : _blockAncestors(blocks, body);
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

  /// The text of block [p] as it is read aloud, with the text nodes it is
  /// made of and where each starts in it. A `<br>` reads as a space that
  /// belongs to no node, so lines of verse aren't glued together.
  static (String, List<dom.Text>, List<int>) _blockText(dom.Element p) {
    final plain = StringBuffer();
    final nodes = <dom.Text>[];
    final starts = <int>[];
    void collect(dom.Node node) {
      for (final child in node.nodes) {
        if (child is dom.Text) {
          nodes.add(child);
          starts.add(plain.length);
          plain.write(child.data);
        } else if (child is dom.Element) {
          if (child.localName == 'br') {
            plain.write(' ');
          } else if (child.localName != 'style') {
            collect(child);
          }
        }
      }
    }

    collect(p);
    return (plain.toString(), nodes, starts);
  }

  /// Mark the sentences of a block (see [_blockText]) and return their
  /// spoken text. Returns an empty list (and changes nothing) when the block
  /// holds a single sentence.
  static List<TtsSentence> _wrapSentences(
    String plain,
    List<dom.Text> nodes,
    List<int> starts,
    int paraIndex,
  ) {
    final ranges = sentenceRanges(plain);
    if (ranges.length < 2) return const [];

    // Split each text node at sentence edges and wrap the in-sentence pieces.
    // Nodes and sentences are both in reading order, so [s] only moves on.
    var s = 0;
    for (var n = 0; n < nodes.length; n++) {
      final node = nodes[n];
      final end = starts[n] + node.data.length;

      final pieces = <dom.Node>[];
      var pos = starts[n];
      while (s < ranges.length && pos < end) {
        final (rs, re) = ranges[s];
        if (re <= pos) {
          s++;
          continue;
        }
        if (rs >= end) break;
        final a = rs > pos ? rs : pos;
        final b = re < end ? re : end;
        if (a > pos) pieces.add(dom.Text(plain.substring(pos, a)));
        final piece = plain.substring(a, b);
        if (piece.trim().isEmpty) {
          pieces.add(dom.Text(piece));
        } else {
          pieces.add(
            dom.Element.tag('span')
              ..classes.add('tts-sent')
              ..attributes['data-para'] = '$paraIndex'
              ..attributes['data-sent'] = '$s'
              ..append(dom.Text(piece)),
          );
        }
        pos = b;
      }
      if (pos < end) pieces.add(dom.Text(plain.substring(pos, end)));

      final parent = node.parentNode!;
      for (final piece in pieces) {
        parent.insertBefore(piece, node);
      }
      node.remove();
    }

    return [
      for (var s = 0; s < ranges.length; s++)
        (index: s, text: plain.substring(ranges[s].$1, ranges[s].$2).trim()),
    ];
  }

  static const _closers = {'"', "'", '”', '’', ')', ']'};
  static const _abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr', 'prof', 'mt', 'vs', 'etc',
  };

  static final _letter = RegExp(r'[A-Za-z]');

  static bool _isSpace(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u00A0';

  /// Sentence spans of plain [text] as [start, end) offsets, excluding the
  /// whitespace between sentences. A sentence ends at . ! or ? (plus any
  /// closing quotes/brackets) followed by whitespace, except after a common
  /// abbreviation or an initial.
  static List<(int, int)> sentenceRanges(String text) {
    final ranges = <(int, int)>[];
    var i = 0;
    while (i < text.length && _isSpace(text[i])) {
      i++;
    }
    var start = i;
    while (i < text.length) {
      final char = text[i];
      if ((char == '.' || char == '!' || char == '?') &&
          !(char == '.' && _followsAbbreviation(text, i))) {
        var end = i + 1;
        while (end < text.length && _closers.contains(text[end])) {
          end++;
        }
        if (end < text.length && _isSpace(text[end])) {
          ranges.add((start, end));
          i = end;
          while (i < text.length && _isSpace(text[i])) {
            i++;
          }
          start = i;
          continue;
        }
      }
      i++;
    }
    var end = text.length;
    while (end > start && _isSpace(text[end - 1])) {
      end--;
    }
    if (end > start) ranges.add((start, end));
    return ranges;
  }

  /// True when the '.' at [dot] ends a word like "Mr" or "etc", or an
  /// initial ("J. R. R. Tolkien").
  static bool _followsAbbreviation(String text, int dot) {
    var start = dot;
    while (start > 0 && _letter.hasMatch(text[start - 1])) {
      start--;
    }
    if (start == dot) return false;
    final word = text.substring(start, dot);
    // "I" is left out: it ends sentences far more often than it starts names.
    if (word.length == 1 && word != 'I' && word == word.toUpperCase()) {
      return true;
    }
    return _abbreviations.contains(word.toLowerCase());
  }
}

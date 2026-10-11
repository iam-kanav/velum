/// A word read aloud differently from how it's written, e.g. "Mr." read as
/// "Mister", so the voice doesn't pause at the period as if a sentence ended.
class Pronunciation {
  final String written;
  final String spoken;

  const Pronunciation(this.written, this.spoken);

  /// Both sides filled in; others are never applied.
  bool get isComplete => written.trim().isNotEmpty && spoken.trim().isNotEmpty;

  Map<String, String> toJson() => {'written': written, 'spoken': spoken};

  static Pronunciation? fromJson(Object? json) {
    if (json is! Map) return null;
    final written = json['written'];
    final spoken = json['spoken'];
    if (written is! String || spoken is! String) return null;
    return Pronunciation(written, spoken);
  }
}

/// The reader's pronunciation rules, applied to text just before it's spoken.
/// Rules match whole words, ignoring case, and each piece of text is changed
/// at most once, so one rule's output is never rewritten by another.
class Pronunciations {
  final List<Pronunciation> rules;
  final RegExp? _pattern;
  final Map<String, String> _spoken;

  Pronunciations(this.rules)
    : _spoken = {
        for (final r in rules)
          if (r.isComplete) r.written.trim().toLowerCase(): r.spoken.trim(),
      },
      _pattern = _compile(rules);

  /// Titles whose period makes voices pause mid-sentence.
  static const defaults = [
    Pronunciation('Mr.', 'Mister'),
    Pronunciation('Mrs.', 'Missus'),
    Pronunciation('Ms.', 'Miz'),
    Pronunciation('Dr.', 'Doctor'),
  ];

  static const _wordChar = r'[\p{L}\p{N}_]';

  static RegExp? _compile(List<Pronunciation> rules) {
    final words =
        {
            for (final r in rules)
              if (r.isComplete) r.written.trim(),
          }.toList()
          // Longest first, so "Mrs." wins over a shorter rule it contains.
          ..sort((a, b) => b.length.compareTo(a.length));
    if (words.isEmpty) return null;
    final alternatives = words.map(RegExp.escape).join('|');
    return RegExp(
      '(?<!$_wordChar)(?:$alternatives)(?!$_wordChar)',
      caseSensitive: false,
      unicode: true,
    );
  }

  /// [text] as the voice should read it.
  String apply(String text) {
    final pattern = _pattern;
    if (pattern == null) return text;
    return text.replaceAllMapped(
      pattern,
      (m) => _spoken[m[0]!.toLowerCase()] ?? m[0]!,
    );
  }
}

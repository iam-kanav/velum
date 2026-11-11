import 'dart:ui' show Color;

/// The highlight colours by name, as they look on the page.
const Map<String, Color> highlightColors = {
  'yellow': Color(0xFFFFF176),
  'green': Color(0xFF81C784),
  'blue': Color(0xFF64B5F6),
  'pink': Color(0xFFF48FB1),
  'orange': Color(0xFFFFB74D),
};

/// The CSS colour a highlight called [name] is painted with in the reader.
String highlightCss(String name) {
  final c = highlightColors[name] ?? highlightColors['yellow']!;
  int channel(double v) => (v * 255).round();
  return 'rgba(${channel(c.r)}, ${channel(c.g)}, ${channel(c.b)}, 0.4)';
}

class Highlight {
  final String id;
  final String bookPath;
  final int chapterIndex;
  final String text;
  final String color; // 'yellow', 'green', 'blue', 'pink', 'orange'
  final int startOffset;
  final int endOffset;
  final DateTime createdAt;

  const Highlight({
    required this.id,
    required this.bookPath,
    required this.chapterIndex,
    required this.text,
    required this.color,
    required this.startOffset,
    required this.endOffset,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookPath': bookPath,
    'chapterIndex': chapterIndex,
    'text': text,
    'color': color,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
    id: json['id'] as String,
    bookPath: json['bookPath'] as String,
    chapterIndex: json['chapterIndex'] as int,
    text: json['text'] as String,
    color: json['color'] as String,
    startOffset: json['startOffset'] as int,
    endOffset: json['endOffset'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

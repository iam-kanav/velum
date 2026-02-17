import 'package:equatable/equatable.dart';

class Highlight extends Equatable {
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

  @override
  List<Object?> get props => [id, bookPath, chapterIndex, text, color, startOffset, endOffset, createdAt];
}

import 'package:equatable/equatable.dart';

class Bookmark extends Equatable {
  final String id;
  final String bookPath;
  final int chapterIndex;
  final double scrollPosition;
  final String? label; // Optional user-provided label
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookPath,
    required this.chapterIndex,
    required this.scrollPosition,
    this.label,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookPath': bookPath,
    'chapterIndex': chapterIndex,
    'scrollPosition': scrollPosition,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    bookPath: json['bookPath'] as String,
    chapterIndex: json['chapterIndex'] as int,
    scrollPosition: (json['scrollPosition'] as num).toDouble(),
    label: json['label'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  List<Object?> get props => [id, bookPath, chapterIndex, scrollPosition, label, createdAt];
}

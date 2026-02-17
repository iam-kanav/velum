import 'package:equatable/equatable.dart';

class ScannedBook extends Equatable {
  final String filePath;
  final String title;
  final String author;
  final DateTime? addedAt;
  final String? coverBase64; // Base64 encoded cover image
  final bool isPinned;
  final DateTime? lastReadTime;
  final int? lastReadChapter;
  final double? lastReadPosition;

  const ScannedBook({
    required this.filePath,
    required this.title,
    required this.author,
    this.addedAt,
    this.coverBase64,
    this.isPinned = false,
    this.lastReadTime,
    this.lastReadChapter,
    this.lastReadPosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'title': title,
      'author': author,
      'addedAt': addedAt?.toIso8601String(),
      'coverBase64': coverBase64,
      'isPinned': isPinned,
      'lastReadTime': lastReadTime?.toIso8601String(),
      'lastReadChapter': lastReadChapter,
      'lastReadPosition': lastReadPosition,
    };
  }

  factory ScannedBook.fromJson(Map<String, dynamic> json) {
    return ScannedBook(
      filePath: json['filePath'] as String,
      title: json['title'] as String,
      author: json['author'] as String? ?? 'Unknown Author',
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String)
          : null,
      coverBase64: json['coverBase64'] as String?,
      isPinned: json['isPinned'] is bool ? json['isPinned'] as bool : false,
      lastReadTime: json['lastReadTime'] != null
          ? DateTime.tryParse(json['lastReadTime'] as String)
          : null,
      lastReadChapter: json['lastReadChapter'] as int?,
      lastReadPosition: (json['lastReadPosition'] as num?)?.toDouble(),
    );
  }

  ScannedBook copyWith({
    String? filePath,
    String? title,
    String? author,
    DateTime? addedAt,
    String? coverBase64,
    bool? isPinned,
    DateTime? lastReadTime,
    int? lastReadChapter,
    double? lastReadPosition,
  }) {
    return ScannedBook(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      author: author ?? this.author,
      addedAt: addedAt ?? this.addedAt,
      coverBase64: coverBase64 ?? this.coverBase64,
      isPinned: isPinned ?? this.isPinned,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      lastReadChapter: lastReadChapter ?? this.lastReadChapter,
      lastReadPosition: lastReadPosition ?? this.lastReadPosition,
    );
  }

  @override
  List<Object?> get props => [
    filePath,
    title,
    author,
    addedAt,
    coverBase64,
    isPinned,
    lastReadTime,
    lastReadChapter,
    lastReadPosition,
  ];
}

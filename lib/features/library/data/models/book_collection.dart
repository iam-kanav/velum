/// A user-made group of books ("Classics", "To read"). A book can be in any
/// number of collections; [bookPaths] are library file paths.
class BookCollection {
  final String id;
  final String name;
  final List<String> bookPaths;

  /// Books in this collection are left out of "All books" and only show
  /// inside the collection.
  final bool hideFromLibrary;

  const BookCollection({
    required this.id,
    required this.name,
    this.bookPaths = const [],
    this.hideFromLibrary = false,
  });

  BookCollection copyWith({
    String? name,
    List<String>? bookPaths,
    bool? hideFromLibrary,
  }) => BookCollection(
    id: id,
    name: name ?? this.name,
    bookPaths: bookPaths ?? this.bookPaths,
    hideFromLibrary: hideFromLibrary ?? this.hideFromLibrary,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bookPaths': bookPaths,
    'hideFromLibrary': hideFromLibrary,
  };

  factory BookCollection.fromJson(Map<String, dynamic> json) => BookCollection(
    id: json['id'] as String,
    name: json['name'] as String,
    bookPaths: List<String>.from(json['bookPaths'] as List? ?? const []),
    hideFromLibrary: json['hideFromLibrary'] as bool? ?? false,
  );
}

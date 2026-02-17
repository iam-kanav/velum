class CustomFont {
  final String id;
  final String name;
  final String path;

  const CustomFont({required this.id, required this.name, required this.path});

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'path': path};
  }

  factory CustomFont.fromJson(Map<String, dynamic> json) {
    return CustomFont(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomFont &&
        other.id == id &&
        other.name == name &&
        other.path == path;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ path.hashCode;
}

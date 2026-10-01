import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/book_collection.dart';

/// Stores collections (in creation order) in SharedPreferences.
class CollectionService {
  static const _key = 'book_collections';
  final SharedPreferences _prefs;

  CollectionService(this._prefs);

  List<BookCollection> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BookCollection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('Failed to read collections: $e');
      return [];
    }
  }

  Future<void> _save(List<BookCollection> collections) => _prefs.setString(
    _key,
    jsonEncode(collections.map((c) => c.toJson()).toList()),
  );

  Future<BookCollection> create(
    String name,
    List<String> bookPaths, {
    bool hideFromLibrary = false,
  }) async {
    final collection = BookCollection(
      id: const Uuid().v4(),
      name: name,
      bookPaths: bookPaths,
      hideFromLibrary: hideFromLibrary,
    );
    await _save([...load(), collection]);
    return collection;
  }

  Future<void> update(String id, {String? name, bool? hideFromLibrary}) =>
      _save([
        for (final c in load())
          c.id == id
              ? c.copyWith(name: name, hideFromLibrary: hideFromLibrary)
              : c,
      ]);

  Future<void> delete(String id) =>
      _save(load().where((c) => c.id != id).toList());

  /// Add [paths] to or remove them from the collection [id].
  Future<void> setMembership(String id, Iterable<String> paths, bool member) =>
      _save([
        for (final c in load())
          if (c.id != id)
            c
          else
            c.copyWith(
              bookPaths: member
                  ? [
                      ...c.bookPaths,
                      ...paths.where((p) => !c.bookPaths.contains(p)),
                    ]
                  : c.bookPaths.where((p) => !paths.contains(p)).toList(),
            ),
      ]);

  /// Drop a book removed from the library from every collection.
  Future<void> forgetBook(String path) => _save([
    for (final c in load())
      c.copyWith(bookPaths: c.bookPaths.where((p) => p != path).toList()),
  ]);
}

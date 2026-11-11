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
    final collections = <BookCollection>[];
    try {
      for (final entry in jsonDecode(raw) as List) {
        // One by one: a collection that can't be read is left out, instead
        // of the next save replacing all of them with nothing.
        try {
          collections.add(
            BookCollection.fromJson(Map<String, dynamic>.from(entry as Map)),
          );
        } catch (e) {
          debugPrint('Skipping unreadable collection: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to read collections: $e');
    }
    return collections;
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

  /// Drop books removed from the library from every collection.
  Future<void> forgetBooks(Iterable<String> paths) {
    final gone = paths.toSet();
    return _save([
      for (final c in load())
        c.copyWith(
          bookPaths: c.bookPaths.where((p) => !gone.contains(p)).toList(),
        ),
    ]);
  }

  /// Books whose file moved ([moves]: old path to new) stay in their
  /// collections under the new path.
  Future<void> moveBooks(Map<String, String> moves) => _save([
    for (final c in load())
      // A set, in case the new path was somehow in the collection already.
      c.copyWith(
        bookPaths: {for (final p in c.bookPaths) moves[p] ?? p}.toList(),
      ),
  ]);
}

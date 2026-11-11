import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// What Velum keeps about one book besides its library entry: highlights,
/// bookmarks and where the reader was in each chapter. Each is one
/// SharedPreferences string keyed by the book's path.
class BookData {
  static const highlights = 'highlights';
  static const bookmarks = 'bookmarks';
  static const chapterPositions = 'chapter_positions';
  static const _kinds = [highlights, bookmarks, chapterPositions];

  static String _key(String kind, String bookPath) => '$kind:$bookPath';

  /// Keys used to end in the path's `hashCode`, which can't be listed,
  /// moved with the book, or relied on across Dart versions.
  static String _legacyKey(String kind, String bookPath) =>
      '${kind}_${bookPath.hashCode}';

  static String? read(SharedPreferences prefs, String kind, String bookPath) {
    final value = prefs.getString(_key(kind, bookPath));
    if (value != null) return value;
    final legacy = prefs.getString(_legacyKey(kind, bookPath));
    if (legacy == null) return null;
    prefs.setString(_key(kind, bookPath), legacy);
    prefs.remove(_legacyKey(kind, bookPath));
    return legacy;
  }

  /// The records kept as a JSON list under [kind]. Never throws: a record
  /// that can't be read is left out, so one bad entry doesn't take the
  /// book's other highlights or bookmarks with it.
  static List<T> readRecords<T>(
    SharedPreferences prefs,
    String kind,
    String bookPath,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final records = <T>[];
    try {
      final value = read(prefs, kind, bookPath);
      final decoded = value == null ? null : jsonDecode(value);
      if (decoded is! List) return records;
      for (final entry in decoded) {
        try {
          records.add(fromJson(Map<String, dynamic>.from(entry as Map)));
        } catch (_) {}
      }
    } catch (_) {}
    return records;
  }

  static Future<void> write(
    SharedPreferences prefs,
    String kind,
    String bookPath,
    String value,
  ) => prefs.setString(_key(kind, bookPath), value);

  /// Forget everything kept about the book at [bookPath].
  static Future<void> delete(SharedPreferences prefs, String bookPath) async {
    for (final kind in _kinds) {
      await prefs.remove(_key(kind, bookPath));
      await prefs.remove(_legacyKey(kind, bookPath));
    }
  }

  /// The book at [from] now lives at [to]: take its data along, unless the
  /// new path already has some.
  static Future<void> move(
    SharedPreferences prefs,
    String from,
    String to,
  ) async {
    for (final kind in _kinds) {
      final value = read(prefs, kind, from);
      if (value != null && read(prefs, kind, to) == null) {
        await prefs.setString(_key(kind, to), value);
      }
    }
    await delete(prefs, from);
  }
}

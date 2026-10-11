import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Where Velum keeps its own files: the library database, imported books,
/// notes and fonts.
///
/// Android uses the app's documents folder, as it always has. The Mac app
/// isn't sandboxed (so it can scan your folders for books), which makes its
/// documents folder your own ~/Documents; it uses Application Support instead.
Future<Directory> getAppDataDirectory() => Platform.isMacOS
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();

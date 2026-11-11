import 'dart:io';
import 'package:path_provider/path_provider.dart';

Directory? _appDataDirectory;

/// Where Velum keeps its own files: the library database, imported books,
/// notes and fonts.
///
/// Android uses the app's documents folder, as it always has. The Mac app
/// isn't sandboxed (so it can scan your folders for books), which makes its
/// documents folder your own ~/Documents; it uses Application Support instead.
Future<Directory> getAppDataDirectory() async =>
    _appDataDirectory ??= await (Platform.isMacOS
        ? getApplicationSupportDirectory()
        : getApplicationDocumentsDirectory());

/// [getAppDataDirectory]'s path once it has been looked up, which `main`
/// does before anything else runs. Null before that (and in unit tests).
String? get appDataPath => _appDataDirectory?.path;

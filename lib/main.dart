import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/app_directory.dart';
import 'core/theme/app_theme.dart';

import 'package:hive/hive.dart';

import 'features/settings/data/models/reader_settings.dart';
import 'features/settings/presentation/providers/settings_notifier.dart';
import 'features/reader/data/services/epub_service.dart';
import 'features/reader/data/services/highlight_service.dart';
import 'features/reader/data/services/bookmark_service.dart';
import 'features/library/data/models/scanned_book.dart';
import 'features/library/data/services/library_service.dart';
import 'features/library/presentation/providers/library_notifier.dart';
import 'features/tts/data/services/device_tts_engine.dart';
import 'features/tts/data/services/edge_tts_engine.dart';
import 'features/tts/data/services/phonon_model.dart';
import 'features/tts/data/services/phonon_tts_engine.dart';
import 'features/tts/data/services/velum_audio_handler.dart';
import 'features/tts/presentation/providers/tts_notifier.dart';

import 'features/library/data/services/collection_service.dart';
import 'features/notes/data/clipboard_listen.dart';
import 'features/notes/presentation/note_editor_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Initialize Hive
  Hive.init((await getAppDataDirectory()).path);
  Hive.registerAdapter(ScannedBookAdapter());
  final booksBox = await Hive.openBox<ScannedBook>('books_box');

  final libraryService = LibraryService(prefs, booksBox);
  // Migrate old SharedPreferences data to Hive if necessary
  await libraryService.migrateFromSharedPreferencesIfNeeded();

  final highlightService = HighlightService(prefs);
  final bookmarkService = BookmarkService(prefs);

  // Initialize audio_service for media notification controls
  final audioHandler = await AudioService.init(
    builder: () => VelumAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.velum.reader.tts',
      androidNotificationChannelName: 'Velum TTS Playback',
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  // Made here rather than by the widget tree: a "Listen to clipboard" tap
  // can start the app in the background, with no screen to build them.
  final libraryNotifier = LibraryNotifier(
    libraryService,
    CollectionService(prefs),
  );
  final phononModel = PhononModel();
  // App-wide, so reading aloud carries on in the library and while another
  // book is open.
  final ttsNotifier = TtsNotifier(
    DeviceTtsEngine(),
    EdgeTtsEngine(),
    PhononTtsEngine(phononModel),
    phononModel,
    prefs,
  );
  // Not awaited unless the clipboard is listened to, so a failure is
  // handled here rather than left as an unhandled async error.
  final ttsReady = ttsNotifier.init().catchError((Object e) {
    debugPrint('Read-aloud failed to start: $e');
  });
  audioHandler.attachNotifier(ttsNotifier);
  final router = createAppRouter(libraryNotifier);
  ClipboardListen(
    libraryNotifier,
    ttsNotifier,
    ttsReady,
    (path) {
      // Going to the note replaces every open screen, and an editor would
      // lose what was typed. The note still plays and is in the library.
      if (NoteEditorScreen.hasUnsavedChanges) return;
      router.go('/reader?path=${Uri.encodeComponent(path)}');
    },
  ).start();

  runApp(
    MainApp(
      prefs: prefs,
      libraryService: libraryService,
      highlightService: highlightService,
      bookmarkService: bookmarkService,
      libraryNotifier: libraryNotifier,
      ttsNotifier: ttsNotifier,
      router: router,
    ),
  );
}

class MainApp extends StatelessWidget {
  final SharedPreferences prefs;
  final LibraryService libraryService;
  final HighlightService highlightService;
  final BookmarkService bookmarkService;
  final LibraryNotifier libraryNotifier;
  final TtsNotifier ttsNotifier;
  final GoRouter router;

  const MainApp({
    super.key,
    required this.prefs,
    required this.libraryService,
    required this.highlightService,
    required this.bookmarkService,
    required this.libraryNotifier,
    required this.ttsNotifier,
    required this.router,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => const EpubService()),
        Provider.value(value: libraryService),
        Provider.value(value: highlightService),
        Provider.value(value: bookmarkService),
        Provider.value(value: prefs),
        ChangeNotifierProvider(
          create: (context) =>
              SettingsNotifier(context.read<SharedPreferences>()),
        ),
        ChangeNotifierProvider.value(value: libraryNotifier),
        ChangeNotifierProvider.value(value: ttsNotifier),
        ChangeNotifierProvider.value(value: ttsNotifier.phononModel),
      ],
      child: VelumApp(router: router),
    );
  }
}

class VelumApp extends StatelessWidget {
  final GoRouter router;

  const VelumApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    // Only the app theme matters here: watching all of the settings would
    // rebuild the whole app on every slider tick.
    final appTheme = context.select<SettingsNotifier, ReaderTheme>(
      (notifier) => notifier.settings.appTheme,
    );

    // Derive ThemeMode from the user's chosen appTheme
    final themeMode = switch (appTheme) {
      ReaderTheme.dark => ThemeMode.dark,
      _ => ThemeMode.light,
    };

    return MaterialApp.router(
      title: 'Velum',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

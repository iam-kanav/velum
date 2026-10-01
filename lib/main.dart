import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';
import 'package:velum/core/services/ad_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

import 'package:hive_flutter/hive_flutter.dart';

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
import 'features/tts/data/services/velum_audio_handler.dart';

import 'core/providers/ad_notifier.dart';
import 'features/library/data/services/collection_service.dart';

late VelumAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the ads SDK without blocking the first frame; ads load once it's ready.
  unawaited(AdService().initialize());

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(ScannedBookAdapter());
  final booksBox = await Hive.openBox<ScannedBook>('books_box');

  final libraryService = LibraryService(prefs, booksBox);
  // Migrate old SharedPreferences data to Hive if necessary
  await libraryService.migrateFromSharedPreferencesIfNeeded();

  final highlightService = HighlightService(prefs);
  final bookmarkService = BookmarkService(prefs);

  // Initialize audio_service for media notification controls
  audioHandler = await AudioService.init(
    builder: () => VelumAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.velum.reader.tts',
      androidNotificationChannelName: 'Velum TTS Playback',
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(
    MainApp(
      prefs: prefs,
      libraryService: libraryService,
      highlightService: highlightService,
      bookmarkService: bookmarkService,
    ),
  );
}

class MainApp extends StatelessWidget {
  final SharedPreferences prefs;
  final LibraryService libraryService;
  final HighlightService highlightService;
  final BookmarkService bookmarkService;

  const MainApp({
    super.key,
    required this.prefs,
    required this.libraryService,
    required this.highlightService,
    required this.bookmarkService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => const EpubService()),
        Provider.value(value: libraryService),
        Provider.value(value: highlightService),
        Provider.value(value: bookmarkService),
        Provider(create: (_) => DeviceTtsEngine()),
        Provider(create: (_) => EdgeTtsEngine()),
        Provider.value(value: prefs),
        ChangeNotifierProvider(
          create: (context) =>
              SettingsNotifier(context.read<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (context) => LibraryNotifier(
            context.read<LibraryService>(),
            CollectionService(context.read<SharedPreferences>()),
          ),
        ),
        ChangeNotifierProvider(create: (_) => AdNotifier()),
        Provider<VelumAudioHandler>.value(value: audioHandler),
      ],
      child: const VelumApp(),
    );
  }
}

class VelumApp extends StatefulWidget {
  const VelumApp({super.key});

  @override
  State<VelumApp> createState() => _VelumAppState();
}

class _VelumAppState extends State<VelumApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Initialize router once to prevent recreation on rebuilds
    final libraryNotifier = context.read<LibraryNotifier>();
    _router = createAppRouter(libraryNotifier);
  }

  @override
  Widget build(BuildContext context) {
    final settingsNotifier = context.watch<SettingsNotifier>();

    // Derive ThemeMode from the user's chosen appTheme
    final themeMode = switch (settingsNotifier.settings.appTheme) {
      ReaderTheme.dark => ThemeMode.dark,
      _ => ThemeMode.light,
    };

    return MaterialApp.router(
      title: 'Velum',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

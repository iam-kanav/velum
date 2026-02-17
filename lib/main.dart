import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

import 'features/settings/data/models/reader_settings.dart';
import 'features/settings/presentation/providers/settings_notifier.dart';
import 'features/reader/data/services/epub_service.dart';
import 'features/reader/data/services/highlight_service.dart';
import 'features/reader/presentation/providers/reader_notifier.dart';
import 'features/reader/presentation/providers/highlight_notifier.dart';
import 'features/library/data/services/library_service.dart';
import 'features/library/presentation/providers/library_notifier.dart';
import 'features/tts/data/services/tts_service.dart';
import 'features/tts/data/services/velum_audio_handler.dart';

import 'features/tts/presentation/providers/tts_notifier.dart';
import 'core/services/ad_service.dart';

late VelumAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Ads
  // await AdService().initialize();

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final libraryService = LibraryService(prefs);
  final highlightService = HighlightService(prefs);
  final ttsService = TtsService();

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
      ttsService: ttsService,
    ),
  );
}

class MainApp extends StatelessWidget {
  final SharedPreferences prefs;
  final LibraryService libraryService;
  final HighlightService highlightService;
  final TtsService ttsService;

  const MainApp({
    super.key,
    required this.prefs,
    required this.libraryService,
    required this.highlightService,
    required this.ttsService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => const EpubService()),
        Provider.value(value: libraryService),
        Provider.value(value: highlightService),
        Provider.value(value: ttsService),
        Provider.value(value: prefs),
        ChangeNotifierProvider(
          create: (context) =>
              SettingsNotifier(context.read<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ReaderNotifier(
            context.read<EpubService>(),
            context.read<LibraryService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => LibraryNotifier(context.read<LibraryService>()),
        ),
        ChangeNotifierProvider(
          create: (context) => HighlightNotifier(context.read<HighlightService>()),
        ),
        Provider<VelumAudioHandler>.value(value: audioHandler),
        ChangeNotifierProvider(
          create: (context) {
            final ttsNotifier = TtsNotifier(
              context.read<TtsService>(),
              context.read<SharedPreferences>(),
            )..init();
            audioHandler.attachNotifier(ttsNotifier);
            return ttsNotifier;
          },
        ),
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

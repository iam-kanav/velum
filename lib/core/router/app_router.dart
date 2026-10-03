import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/library/presentation/screens/library_screen.dart';
import '../../features/library/presentation/providers/library_notifier.dart';
import '../../features/reader/presentation/screens/reader_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';

import 'package:provider/provider.dart';
import '../../features/reader/data/services/epub_service.dart';
import '../../features/library/data/services/library_service.dart';
import '../../features/reader/data/services/highlight_service.dart';
import '../../features/reader/data/services/bookmark_service.dart';
import '../../features/reader/presentation/providers/reader_notifier.dart';
import '../../features/reader/presentation/providers/highlight_notifier.dart';
import '../../features/reader/presentation/providers/bookmark_notifier.dart';
import '../../features/notes/presentation/note_editor_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Notifies only when onboarding completes. The router must not refresh on
/// every library change (progress saves, notes): a refresh racing an
/// imperative pop re-adds the route that was just closed.
class _OnboardingListenable extends ChangeNotifier {
  final LibraryNotifier _library;
  late bool _complete = _library.isOnboardingComplete;

  _OnboardingListenable(this._library) {
    _library.addListener(_check);
  }

  void _check() {
    if (_library.isOnboardingComplete == _complete) return;
    _complete = _library.isOnboardingComplete;
    notifyListeners();
  }
}

GoRouter createAppRouter(LibraryNotifier libraryNotifier) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _OnboardingListenable(libraryNotifier),
    redirect: (context, state) {
      final isOnboarding = state.matchedLocation == '/onboarding';
      if (!libraryNotifier.isOnboardingComplete) {
        // If onboarding is not complete, redirect to onboarding unless already there
        return isOnboarding ? null : '/onboarding';
      }
      if (isOnboarding && libraryNotifier.isOnboardingComplete) {
        // If onboarding is complete but we are at onboarding, go to library
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const LibraryScreen()),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final path = state.uri.queryParameters['path'];
          if (path == null || path.isEmpty) {
            // Fallback to library if no path provided
            return const LibraryScreen();
          }
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(
                create: (context) => ReaderNotifier(
                  context.read<EpubService>(),
                  context.read<LibraryService>(),
                ),
              ),
              ChangeNotifierProvider(
                create: (context) =>
                    HighlightNotifier(context.read<HighlightService>()),
              ),
              ChangeNotifierProvider(
                create: (context) =>
                    BookmarkNotifier(context.read<BookmarkService>()),
              ),
            ],
            child: ReaderScreen(assetPath: path),
          );
        },
      ),
      GoRoute(
        path: '/editor',
        builder: (context, state) =>
            NoteEditorScreen(path: state.uri.queryParameters['path']),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/library/presentation/screens/library_screen.dart';
import '../../features/library/presentation/providers/library_notifier.dart';
import '../../features/reader/presentation/screens/reader_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter(LibraryNotifier libraryNotifier) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: libraryNotifier,
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
          return ReaderScreen(assetPath: path);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

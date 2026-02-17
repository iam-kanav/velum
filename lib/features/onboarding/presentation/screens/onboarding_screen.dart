import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import 'package:velum/features/library/presentation/providers/library_notifier.dart';

// App accent green matching the icon
const Color _accentGreen = Color(0xFF4CAF50);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    // Validate Library Setup step (Page 1 -> 2)
    if (_currentPage == 1) {
      final libraryNotifier = context.read<LibraryNotifier>();
      final hasSelectedOption =
          libraryNotifier.isAutoScanEnabled || libraryNotifier.books.isNotEmpty;

      if (!hasSelectedOption) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an option to build your library'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _finishOnboarding() async {
    final libraryNotifier = context.read<LibraryNotifier>();
    await libraryNotifier.completeOnboarding();
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<SettingsNotifier>().settings.appTheme;

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics:
                    const NeverScrollableScrollPhysics(), // Disable swiping to enforce flow
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  _WelcomePage(onNext: _nextPage),
                  _LibrarySetupPage(onNext: _nextPage),
                  _NotificationSetupPage(onNext: _nextPage),
                  _ThemeSetupPage(onFinish: _finishOnboarding),
                ],
              ),
            ),
            // Page indicator
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? _accentGreen
                          : appTheme.textColor.withAlpha(60),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAGE 1: WELCOME
// ════════════════════════════════════════════════════════════════════════════

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<SettingsNotifier>().settings.appTheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // App Icon
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.asset(
              'assets/icons/android/play_store_512.png',
              width: 120,
              height: 120,
            ),
          ),
          const SizedBox(height: 40),
          // App name
          Text(
            'Velum',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: appTheme.textColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          // Tagline
          Text(
            'Your Beautiful EPUB Reader',
            style: TextStyle(
              fontSize: 18,
              color: appTheme.textColor.withAlpha(180),
            ),
          ),
          const SizedBox(height: 48),
          // Features
          _FeatureItem(
            icon: Icons.library_add,
            text: 'Add EPUB books from your device',
            theme: appTheme,
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.palette,
            text: 'Customizable themes for reading',
            theme: appTheme,
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.text_fields,
            text: 'Adjust fonts, sizes, and spacing',
            theme: appTheme,
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.record_voice_over,
            text: 'Listen to books with Text-to-Speech',
            theme: appTheme,
          ),
          const Spacer(),
          // Next button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final ReaderTheme theme;

  const _FeatureItem({
    required this.icon,
    required this.text,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _accentGreen.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _accentGreen, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: theme.textColor.withAlpha(200),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAGE 2: LIBRARY SETUP (Auto-Detect + Manual)
// ════════════════════════════════════════════════════════════════════════════

class _LibrarySetupPage extends StatefulWidget {
  final VoidCallback onNext;

  const _LibrarySetupPage({required this.onNext});

  @override
  State<_LibrarySetupPage> createState() => _LibrarySetupPageState();
}

class _LibrarySetupPageState extends State<_LibrarySetupPage> {
  Future<void> _startAutoDetect() async {
    final notifier = context.read<LibraryNotifier>();

    // Request permission
    final granted = await notifier.requestStoragePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission is required to scan for books'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Enable auto-scan and start scanning
    await notifier.setAutoScanEnabled(true);
    await notifier.scanDevice();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<SettingsNotifier>().settings.appTheme;
    final libraryNotifier = context.watch<LibraryNotifier>();

    final hasSelectedOption =
        libraryNotifier.isAutoScanEnabled || libraryNotifier.books.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          // ... (rest of the UI remains the same until the button)
          // Icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.library_books,
              size: 50,
              color: Colors.orange.shade600,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Build Your Library',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: appTheme.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose how to add books to your library',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: appTheme.textColor.withAlpha(180),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Option 1: Auto-Detect (Recommended)
          _buildOptionCard(
            appTheme: appTheme,
            icon: Icons.manage_search,
            iconColor: Colors.green,
            title: 'Auto-Detect EPUBs',
            subtitle: 'Scan your device for all EPUB files',
            badge: 'Recommended',
            isScanning: libraryNotifier.isScanning,
            scanProgress: libraryNotifier.scanProgress,
            onTap: libraryNotifier.isScanning ? null : _startAutoDetect,
          ),

          const SizedBox(height: 12),

          // Option 2: Manual Selection
          _buildOptionCard(
            appTheme: appTheme,
            icon: Icons.file_open,
            iconColor: _accentGreen,
            title: 'Select Files Manually',
            subtitle: 'Pick individual EPUB files',
            onTap: libraryNotifier.isScanning
                ? null
                : () => libraryNotifier.pickFiles(),
          ),

          const SizedBox(height: 16),

          // Result feedback
          if (libraryNotifier.isScanning) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: appTheme.textColor.withAlpha(150),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Found ${libraryNotifier.scanProgress} books...',
                  style: TextStyle(
                    fontSize: 14,
                    color: appTheme.textColor.withAlpha(150),
                  ),
                ),
              ],
            ),
          ] else if (libraryNotifier.books.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${libraryNotifier.books.length} book${libraryNotifier.books.length == 1 ? '' : 's'} in your library',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: appTheme.textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Settings note
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: appTheme.textColor.withAlpha(100),
              ),
              const SizedBox(width: 6),
              Text(
                'You can change this later in Settings',
                style: TextStyle(
                  fontSize: 12,
                  color: appTheme.textColor.withAlpha(100),
                ),
              ),
            ],
          ),

          const Spacer(),

          // Continue button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (libraryNotifier.isScanning || !hasSelectedOption)
                  ? null
                  : widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _accentGreen.withAlpha(100),
                disabledForegroundColor: Colors.white.withAlpha(150),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required ReaderTheme appTheme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badge,
    bool isScanning = false,
    int scanProgress = 0,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: appTheme.textColor.withAlpha(40),
              width: 1,
            ),
            color: Colors.transparent,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isScanning
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: iconColor,
                        ),
                      )
                    : Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: appTheme.textColor,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: iconColor.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isScanning ? 'Scanning... found $scanProgress' : subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: appTheme.textColor.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: appTheme.textColor.withAlpha(60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAGE 3: NOTIFICATION ACCESS
// ════════════════════════════════════════════════════════════════════════════

class _NotificationSetupPage extends StatefulWidget {
  final VoidCallback onNext;

  const _NotificationSetupPage({required this.onNext});

  @override
  State<_NotificationSetupPage> createState() => _NotificationSetupPageState();
}

class _NotificationSetupPageState extends State<_NotificationSetupPage> {
  bool _granted = false;
  bool _requested = false;

  Future<void> _requestPermission() async {
    final status = await Permission.notification.request();
    setState(() {
      _granted = status.isGranted;
      _requested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<SettingsNotifier>().settings.appTheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          // Icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: _accentGreen.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active,
              size: 50,
              color: _accentGreen,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Playback Controls',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: appTheme.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Allow notifications to control Text-to-Speech playback from your notification shade, even when the app is in the background.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: appTheme.textColor.withAlpha(180),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Feature bullets
          _FeatureItem(
            icon: Icons.play_circle_outline,
            text: 'Play and pause from notifications',
            theme: appTheme,
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.skip_next,
            text: 'Skip paragraphs forward or back',
            theme: appTheme,
          ),
          const SizedBox(height: 16),
          _FeatureItem(
            icon: Icons.open_in_new,
            text: 'Tap notification to return to reader',
            theme: appTheme,
          ),

          const SizedBox(height: 32),

          // Grant button or status
          if (_granted) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notification access granted',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: appTheme.textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.notifications, size: 20),
                label: Text(
                  _requested ? 'Try Again' : 'Allow Notifications',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentGreen,
                  side: BorderSide(color: _accentGreen.withAlpha(180)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],

          const Spacer(),

          // Continue button (always enabled - permission is optional)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                _granted ? 'Continue' : 'Skip for Now',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAGE 4: THEME SETUP
// ════════════════════════════════════════════════════════════════════════════

class _ThemeSetupPage extends StatelessWidget {
  final VoidCallback onFinish;

  const _ThemeSetupPage({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    final settingsNotifier = context.watch<SettingsNotifier>();
    final settings = settingsNotifier.settings;
    final appTheme = settings.appTheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Spacer(),
          // Icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.purple.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.palette, size: 50, color: Colors.purple.shade600),
          ),
          const SizedBox(height: 32),
          Text(
            'Choose Your Themes',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: appTheme.textColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'You can set different themes for the app and for reading. Change these anytime in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: appTheme.textColor.withAlpha(180),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          // App Theme
          _ThemeSection(
            title: 'App Theme',
            subtitle: 'For Library & Settings',
            selectedTheme: settings.appTheme,
            displayTheme: appTheme,
            onSelect: (theme) => settingsNotifier.updateAppTheme(theme),
          ),
          const SizedBox(height: 24),
          // Reader Theme
          _ThemeSection(
            title: 'Reader Theme',
            subtitle: 'For reading books',
            selectedTheme: settings.readerTheme,
            displayTheme: appTheme,
            onSelect: (theme) => settingsNotifier.updateReaderTheme(theme),
          ),
          const Spacer(),
          // Finish button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Start Reading',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final ReaderTheme selectedTheme;
  final ReaderTheme displayTheme;
  final void Function(ReaderTheme) onSelect;

  const _ThemeSection({
    required this.title,
    required this.subtitle,
    required this.selectedTheme,
    required this.displayTheme,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: displayTheme.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: displayTheme.textColor.withAlpha(150),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ReaderTheme.values.map((theme) {
            final isSelected = selectedTheme == theme;
            return GestureDetector(
              onTap: () => onSelect(theme),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.backgroundColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? _accentGreen
                            : Colors.grey.withAlpha(60),
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: _accentGreen.withAlpha(60),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        'Aa',
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    theme.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: displayTheme.textColor.withAlpha(
                        isSelected ? 255 : 150,
                      ),
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

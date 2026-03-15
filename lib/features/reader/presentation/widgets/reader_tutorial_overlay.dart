import 'dart:math';
import 'package:flutter/material.dart';

/// Describes a single step in the reader tutorial.
class _TutorialStep {
  final String title;
  final String description;
  final IconData icon;

  /// Key name to look up in [ReaderTutorialOverlay.elementKeys].
  /// null = no spotlight (full dark overlay).
  final String? elementKey;

  /// Extra padding radius around the widget bounds.
  final double spotlightPadding;

  const _TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    this.elementKey,
    this.spotlightPadding = 14,
  });
}

/// Full-screen tutorial overlay with spotlight cut-outs for the reader screen.
/// Spotlights are positioned using [GlobalKey] → [RenderBox.localToGlobal]
/// for pixel-perfect accuracy on any device.
class ReaderTutorialOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final double bottomOffset;

  /// Keys attached to actual widgets in the reader UI. The overlay uses these
  /// to resolve real on-screen positions rather than guessing from constants.
  final Map<String, GlobalKey> elementKeys;

  const ReaderTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.elementKeys,
    this.bottomOffset = 0,
  });

  @override
  State<ReaderTutorialOverlay> createState() => _ReaderTutorialOverlayState();
}

class _ReaderTutorialOverlayState extends State<ReaderTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  static const _accentGreen = Color(0xFF4CAF50);

  static const List<_TutorialStep> _steps = [
    _TutorialStep(
      title: 'Welcome to the Reader',
      description:
          'Let\'s take a quick tour so you know\nhow to get the most out of Velum.',
      icon: Icons.auto_stories_rounded,
    ),
    _TutorialStep(
      title: 'Navigate Chapters',
      description: 'Swipe left or right anywhere\nto move between chapters.',
      icon: Icons.swipe_rounded,
    ),
    _TutorialStep(
      title: 'Back to Library',
      description: 'Tap the back arrow to return\nto your book library.',
      icon: Icons.arrow_back_rounded,
      elementKey: 'back',
      spotlightPadding: 12,
    ),
    _TutorialStep(
      title: 'Table of Contents',
      description:
          'Tap the chapter name to open\nthe contents list and jump\nto any chapter.',
      icon: Icons.list_rounded,
      elementKey: 'chapterName',
      spotlightPadding: 16,
    ),
    _TutorialStep(
      title: 'Highlight Text',
      description:
          'Long-press to select text, then\npick a colour to save a highlight.',
      icon: Icons.highlight_rounded,
    ),
    _TutorialStep(
      title: 'Your Highlights',
      description:
          'Tap here to see all your saved\nhighlights and jump back to them.',
      icon: Icons.bookmark_rounded,
      elementKey: 'highlights',
      spotlightPadding: 12,
    ),
    _TutorialStep(
      title: 'Settings',
      description:
          'Tap here to customise your reading\nexperience and TTS voice settings.',
      icon: Icons.settings_rounded,
      elementKey: 'settings',
      spotlightPadding: 12,
    ),
    _TutorialStep(
      title: 'Play / Pause TTS',
      description:
          'Tap this button to start or pause\ntext-to-speech narration.\nThe ring around it shows how much\nof the chapter has been prepared.',
      icon: Icons.play_circle_outline_rounded,
      elementKey: 'fab',
      spotlightPadding: 16,
    ),
    _TutorialStep(
      title: 'Skip Around',
      description:
          'Double-tap any paragraph to jump\nTTS playback to that position.',
      icon: Icons.touch_app_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    _animController.reverse().then((_) => widget.onDismiss());
  }

  /// Resolve the center + radius of a step's spotlight by looking up the
  /// GlobalKey in [widget.elementKeys] and reading the real RenderBox bounds.
  /// Returns null if no key is set or the widget isn't in the tree yet.
  ({Offset center, double radius})? _resolveSpotlight(_TutorialStep step) {
    final keyName = step.elementKey;
    if (keyName == null) return null;

    final key = widget.elementKeys[keyName];
    if (key == null) return null;

    final ctx = key.currentContext;
    if (ctx == null) return null;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final size = box.size;
    final topLeft = box.localToGlobal(Offset.zero);
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    // Radius = half the largest dimension + padding
    final radius = max(size.width, size.height) / 2 + step.spotlightPadding;

    return (center: center, radius: radius);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final step = _steps[_currentStep];
    final spotlight = _resolveSpotlight(step);
    final isLastStep = _currentStep == _steps.length - 1;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Dark overlay with spotlight cut-out
            Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  center: spotlight?.center,
                  radius: spotlight?.radius ?? 40,
                  overlayColor: Colors.black.withAlpha((0.78 * 255).round()),
                ),
              ),
            ),

            // Absorb all taps so the reader doesn't respond
            Positioned.fill(
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

            // Content card — positioned opposite the spotlight
            _buildContentCard(step, spotlight?.center, screenSize),

            // Page dots + navigation buttons
            Positioned(
              bottom: max(MediaQuery.of(context).padding.bottom + 16, 32),
              left: 0,
              right: 0,
              child: _buildNavigation(isLastStep),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard(
    _TutorialStep step,
    Offset? spotlightCenter,
    Size screenSize,
  ) {
    double top;
    if (spotlightCenter == null) {
      top = screenSize.height * 0.30;
    } else if (spotlightCenter.dy > screenSize.height * 0.5) {
      // Spotlight in lower half → card in upper area
      top = screenSize.height * 0.18;
    } else {
      // Spotlight in upper half → card in lower area
      top = screenSize.height * 0.52;
    }

    return Positioned(
      top: top,
      left: 32,
      right: 32,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Container(
          key: ValueKey(_currentStep),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _accentGreen.withAlpha((0.3 * 255).round()),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentGreen.withAlpha((0.08 * 255).round()),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentGreen.withAlpha((0.12 * 255).round()),
                ),
                child: Icon(step.icon, size: 32, color: _accentGreen),
              ),
              const SizedBox(height: 20),
              Text(
                step.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                step.description,
                style: TextStyle(
                  color: Colors.white.withAlpha((0.7 * 255).round()),
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigation(bool isLastStep) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Page dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_steps.length, (index) {
            final isActive = index == _currentStep;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? _accentGreen
                    : Colors.white.withAlpha((0.25 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            children: [
              TextButton(
                onPressed: _dismiss,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: Colors.white.withAlpha((0.5 * 255).round()),
                    fontSize: 15,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLastStep ? 'Got it!' : 'Next',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!isLastStep) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// CustomPainter that draws a dark overlay with a transparent spotlight circle.
class _SpotlightPainter extends CustomPainter {
  final Offset? center;
  final double radius;
  final Color overlayColor;

  _SpotlightPainter({
    this.center,
    this.radius = 40,
    this.overlayColor = const Color(0xC8000000),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;

    if (center == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    final overlayPath = Path()..addRect(Offset.zero & size);
    final spotlightPath = Path()
      ..addOval(Rect.fromCircle(center: center!, radius: radius));

    canvas.drawPath(
      Path.combine(PathOperation.difference, overlayPath, spotlightPath),
      paint,
    );

    // Glow ring
    canvas.drawCircle(
      center!,
      radius,
      Paint()
        ..color = const Color(0xFF4CAF50).withAlpha((0.35 * 255).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Crisp ring
    canvas.drawCircle(
      center!,
      radius,
      Paint()
        ..color = const Color(0xFF4CAF50).withAlpha((0.6 * 255).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.center != center || old.radius != radius;
}

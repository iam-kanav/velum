import 'dart:math';
import 'package:flutter/material.dart';
import 'package:velum/core/theme/app_colors.dart';

/// Describes a single step in the reader tutorial.
class _TutorialStep {
  final String title;
  final String description;
  final IconData icon;

  /// Key name to look up in [ReaderTutorialOverlay.elementKeys].
  /// null = no spotlight (full dark overlay).
  final String? elementKey;

  /// Extra room around the widget's bounds.
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

  /// Keys attached to actual widgets in the reader UI. The overlay uses these
  /// to resolve real on-screen positions rather than guessing from constants.
  final Map<String, GlobalKey> elementKeys;

  const ReaderTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.elementKeys,
  });

  @override
  State<ReaderTutorialOverlay> createState() => _ReaderTutorialOverlayState();
}

class _ReaderTutorialOverlayState extends State<ReaderTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;

  /// The current step's spotlight, measured after layout.
  Rect? _spotlight;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  static const _accent = AppColors.accent;

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
          'Tap this button to start or pause\ntext-to-speech narration.\nThe badge on it shows how much\nof the chapter has been prepared.',
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
      setState(() {
        _currentStep++;
        _spotlight = _resolveSpotlight(_steps[_currentStep]);
      });
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    _animController.reverse().then((_) => widget.onDismiss());
  }

  /// The bounds of a step's target plus its padding, in this overlay's
  /// coordinates. Null if the step has none or it isn't laid out.
  Rect? _resolveSpotlight(_TutorialStep step) {
    final keyName = step.elementKey;
    if (keyName == null) return null;

    final target = widget.elementKeys[keyName]?.currentContext
        ?.findRenderObject();
    final overlay = context.findRenderObject();
    if (target is! RenderBox || !target.attached || !target.hasSize) {
      return null;
    }
    if (overlay is! RenderBox || !overlay.hasSize) return null;

    final topLeft = overlay.globalToLocal(target.localToGlobal(Offset.zero));
    return (topLeft & target.size).inflate(step.spotlightPadding);
  }

  /// The target's position is only known once the frame is laid out, and
  /// moves when the window is rotated or resized: measure again after
  /// every build.
  void _measureAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final spotlight = _resolveSpotlight(_steps[_currentStep]);
      if (spotlight != _spotlight) setState(() => _spotlight = spotlight);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read so that a rotate or resize rebuilds, and so measures again.
    MediaQuery.sizeOf(context);
    final safeArea = MediaQuery.paddingOf(context);
    final step = _steps[_currentStep];
    final spotlight = _spotlight;
    final isLastStep = _currentStep == _steps.length - 1;
    final top = safeArea.top + 16;
    _measureAfterLayout();

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
                  spotlight: spotlight,
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

            // Content card above the page dots + navigation buttons
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: top,
                  bottom: max(safeArea.bottom + 16, 32),
                ),
                child: Column(
                  children: [
                    Expanded(child: _buildContentCard(step, spotlight, top)),
                    _buildNavigation(isLastStep),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Below this much room beside the spotlight, the card uses the whole
  /// area and may cover it.
  static const double _minCardSpace = 200;

  /// The card, in the space above the dots and buttons ([areaTop] is where
  /// that space starts). It sits on the far side of the spotlight, and
  /// scrolls when a short or landscape screen can't fit it.
  Widget _buildContentCard(_TutorialStep step, Rect? spotlight, double areaTop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaBottom = areaTop + constraints.maxHeight;
        var above = 0.0, below = 0.0;
        if (spotlight != null) {
          if (spotlight.center.dy > (areaTop + areaBottom) / 2) {
            // Spotlight in lower half → card above it
            below = max(0, areaBottom - spotlight.top);
          } else {
            // Spotlight in upper half → card below it
            above = max(0, spotlight.bottom - areaTop);
          }
          if (constraints.maxHeight - above - below < _minCardSpace) {
            above = below = 0;
          }
        }

        return Padding(
          padding: EdgeInsets.only(top: above, bottom: below),
          child: Center(
            child: SingleChildScrollView(
              // Room for the card's glow, which the scroll view clips.
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: _buildCard(step),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(_TutorialStep step) {
    return AnimatedSwitcher(
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
            color: _accent.withAlpha((0.3 * 255).round()),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withAlpha((0.08 * 255).round()),
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
                color: _accent.withAlpha((0.12 * 255).round()),
              ),
              child: Icon(step.icon, size: 32, color: _accent),
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
                    ? _accent
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
                  backgroundColor: _accent,
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

/// Draws a dark overlay with the spotlight cut out of it. The cut-out is
/// rounded to the target's shorter side: a circle around a button, a pill
/// around something wide like the chapter name.
class _SpotlightPainter extends CustomPainter {
  final Rect? spotlight;
  final Color overlayColor;

  _SpotlightPainter({required this.spotlight, required this.overlayColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;
    final spotlight = this.spotlight;

    if (spotlight == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    final cutOut = RRect.fromRectAndRadius(
      spotlight,
      Radius.circular(spotlight.shortestSide / 2),
    );
    final overlayPath = Path()..addRect(Offset.zero & size);
    final spotlightPath = Path()..addRRect(cutOut);

    canvas.drawPath(
      Path.combine(PathOperation.difference, overlayPath, spotlightPath),
      paint,
    );

    // Glow ring
    canvas.drawRRect(
      cutOut,
      Paint()
        ..color = AppColors.accent.withAlpha((0.35 * 255).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Crisp ring
    canvas.drawRRect(
      cutOut,
      Paint()
        ..color = AppColors.accent.withAlpha((0.6 * 255).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.spotlight != spotlight || old.overlayColor != overlayColor;
}

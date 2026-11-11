import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

/// Velum's motion scale: how long things take, how they ease and how far
/// they travel. The values follow the transitions.dev motion tokens, so
/// every surface moves the same way: quick out, slower and softer in.
abstract final class Motion {
  // Durations
  static const stagger = Duration(milliseconds: 40);
  static const micro = Duration(milliseconds: 80);
  static const quick = Duration(milliseconds: 150); // closes, text swaps
  static const fast = Duration(milliseconds: 250); // opens, icon swaps, pages
  static const medium = Duration(milliseconds: 350); // sheet close
  static const slow = Duration(milliseconds: 400); // sheet open
  static const verySlow = Duration(milliseconds: 500); // text reveal, success

  // Easings
  static const smoothOut = Cubic(0.22, 1, 0.36, 1);
  static const bounce = Cubic(0.34, 1.36, 0.64, 1);

  // Distances, in logical pixels
  static const distanceMicro = 4.0;
  static const distanceBase = 8.0;
  static const distanceMedium = 12.0;

  // Scales a surface opens from
  static const scaleDialog = 0.96;
  static const scaleMenu = 0.97;

  // Blur radii
  static const blurSmall = 2.0;
  static const blurMedium = 3.0;

  /// How bottom sheets slide: slower in than out.
  static const sheet = AnimationStyle(
    duration: slow,
    reverseDuration: medium,
    curve: smoothOut,
    reverseCurve: Curves.easeIn,
  );

  /// Whether the person asked their device for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Fade, blur and a small move or scale, driven by [animation]: the shared
/// look of things arriving and leaving.
class MotionReveal extends StatelessWidget {
  final Animation<double> animation;
  final Offset offset;
  final double scale;
  final double blur;
  final Alignment alignment;
  final Widget child;

  const MotionReveal({
    super.key,
    required this.animation,
    required this.child,
    this.offset = Offset.zero,
    this.scale = 1,
    this.blur = 0,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        final away = 1 - t;
        final sigma = blur * away;
        Widget result = child!;
        if (sigma > 0.05) {
          result = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: result,
          );
        }
        if (scale != 1) {
          result = Transform.scale(
            scale: scale + (1 - scale) * t,
            alignment: alignment,
            child: result,
          );
        }
        if (offset != Offset.zero) {
          result = Transform.translate(offset: offset * away, child: result);
        }
        return Opacity(opacity: t, child: result);
      },
    );
  }
}

/// Swaps its child in place whenever the child's key changes.
///
/// [MotionSwap.icon] cross-fades two icons with a blur and a scale;
/// [MotionSwap.text] lets the old text sink away while the new one rises in.
class MotionSwap extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Offset offset;
  final double scale;
  final Alignment alignment;

  /// For two icons sharing a slot (play ↔ pause).
  const MotionSwap.icon({super.key, required this.child})
    : duration = Motion.fast,
      offset = Offset.zero,
      scale = 0.6,
      alignment = Alignment.center;

  /// For a label or number that changes in place.
  const MotionSwap.text({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  }) : duration = Motion.quick,
       offset = const Offset(0, Motion.distanceMicro),
       scale = 1;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => MotionReveal(
        animation: animation,
        offset: offset,
        scale: scale,
        blur: Motion.blurSmall,
        child: child,
      ),
      child: child,
    );
  }
}

/// Lets its child rise into place the first time it appears: a blurred
/// fade up. Give stacked lines or grid items increasing [index] values and
/// they arrive one after another.
class RevealIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration step;
  final Duration duration;
  final double distance;
  final double blur;

  /// False shows the child in place at once (for items that turn up after
  /// the screen's entrance, such as grid cards scrolled into view).
  final bool animate;

  const RevealIn({
    super.key,
    required this.child,
    this.index = 0,
    this.step = Motion.micro,
    this.duration = Motion.verySlow,
    this.distance = Motion.distanceMedium,
    this.blur = Motion.blurMedium,
    this.animate = true,
  });

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    final delay = widget.step * widget.index;
    if (!widget.animate) {
      _controller.value = 1;
    } else if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;
    return MotionReveal(
      animation: _animation,
      offset: Offset(0, widget.distance),
      blur: widget.blur,
      child: widget.child,
    );
  }
}

/// Grows its child from just under full size as it fades in, the first
/// time it appears: how menus and floating bars open.
class PopIn extends StatelessWidget {
  final Widget child;
  final double scale;
  final Alignment alignment;

  const PopIn({
    super.key,
    required this.child,
    this.scale = Motion.scaleMenu,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.fast,
      curve: Motion.smoothOut,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale + (1 - scale) * t,
          alignment: alignment,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Shrinks its child a touch while it is pressed, so cards and buttons
/// feel like they give under a finger. Doesn't handle the tap itself.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;

  const PressScale({super.key, required this.child, this.scale = 0.97});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !Motion.reduced(context) ? widget.scale : 1,
        duration: _down ? Motion.micro : Motion.fast,
        curve: Motion.smoothOut,
        child: widget.child,
      ),
    );
  }
}

/// A dialog that scales up from just under full size as it fades in, and
/// leaves faster than it came. Takes the place of [showDialog].
Future<T?> showMotionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: Motion.fast,
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      if (Motion.reduced(context)) return child;
      return MotionReveal(
        animation: CurvedAnimation(
          parent: animation,
          curve: Motion.smoothOut,
          // The close runs the same 250ms backwards; easing it out early
          // gets the dialog gone in about the first 150ms.
          reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
        ),
        scale: Motion.scaleDialog,
        child: child,
      );
    },
  );
}

/// Pages fade in over a short slide, and the page underneath eases back,
/// instead of each platform's stock route animation.
class MotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.fast;

  @override
  Duration get reverseTransitionDuration => Motion.fast;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    final entering = CurvedAnimation(
      parent: animation,
      curve: Motion.smoothOut,
      reverseCurve: Curves.easeIn,
    );
    // The page being covered drifts the other way and dims slightly.
    final covered = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Motion.smoothOut,
      reverseCurve: Curves.easeIn,
    );
    return AnimatedBuilder(
      animation: covered,
      child: MotionReveal(
        animation: entering,
        offset: const Offset(Motion.distanceBase * 3, 0),
        child: child,
      ),
      builder: (context, child) => Transform.translate(
        offset: Offset(-Motion.distanceBase * 3 * covered.value, 0),
        child: Opacity(opacity: 1 - 0.3 * covered.value, child: child),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Fades and slides [child] up into place once, when first built — the
/// Zoho-style entrance for cards and list items. [delay] staggers a group
/// (e.g. `Duration(milliseconds: 40 * index)`, capped so long lists don't
/// keep animating).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 12,
  });

  /// Stagger delay for the [index]th item of a list: the first screenful
  /// ripples in one after another; items built later (scrolled into view)
  /// just fade in straight away.
  static Duration stagger(int index) =>
      Duration(milliseconds: index < 12 ? 35 * index : 0);

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.normal);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: AppMotion.curve);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - _t.value)),
          child: child,
        ),
      ),
    );
  }
}

/// A white card that lifts slightly with a deeper shadow on hover (desktop/
/// web) and dips on press — the Zoho card feel.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final lift = _pressed ? 0.0 : (_hover ? -3.0 : 0.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTapDown: widget.onTap != null
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          transform: Matrix4.translationValues(0, lift, 0),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.color ?? AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: _hover ? AppColors.blue.withValues(alpha: 0.35) : AppColors.border,
            ),
            boxShadow: _hover ? AppShadows.raised : AppShadows.card,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Zoho's four-colour brand strip (blue · green · amber · red).
class BrandStripe extends StatelessWidget {
  final double height;
  const BrandStripe({super.key, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final c in AppColors.stripe)
            // A Container with no child fills the space it's given; a bare
            // ColoredBox would collapse to zero height.
            Expanded(child: Container(color: c)),
        ],
      ),
    );
  }
}

/// Animates a number counting up to [value] whenever it changes, formatted
/// by [format] (e.g. a currency formatter).
class CountUpText extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: AppMotion.slow * 2,
      curve: AppMotion.curve,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// A grey placeholder block with a moving shine, shown while data loads.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadii.control,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final x = -1.0 + 3 * _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x, 0),
              colors: const [
                Color(0xFFEDEFF2),
                Color(0xFFF8F9FB),
                Color(0xFFEDEFF2),
              ],
            ),
          ),
        );
      },
    );
  }
}

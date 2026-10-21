import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Fades and slides [child] up into place once, when first built — the
/// entrance for cards and list items. [delay] staggers a group
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
/// web) and shrinks a touch on press, so every tap feels answered.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  /// Overrides the resting border (e.g. a selected or out-of-stock card);
  /// hover still tints it blue unless set.
  final Color? borderColor;
  final double borderWidth;

  /// Clip the content to the rounded corners (cards with edge-to-edge
  /// images).
  final bool clip;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.clip = false,
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
    final scale = _pressed ? 0.975 : 1.0;
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
          transform: Matrix4.translationValues(0, lift, 0)
            ..scaleByDouble(scale, scale, 1, 1),
          transformAlignment: Alignment.center,
          padding: widget.padding,
          clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
          decoration: BoxDecoration(
            color: widget.color ?? AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: widget.borderColor ??
                  (_hover
                      ? AppColors.blue.withValues(alpha: 0.35)
                      : AppColors.border),
              width: widget.borderWidth,
            ),
            boxShadow: _hover ? AppShadows.raised : AppShadows.card,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The thin violet → magenta → pink brand strip.
class BrandStripe extends StatelessWidget {
  final double height;
  const BrandStripe({super.key, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: AppColors.stripe),
      ),
    );
  }
}

/// Shrinks [child] slightly while pressed and springs back on release,
/// with a light haptic tick — for buttons and tiles that aren't cards.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.94,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: _pressed
              ? const Duration(milliseconds: 90)
              : const Duration(milliseconds: 320),
          curve: _pressed ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A rounded square filled with [gradient] holding a white [icon] — the
/// app's icon style for menu tiles and section headers.
class GradientIconTile extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final double size;

  const GradientIconTile({
    super.key,
    required this.icon,
    required this.gradient,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = gradient.colors.last;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.35),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}

/// A gradient page header with rounded bottom corners. [title] shows in
/// large white type; [child] (search bars, filters) sits under it.
class GradientHeader extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? child;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const GradientHeader({
    super.key,
    this.title,
    this.subtitle,
    this.child,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 18),
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        boxShadow: AppShadows.glow(const Color(0xFF7C3AED)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Soft light blobs for depth.
          Positioned(
            right: -40,
            top: -60,
            child: _Blob(size: 160, opacity: 0.12),
          ),
          Positioned(
            left: -30,
            bottom: -70,
            child: _Blob(size: 130, opacity: 0.08),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title!,
                            style: textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
                if (child != null) const SizedBox(height: 14),
              ],
              ?child,
            ],
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
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

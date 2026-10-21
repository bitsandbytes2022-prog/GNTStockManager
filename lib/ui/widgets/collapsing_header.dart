import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

/// A header (app bar, search bar, filters…) that slides away as [body] is
/// scrolled down and comes back as soon as it's scrolled up — like a
/// floating, snapping SliverAppBar, but around any existing scrolling body.
///
/// The header follows the finger while scrolling, then snaps fully open or
/// closed when the scroll ends. Only active on phone widths unless
/// [enabled] says otherwise; elsewhere it's a plain header-above-body column.
class CollapsingHeader extends StatefulWidget {
  final Widget header;
  final Widget body;

  /// Defaults to on for widths under 768.
  final bool? enabled;

  /// Fills the status-bar strip above the header (when there is one), so
  /// content never shows through there while the header is hidden.
  final Color statusBarColor;

  const CollapsingHeader({
    super.key,
    required this.header,
    required this.body,
    this.enabled,
    this.statusBarColor = Colors.white,
  });

  @override
  State<CollapsingHeader> createState() => _CollapsingHeaderState();
}

class _CollapsingHeaderState extends State<CollapsingHeader>
    with SingleTickerProviderStateMixin {
  /// 0 = header fully shown, 1 = fully hidden.
  late final AnimationController _hidden = AnimationController(
    vsync: this,
    duration: AppMotion.normal,
  );
  double _headerHeight = 0;

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  void _show() {
    if (_hidden.value > 0 && !_hidden.isAnimating) {
      _hidden.animateTo(0, curve: AppMotion.curve);
    }
  }

  bool _onScroll(ScrollNotification n) {
    final m = n.metrics;
    if (m.axis != Axis.vertical || _headerHeight <= 0) return false;

    // Not enough to scroll for hiding to be worth it (and hiding would let
    // the content fit, leaving no way to scroll the header back).
    if (m.maxScrollExtent - m.minScrollExtent < _headerHeight * 1.5) {
      _show();
      return false;
    }

    if (n is ScrollUpdateNotification) {
      if (m.pixels <= m.minScrollExtent) {
        _hidden.value = 0;
      } else {
        final delta = n.scrollDelta ?? 0;
        // Past the end (iOS bounce) doesn't count as scrolling up.
        if (!(delta < 0 && m.pixels > m.maxScrollExtent)) {
          _hidden.value =
              (_hidden.value + delta / _headerHeight).clamp(0.0, 1.0);
        }
      }
    } else if (n is OverscrollNotification && n.overscroll < 0) {
      _show();
    } else if (n is ScrollEndNotification) {
      final target = m.pixels <= m.minScrollExtent
          ? 0.0
          : (_hidden.value > 0.5 ? 1.0 : 0.0);
      if (_hidden.value != target) {
        _hidden.animateTo(target, curve: AppMotion.curve);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.enabled ?? MediaQuery.sizeOf(context).width < 768;
    if (!enabled) {
      return Column(
        children: [widget.header, Expanded(child: widget.body)],
      );
    }

    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        if (top > 0) Container(height: top, color: widget.statusBarColor),
        MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: AnimatedBuilder(
            animation: _hidden,
            builder: (context, child) => ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1 - _hidden.value,
                child: Opacity(
                  // Fade the last stretch so it doesn't just get cut off.
                  opacity: (1 - _hidden.value * 1.2).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            ),
            child: _SizeReporter(
              onHeight: (h) => _headerHeight = h,
              child: widget.header,
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.body,
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports [child]'s laid-out height after each layout.
class _SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _SizeReporter({required this.onHeight, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, _RenderSizeReporter renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  ValueChanged<double> onHeight;
  _RenderSizeReporter(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

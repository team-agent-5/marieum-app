import 'dart:async';

import 'package:flutter/material.dart';

/// A side menu that sits behind the main pane and is revealed by sliding the
/// whole pane (content and bottom navigation) to the right.
class PushDrawer extends StatefulWidget {
  const PushDrawer({
    required this.drawer,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget drawer;
  final Widget child;

  /// When false the drawer cannot be opened, e.g. while recording.
  final bool enabled;

  static const duration = Duration(milliseconds: 340);
  static const curve = Cubic(0.32, 0.72, 0, 1);
  static const overlap = 8.0;
  static const cornerRadius = 28.0;
  static const drawerLag = 26.0;
  static const backdrop = Color(0xFFDEE9FA);

  /// Width of the left strip that starts an opening swipe, beyond the
  /// system back-gesture area.
  static const edgeWidth = 24.0;
  static const flingVelocity = 365.0;

  static double drawerWidthFor(double screenWidth) =>
      (screenWidth * 0.8).clamp(280.0, 320.0);

  @override
  State<PushDrawer> createState() => _PushDrawerState();
}

class _PushDrawerState extends State<PushDrawer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: PushDrawer.duration,
  );

  bool get _isOpen =>
      _controller.status == AnimationStatus.forward ||
      _controller.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((_) => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : PushDrawer.duration;
  }

  @override
  void didUpdateWidget(PushDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _isOpen) close(animate: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void open() {
    if (!widget.enabled || _isOpen) return;
    unawaited(_controller.forward());
  }

  double _dragExtent = 1;

  void _dragStart(DragStartDetails _) => _controller.stop();

  void _dragUpdate(DragUpdateDetails details) {
    _controller.value += details.primaryDelta! / _dragExtent;
  }

  void _dragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() >= PushDrawer.flingVelocity
        ? velocity > 0
        : _controller.value >= .5;
    unawaited(open ? _controller.forward() : _controller.reverse());
  }

  void close({bool animate = true}) {
    if (_controller.isDismissed) return;
    if (animate) {
      unawaited(_controller.reverse());
    } else {
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) => PushDrawerScope._(
    state: this,
    isOpen: _isOpen,
    child: PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final drawerWidth = PushDrawer.drawerWidthFor(constraints.maxWidth);
          final shift = drawerWidth - PushDrawer.overlap;
          _dragExtent = shift;
          final edge =
              MediaQuery.systemGestureInsetsOf(context).left +
              PushDrawer.edgeWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = PushDrawer.curve.transform(_controller.value);
              final radius = Radius.circular(PushDrawer.cornerRadius * t);
              return Material(
                color: PushDrawer.backdrop,
                child: Stack(
                  children: [
                    if (!_controller.isDismissed)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: drawerWidth,
                        child: Transform.translate(
                          offset: Offset(-PushDrawer.drawerLag * (1 - t), 0),
                          child: Opacity(
                            opacity: 0.55 + 0.45 * t,
                            child: GestureDetector(
                              onHorizontalDragStart: _dragStart,
                              onHorizontalDragUpdate: _dragUpdate,
                              onHorizontalDragEnd: _dragEnd,
                              child: Semantics(
                                label: '앱 메뉴',
                                container: true,
                                explicitChildNodes: true,
                                child: widget.drawer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      key: const ValueKey('push_drawer_pane'),
                      offset: Offset(shift * t, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.horizontal(left: radius),
                          boxShadow: t == 0
                              ? null
                              : [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF17233D,
                                    ).withValues(alpha: 0.10 * t),
                                    offset: const Offset(-10, 0),
                                    blurRadius: 24,
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.horizontal(left: radius),
                          child: Stack(
                            children: [
                              ExcludeSemantics(
                                excluding: _isOpen,
                                child: AbsorbPointer(
                                  absorbing: _isOpen,
                                  child: widget.child,
                                ),
                              ),
                              if (_isOpen)
                                Positioned.fill(
                                  child: GestureDetector(
                                    key: const ValueKey('push_drawer_close'),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: close,
                                    onHorizontalDragStart: _dragStart,
                                    onHorizontalDragUpdate: _dragUpdate,
                                    onHorizontalDragEnd: _dragEnd,
                                  ),
                                ),
                              // Stays mounted through an opening swipe so the
                              // gesture is not cut off.
                              if (widget.enabled && _controller.value < 1)
                                Positioned(
                                  key: const ValueKey('push_drawer_edge'),
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: edge,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onHorizontalDragStart: _dragStart,
                                    onHorizontalDragUpdate: _dragUpdate,
                                    onHorizontalDragEnd: _dragEnd,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class PushDrawerScope extends InheritedWidget {
  const PushDrawerScope._({
    required this._state,
    required this.isOpen,
    required super.child,
  });

  final _PushDrawerState _state;
  final bool isOpen;

  void open() => _state.open();

  /// Without animation the pane is back in place before a new page appears.
  void close({bool animate = true}) => _state.close(animate: animate);

  static PushDrawerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PushDrawerScope>();

  static PushDrawerScope of(BuildContext context) => maybeOf(context)!;

  @override
  bool updateShouldNotify(PushDrawerScope oldWidget) =>
      isOpen != oldWidget.isOpen;
}

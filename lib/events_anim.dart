import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_state.dart';

enum EventKind { six, four, noBall, wide, out, goal, yellow, red }

class _Cfg {
  final String text, emoji;
  final Color color;
  final int particles;
  const _Cfg(this.text, this.emoji, this.color, this.particles);
}

_Cfg _cfgFor(EventKind k) {
  switch (k) {
    case EventKind.six:
      return const _Cfg('SIX!', '🏏', Color(0xFFFF6F00), 110);
    case EventKind.four:
      return const _Cfg('FOUR!', '🏏', Color(0xFF1565C0), 60);
    case EventKind.noBall:
      return const _Cfg('NO BALL', '🚫', Color(0xFFD50000), 0);
    case EventKind.wide:
      return const _Cfg('WIDE', '↔', Color(0xFFF9A825), 0);
    case EventKind.out:
      return const _Cfg('OUT!', '☝', Color(0xFFB71C1C), 70);
    case EventKind.goal:
      return const _Cfg('GOAL!', '⚽', Color(0xFF2E7D32), 110);
    case EventKind.yellow:
      return const _Cfg('YELLOW CARD', '🟨', Color(0xFFF9A825), 0);
    case EventKind.red:
      return const _Cfg('RED CARD', '🟥', Color(0xFFB71C1C), 0);
  }
}

/// Wrap a screen body with this; call `key.currentState?.show([...])`.
class EventOverlay extends StatefulWidget {
  final Widget child;
  const EventOverlay({super.key, required this.child});
  @override
  State<EventOverlay> createState() => EventOverlayState();
}

class EventOverlayState extends State<EventOverlay> {
  EventKind? _current;
  final _pending = <EventKind>[];
  int _seq = 0;

  VoidCallback? _onDone;

  /// Plays the animations in order. [onDone] runs after the last one finishes
  /// (immediately if there is nothing to play).
  void show(List<EventKind> kinds, {VoidCallback? onDone}) {
    if (!AppState.I.animations || kinds.isEmpty) {
      onDone?.call();
      return;
    }
    _pending
      ..clear()
      ..addAll(kinds);
    _onDone = onDone;
    _next();
  }

  void _next() {
    if (!mounted) return;
    if (_pending.isEmpty) {
      setState(() => _current = null);
      final cb = _onDone;
      _onDone = null;
      cb?.call();
      return;
    }
    setState(() {
      _current = _pending.removeAt(0);
      _seq++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (_current != null)
        Positioned.fill(
          child: IgnorePointer(
            child: EventAnim(key: ValueKey(_seq), kind: _current!, onDone: _next),
          ),
        ),
    ]);
  }
}

class _P {
  final double angle, speed, size, spin;
  final Color color;
  _P(this.angle, this.speed, this.size, this.spin, this.color);
}

class EventAnim extends StatefulWidget {
  final EventKind kind;
  final VoidCallback onDone;
  const EventAnim({super.key, required this.kind, required this.onDone});
  @override
  State<EventAnim> createState() => _EventAnimState();
}

class _EventAnimState extends State<EventAnim> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_P> _ps;

  @override
  void initState() {
    super.initState();
    final cfg = _cfgFor(widget.kind);
    final rnd = math.Random();
    final palette = <Color>[
      const Color(0xFFFFD600), Colors.white, cfg.color, const Color(0xFFFF4081),
      const Color(0xFF00E5FF), const Color(0xFF69F0AE),
    ];
    _ps = [
      for (int i = 0; i < cfg.particles; i++)
        _P(
          rnd.nextDouble() * math.pi * 2,
          0.25 + rnd.nextDouble() * 0.75,
          8 + rnd.nextDouble() * 14,
          (rnd.nextDouble() - 0.5) * 2,
          palette[rnd.nextInt(palette.length)],
        ),
    ];
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfgFor(widget.kind);
    return MediaQuery.withNoTextScaling(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final fadeOut = t > 0.75 ? 1 - (t - 0.75) / 0.25 : 1.0;
          final fadeIn = (t / 0.08).clamp(0.0, 1.0);
          final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0);
          final scale = 0.2 + 0.8 * Curves.elasticOut.transform((t / 0.4).clamp(0.0, 1.0));
          double dx = 0;
          if (widget.kind == EventKind.out && t < 0.5) {
            dx = math.sin(t * 60) * 14 * (1 - t / 0.5);
          }
          return LayoutBuilder(builder: (context, box) {
            final base = math.min(box.maxWidth, box.maxHeight * 1.4);
            return Stack(fit: StackFit.expand, children: [
              Container(color: cfg.color.withAlpha((0.4 * opacity * 255).round())),
              if (cfg.particles > 0) CustomPaint(painter: _ParticlePainter(t, _ps)),
              Center(
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(dx, 0),
                    child: Transform.scale(
                      scale: scale,
                      child: SizedBox(
                        width: box.maxWidth * 0.9,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(cfg.emoji,
                                style: TextStyle(
                                    fontSize: base * 0.14, decoration: TextDecoration.none)),
                            Text(
                              cfg.text,
                              style: TextStyle(
                                fontSize: base * 0.2,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                                shadows: const [
                                  Shadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 5)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          });
        },
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double t;
  final List<_P> ps;
  _ParticlePainter(this.t, this.ps);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxD = size.shortestSide;
    final alpha = 1 - ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    for (final p in ps) {
      final d = Curves.easeOutCubic.transform((t / 0.7).clamp(0.0, 1.0)) * p.speed * maxD * 0.8;
      final pos = c +
          Offset(math.cos(p.angle) * d, math.sin(p.angle) * d + 0.6 * maxD * t * t);
      final paint = Paint()..color = p.color.withAlpha((alpha * 255).round());
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t * 8);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

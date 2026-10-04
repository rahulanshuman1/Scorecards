import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class MilestoneInfo {
  final String name, team;
  final int runs, balls, fours, sixes, milestone;
  final double strikeRate;
  final String? photoPath;
  const MilestoneInfo({
    required this.name,
    required this.team,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.milestone,
    required this.strikeRate,
    this.photoPath,
  });

  String get title {
    switch (milestone) {
      case 50:
        return 'FIFTY!';
      case 100:
        return 'CENTURY!';
      case 200:
        return 'DOUBLE CENTURY!';
      case 300:
        return 'TRIPLE CENTURY!';
      default:
        return '$milestone!';
    }
  }
}

class _Conf {
  final double x, offset, speed, size, sway, spin;
  final Color color;
  _Conf(this.x, this.offset, this.speed, this.size, this.sway, this.spin, this.color);
}

class MilestoneAnim extends StatefulWidget {
  final MilestoneInfo info;
  final VoidCallback onDone;
  const MilestoneAnim({super.key, required this.info, required this.onDone});
  @override
  State<MilestoneAnim> createState() => _MilestoneAnimState();
}

class _MilestoneAnimState extends State<MilestoneAnim> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Conf> _conf;
  static const _gold = Color(0xFFFFD600);

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    const palette = [
      Color(0xFFFFD600), Colors.white, Color(0xFFFF4081), Color(0xFF00E5FF),
      Color(0xFF69F0AE), Color(0xFFFF9100),
    ];
    _conf = [
      for (int i = 0; i < 150; i++)
        _Conf(
          rnd.nextDouble(),
          rnd.nextDouble(),
          1.2 + rnd.nextDouble() * 2.0,
          8 + rnd.nextDouble() * 12,
          10 + rnd.nextDouble() * 30,
          (rnd.nextDouble() - 0.5) * 2,
          palette[rnd.nextInt(palette.length)],
        ),
    ];
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500));
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

  Text _t(String s, double size,
          {Color color = Colors.white, FontWeight w = FontWeight.w700, double spacing = 0}) =>
      Text(
        s,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: w,
          letterSpacing: spacing,
          decoration: TextDecoration.none,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 3))],
        ),
      );

  Widget _stat(String label, String value, double base) => Padding(
        padding: EdgeInsets.symmetric(horizontal: base * 0.012),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: base * 0.028, vertical: base * 0.014),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(35),
            borderRadius: BorderRadius.circular(base * 0.02),
            border: Border.all(color: Colors.white.withAlpha(90)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _t(value, base * 0.05, w: FontWeight.w900),
            _t(label, base * 0.02, color: Colors.white70, spacing: 1),
          ]),
        ),
      );

  Widget _avatar(double size, double base) {
    final info = widget.info;
    final parts = info.name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.take(2).map((e) => e.substring(0, 1).toUpperCase()).join();
    final fallback = Container(
      color: const Color(0xFF6A1B9A),
      alignment: Alignment.center,
      child: _t(initials, size * 0.4, w: FontWeight.w900),
    );
    Widget inner = fallback;
    if (info.photoPath != null) {
      inner = Image.file(
        File(info.photoPath!),
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _gold, width: base * 0.01),
        boxShadow: [BoxShadow(color: _gold.withAlpha(140), blurRadius: base * 0.05)],
      ),
      child: ClipOval(child: inner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return MediaQuery.withNoTextScaling(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final fadeIn = (t / 0.08).clamp(0.0, 1.0);
          final fadeOut = t > 0.85 ? 1 - (t - 0.85) / 0.15 : 1.0;
          final o = (fadeIn * fadeOut).clamp(0.0, 1.0);
          final scale = 0.3 + 0.7 * Curves.elasticOut.transform((t / 0.35).clamp(0.0, 1.0));
          return LayoutBuilder(builder: (context, box) {
            final base = math.min(box.maxWidth, box.maxHeight * 1.2);
            final a = (0.93 * o * 255).round();
            return Stack(fit: StackFit.expand, children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0D1B4C).withAlpha(a),
                      const Color(0xFF7B1FA2).withAlpha(a),
                    ],
                  ),
                ),
              ),
              CustomPaint(painter: _ConfPainter(t, _conf, o)),
              Center(
                child: Opacity(
                  opacity: o,
                  child: Transform.scale(
                    scale: scale,
                    child: SizedBox(
                      width: box.maxWidth * 0.92,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          _t(info.title, base * 0.12, color: _gold, w: FontWeight.w900, spacing: 3),
                          SizedBox(height: base * 0.03),
                          _avatar(base * 0.3, base),
                          SizedBox(height: base * 0.025),
                          _t(info.name, base * 0.07, w: FontWeight.w800),
                          _t(info.team, base * 0.032, color: Colors.white70),
                          SizedBox(height: base * 0.01),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              _t('${info.runs}', base * 0.2, w: FontWeight.w900),
                              SizedBox(width: base * 0.02),
                              _t('(${info.balls} balls)', base * 0.05, color: Colors.white70),
                            ],
                          ),
                          SizedBox(height: base * 0.02),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            _stat('BALLS', '${info.balls}', base),
                            _stat('STRIKE RATE', info.strikeRate.toStringAsFixed(1), base),
                            _stat('FOURS', '${info.fours}', base),
                            _stat('SIXES', '${info.sixes}', base),
                          ]),
                        ]),
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

class _ConfPainter extends CustomPainter {
  final double t, o;
  final List<_Conf> cs;
  _ConfPainter(this.t, this.cs, this.o);

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = (o * 255).round();
    for (final p in cs) {
      final phase = (t * p.speed + p.offset) % 1.0;
      final y = phase * (size.height + 60) - 30;
      final x = p.x * size.width + math.sin(phase * 8 + p.offset * 10) * p.sway;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase * p.spin * 10);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
        Paint()..color = p.color.withAlpha(alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfPainter old) => old.t != t || old.o != o;
}

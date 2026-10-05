import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'models.dart';

enum BreakKind { timeout, innings }

/// Opens the full-screen broadcast-style break screen and waits until it closes.
Future<void> showBreak(
  BuildContext context, {
  required CricketMatch match,
  required BreakKind kind,
  required int seconds,
  String? calledBy,
  int timeoutNo = 0,
  int timeoutTotal = 0,
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 600),
    reverseTransitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, __, ___) => BreakScreen(
      match: match,
      kind: kind,
      seconds: seconds,
      calledBy: calledBy,
      timeoutNo: timeoutNo,
      timeoutTotal: timeoutTotal,
    ),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.06, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  ));
}

class BreakScreen extends StatefulWidget {
  final CricketMatch match;
  final BreakKind kind;
  final int seconds;
  final String? calledBy;
  final int timeoutNo, timeoutTotal;
  const BreakScreen({
    super.key,
    required this.match,
    required this.kind,
    required this.seconds,
    this.calledBy,
    this.timeoutNo = 0,
    this.timeoutTotal = 0,
  });

  @override
  State<BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<BreakScreen> with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _intro, _pulse, _bg, _end;
  late Duration _total, _remaining;
  DateTime _last = DateTime.now();
  bool _paused = false, _ending = false;
  int _lastSec = -1;

  bool get _isTimeout => widget.kind == BreakKind.timeout;
  CricketMatch get m => widget.match;
  Color get _accent => _isTimeout ? const Color(0xFFFFB300) : const Color(0xFF29B6F6);
  Color get _accent2 => _isTimeout ? const Color(0xFFFF6F00) : const Color(0xFF7C4DFF);

  @override
  void initState() {
    super.initState();
    _total = Duration(seconds: math.max(1, widget.seconds));
    _remaining = _total;
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..forward();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _bg = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
    _end = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
    _end.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) Navigator.of(context).maybePop();
    });
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _intro.dispose();
    _pulse.dispose();
    _bg.dispose();
    _end.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    final dt = now.difference(_last);
    _last = now;
    if (!_paused && !_ending && _intro.isCompleted) {
      _remaining -= dt;
      if (_remaining <= Duration.zero) {
        _remaining = Duration.zero;
        _finish();
      }
      final sec = _remaining.inSeconds;
      if (sec != _lastSec) {
        _lastSec = sec;
        if (sec <= 5 && sec > 0) HapticFeedback.selectionClick();
      }
    }
    if (mounted) setState(() {});
  }

  void _finish() {
    if (_ending) return;
    _ending = true;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    _end.forward();
  }

  void _addMinute() {
    setState(() {
      _remaining += const Duration(minutes: 1);
      if (_remaining > _total) _total = _remaining;
    });
  }

  // ---------------------------------------------------------------- helpers

  Widget _txt(String s, double size,
          {Color color = Colors.white, FontWeight w = FontWeight.w600, double ls = 0}) =>
      Text(
        s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: w,
          letterSpacing: ls,
          decoration: TextDecoration.none,
        ),
      );

  Widget _stagger(double from, double to, Widget child, {Offset slide = const Offset(0, 40)}) {
    final t = Curves.easeOutCubic.transform(((_intro.value - from) / (to - from)).clamp(0.0, 1.0));
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(slide.dx * (1 - t), slide.dy * (1 - t)),
        child: child,
      ),
    );
  }

  Widget _panel(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withAlpha(24), Colors.white.withAlpha(8)],
          ),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: child,
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          _txt(title, 13, color: Colors.white70, w: FontWeight.w700, ls: 3),
        ]),
      );

  Widget _initials(String s, double size) => Container(
        color: const Color(0xFF3949AB),
        alignment: Alignment.center,
        child: _txt(s, size * 0.4, w: FontWeight.w800),
      );

  Widget _avatar(String team, String name, double size) {
    final p = AppState.I.photoFor(team, name);
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final ini = parts.isEmpty ? '?' : parts.take(2).map((e) => e[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _accent, width: 2),
        boxShadow: [BoxShadow(color: _accent.withAlpha(90), blurRadius: 12)],
      ),
      child: ClipOval(
        child: p != null
            ? Image.file(File(p),
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _initials(ini, size))
            : _initials(ini, size),
      ),
    );
  }

  BatStat? _bs(Innings i, String? n) {
    if (n == null) return null;
    for (final b in i.batting) {
      if (b.name == n) return b;
    }
    return null;
  }

  // ----------------------------------------------------------------- header

  Widget _header() {
    final title = _isTimeout ? 'STRATEGIC TIMEOUT' : 'INNINGS BREAK';
    String sub;
    if (_isTimeout) {
      sub = '${widget.calledBy ?? 'Strategic timeout'}'
          '${widget.timeoutTotal > 0 ? '   •   Timeout ${widget.timeoutNo} of ${widget.timeoutTotal}' : ''}';
    } else {
      final i = m.innings[0];
      sub = '${m.teamA} ${i.runs}/${i.wickets} (${i.overs} ov)   •   First innings complete';
    }
    final line = Curves.easeOutCubic.transform(((_intro.value - 0.2) / 0.5).clamp(0.0, 1.0));
    final blink = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi));
    return _stagger(
      0,
      0.5,
      Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Opacity(
            opacity: blink,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Color(0xFFFF1744), shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          _txt('MATCH PAUSED', 13, color: Colors.white70, w: FontWeight.w700, ls: 5),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: ShaderMask(
            shaderCallback: (r) =>
                LinearGradient(colors: [Colors.white, _accent]).createShader(r),
            child: _txt(title, 54, w: FontWeight.w900, ls: 6),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 3,
          width: 280 * line,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_accent, _accent2]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 10),
        _txt(sub, 16, color: Colors.white70),
      ]),
      slide: const Offset(0, -30),
    );
  }

  // ------------------------------------------------------------------- ring

  Widget _ring(double size) {
    final frac = (_remaining.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final urgent = _remaining.inSeconds < 10 && !_ending;
    final pulseV = math.sin(_pulse.value * 2 * math.pi);
    final color = urgent ? const Color(0xFFFF1744) : _accent;
    final t = Curves.easeOutBack.transform(((_intro.value - 0.15) / 0.6).clamp(0.0, 1.0));
    final secs = (_remaining.inMilliseconds / 1000).ceil();
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    final digitScale = urgent ? 1 + 0.05 * (0.5 + 0.5 * pulseV) : 1.0;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.6 + 0.4 * t,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(frac, color, _accent2, urgent ? 0.6 + 0.4 * pulseV : 0.55),
            ),
            Transform.scale(
              scale: digitScale,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '$mm:$ss',
                  style: TextStyle(
                    fontSize: size * 0.24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 2,
                    decoration: TextDecoration.none,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                _txt(_paused ? 'PAUSED' : 'REMAINING', size * 0.05,
                    color: _paused ? Colors.amber : Colors.white60, w: FontWeight.w700, ls: 4),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- controls

  Widget _controls() {
    final off = _ending;
    return _stagger(
      0.5,
      1.0,
      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          ),
          onPressed: off ? null : () => setState(() => _paused = !_paused),
          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          label: Text(_paused ? 'Resume' : 'Pause'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
          onPressed: off ? null : _addMinute,
          icon: const Icon(Icons.add),
          label: const Text('+1 min'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
          onPressed: off ? null : _finish,
          icon: const Icon(Icons.skip_next),
          label: Text(_isTimeout ? 'End timeout' : 'Start 2nd innings'),
        ),
      ]),
    );
  }

  // --------------------------------------------------------- timeout details

  Widget _timeoutInfo() {
    final i = m.now;
    final chasing = m.current == 1;
    final need = m.target - i.runs;
    final balls = m.overs * 6 - i.legalBalls;
    final rrr = balls > 0 ? need * 6 / balls : 0.0;
    final proj = i.legalBalls == 0 ? 0 : (i.runs * (m.overs * 6) / i.legalBalls).round();
    final st = _bs(i, i.striker);
    final ns = _bs(i, i.nonStriker);
    BowlStat? bw;
    for (final b in i.bowling) {
      if (b.name == i.bowler) bw = b;
    }

    Widget batter(String? name, BatStat? s, bool onStrike) {
      if (name == null) return const SizedBox.shrink();
      return Expanded(
        child: Row(children: [
          _avatar(m.battingTeam, name, 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _txt('$name${onStrike ? '  *' : ''}', 16, w: FontWeight.w700),
              _txt('${s?.runs ?? 0} (${s?.balls ?? 0})', 14, color: Colors.white70),
            ]),
          ),
        ]),
      );
    }

    return _stagger(
      0.35,
      1.0,
      Column(children: [
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('MATCH SITUATION'),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _txt(m.battingTeam, 24, w: FontWeight.w800)),
            _txt('${i.runs}/${i.wickets}', 52, w: FontWeight.w900),
          ]),
          const SizedBox(height: 4),
          _txt('Overs ${i.overs} / ${m.overs}     CRR ${i.runRate.toStringAsFixed(2)}', 15,
              color: Colors.white70),
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(color: Colors.white24, height: 1)),
          if (chasing) ...[
            _txt('TARGET ${m.target}', 13, color: Colors.white60, w: FontWeight.w700, ls: 3),
            const SizedBox(height: 4),
            _txt('NEED $need FROM $balls BALLS', 22, color: _accent, w: FontWeight.w800),
            const SizedBox(height: 2),
            _txt('Required run rate ${rrr.toStringAsFixed(2)}', 15, color: Colors.white70),
          ] else ...[
            _txt('PROJECTED SCORE', 13, color: Colors.white60, w: FontWeight.w700, ls: 3),
            const SizedBox(height: 4),
            _txt('$proj', 34, color: _accent, w: FontWeight.w900),
            _txt('at the current run rate', 14, color: Colors.white70),
          ],
        ])),
        const SizedBox(height: 14),
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('AT THE CREASE'),
          Row(children: [
            batter(i.striker, st, true),
            const SizedBox(width: 10),
            batter(i.nonStriker, ns, false),
          ]),
          if (i.bowler != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              _avatar(m.bowlingTeam, i.bowler!, 46),
              const SizedBox(width: 10),
              Expanded(child: _txt('${i.bowler}', 16, w: FontWeight.w700)),
              _txt(
                bw == null ? '0.0-0-0' : '${bw.overs}-${bw.runs}-${bw.wkts}',
                18,
                color: _accent,
                w: FontWeight.w800,
              ),
            ]),
          ],
        ])),
      ]),
    );
  }

  // ---------------------------------------------------- innings break details

  Widget _inningsInfo() {
    final i = m.innings[0];
    final bat = [...i.batting]..sort((a, b) => b.runs.compareTo(a.runs));
    final topBat = bat.where((b) => b.balls > 0 || b.runs > 0).take(3).toList();
    final bowl = [...i.bowling]..sort((a, b) {
        final w = b.wkts.compareTo(a.wkts);
        return w != 0 ? w : a.runs.compareTo(b.runs);
      });
    final topBowl = bowl.take(3).toList();
    final rrr = m.target * 6 / (m.overs * 6);

    Widget row(String team, String name, String main, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            _avatar(team, name, 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none),
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _txt(main, 20, w: FontWeight.w800),
              _txt(sub, 12, color: Colors.white60),
            ]),
          ]),
        );

    return _stagger(
      0.35,
      1.0,
      Column(children: [
        _panel(Column(children: [
          _txt('TARGET', 13, color: Colors.white60, w: FontWeight.w700, ls: 5),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: m.target.toDouble()),
            duration: const Duration(milliseconds: 2200),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => ShaderMask(
              shaderCallback: (r) =>
                  LinearGradient(colors: [Colors.white, _accent]).createShader(r),
              child: _txt('${v.round()}', 96, w: FontWeight.w900),
            ),
          ),
          _txt('${m.teamB} need ${m.target} runs from ${m.overs} overs (${m.overs * 6} balls)', 16,
              color: Colors.white70),
          const SizedBox(height: 4),
          _txt('Required run rate ${rrr.toStringAsFixed(2)}', 15, color: _accent, w: FontWeight.w700),
        ])),
        const SizedBox(height: 14),
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('${m.teamA.toUpperCase()} – TOP BATTERS'),
          if (topBat.isEmpty) _txt('No runs recorded', 14, color: Colors.white54),
          for (final b in topBat)
            row(m.teamA, b.name, '${b.runs}${b.out ? '' : '*'}',
                '${b.balls} balls • SR ${b.sr.toStringAsFixed(1)}'),
        ])),
        const SizedBox(height: 14),
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('${m.teamB.toUpperCase()} – TOP BOWLERS'),
          if (topBowl.isEmpty) _txt('No bowling recorded', 14, color: Colors.white54),
          for (final b in topBowl)
            row(m.teamB, b.name, '${b.wkts}/${b.runs}',
                '${b.overs} ov • Econ ${b.econ.toStringAsFixed(2)}'),
        ])),
      ]),
    );
  }

  // ----------------------------------------------------------- closing splash

  Widget _endSplash() {
    return AnimatedBuilder(
      animation: _end,
      builder: (context, _) {
        final t = _end.value;
        final inT = Curves.easeOutCubic.transform((t / 0.25).clamp(0.0, 1.0));
        final textT = Curves.easeOutBack.transform(((t - 0.12) / 0.4).clamp(0.0, 1.0));
        final title = _isTimeout ? 'PLAY RESUMES' : 'SECOND INNINGS';
        final line = _isTimeout
            ? '${m.bowlingTeam} to bowl   •   ${m.battingTeam} ${m.now.runs}/${m.now.wickets}'
            : '${m.teamB} need ${m.target} runs from ${m.overs * 6} balls';
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.5 + 1.0 * inT,
              colors: [
                _accent.withAlpha((235 * inT).round()),
                _accent2.withAlpha((245 * inT).round()),
                const Color(0xFF05070F).withAlpha((255 * inT).round()),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: Center(
            child: Opacity(
              opacity: textT.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.7 + 0.3 * textT,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Transform.rotate(
                    angle: t * 2 * math.pi * 1.5,
                    child: const Icon(Icons.sports_cricket, size: 72, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      line,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------- build

  Widget _content(BoxConstraints box) {
    final wide = box.maxWidth >= 900;
    final ringSize = wide
        ? math.min(box.maxHeight * 0.58, box.maxWidth * 0.38)
        : math.min(box.maxWidth * 0.76, 340.0);
    final info = _isTimeout ? _timeoutInfo() : _inningsInfo();
    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          _header(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(padding: const EdgeInsets.all(34), child: _ring(ringSize)),
                      const SizedBox(height: 8),
                      _controls(),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 28),
              Expanded(flex: 6, child: SingleChildScrollView(child: info)),
            ]),
          ),
        ]),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _header(),
        const SizedBox(height: 18),
        Padding(padding: const EdgeInsets.all(30), child: _ring(ringSize)),
        _controls(),
        const SizedBox(height: 20),
        info,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _remaining.inSeconds < 10 && !_ending;
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: const Color(0xFF05070F),
        body: Stack(fit: StackFit.expand, children: [
          CustomPaint(
            painter: _BgPainter(_bg.value, _accent, _accent2, urgent ? const Color(0xFFFF1744) : null),
          ),
          SafeArea(child: LayoutBuilder(builder: (context, box) => _content(box))),
          if (_ending) _endSplash(),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double frac, glow;
  final Color c1, c2;
  _RingPainter(this.frac, this.c1, this.c2, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 14;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = Colors.white.withAlpha(24),
    );
    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 60;
      tick.color = (i / 60 < frac) ? c1.withAlpha(210) : Colors.white.withAlpha(34);
      final r1 = r + 18, r2 = r + (i % 5 == 0 ? 30 : 24);
      canvas.drawLine(
        center + Offset(math.cos(a) * r1, math.sin(a) * r1),
        center + Offset(math.cos(a) * r2, math.sin(a) * r2),
        tick,
      );
    }
    if (frac <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: r);
    final sweep = 2 * math.pi * frac;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round
        ..color = c1.withAlpha((130 * glow).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [c2, c1],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    final ea = -math.pi / 2 + sweep;
    final dot = center + Offset(math.cos(ea) * r, math.sin(ea) * r);
    canvas.drawCircle(dot, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      dot,
      16,
      Paint()
        ..color = c1.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

class _BgPainter extends CustomPainter {
  final double t;
  final Color a1, a2;
  final Color? alert;
  _BgPainter(this.t, this.a1, this.a2, this.alert);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05070F), Color(0xFF0B1030)],
        ).createShader(rect),
    );
    final al = alert;
    final cols = al != null ? [al, al, al] : [a1, a2, a1];
    for (var i = 0; i < 3; i++) {
      final cx = size.width * (0.5 + 0.38 * math.sin(2 * math.pi * (t * (i + 1) + i * 0.33)));
      final cy = size.height * (0.5 + 0.32 * math.cos(2 * math.pi * (t * (i + 1) + i * 0.61)));
      final rad = size.shortestSide * 0.7;
      final c = Offset(cx, cy);
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..shader = RadialGradient(
            colors: [cols[i].withAlpha(al != null ? 70 : 55), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: rad)),
      );
    }
    final rnd = math.Random(7);
    final sp = Paint();
    for (var i = 0; i < 60; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final ph = rnd.nextDouble();
      final r = 0.8 + rnd.nextDouble() * 1.8;
      final a = ((math.sin(2 * math.pi * (t * 24 + ph)) * 0.5 + 0.5) * 120).round();
      sp.color = Colors.white.withAlpha(a);
      canvas.drawCircle(Offset(x, y), r, sp);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => true;
}

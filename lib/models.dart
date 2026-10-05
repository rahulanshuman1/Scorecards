import 'dart:math';

String _p(Object v, int w) => v.toString().padLeft(w);

abstract class SportMatch {
  String id;
  String teamA;
  String teamB;
  DateTime date;
  SportMatch(this.id, this.teamA, this.teamB, this.date);
  String get sport;
  String get summary;
  Map<String, dynamic> toJson();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(999)}';

  static SportMatch fromJson(Map<String, dynamic> j) =>
      j['sport'] == 'cricket' ? CricketMatch.fromJson(j) : FootballMatch.fromJson(j);
}

// ---------------- CRICKET ----------------

class Ball {
  int runs; // off the bat, or wide/no-ball/bye/leg-bye runs
  String? extra; // 'wd', 'nb', 'b', 'lb' or null
  bool wicket;
  String? wkType; // bowled, caught, lbw, stumped, hit wicket, run out
  String? out; // dismissed batter
  // state BEFORE the ball (used for stats and undo)
  String? batter, nonStriker, bowler;

  Ball({
    this.runs = 0,
    this.extra,
    this.wicket = false,
    this.wkType,
    this.out,
    this.batter,
    this.nonStriker,
    this.bowler,
  });

  bool get legal => extra != 'wd' && extra != 'nb';
  bool get penalty => extra == 'wd' || extra == 'nb';
  int get total => runs + (penalty ? 1 : 0);
  int get batterRuns => (extra == null || extra == 'nb') ? runs : 0;
  bool get facedByBatter => extra != 'wd';
  int get bowlerRuns => (extra == 'b' || extra == 'lb') ? 0 : total;
  bool get bowlerWicket => wicket && wkType != 'run out';
  int get extraRuns {
    switch (extra) {
      case 'wd':
        return 1 + runs;
      case 'nb':
        return 1;
      case 'b':
      case 'lb':
        return runs;
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'r': runs, 'e': extra, 'w': wicket, 'wt': wkType, 'o': out,
        'b': batter, 'n': nonStriker, 'bw': bowler,
      };
  factory Ball.fromJson(Map<String, dynamic> j) => Ball(
        runs: j['r'], extra: j['e'], wicket: j['w'], wkType: j['wt'], out: j['o'],
        batter: j['b'], nonStriker: j['n'], bowler: j['bw'],
      );

  String get label {
    if (extra == 'wd') return runs > 0 ? 'Wd+$runs' : 'Wd';
    if (extra == 'nb') return runs > 0 ? 'Nb+$runs' : 'Nb';
    if (extra == 'b') return 'B$runs';
    if (extra == 'lb') return 'Lb$runs';
    if (wicket) return 'W';
    return '$runs';
  }
}

class BatStat {
  final String name;
  int runs = 0, balls = 0, fours = 0, sixes = 0;
  String? how;
  BatStat(this.name);
  bool get out => how != null;
  double get sr => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlStat {
  final String name;
  int balls = 0, runs = 0, wkts = 0;
  BowlStat(this.name);
  String get overs => '${balls ~/ 6}.${balls % 6}';
  double get econ => balls == 0 ? 0 : runs * 6 / balls;
}

/// A batter who retired hurt and was replaced at the crease.
class Retirement {
  final String name; // who retired
  final String replacement; // who came in
  final int atBall; // balls bowled in the innings when it happened
  final bool wasStriker;
  Retirement(this.name, this.replacement, this.atBall, this.wasStriker);

  Map<String, dynamic> toJson() => {'n': name, 'r': replacement, 'a': atBall, 's': wasStriker};
  factory Retirement.fromJson(Map<String, dynamic> j) =>
      Retirement(j['n'], j['r'], j['a'], j['s']);
}

class Innings {
  List<Ball> balls;
  String? striker, nonStriker, bowler;
  List<Retirement> retired;

  Innings({
    List<Ball>? balls,
    this.striker,
    this.nonStriker,
    this.bowler,
    List<Retirement>? retired,
  })  : balls = balls ?? [],
        retired = retired ?? [];

  /// Retire the striker (or non-striker) hurt and bring in [replacement].
  void retire(bool strikerOut, String replacement) {
    final name = strikerOut ? striker : nonStriker;
    if (name == null) return;
    retired.add(Retirement(name, replacement, balls.length, strikerOut));
    if (strikerOut) {
      striker = replacement;
    } else {
      nonStriker = replacement;
    }
  }

  bool _undoRetire() {
    if (retired.isEmpty || retired.last.atBall < balls.length) return false;
    final r = retired.removeLast();
    if (r.wasStriker) {
      striker = r.name;
    } else {
      nonStriker = r.name;
    }
    return true;
  }

  int get runs => balls.fold(0, (s, b) => s + b.total);
  int get wickets => balls.where((b) => b.wicket).length;
  int get legalBalls => balls.where((b) => b.legal).length;
  String get overs => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get runRate => legalBalls == 0 ? 0 : runs * 6 / legalBalls;
  int get extras => balls.fold(0, (s, b) => s + b.extraRuns);
  bool get needsPlayers => striker == null || nonStriker == null || bowler == null;

  List<Ball> get currentOver {
    int done = (legalBalls ~/ 6) * 6;
    if (legalBalls > 0 && legalBalls % 6 == 0 && balls.isNotEmpty && balls.last.legal) {
      done -= 6;
    }
    final out = <Ball>[];
    int seen = 0;
    for (final b in balls) {
      if (seen >= done) out.add(b);
      if (b.legal) seen++;
    }
    return out;
  }

  void _swap() {
    final t = striker;
    striker = nonStriker;
    nonStriker = t;
  }

  void add(Ball b) {
    b.batter = striker;
    b.nonStriker = nonStriker;
    b.bowler = bowler;
    if (b.wicket && b.out == null) b.out = striker;
    balls.add(b);
    if (b.wicket) {
      if (b.out == striker) {
        striker = null;
      } else {
        nonStriker = null;
      }
    } else if (b.runs.isOdd) {
      _swap();
    }
    if (b.legal && legalBalls % 6 == 0) {
      _swap();
      bowler = null;
    }
  }

  void undo() {
    if (_undoRetire()) return;
    if (balls.isEmpty) return;
    final b = balls.removeLast();
    striker = b.batter;
    nonStriker = b.nonStriker;
    bowler = b.bowler;
  }

  List<String> get bowlerNames {
    final s = <String>[];
    for (final b in balls) {
      if (b.bowler != null && !s.contains(b.bowler)) s.add(b.bowler!);
    }
    return s;
  }

  List<BatStat> get batting {
    final map = <String, BatStat>{};
    BatStat s(String n) => map.putIfAbsent(n, () => BatStat(n));
    final away = <String>{}; // retired hurt and not back at the crease
    var ri = 0;
    void applyRetirements(int upTo) {
      while (ri < retired.length && retired[ri].atBall <= upTo) {
        final r = retired[ri++];
        s(r.name);
        away.add(r.name);
      }
    }

    for (var bi = 0; bi < balls.length; bi++) {
      applyRetirements(bi);
      final b = balls[bi];
      away.remove(b.batter);
      away.remove(b.nonStriker);
      final st = s(b.batter ?? 'Unknown');
      if (b.nonStriker != null) s(b.nonStriker!);
      st.runs += b.batterRuns;
      if (b.facedByBatter) st.balls++;
      if (b.extra == null || b.extra == 'nb') {
        if (b.runs == 4) st.fours++;
        if (b.runs == 6) st.sixes++;
      }
      if (b.wicket) s(b.out ?? 'Unknown').how = b.wkType ?? 'out';
    }
    applyRetirements(balls.length);
    if (striker != null) {
      s(striker!);
      away.remove(striker);
    }
    if (nonStriker != null) {
      s(nonStriker!);
      away.remove(nonStriker);
    }
    for (final n in away) {
      final st = map[n];
      if (st != null && st.how == null) st.how = 'retired hurt';
    }
    return map.values.toList();
  }

  List<BowlStat> get bowling {
    final map = <String, BowlStat>{};
    for (final b in balls) {
      final st = map.putIfAbsent(b.bowler ?? 'Unknown', () => BowlStat(b.bowler ?? 'Unknown'));
      if (b.legal) st.balls++;
      st.runs += b.bowlerRuns;
      if (b.bowlerWicket) st.wkts++;
    }
    return map.values.toList();
  }

  Map<String, dynamic> toJson() => {
        'balls': balls.map((b) => b.toJson()).toList(),
        's': striker, 'n': nonStriker, 'bw': bowler,
        'ret': retired.map((r) => r.toJson()).toList(),
      };
  factory Innings.fromJson(Map<String, dynamic> j) => Innings(
        balls: (j['balls'] as List).map((b) => Ball.fromJson(Map<String, dynamic>.from(b))).toList(),
        striker: j['s'], nonStriker: j['n'], bowler: j['bw'],
        retired: ((j['ret'] ?? []) as List)
            .map((r) => Retirement.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

class CricketMatch extends SportMatch {
  int overs;
  List<Innings> innings;
  int current; // 0 or 1
  bool finished;
  List<String> playersA, playersB;

  CricketMatch({
    required String id,
    required String teamA,
    required String teamB,
    required this.overs,
    DateTime? date,
    List<Innings>? innings,
    this.current = 0,
    this.finished = false,
    List<String>? playersA,
    List<String>? playersB,
  })  : innings = innings ?? [Innings(), Innings()],
        playersA = playersA ?? [],
        playersB = playersB ?? [],
        super(id, teamA, teamB, date ?? DateTime.now());

  @override
  String get sport => 'cricket';

  String get battingTeam => current == 0 ? teamA : teamB;
  String get bowlingTeam => current == 0 ? teamB : teamA;
  List<String> get battingPlayers => current == 0 ? playersA : playersB;
  List<String> get bowlingPlayers => current == 0 ? playersB : playersA;
  Innings get now => innings[current];
  int get target => innings[0].runs + 1;

  bool get inningsOver {
    if (now.wickets >= 10 || now.legalBalls >= overs * 6) return true;
    if (current == 1 && now.runs >= target) return true;
    return false;
  }

  void addBall(Ball b) {
    if (finished || inningsOver || now.needsPlayers) return;
    now.add(b);
    if (inningsOver && current == 1) finished = true;
  }

  void undo() {
    if (now.balls.isNotEmpty || now.retired.isNotEmpty) {
      now.undo();
      finished = false;
    } else if (current == 1) {
      current = 0;
      finished = false;
    }
  }

  void endInnings() {
    if (current == 0) {
      current = 1;
    } else {
      finished = true;
    }
  }

  String get result {
    if (!finished) return '';
    final a = innings[0].runs, b = innings[1].runs;
    if (b >= target) return '$teamB won by ${10 - innings[1].wickets} wickets';
    if (b < a) return '$teamA won by ${a - b} runs';
    return 'Match tied';
  }

  @override
  String get summary {
    final s =
        '$teamA ${innings[0].runs}/${innings[0].wickets}  vs  $teamB ${innings[1].runs}/${innings[1].wickets}';
    return finished ? '$s • $result' : '$s • In progress';
  }

  /// Plain ASCII scorecard (used for PDF export and copy).
  String get scorecardText {
    final sb = StringBuffer();
    sb.writeln('$teamA vs $teamB  ($overs overs)');
    sb.writeln(date.toString().substring(0, 16));
    for (int k = 0; k < 2; k++) {
      final i = innings[k];
      if (k == 1 && current == 0 && i.balls.isEmpty) continue;
      sb.writeln();
      sb.writeln('${k == 0 ? teamA : teamB}  ${i.runs}/${i.wickets}  (${i.overs} ov)');
      sb.writeln('-' * 52);
      sb.writeln('${'Batter'.padRight(16)}${_p('R', 5)}${_p('B', 5)}${_p('4s', 5)}${_p('6s', 5)}${_p('SR', 7)}');
      for (final b in i.batting) {
        final nm = (b.name + (b.out ? '' : '*')).padRight(16);
        sb.writeln('$nm${_p(b.runs, 5)}${_p(b.balls, 5)}${_p(b.fours, 5)}${_p(b.sixes, 5)}${_p(b.sr.toStringAsFixed(1), 7)}  ${b.how ?? ''}');
      }
      sb.writeln('Extras: ${i.extras}   Total: ${i.runs}/${i.wickets} (${i.overs} ov)');
      sb.writeln();
      sb.writeln('${'Bowler'.padRight(16)}${_p('O', 6)}${_p('R', 5)}${_p('W', 4)}${_p('Econ', 7)}');
      for (final b in i.bowling) {
        sb.writeln('${b.name.padRight(16)}${_p(b.overs, 6)}${_p(b.runs, 5)}${_p(b.wkts, 4)}${_p(b.econ.toStringAsFixed(2), 7)}');
      }
    }
    if (finished) {
      sb.writeln();
      sb.writeln('Result: $result');
    }
    return sb.toString();
  }

  @override
  Map<String, dynamic> toJson() => {
        'sport': 'cricket',
        'id': id,
        'teamA': teamA,
        'teamB': teamB,
        'date': date.toIso8601String(),
        'overs': overs,
        'current': current,
        'finished': finished,
        'pA': playersA,
        'pB': playersB,
        'innings': innings.map((i) => i.toJson()).toList(),
      };

  factory CricketMatch.fromJson(Map<String, dynamic> j) => CricketMatch(
        id: j['id'],
        teamA: j['teamA'],
        teamB: j['teamB'],
        date: DateTime.parse(j['date']),
        overs: j['overs'],
        current: j['current'],
        finished: j['finished'],
        playersA: List<String>.from(j['pA'] ?? const []),
        playersB: List<String>.from(j['pB'] ?? const []),
        innings: (j['innings'] as List)
            .map((i) => Innings.fromJson(Map<String, dynamic>.from(i)))
            .toList(),
      );
}

// ---------------- FOOTBALL ----------------

class FootballEvent {
  String type; // goal, yellow, red, sub, owngoal
  int team; // 0 or 1
  String player;
  int minute;
  FootballEvent(this.type, this.team, this.player, this.minute);

  Map<String, dynamic> toJson() => {'t': type, 'team': team, 'p': player, 'm': minute};
  factory FootballEvent.fromJson(Map<String, dynamic> j) =>
      FootballEvent(j['t'], j['team'], j['p'], j['m']);
}

class FootballMatch extends SportMatch {
  List<FootballEvent> events;
  int seconds; // elapsed match time
  int period; // 1,2 = halves, 3,4 = extra time
  bool finished;
  List<String> playersA, playersB;

  FootballMatch({
    required String id,
    required String teamA,
    required String teamB,
    DateTime? date,
    List<FootballEvent>? events,
    this.seconds = 0,
    this.period = 1,
    this.finished = false,
    List<String>? playersA,
    List<String>? playersB,
  })  : events = events ?? [],
        playersA = playersA ?? [],
        playersB = playersB ?? [],
        super(id, teamA, teamB, date ?? DateTime.now());

  @override
  String get sport => 'football';

  int get minute => seconds ~/ 60 + 1;

  int score(int team) =>
      events.where((e) => (e.type == 'goal' && e.team == team) ||
          (e.type == 'owngoal' && e.team != team)).length;

  int count(String type, int team) =>
      events.where((e) => e.type == type && e.team == team).length;

  String get periodLabel =>
      const ['', '1st Half', '2nd Half', 'Extra Time 1', 'Extra Time 2'][period];

  @override
  String get summary {
    final s = '$teamA ${score(0)} - ${score(1)} $teamB';
    return finished ? '$s • Full time' : '$s • In progress';
  }

  @override
  Map<String, dynamic> toJson() => {
        'sport': 'football',
        'id': id,
        'teamA': teamA,
        'teamB': teamB,
        'date': date.toIso8601String(),
        'seconds': seconds,
        'period': period,
        'finished': finished,
        'pA': playersA,
        'pB': playersB,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory FootballMatch.fromJson(Map<String, dynamic> j) => FootballMatch(
        id: j['id'],
        teamA: j['teamA'],
        teamB: j['teamB'],
        date: DateTime.parse(j['date']),
        seconds: j['seconds'],
        period: j['period'],
        finished: j['finished'],
        playersA: List<String>.from(j['pA'] ?? const []),
        playersB: List<String>.from(j['pB'] ?? const []),
        events: (j['events'] as List)
            .map((e) => FootballEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

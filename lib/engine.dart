import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Oyunun tüm mantığı burada. Arayüzden bağımsızdır; ChangeNotifier olduğu
/// için ekranlar ListenableBuilder ile dinler.
class GameEngine extends ChangeNotifier {
  GameEngine({Random? random}) : rng = random ?? Random();

  final Random rng;
  String lang = 'tr';
  bool loaded = false;
  final List<Country> countries = [];
  final List<GameEvent> events = [];
  final List<JobDef> jobs = [];
  Json names = {};
  Character? c;
  Decision? pending;

  static const _traitW = {
    'loyal': 24.0,
    'caring': 20.0,
    'hardworking': 20.0,
    'spender': 14.0,
    'cheater': 10.0,
    'plain': 12.0,
  };

  String b(String tr, String en) => lang == 'tr' ? tr : en;

  void setLang(String l) {
    lang = l;
    notifyListeners();
  }

  String eduName(int e) {
    final tr = ['Eğitimsiz', 'İlköğretim', 'Lise', 'Üniversite', 'Yüksek lisans'];
    final en = ['No schooling', 'Primary', 'High school', 'University', 'Postgraduate'];
    return (lang == 'tr' ? tr : en)[min(4, max(0, e))];
  }

  // ───────────────────────── Veri yükleme ─────────────────────────

  Future<void> load({Future<String> Function(String file)? reader}) async {
    final read = reader ?? (String f) => rootBundle.loadString('assets/data/$f');
    Future<List<dynamic>> list(String f) async => jsonDecode(await read(f)) as List<dynamic>;

    countries
      ..clear()
      ..addAll((await list('countries.json')).map((e) => Country.fromJson(Map<String, dynamic>.from(e as Map))));
    events
      ..clear()
      ..addAll((await list('events.json')).map((e) => GameEvent.fromJson(Map<String, dynamic>.from(e as Map))));
    jobs
      ..clear()
      ..addAll((await list('jobs.json')).map((e) => JobDef.fromJson(Map<String, dynamic>.from(e as Map))));
    names = Map<String, dynamic>.from(jsonDecode(await read('names.json')) as Map);
    loaded = true;
    notifyListeners();
  }

  // ───────────────────────── Yardımcılar ─────────────────────────

  double _gauss() {
    final u1 = 1 - rng.nextDouble(), u2 = rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  bool _p(double p) => rng.nextDouble() < p;
  int _ri(int a, int z) => a + rng.nextInt(z - a + 1);
  double _cl(double v, [double lo = 0, double hi = 100]) => v < lo ? lo : (v > hi ? hi : v);

  T _weighted<T>(List<T> items, double Function(T) w) {
    final ws = [for (final i in items) max(0.0001, w(i))];
    var r = rng.nextDouble() * ws.fold<double>(0, (a, x) => a + x);
    for (var i = 0; i < items.length; i++) {
      r -= ws[i];
      if (r <= 0) return items[i];
    }
    return items.last;
  }

  String _name(String region, bool female) {
    final pool = (names[region] ?? names['west']) as Map;
    final list = List<String>.from(pool[female ? 'f' : 'm'] as List);
    return list[rng.nextInt(list.length)];
  }

  void _say(Character ch, String text, String kind) => ch.log.add(LogEntry(ch.age, text, kind));

  String _fill(Character ch, String s) {
    if (!s.contains('{')) return s;
    final kid = ch.children.isEmpty
        ? b('çocuğun', 'your child')
        : ch.children[rng.nextInt(ch.children.length)].name;
    return s
        .replaceAll('{country}', loc(ch.country.name, lang))
        .replaceAll('{spouse}', ch.spouse?.name ?? b('eşin', 'your partner'))
        .replaceAll('{job}', ch.job == null ? b('işin', 'your job') : loc(ch.job!.def.name, lang))
        .replaceAll('{child}', kid)
        .replaceAll('{name}', ch.name);
  }

  // ───────────────────────── Yeni hayat ─────────────────────────

  /// Doğum ülkesi, yıllık doğum sayısına göre ağırlıklı seçilir.
  void newLife() {
    final country = _weighted<Country>(countries, (x) => x.births);
    final female = _p(0.488);
    final ch = Character(
      name: _name(country.region, female),
      female: female,
      country: country,
      health: _cl(62 + (country.lifeExp - 65) * 0.4 + _gauss() * 10, 35, 100),
      happiness: _cl(60 + _gauss() * 8),
      smarts: _cl(50 + _gauss() * 18),
      looks: _cl(50 + _gauss() * 18),
      social: _cl(50 + _gauss() * 12),
      luck: _cl(50 + _gauss() * 20),
      famWealth: _cl(50 + _gauss() * 22),
      retireAge: (country.gdp >= 15 ? 65 : 60) + _ri(0, 3),
    );
    c = ch;
    pending = null;
    final cn = loc(country.name, lang);
    _say(
      ch,
      b('$cn ülkesinde ${female ? 'kız' : 'erkek'} olarak dünyaya geldin. Adın ${ch.name}.',
          'You were born ${female ? 'a girl' : 'a boy'} in $cn. Your name is ${ch.name}.'),
      'milestone',
    );
    final fam = ch.famWealth > 70
        ? b('oldukça varlıklı', 'quite wealthy')
        : ch.famWealth < 30
            ? b('geçim sıkıntısı çekiyor', 'struggling to get by')
            : b('orta halli', 'middle-income');
    _say(ch, b('Ailen $fam.', 'Your family is $fam.'), 'info');
    notifyListeners();
  }

  // ───────────────────────── Oyun akışı ─────────────────────────

  void advanceYear() {
    final ch = c;
    if (ch == null || !ch.alive || pending != null) return;
    _tick(ch);
    notifyListeners();
  }

  /// Bir karar çıkana ya da hayat bitene kadar (en fazla [maxYears]) ilerler.
  void fastForward({int maxYears = 10}) {
    final ch = c;
    if (ch == null || !ch.alive || pending != null) return;
    for (var i = 0; i < maxYears && ch.alive && pending == null; i++) {
      _tick(ch);
    }
    notifyListeners();
  }

  void choose(DecisionOption o) {
    final ch = c, d = pending;
    if (ch == null || d == null) return;
    pending = null;
    _say(ch, '${d.title}: ${o.label}', 'choice');
    o.pick();
    notifyListeners();
  }

  void _tick(Character ch) {
    ch.age++;
    for (final k in ch.children) {
      k.age++;
    }
    _ageStats(ch);
    if (!ch.alive) return;
    _economy(ch);
    _jobYear(ch);
    if (_deathRoll(ch)) return;
    _spouseYear(ch);
    _milestones(ch);

    var n = _p(0.55) ? 1 : 0;
    if (_p(0.15)) n++;
    for (var i = 0; i < n && ch.alive; i++) {
      final ev = _pickEvent(ch, auto: true);
      if (ev != null) {
        ch.seen[ev.id] = ch.age;
        _resolve(ch, ev.autoOutcomes, fallback: ev.text);
      }
    }
    if (!ch.alive) return;
    pending = _forcedDecision(ch) ?? _engineDecision(ch) ?? _eventDecision(ch);
  }

  // ───────────────────────── Yıllık istatistikler ─────────────────────────

  void _ageStats(Character ch) {
    final a = ch.age;
    ch.health += _gauss() * 1.2;
    if (a < 20) ch.health += 0.6;
    if (a > 35) ch.health -= (a - 35) * 0.035 + 0.1;
    if (ch.flags.contains('smoker')) ch.health -= 0.8;
    if (ch.country.gdp < 3) ch.health -= 0.15;
    if (a > 30) ch.looks -= 0.2 + (a - 30) * 0.01;
    if (a < 25 && ch.edu >= 2) ch.smarts += 0.4;
    ch.social += _gauss() * 1.5 + (ch.spouse != null ? 0.3 : 0);

    final rel = a < 18 ? (ch.famWealth - 50) / 25 : _cl(ch.money / ch.country.gdp, -3, 6);
    final target = 52 +
        rel * 2.5 +
        (ch.social - 50) * 0.25 +
        (ch.health - 60) * 0.15 +
        ((ch.spouse?.bond ?? 50) - 50) * 0.1;
    ch.happiness += (target - ch.happiness) * 0.15 + _gauss() * 2;
    _clampStats(ch);
  }

  void _clampStats(Character ch) {
    ch.health = _cl(ch.health);
    ch.happiness = _cl(ch.happiness);
    ch.smarts = _cl(ch.smarts);
    ch.looks = _cl(ch.looks);
    ch.social = _cl(ch.social);
    ch.luck = _cl(ch.luck);
    ch.famWealth = _cl(ch.famWealth);
    if (ch.health <= 0 && ch.alive) _die(ch, b('Sağlık sorunları', 'Health failure'));
  }

  void _economy(Character ch) {
    final g = ch.country.gdp;
    if (ch.age < 18) return;
    if (!ch.flags.contains('adult')) {
      ch.flags.add('adult');
      ch.money = (ch.famWealth - 30) / 100 * g * 1.5;
    }
    var inc = 0.0;
    var exp = g * 0.62;
    if (ch.uniUntil != null) {
      exp = g * 0.30 * (1 - ch.famWealth / 150);
      ch.jobIncome = 0;
    } else if (ch.job != null) {
      ch.jobIncome = g * ch.job!.def.pay * pow(1.12, ch.job!.level - 1) * (ch.edu >= 4 ? 1.15 : 1.0);
      inc = ch.jobIncome;
    } else if (ch.retired) {
      inc = ch.pension;
      ch.jobIncome = 0;
    } else {
      inc = g * 0.2;
      ch.jobIncome = 0;
    }
    final s = ch.spouse;
    if (s != null) {
      inc += g * s.pay * 0.7 * (s.trait == 'hardworking' ? 1.2 : 1.0);
      if (s.trait == 'spender') exp += g * 0.12;
    }
    exp += ch.children.where((k) => k.age < 22).length * g * 0.14;
    if (ch.flags.contains('owns_home')) exp -= g * 0.08;
    ch.income = inc;
    ch.money += inc - exp;
    if (ch.money > ch.peakMoney) ch.peakMoney = ch.money;
  }

  void _jobYear(Character ch) {
    final j = ch.job;
    if (j == null) return;
    j.years++;
    ch.happiness -= (j.def.stress - 50) / 80;
    ch.health -= j.def.drain;
    if (j.level < 5 && _p(0.07 + ch.smarts / 1500 + (ch.luck - 50) / 2500)) {
      j.level++;
      ch.happiness += 5;
      _say(
        ch,
        b('Terfi aldın: ${loc(j.def.name, lang)} (seviye ${j.level}).',
            'You were promoted: ${loc(j.def.name, lang)} (level ${j.level}).'),
        'good',
      );
    }
  }

  // ───────────────────────── Ölüm ve şans ─────────────────────────

  /// Yıllık ölüm olasılığı: ülkenin yaşam beklentisine dayalı Gompertz eğrisi,
  /// sağlık, şans ve yaşam tarzıyla çarpılır.
  double _hazard(int age, double lifeExp, double risk, double health, double luck, Set<String> flags) {
    final infant = 0.002 + 0.07 * (1 - _cl((lifeExp - 50) / 35, 0, 1));
    double h;
    if (age <= 1) {
      h = infant;
    } else if (age < 5) {
      h = infant * 0.25;
    } else if (age < 15) {
      h = infant * 0.05;
    } else {
      h = 0.0004 + risk * 0.002 * (age < 40 ? 1 : 0.3) + 0.01 * exp(0.1 * (age - (lifeExp - 20)));
    }
    h *= exp((50 - health) / 50) * exp((50 - luck) / 150);
    if (flags.contains('smoker')) h *= 1.6;
    if (flags.contains('athlete')) h *= 0.85;
    return _cl(h, 0, 0.95);
  }

  /// true dönerse oyuncu öldü.
  bool _deathRoll(Character ch) {
    final h = _hazard(ch.age, ch.country.lifeExp, ch.country.risk, ch.health, ch.luck, ch.flags);
    if (!_p(h)) return false;
    // Şansa bağlı "kıl payı kurtulma"
    final save = 0.10 + ch.luck / 400 + (ch.age < 5 ? 0.3 : 0);
    if (_p(save)) {
      ch.health = _cl(ch.health - 18);
      _say(
        ch,
        ch.age < 5
            ? b('Ağır bir hastalık geçirdin ama atlattın.', 'You went through a severe illness but pulled through.')
            : b('Ölümden kıl payı döndün; doktorlar buna mucize dedi.',
                'You narrowly escaped death; doctors called it a miracle.'),
        'bad',
      );
      return false;
    }
    _die(ch, _causeOf(ch));
    return true;
  }

  String _causeOf(Character ch) {
    final a = ch.age;
    final List<String> pool = a < 5
        ? [b('Çocukluk hastalığı', 'Childhood illness')]
        : a < 40
            ? [b('Kaza', 'Accident'), b('Ani hastalık', 'Sudden illness')]
            : a < 65
                ? [b('Kalp krizi', 'Heart attack'), b('Kanser', 'Cancer'), b('Kaza', 'Accident'), b('Ani hastalık', 'Sudden illness')]
                : [b('Yaşlılık', 'Old age'), b('Kalp yetmezliği', 'Heart failure'), b('Zatürre', 'Pneumonia'), b('Uykusunda', 'Peacefully in sleep')];
    return pool[rng.nextInt(pool.length)];
  }

  void _die(Character ch, String cause) {
    ch.alive = false;
    ch.cause = cause;
    pending = null;
    _say(ch, b('${ch.age} yaşında hayatını kaybettin: $cause.', 'You died at ${ch.age}: $cause.'), 'bad');
  }

  // ───────────────────────── Eş ve çocuklar ─────────────────────────

  void _spouseYear(Character ch) {
    final s = ch.spouse;
    if (s == null) return;
    s.age++;
    s.yearsMarried++;
    var d = (s.kind - 50) / 50 + _gauss() * 2 + (ch.happiness - 50) / 40 + (ch.money < 0 ? -1.5 : 0.3) - 0.8;
    if (s.trait == 'loyal') d += 1;
    if (s.trait == 'caring') d += 1.2;
    s.bond = _cl(s.bond + d);
    if (!s.traitKnown && s.yearsMarried >= 3 && _p(0.3)) _revealTrait(ch, s);
    final h = _hazard(s.age, ch.country.lifeExp, ch.country.risk, 60, 50, const {});
    if (s.age > 25 && _p(h)) {
      ch.spouse = null;
      ch.happiness -= 25;
      ch.social -= 4;
      ch.flags.add('widowed');
      _say(ch, b('Eşini kaybettin. Büyük bir boşluk kaldı geride.', 'You lost your partner. A great emptiness remains.'), 'bad');
      _clampStats(ch);
    }
  }

  /// Evlendikten birkaç yıl sonra eşin gizli özelliği ortaya çıkar.
  void _revealTrait(Character ch, Person s) {
    s.traitKnown = true;
    final g = ch.country.gdp;
    switch (s.trait) {
      case 'cheater':
        s.bond = _cl(s.bond - 25);
        ch.happiness -= 12;
        _say(ch, b('Eşinin seni aldattığını öğrendin; evliliğin sarsıldı.', 'You found out your partner cheated; your marriage is shaken.'), 'bad');
      case 'spender':
        s.bond = _cl(s.bond - 8);
        ch.money -= g * 0.5;
        _say(ch, b('Eşinin gizli harcamalarını ve borçlarını fark ettin.', 'You discovered your partner\'s hidden spending and debts.'), 'bad');
      case 'loyal':
        s.bond = _cl(s.bond + 8);
        ch.happiness += 4;
        _say(ch, b('Zor günlerde eşinin ne kadar sadık olduğunu gördün.', 'In hard times you saw how loyal your partner is.'), 'good');
      case 'hardworking':
        ch.money += g * 0.4;
        _say(ch, b('Eşinin çalışkanlığı hane gelirine yansımaya başladı.', 'Your partner\'s hard work started to show in household income.'), 'good');
      case 'caring':
        ch.health += 3;
        ch.happiness += 5;
        _say(ch, b('Hasta olduğunda eşin başucundan ayrılmadı.', 'When you were ill, your partner never left your side.'), 'good');
      default:
        break;
    }
    _clampStats(ch);
  }

  Person _genPerson(Character ch) {
    final female = !ch.female;
    final okJobs = jobs.where((j) => j.minEdu <= min(4, ch.edu + 1)).toList();
    final jd = okJobs[rng.nextInt(okJobs.length)];
    final kind = _cl(55 + _gauss() * 20).round();
    return Person(
      name: _name(ch.country.region, female),
      age: max(18, ch.age + _ri(-4, 5)),
      female: female,
      looks: _cl(55 + _gauss() * 20).round(),
      smarts: _cl(55 + _gauss() * 20).round(),
      kind: kind,
      jobName: jd.name,
      pay: jd.pay * (0.8 + rng.nextDouble() * 0.5),
      trait: _weighted<String>(_traitW.keys.toList(), (t) => _traitW[t]!),
      bond: _cl(45 + kind * 0.25 + _gauss() * 6),
    );
  }

  // ───────────────────────── Dönüm noktaları ─────────────────────────

  void _milestones(Character ch) {
    final a = ch.age;
    final e = ch.country.edu;
    ch.flags.remove('grad_offer');

    if (a == 6) {
      if (_p(0.45 + 0.55 * e)) {
        ch.flags.add('in_school');
        _say(ch, b('Okula başladın.', 'You started school.'), 'milestone');
      } else {
        ch.smarts -= 3;
        _say(ch, b('Okula gidemedin; küçük yaşta aileye yardım etmeye başladın.', 'You could not attend school and started helping your family early.'), 'bad');
      }
    }
    if (a == 12 && ch.flags.contains('in_school')) {
      ch.edu = max(ch.edu, 1);
      _say(ch, b('İlköğretimi bitirdin.', 'You finished primary school.'), 'milestone');
    }
    if (a == 17 && ch.edu == 1 && ch.flags.contains('in_school')) {
      if (_p(0.35 + 0.55 * e + (ch.smarts - 50) / 300)) {
        ch.edu = 2;
        _say(ch, b('Liseyi bitirdin.', 'You graduated from high school.'), 'milestone');
      } else {
        _say(ch, b('Liseyi yarıda bıraktın.', 'You dropped out of high school.'), 'bad');
      }
    }
    if (a == 18) ch.flags.remove('in_school');

    final uni = ch.uniUntil;
    if (uni != null && a >= uni) {
      ch.edu = ch.uniEdu;
      ch.uniUntil = null;
      ch.smarts += 3;
      _say(ch, b('Mezun oldun: ${eduName(ch.edu)}.', 'You graduated: ${eduName(ch.edu)}.'), 'milestone');
      if (ch.edu == 3) ch.flags.add('grad_offer');
    }

    if (!ch.retired && a >= ch.retireAge) {
      _retire(ch);
      _say(ch, b('Emekli oldun.', 'You retired.'), 'milestone');
    }
  }

  void _retire(Character ch) {
    if (ch.retired) return;
    ch.retired = true;
    final base = ch.jobIncome > 0 ? ch.jobIncome : ch.country.gdp * 0.4;
    ch.pension = base * (ch.country.gdp >= 15 ? 0.5 : ch.country.gdp >= 5 ? 0.3 : 0.12);
    ch.job = null;
  }

  // ───────────────────────── Motorun kendi kararları ─────────────────────────

  Decision? _engineDecision(Character ch) =>
      _divorceDecision(ch) ?? _marriageDecision(ch) ?? _childDecision(ch) ?? _jobDecision(ch);

  Decision? _divorceDecision(Character ch) {
    final s = ch.spouse;
    if (s == null || s.bond >= 25 || !_p(0.5)) return null;
    final g = ch.country.gdp;
    return Decision(
      title: b('Evlilik krizi', 'Marriage crisis'),
      body: b('${s.name} ile ilişkiniz çok kötü durumda. Ne yapacaksın?', 'Your relationship with ${s.name} is in bad shape. What will you do?'),
      options: [
        DecisionOption(
          label: b('Boşan', 'Get divorced'),
          pick: () {
            ch.spouse = null;
            ch.happiness -= 10;
            ch.social -= 4;
            ch.money -= g * 0.6;
            ch.flags.add('divorced');
            _say(ch, b('Boşandınız. Yeni bir sayfa açmak zorundasın.', 'You divorced. Time to start a new chapter.'), 'bad');
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Evliliği kurtarmaya çalış', 'Try to save the marriage'),
          hint: b('Zaman ve para gerektirir', 'Takes time and money'),
          pick: () {
            ch.spouse?.bond = _cl(ch.spouse!.bond + 18);
            ch.money -= g * 0.1;
            ch.happiness -= 2;
            _say(ch, b('Danışmanlığa gidip ilişkinizi onarmaya çalıştınız.', 'You went to counseling to repair your relationship.'), 'info');
            _clampStats(ch);
          },
        ),
      ],
    );
  }

  Decision? _marriageDecision(Character ch) {
    final lo = max(18, ch.country.marriageAge.round() - 6);
    final hi = ch.country.marriageAge.round() + 14;
    if (ch.spouse != null || ch.age < lo || ch.age > hi) return null;
    if (ch.age - (ch.seen['marry'] ?? -9) < 2) return null;
    if (!_p(0.14 + (ch.social - 50) / 700)) return null;

    final count = _ri(2, 4);
    final cands = [for (var i = 0; i < count; i++) _genPerson(ch)];
    return Decision(
      title: b('Evlilik zamanı mı?', 'Time to settle down?'),
      body: b('Hayatına girebilecek birkaç kişiyle tanıştın. Biriyle ilerlemek ister misin?', 'You met a few people who could enter your life. Want to pursue someone?'),
      options: [
        for (final p in cands)
          DecisionOption(
            label: '${p.name} (${p.age}) · ${loc(p.jobName, lang)}',
            hint: b('Çekicilik ${p.looks} · Zekâ ${p.smarts} · Karakter ${p.kind}', 'Looks ${p.looks} · Smarts ${p.smarts} · Character ${p.kind}'),
            pick: () => _propose(ch, p),
          ),
        DecisionOption(
          label: b('Şimdilik hayır', 'Not now'),
          pick: () {
            ch.seen['marry'] = ch.age;
            _say(ch, b('Şimdilik bekar kalmayı seçtin.', 'You chose to stay single for now.'), 'info');
          },
        ),
      ],
    );
  }

  void _propose(Character ch, Person p) {
    ch.seen['marry'] = ch.age;
    final acc = _cl(
      0.45 + (ch.looks + ch.smarts + ch.social) / 600 + (ch.money / ch.country.gdp) * 0.03 + (ch.luck - 50) / 500,
      0.25,
      0.92,
    );
    if (_p(acc)) {
      ch.spouse = p;
      ch.marriages++;
      ch.happiness += 12;
      ch.social += 4;
      ch.flags.remove('widowed');
      _say(ch, b('${p.name} teklifini kabul etti, evlendiniz!', '${p.name} said yes and you got married!'), 'good');
    } else {
      ch.happiness -= 8;
      _say(ch, b('${p.name} teklifini reddetti. Canın çok sıkıldı.', '${p.name} turned you down. It hurt.'), 'bad');
    }
    _clampStats(ch);
  }

  Decision? _childDecision(Character ch) {
    final s = ch.spouse;
    if (s == null || s.yearsMarried < 1 || ch.children.length >= 6) return null;
    final motherAge = ch.female ? ch.age : s.age;
    if (motherAge > 42) return null;
    if (ch.age - (ch.seen['child'] ?? -9) < 2) return null;
    if (!_p(ch.country.fertility / 9 * pow(0.6, ch.children.length))) return null;

    return Decision(
      title: b('Aile büyür mü?', 'Growing the family?'),
      body: b('${s.name} ile çocuk sahibi olmayı konuşuyorsunuz.', 'You and ${s.name} are talking about having a child.'),
      options: [
        DecisionOption(
          label: b('Evet, çocuk isteyelim', 'Yes, let\'s have a child'),
          pick: () {
            ch.seen['child'] = ch.age;
            final p = _cl(0.85 - max(0, motherAge - 30) * 0.04, 0.2, 0.9);
            if (_p(p)) {
              final girl = _p(0.49);
              final kid = Child(name: _name(ch.country.region, girl), age: 0, female: girl);
              ch.children.add(kid);
              ch.happiness += 10;
              ch.health -= 1;
              _say(ch, b('${kid.name} dünyaya geldi! Hayatın bambaşka bir hal aldı.', '${kid.name} was born! Your life changed completely.'), 'good');
            } else {
              ch.happiness -= 4;
              _say(ch, b('Denediniz ama olmadı.', 'You tried but it didn\'t happen.'), 'bad');
            }
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Şimdilik hayır', 'Not now'),
          pick: () {
            ch.seen['child'] = ch.age;
            _say(ch, b('Çocuk sahibi olmayı ertelediniz.', 'You postponed having a child.'), 'info');
          },
        ),
      ],
    );
  }

  Decision? _jobDecision(Character ch) {
    if (ch.retired || ch.age < 18 || ch.age > 60 || ch.uniUntil != null) return null;
    final employed = ch.job != null;
    if (employed) {
      if (ch.age < 22 || ch.age - (ch.seen['job'] ?? -9) < 4 || !_p(0.07)) return null;
    } else if (!_p(0.6)) {
      return null;
    }
    final pool = jobs.where((j) => j.minEdu <= ch.edu && j.id != ch.job?.def.id).toList()..shuffle(rng);
    if (pool.isEmpty) return null;
    final offers = pool.take(employed ? 2 : 3).toList();
    final g = ch.country.gdp;
    return Decision(
      title: employed ? b('Yeni iş teklifi', 'New job offer') : b('İş teklifleri', 'Job offers'),
      body: employed
          ? b('Başka bir yerden teklif aldın. Geçmek ister misin?', 'You got an offer elsewhere. Will you switch?')
          : b('Çalışma hayatına atılma vakti. Önünde birkaç seçenek var.', 'Time to find work. You have a few options.'),
      options: [
        for (final j in offers)
          DecisionOption(
            label: loc(j.name, lang),
            hint: b('~${fmtMoney(g * j.pay)}/yıl · stres ${j.stress}', '~${fmtMoney(g * j.pay)}/yr · stress ${j.stress}'),
            pick: () => _applyFor(ch, j),
          ),
        DecisionOption(
          label: employed ? b('Mevcut işimde kal', 'Stay in my job') : b('Şimdilik bekle', 'Wait for now'),
          pick: () {
            ch.seen['job'] = ch.age;
            _say(ch, b('Teklifleri değerlendirmedin.', 'You passed on the offers.'), 'info');
          },
        ),
      ],
    );
  }

  void _applyFor(Character ch, JobDef j) {
    ch.seen['job'] = ch.age;
    final p = _cl(0.6 + (ch.smarts - 50) / 150 + (ch.luck - 50) / 300 + (ch.edu > j.minEdu ? 0.1 : 0), 0.3, 0.95);
    final name = loc(j.name, lang);
    if (_p(p)) {
      ch.job = Job(j);
      ch.jobsHeld++;
      ch.happiness += 4;
      _say(ch, b('$name olarak işe girdin.', 'You got a job as: $name.'), 'good');
    } else {
      ch.happiness -= 4;
      _say(ch, b('$name mülakatında elendin.', 'You were turned down for the $name job.'), 'bad');
    }
    _clampStats(ch);
  }

  // ───────────────────────── Olay sistemi (JSON) ─────────────────────────

  bool _ok(Character ch, Map<String, dynamic> cond) {
    if (cond.isEmpty) return true;
    bool below(double v, String k) => cond[k] != null && v < (cond[k] as num);
    bool above(double v, String k) => cond[k] != null && v > (cond[k] as num);

    if (cond['female'] != null && cond['female'] != ch.female) return false;
    if (cond['country'] != null && !(cond['country'] as List).contains(ch.country.code)) return false;
    if (cond['region'] != null && !(cond['region'] as List).contains(ch.country.region)) return false;
    if (below(ch.health, 'minHealth') || above(ch.health, 'maxHealth')) return false;
    if (below(ch.happiness, 'minHappiness') || above(ch.happiness, 'maxHappiness')) return false;
    if (below(ch.smarts, 'minSmarts') || above(ch.smarts, 'maxSmarts')) return false;
    if (below(ch.social, 'minSocial') || above(ch.social, 'maxSocial')) return false;
    if (below(ch.luck, 'minLuck') || above(ch.luck, 'maxLuck')) return false;
    final rel = ch.money / ch.country.gdp;
    if (below(rel, 'minMoney') || above(rel, 'maxMoney')) return false;
    if (below(ch.edu.toDouble(), 'minEdu') || above(ch.edu.toDouble(), 'maxEdu')) return false;
    if (below(ch.famWealth, 'minFam') || above(ch.famWealth, 'maxFam')) return false;
    if (below(ch.country.risk, 'minRisk')) return false;
    if (below(ch.country.gdp, 'minGdp') || above(ch.country.gdp, 'maxGdp')) return false;
    if (cond['married'] != null && cond['married'] != (ch.spouse != null)) return false;
    if (cond['hasJob'] != null && cond['hasJob'] != (ch.job != null)) return false;
    if (cond['hasKids'] != null && cond['hasKids'] != ch.children.isNotEmpty) return false;
    if (cond['retired'] != null && cond['retired'] != ch.retired) return false;
    for (final f in (cond['flagsAll'] as List? ?? const [])) {
      if (!ch.flags.contains(f)) return false;
    }
    for (final f in (cond['flagsNone'] as List? ?? const [])) {
      if (ch.flags.contains(f)) return false;
    }
    return true;
  }

  bool _eligible(Character ch, GameEvent ev) {
    if (ch.age < ev.minAge || ch.age > ev.maxAge) return false;
    final last = ch.seen[ev.id];
    if (last != null && (ev.once || ch.age - last < ev.cooldown)) return false;
    return _ok(ch, ev.cond);
  }

  /// Uygun olaylar arasından ağırlıklı seçim. Şans, iyi/kötü olayların
  /// görülme sıklığını kaydırır; ülke riski afet benzeri olayları artırır.
  GameEvent? _pickEvent(Character ch, {required bool auto}) {
    final pool = events.where((e) => !e.force && (e.choices.isEmpty == auto) && _eligible(ch, e)).toList();
    if (pool.isEmpty) return null;
    return _weighted<GameEvent>(pool, (e) {
      var w = e.weight;
      if (e.tone == 'good') w *= 0.6 + ch.luck / 125;
      if (e.tone == 'bad') w *= 1.4 - ch.luck / 125;
      if (e.riskScale) w *= 0.3 + ch.country.risk * 2;
      return w;
    });
  }

  Decision? _forcedDecision(Character ch) {
    for (final ev in events) {
      if (ev.force && ev.choices.isNotEmpty && _eligible(ch, ev)) return _decisionFromEvent(ch, ev);
    }
    return null;
  }

  Decision? _eventDecision(Character ch) {
    if (!_p(0.32)) return null;
    final ev = _pickEvent(ch, auto: false);
    return ev == null ? null : _decisionFromEvent(ch, ev);
  }

  Decision _decisionFromEvent(Character ch, GameEvent ev) {
    ch.seen[ev.id] = ch.age;
    return Decision(
      title: ev.title != null ? _fill(ch, loc(ev.title, lang)) : b('Karar zamanı · ${ch.age} yaş', 'Decision time · age ${ch.age}'),
      body: _fill(ch, loc(ev.text, lang)),
      options: [
        for (final choice in ev.choices)
          DecisionOption(
            label: _fill(ch, loc(choice.text, lang)),
            pick: () => _resolve(ch, choice.outcomes),
          ),
      ],
    );
  }

  void _resolve(Character ch, List<Outcome> os, {dynamic fallback}) {
    if (os.isEmpty) return;
    _applyOutcome(ch, _pickOutcome(ch, os), fallback: fallback);
  }

  double _stat(Character ch, String k) => switch (k) {
        'health' => ch.health,
        'happiness' => ch.happiness,
        'smarts' => ch.smarts,
        'looks' => ch.looks,
        'social' => ch.social,
        'luck' => ch.luck,
        'famWealth' => ch.famWealth,
        _ => 50.0,
      };

  /// Birden fazla sonuç varsa ağırlıklı zar atılır. `lucky` sonuçlar şansla,
  /// `check` sonuçlar ilgili istatistikle güçlenir.
  Outcome _pickOutcome(Character ch, List<Outcome> os) {
    if (os.length == 1) return os.first;
    return _weighted<Outcome>(os, (o) {
      var w = o.w;
      if (o.lucky) w *= 0.5 + ch.luck / 100;
      if (o.check != null) w *= 0.5 + _stat(ch, o.check!) / 100;
      return w;
    });
  }

  void _applyOutcome(Character ch, Outcome o, {dynamic fallback}) {
    _apply(ch, o.effects);
    ch.flags.addAll(o.setFlags);
    ch.flags.removeAll(o.clearFlags);
    final text = _fill(ch, loc(o.result ?? fallback, lang));
    if (text.isNotEmpty) _say(ch, text, _kind(o.effects));
    if (o.death != null && ch.alive) _die(ch, _fill(ch, loc(o.death, lang)));
  }

  String _kind(Map<String, dynamic> e) {
    double s = 0;
    e.forEach((k, v) {
      if (v is! num) return;
      if (k == 'money') {
        s += v * 8;
      } else if (const ['health', 'happiness', 'smarts', 'looks', 'social'].contains(k)) {
        s += v;
      }
    });
    return s > 3 ? 'good' : (s < -3 ? 'bad' : 'info');
  }

  void _apply(Character ch, Map<String, dynamic> e) {
    double n(dynamic v) => (v as num).toDouble();
    e.forEach((k, v) {
      switch (k) {
        case 'health':
          ch.health += n(v);
        case 'happiness':
          ch.happiness += n(v);
        case 'smarts':
          ch.smarts += n(v);
        case 'looks':
          ch.looks += n(v);
        case 'social':
          ch.social += n(v);
        case 'luck':
          ch.luck += n(v);
        case 'money':
          // Etki, ülkenin kişi başı gelirinin katı olarak yazılır.
          if (ch.age < 18) {
            ch.famWealth += n(v) * 15;
          } else {
            ch.money += n(v) * ch.country.gdp;
          }
        case 'edu':
          ch.edu = min(4, max(0, ch.edu + (v as num).toInt()));
        case 'bond':
          final s = ch.spouse;
          if (s != null) s.bond = _cl(s.bond + n(v));
        case 'quitJob':
          ch.job = null;
        case 'retire':
          _retire(ch);
        case 'loseSpouse':
          ch.spouse = null;
        case 'kids':
          for (var i = 0; i < (v as num).toInt(); i++) {
            final girl = _p(0.49);
            ch.children.add(Child(name: _name(ch.country.region, girl), age: 0, female: girl));
          }
        case 'emigrate':
          _emigrate(ch, v as String);
        case 'startUni':
          final m = v as Map;
          ch.uniUntil = ch.age + (m['years'] as num).toInt();
          ch.uniEdu = (m['edu'] as num).toInt();
          ch.job = null;
      }
    });
    _clampStats(ch);
  }

  void _emigrate(Character ch, String kind) {
    final pool = countries.where((x) => x.code != ch.country.code && (kind == 'rich' ? x.gdp >= 15 : true)).toList();
    if (pool.isEmpty) return;
    final to = pool[rng.nextInt(pool.length)];
    ch.country = to;
    ch.countriesLived++;
    ch.social -= 6;
    ch.flags.add('emigrated');
    _say(ch, b('${loc(to.name, lang)} ülkesine taşındın.', 'You moved to ${loc(to.name, lang)}.'), 'milestone');
  }
}

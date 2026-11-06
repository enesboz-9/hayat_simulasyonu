import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'achievements.dart';
import 'divorce_law.dart';
import 'models.dart';
import 'relationships.dart';

/// Oyunun tüm mantığı burada. Arayüzden bağımsızdır; ChangeNotifier olduğu
/// için ekranlar ListenableBuilder ile dinler.
class GameEngine extends ChangeNotifier {
  GameEngine({Random? random, AchievementStorage? storage})
      : rng = random ?? Random(),
        storage = storage ?? MemoryAchievementStorage();

  final Random rng;

  /// Başarıların kalıcı deposu (uygulamada shared_preferences, testte bellek).
  final AchievementStorage storage;

  /// Şimdiye kadar açılmış tüm başarılar (hayatlar arası kalıcı) ve başlatılan hayat sayısı.
  final Map<String, Unlock> unlocked = {};
  int livesStarted = 0;

  /// Yönelim ayarı (yeni hayatlara uygulanır): opposite, same, both, random.
  String orientationSetting = 'opposite';
  final List<Achievement> _fresh = [];
  String lang = 'tr';
  bool loaded = false;
  final List<Country> countries = [];
  final List<GameEvent> events = [];
  final List<JobDef> jobs = [];
  Json names = {};
  Character? c;
  Decision? pending;

  /// Son kararın değerlere etkisi; arayüz bunu kısa bildirim olarak gösterir.
  List<StatDelta> lastDeltas = const [];


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
    // Ek olaylar (events_more.json): aynı kimlikli olay varsa "_2" ekiyle ayrı
    // bir varyant olarak eklenir; dosya yoksa oyun yine çalışır.
    try {
      final have = events.map((e) => e.id).toSet();
      for (final file in const ['events_more.json', 'events_cosmetic.json', 'events_life.json']) {
        for (final raw in await list(file)) {
          final j = Map<String, dynamic>.from(raw as Map);
          var id = j['id'] as String;
          while (have.contains(id)) {
            id = '${id}_2';
          }
          j['id'] = id;
          have.add(id);
          events.add(GameEvent.fromJson(j));
        }
      }
    } catch (_) {}
    // Uzun vadeli sonuç olayları: ayrı yüklenir ki biri bozulursa diğerleri etkilenmesin.
    try {
      final have = events.map((e) => e.id).toSet();
      for (final raw in await list('events_legacy.json')) {
        final j = Map<String, dynamic>.from(raw as Map);
        if (have.add(j['id'] as String)) events.add(GameEvent.fromJson(j));
      }
    } catch (_) {}
    jobs
      ..clear()
      ..addAll((await list('jobs.json')).map((e) => JobDef.fromJson(Map<String, dynamic>.from(e as Map))));
    names = Map<String, dynamic>.from(jsonDecode(await read('names.json')) as Map);
    await _loadProgress();
    loaded = true;
    notifyListeners();
  }

  // ───────────────────────── Başarılar ─────────────────────────

  Future<void> _loadProgress() async {
    try {
      final raw = await storage.read();
      if (raw == null || raw.isEmpty) return;
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      livesStarted = (m['lives'] as num?)?.toInt() ?? 0;
      final o = m['orientation'];
      if (o is String && kAttractionModes.contains(o)) orientationSetting = o;
      unlocked.clear();
      for (final e in ((m['unlocked'] as Map?) ?? const {}).entries) {
        unlocked[e.key as String] = Unlock.fromJson(Map<String, dynamic>.from(e.value as Map));
      }
    } catch (_) {
      // Bozuk kayıt oyunu engellemesin; sıfırdan başlanır.
    }
  }

  void _saveProgress() {
    final data = jsonEncode({
      'lives': livesStarted,
      'orientation': orientationSetting,
      'unlocked': {for (final e in unlocked.entries) e.key: e.value.toJson()},
    });
    storage.write(data).catchError((_) {});
  }

  void setOrientation(String mode) {
    if (!kAttractionModes.contains(mode)) return;
    orientationSetting = mode;
    _saveProgress();
    notifyListeners();
  }

  /// Arayüz için: açılan başarı sayısı ve toplam başarı sayısı.
  int get unlockedCount => unlocked.length;
  int get achievementTotal => kAchievements.length;

  /// Henüz gösterilmemiş, yeni açılan başarıları verir ve kuyruğu boşaltır.
  List<Achievement> takeFreshUnlocks() {
    final out = List<Achievement>.of(_fresh);
    _fresh.clear();
    return out;
  }

  /// Her yıl ve her karardan sonra çağrılır: bu hayatta henüz kazanılmamış
  /// başarıların koşullarına bakar, sağlananları kaydeder.
  void _achieve(Character ch) {
    final j = ch.job;
    if (j != null) {
      ch.jobIds.add(j.def.id);
      if (j.level > ch.bestJobLevel) ch.bestJobLevel = j.level;
    }
    var changed = false;
    for (final a in kAchievements) {
      if (ch.earned.contains(a.id)) continue;
      var ok = false;
      try {
        ok = a.test(ch);
      } catch (_) {
        // Hatalı bir koşul oyunu çökertmesin.
      }
      if (!ok) continue;
      ch.earned.add(a.id);
      if (!unlocked.containsKey(a.id)) {
        unlocked[a.id] = Unlock(
          age: ch.age,
          who: ch.name,
          flag: ch.birthCountry.flag,
          at: DateTime.now().toIso8601String(),
        );
        ch.firstTime.add(a.id);
        _fresh.add(a);
        changed = true;
      }
    }
    if (changed) _saveProgress();
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
        .replaceAll('{spouse}', ch.spouse?.name ?? ch.partner?.name ?? b('eşin', 'your partner'))
        .replaceAll('{job}', ch.job == null ? b('işin', 'your job') : loc(ch.job!.def.name, lang))
        .replaceAll('{child}', kid)
        .replaceAll('{name}', ch.name);
  }

  // ───────────────────────── Yeni hayat ─────────────────────────

  /// Doğum ülkesi, gerçek hayattaki yıllık doğum sayısıyla orantılı seçilir:
  /// bir ülkede doğma ihtimali = o ülkenin doğum sayısı / dünya doğum sayısı.
  Country _pickBirthCountry() => _weighted<Country>(countries, (x) => x.births);

  /// Yeni hayat başlatır; doğum ülkesi gerçek doğum oranlarına göre seçilir.
  void newLife() {
    final country = _pickBirthCountry();
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
    ch.healthBase = ch.health;
    ch.hasSiblings = _p(_cl(0.35 + country.fertility * 0.15, 0.3, 0.95));
    var attr = orientationSetting;
    if (attr == 'random') {
      final r = rng.nextDouble();
      attr = r < 0.88 ? 'opposite' : (r < 0.92 ? 'same' : 'both');
    }
    ch.attraction = attr;
    ch.attrRandom = orientationSetting == 'random';
    ch.livedIn.add(country.code);
    livesStarted++;
    _saveProgress();
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
    _achieve(ch);
    notifyListeners();
  }

  /// Bir karar çıkana ya da hayat bitene kadar (en fazla [maxYears]) ilerler.
  void fastForward({int maxYears = 10}) {
    final ch = c;
    if (ch == null || !ch.alive || pending != null) return;
    for (var i = 0; i < maxYears && ch.alive && pending == null; i++) {
      _tick(ch);
      _achieve(ch);
    }
    notifyListeners();
  }

  void choose(DecisionOption o) {
    final ch = c, d = pending;
    if (ch == null || d == null) return;
    pending = null;
    _say(ch, '${d.title}: ${o.label}', 'choice');
    final before = _snapshot(ch);
    o.pick();
    _achieve(ch);
    lastDeltas = _diff(before, _snapshot(ch));
    notifyListeners();
  }

  Map<String, double> _snapshot(Character ch) => {
        'health': ch.health,
        'happiness': ch.happiness,
        'smarts': ch.smarts,
        'looks': ch.looks,
        'social': ch.social,
        'money': ch.age < 18 ? 0 : ch.money,
      };

  /// İki görüntü arasındaki farkı döndürür; yuvarlanınca 0 olanlar atlanır.
  List<StatDelta> _diff(Map<String, double> a, Map<String, double> z) {
    final out = <StatDelta>[];
    z.forEach((k, v) {
      final d = v - (a[k] ?? v);
      final shown = k == 'money' ? d.abs() >= 0.05 : d.round() != 0;
      if (shown) out.add(StatDelta(k, d));
    });
    return out;
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
    _partnerYear(ch);
    _affairYear(ch);
    _parentsYear(ch);
    _milestones(ch);
    _dueConsequences(ch);
    if (!ch.alive) return;

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
    pending = _nextDecision(ch);
  }

  /// Eski seçimlerin gecikmeli sonuçlarından zamanı gelenleri uygular.
  void _dueConsequences(Character ch) {
    if (ch.scheduled.isEmpty) return;
    final due = ch.scheduled.where((x) => x.dueAge <= ch.age).toList();
    if (due.isEmpty) return;
    ch.scheduled.removeWhere((x) => x.dueAge <= ch.age);
    for (final x in due) {
      if (!ch.alive) break;
      _applyOutcome(ch, x.outcome);
    }
  }

  /// Seçim ekranı temposu: 6 yaşından önce hiç seçim çıkmaz; sonra çoğunlukla
  /// 2-3 yılda bir, nadiren 1 ya da 4 yılda bir çıkar. Aldatılma / ilişkinin
  /// ortaya çıkması gibi acil sonuç kararları bekletilmez.
  Decision? _nextDecision(Character ch) {
    if (ch.age < 6) return null;
    Decision? d = _affairExposedDecision(ch) ?? _spouseCheatDecision(ch);
    if (d == null && ch.age >= ch.nextDecisionAge) {
      d = _forcedDecision(ch) ?? _engineDecision(ch) ?? _eventDecision(ch);
    }
    if (d != null) ch.nextDecisionAge = ch.age + _decisionGap();
    return d;
  }

  /// Seçimler arası yıl: %6 → 1, %42 → 2, %42 → 3, %10 → 4.
  int _decisionGap() {
    final r = rng.nextDouble();
    if (r < 0.06) return 1;
    if (r < 0.48) return 2;
    if (r < 0.90) return 3;
    return 4;
  }

  /// Anne-baba yaşlanır ve ölebilir; torun müjdesi gelebilir.
  void _parentsYear(Character ch) {
    if (ch.motherAlive) {
      final h = _hazard(ch.age + 27, ch.country.lifeExp, ch.country.risk, 60, 50, const {});
      if (_p(h)) {
        ch.motherAlive = false;
        ch.happiness -= 12;
        _say(ch, b('Annen hayatını kaybetti.', 'Your mother passed away.'), 'bad');
      }
    }
    if (ch.fatherAlive) {
      final h = _hazard(ch.age + 30, ch.country.lifeExp, ch.country.risk, 60, 50, const {});
      if (_p(h)) {
        ch.fatherAlive = false;
        ch.happiness -= 12;
        _say(ch, b('Baban hayatını kaybetti.', 'Your father passed away.'), 'bad');
      }
    }
    if (!ch.flags.contains('grandkids') && ch.children.any((k) => k.age >= 26) && _p(0.1)) {
      ch.flags.add('grandkids');
      ch.happiness += 6;
      _say(ch, b('Torunun dünyaya geldi!', 'Your first grandchild was born!'), 'good');
    }
    _clampStats(ch);
  }

  // ───────────────────────── Hayatın izleri ─────────────────────────

  static const _marks = <String, (String, String, String)>{
    'athlete': ('🏃', 'Spor yapan biri', 'An active athlete'),
    'smoker': ('🚬', 'Sigara içti', 'Smoked'),
    'ex_smoker': ('🫁', 'Sigarayı bıraktı', 'Quit smoking'),
    'drinker': ('🍷', 'Alkol alışkanlığı', 'Drinking habit'),
    'scammed': ('🪤', 'Dolandırıldı', 'Was scammed'),
    'scam_savvy': ('🛡️', 'Dolandırıcılara karşı uyanık', 'Scam-savvy'),
    'scholarship': ('🎓', 'Burslu okudu', 'Won a scholarship'),
    'mentor': ('🧭', 'Genç bir öğrenciye mentor oldu', 'Mentored a young student'),
    'volunteer': ('🤝', 'Gönüllü', 'Volunteer'),
    'business_owner': ('💼', 'Kendi işini kurdu', 'Started a business'),
    'owns_home': ('🏠', 'Ev sahibi oldu', 'Bought a home'),
    'has_pet': ('🐾', 'Evcil dostu vardı', 'Had a pet'),
    'lost_pet': ('🕊️', 'Sadık bir dostunu uğurladı', 'Said goodbye to a loyal companion'),
    'college_fund': ('📚', 'Çocuğuna üniversite fonu kurdu', 'Built a college fund for their child'),
    'family_active': ('👨‍👧', 'Çocuğuyla spor yaptı', 'Stayed active with their child'),
    'emigrated': ('✈️', 'Başka ülkeye göç etti', 'Emigrated'),
    'grandkids': ('👶', 'Torun sahibi oldu', 'Became a grandparent'),
  };

  /// Özet ekranı için: bu hayatı şekillendiren izler ("🏃 Spor yapan biri · 21 yaşından beri").
  List<String> lifeMarks(Character ch) {
    final out = <String>[];
    _marks.forEach((k, v) {
      if (!ch.flags.contains(k)) return;
      final at = ch.flagAge[k];
      final label = b(v.$2, v.$3);
      out.add(at == null ? '${v.$1} $label' : '${v.$1} $label · ${b('$at yaşında', 'age $at')}');
    });
    return out;
  }

  // ───────────────────────── Yıllık istatistikler ─────────────────────────

  void _ageStats(Character ch) {
    final a = ch.age;
    // Hastalık / kaza hasarı her yıl kısmen iyileşir (sağlık, kalıcı düzeye döner).
    // Kalıcı düzeyin üstüne çıkan kazanç (spor, tedavi) yarı yarıya kalıcı olur.
    // Bu olmadan olayların verdiği hasar birikir ve ölüm ortalamanın hep altında kalır.
    final gap = ch.healthBase - ch.health;
    if (gap > 0) {
      ch.health += gap * 0.15;
    } else if (gap < 0) {
      ch.healthBase -= gap * 0.5;
    }
    ch.health += _gauss() * 1.2;
    var det = 0.0; // yaşlanma ve yaşam tarzı: hem sağlığı hem kalıcı düzeyi etkiler
    if (a < 20) det += 0.6;
    if (a > 35) {
      var decay = (a - 35) * 0.035 + 0.1;
      // Uzun yıllar spor: yaşlılıkta sağlık kaybı yavaşlar (en fazla %40).
      // Avantaj spora başladığından beri geçen yıllarla büyür.
      final since = ch.flagAge['athlete'];
      if (ch.flags.contains('athlete') && since != null && a >= 45) {
        decay *= 1 - min(0.4, (a - since) * 0.015);
      }
      det -= decay;
    }
    if (ch.flags.contains('smoker')) det -= 0.8;
    if (ch.country.gdp < 3) det -= 0.15;
    ch.health += det;
    ch.healthBase += det;
    if (a > 30) ch.looks -= 0.2 + (a - 30) * 0.01;
    if (a < 25 && ch.edu >= 2) ch.smarts += 0.4;
    ch.social += _gauss() * 1.5 + (ch.spouse != null || ch.partner != null ? 0.3 : 0);

    final rel = a < 18 ? (ch.famWealth - 50) / 25 : _cl(ch.money / ch.country.gdp, -3, 6);
    final target = 52 +
        rel * 2.5 +
        (ch.social - 50) * 0.25 +
        (ch.health - 60) * 0.15 +
        ((ch.spouse?.bond ?? ch.partner?.bond ?? 50) - 50) * 0.1;
    ch.happiness += (target - ch.happiness) * 0.15 + _gauss() * 2;
    _clampStats(ch);
  }

  void _clampStats(Character ch) {
    ch.health = _cl(ch.health);
    ch.healthBase = _cl(ch.healthBase);
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
      ch.joblessYears = 0;
    } else if (ch.job != null) {
      ch.joblessYears = 0;
      ch.jobIncome = g * ch.job!.def.pay * pow(1.12, ch.job!.level - 1) * (ch.edu >= 4 ? 1.15 : 1.0);
      inc = ch.jobIncome;
    } else if (ch.retired) {
      inc = ch.pension;
      ch.jobIncome = 0;
      ch.joblessYears = 0;
    } else {
      inc = g * 0.2;
      ch.jobIncome = 0;
      ch.joblessYears++;
    }
    final s = ch.spouse;
    if (s != null) {
      inc += g * s.pay * 0.7 * (s.trait == 'hardworking' ? 1.2 : 1.0);
      if (s.trait == 'spender') exp += g * 0.12;
    }
    final lp = ch.partner;
    if (lp != null && lp.living) {
      // Birlikte yaşayan sevgili ortak giderlere katkı verir.
      inc += g * lp.pay * 0.4;
      if (lp.trait == 'spender') exp += g * 0.06;
    }
    exp += ch.children.where((k) => k.age < 22).length * g * 0.14;
    // Boşanmış ebeveyn, küçük çocuklar için ek nafaka/destek öder.
    if (s == null && ch.flags.contains('divorced')) {
      exp += ch.children.where((k) => k.age < 18).length * g * 0.05;
    }
    if (ch.flags.contains('owns_home')) exp -= g * 0.08;
    ch.income = inc;
    ch.money += inc - exp;
    if (ch.money > ch.peakMoney) ch.peakMoney = ch.money;
  }

  void _jobYear(Character ch) {
    final j = ch.job;
    if (j == null) return;
    j.years++;
    if (j.def.id == 'model' && ch.age > 38 && _p(0.3)) {
      ch.job = null;
      ch.happiness -= 3;
      _say(ch, b('Mankenlik kariyerin sona erdi.', 'Your modelling career came to an end.'), 'info');
      return;
    }
    ch.happiness -= (j.def.stress - 50) / 80;
    ch.health -= j.def.drain;
    ch.healthBase -= j.def.drain;
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
      h = 0.0004 + risk * 0.002 * (age < 40 ? 1 : 0.3) + 0.0045 * exp(0.1 * (age - (lifeExp - 20)));
    }
    h *= exp((50 - health) / 50) * exp((50 - luck) / 150);
    if (flags.contains('smoker')) h *= 1.6;
    if (flags.contains('ex_smoker')) h *= 1.15;
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
      ch.nearDeaths++;
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

    // Eşin seni aldattı mı? (yıllık "öğrenilme" ihtimali)
    if (!ch.flags.contains('spouse_cheat_found') && s.yearsMarried >= 1) {
      final cp = s.trait == 'cheater' ? 0.05 : 0.007 + (s.bond < 35 ? 0.012 : 0) + (s.looks > 75 ? 0.004 : 0);
      if (_p(cp)) {
        s.cheated = true;
        ch.flags.add('spouse_cheat_found');
      }
    }

    final h = _hazard(s.age, ch.country.lifeExp, ch.country.risk, 60, 50, const {});
    if (s.age > 25 && _p(h)) {
      ch.spouse = null;
      ch.happiness -= 25;
      ch.social -= 4;
      ch.flags
        ..add('widowed')
        ..remove('affair')
        ..remove('affair_found')
        ..remove('spouse_cheat_found');
      ch.affairYears = 0;
      _say(ch, b('Eşini kaybettin. Büyük bir boşluk kaldı geride.', 'You lost your partner. A great emptiness remains.'), 'bad');
      _clampStats(ch);
      return;
    }

    // Bağ iyice kopmuşsa eş boşanma davası açabilir.
    if (s.bond < 12 && _p(0.25)) {
      _say(ch, b('${s.name} boşanma davası açtı.', '${s.name} filed for divorce.'), 'bad');
      _divorce(ch, byPartner: true);
    }
  }

  /// Kusur kimde? Oyuncu şu an gizli bir ilişki yürütüyorsa ya da eşini
  /// affettiyse kusur "yok" sayılır; eş aldattıysa kusur eştedir.
  Fault _faultOf(Character ch, Person s) {
    if (ch.flags.contains('affair') || ch.flags.contains('forgave')) return Fault.none;
    return s.cheated ? Fault.partner : Fault.none;
  }

  double _playerIncome(Character ch) => ch.retired ? ch.pension : (ch.job != null ? ch.jobIncome : 0.0);

  double _spouseIncome(Character ch, Person s) =>
      ch.country.gdp * s.pay * 0.7 * (s.trait == 'hardworking' ? 1.2 : 1.0);

  DivorceTerms _terms(Character ch, Person s, Fault f, DivorceMode m, bool byPartner, bool? win) =>
      computeDivorceTerms(
        ch: ch,
        spouse: s,
        fault: f,
        mode: m,
        playerIncome: _playerIncome(ch),
        spouseIncome: _spouseIncome(ch, s),
        byPartner: byPartner,
        win: win,
      );

  String _signed(double v) => '${v >= 0 ? '+' : '-'}${fmtMoney(v.abs())}';

  /// Parasal sonucun kısa, okunur dökümü.
  List<String> _termsParts(DivorceTerms t) {
    final parts = <String>[];
    if (t.splitPaid > 0.05) {
      parts.add(b('${t.regime.separate ? 'eşin malı' : 'mal paylaşımı'} -${fmtMoney(t.splitPaid)}',
          '${t.regime.separate ? 'spouse\'s own assets' : 'asset split'} -${fmtMoney(t.splitPaid)}'));
    }
    if (t.compensation.abs() > 0.05) {
      parts.add(b('tazminat ${_signed(t.compensation)}', 'damages ${_signed(t.compensation)}'));
    }
    final mahr = t.mahrPart;
    final nafaka = t.support - mahr;
    if (mahr.abs() > 0.05) parts.add(b('mehir ${_signed(mahr)}', 'mahr ${_signed(mahr)}'));
    if (nafaka.abs() > 0.05) {
      parts.add(b('nafaka ${_signed(nafaka)}', 'alimony ${_signed(nafaka)}'));
    }
    if (t.cost > 0.05) parts.add(b('masraf -${fmtMoney(t.cost)}', 'costs -${fmtMoney(t.cost)}'));
    return parts;
  }

  String _termsHint(DivorceTerms t) {
    final parts = _termsParts(t);
    if (parts.isEmpty) return '';
    return b('Tahmini: ${parts.join(' · ')} (net ${_signed(t.net)})',
        'Estimate: ${parts.join(' · ')} (net ${_signed(t.net)})');
  }

  String _faultText(Fault f) => switch (f) {
        Fault.partner => b('Kusur eşinde: sen suçsuzsun, tazminat ödemezsin, tazminat alırsın.',
            'Your partner is at fault: you owe no damages and you are entitled to damages.'),
        Fault.player => b('Kusur sende.', 'You are at fault.'),
        Fault.none => b('Kimsenin ağır kusuru yok.', 'Neither side is clearly at fault.'),
      };

  /// Boşanma türünü sorar: anlaşmalı (ucuz, tazminat pazarlıkla düşer) ya da
  /// çekişmeli (pahalı, dava kazanılırsa kazanç büyür).
  void _askDivorceMode(Character ch, {bool byPartner = false, Fault? fault}) {
    final s = ch.spouse;
    if (s == null) return;
    final f = fault ?? _faultOf(ch, s);
    final regime = regimeFor(ch.country);
    pending = Decision(
      title: b('Boşanma türü', 'Type of divorce'),
      body: '${_faultText(f)} ${b(regime.tr, regime.en)}',
      options: [
        DecisionOption(
          label: b('Anlaşmalı boşan', 'Uncontested divorce'),
          hint: _termsHint(_terms(ch, s, f, DivorceMode.amicable, byPartner, null)),
          pick: () => _divorce(ch, byPartner: byPartner, fault: f, mode: DivorceMode.amicable),
        ),
        DecisionOption(
          label: b('Davayı sonuna kadar götür', 'Fight it out in court'),
          hint: _termsHint(_terms(ch, s, f, DivorceMode.contested, byPartner, null)),
          pick: () => _divorce(ch, byPartner: byPartner, fault: f, mode: DivorceMode.contested),
        ),
      ],
    );
  }

  /// Boşanma: ülkenin hukukuna ve kusura göre mal paylaşımı, tazminat, nafaka
  /// ve masraf uygulanır. Sayaçlar güncellenir.
  void _divorce(
    Character ch, {
    bool byPartner = false,
    Fault? fault,
    DivorceMode mode = DivorceMode.contested,
  }) {
    final s = ch.spouse;
    if (s == null) return;
    final f = fault ?? _faultOf(ch, s);
    bool? win;
    if (mode == DivorceMode.contested) {
      final tilt = f == Fault.partner ? 0.15 : (f == Fault.player ? -0.2 : 0.0);
      win = _p(_cl(0.5 + (ch.luck - 50) / 400 + tilt, 0.15, 0.85));
    }
    final t = _terms(ch, s, f, mode, byPartner, win);
    ch.money += t.net;
    ch.compReceived += t.received;
    ch.compPaid += t.paidOut;
    ch.spouse = null;
    ch.divorces++;
    ch.happiness -= (byPartner ? 12 : 8) - (mode == DivorceMode.amicable ? 2 : 0);
    if (f == Fault.partner && t.received > 0) ch.happiness += 3;
    ch.social -= 4;
    if (ch.children.any((k) => k.age < 18)) ch.happiness -= 3;
    ch.flags
      ..add('divorced')
      ..remove('widowed')
      ..remove('affair')
      ..remove('affair_found')
      ..remove('spouse_cheat_found')
      ..remove('forgave');
    ch.affairYears = 0;
    ch.seen['marry'] = ch.age;

    final parts = _termsParts(t);
    final summary = parts.isEmpty ? '' : ' ${parts.join(' · ')}.';
    _say(
      ch,
      b('${s.name} ile boşandınız.$summary Net: ${_signed(t.net)}.',
          'You divorced ${s.name}.$summary Net: ${_signed(t.net)}.'),
      t.net >= 0 ? 'info' : 'bad',
    );
    // Hukuki gerekçe.
    if (f == Fault.partner) {
      _say(
        ch,
        t.compensation > 0.05
            ? b('Kusur ${s.name}\'de olduğundan tazminat ödemedin; tersine ${fmtMoney(t.compensation)} tazminat aldın.${win == true ? ' Davayı kazandın.' : (win == false ? ' Dava beklediğinin altında sonuçlandı.' : '')}',
                'Because ${s.name} was at fault you paid no damages; you received ${fmtMoney(t.compensation)} in damages.${win == true ? ' You won the case.' : (win == false ? ' The case ended below your hopes.' : '')}')
            : b('Kusur ${s.name}\'de olduğundan sen tazminat ödemedin.', 'Because ${s.name} was at fault you paid no damages.'),
        'good',
      );
    } else if (f == Fault.player) {
      _say(
        ch,
        t.compensation < -0.05
            ? b('Kusur sende olduğundan ${s.name}\'e ${fmtMoney(-t.compensation)} tazminat ödedin.', 'Because you were at fault you paid ${s.name} ${fmtMoney(-t.compensation)} in damages.')
            : b('Ülkende kusur tazminatı yok; olağan paylaşım kuralları uygulandı.', 'Your country has no fault-based damages; the ordinary division rules applied.'),
        'info',
      );
    }
    _clampStats(ch);
  }

  /// Bu yıl evlilik krizi çıkma ihtimali (0-1). Ülkenin yaklaşık boşanma
  /// istatistiği; evlilik süresi, evlendiği yaş, çocuk, para durumu, eğitim,
  /// gizli ilişki ve ilişki gücüyle çarpılır.
  double divorceChance(Character ch) {
    final s = ch.spouse;
    if (s == null) return 0;
    final y = s.yearsMarried;
    var f = y <= 1
        ? 0.7
        : y <= 7
            ? 1.5
            : y <= 14
                ? 1.0
                : y <= 24
                    ? 0.65
                    : 0.35;
    if (s.ageAtMarriage < 22) {
      f *= 1.5;
    } else if (s.ageAtMarriage > 30) {
      f *= 0.85;
    }
    if (ch.children.any((k) => k.age < 18)) f *= 0.7;
    if (ch.money < 0) f *= 1.35;
    if (ch.edu >= 3) f *= 0.9;
    if (ch.flags.contains('affair')) f *= 1.8;
    if (s.bond < 25) {
      f *= 3.0;
    } else if (s.bond < 40) {
      f *= 1.8;
    } else if (s.bond > 70) {
      f *= 0.4;
    }
    return _cl(ch.country.divorce / 100 * f * 1.35, 0, 0.6);
  }

  /// Oyuncuya gösterilen yaklaşık "ömür boyu boşanma" yüzdesi.
  int _lifetimeDivorcePct(Country c) => (100 * (1 - pow(1 - c.divorce / 100, 30))).round();

  String _crisisReason(Character ch, Person s) {
    final opts = <(double, String, String)>[
      (ch.money < 0 ? 3.0 : 0.5, 'Para sıkıntısı yüzünden sürekli tartışıyorsunuz.', 'Money trouble keeps causing fights.'),
      (s.bond < 40 ? 3.5 : 2.0, 'Zamanla birbirinizden koptunuz.', 'You have slowly drifted apart.'),
      (1.5, '${s.name} ile sürekli tartışıyorsunuz.', 'You keep arguing with ${s.name}.'),
      (s.trait == 'spender' && s.traitKnown ? 2.5 : 0.0001, 'Eşinin harcamaları evliliği zorluyor.', 'Your partner\'s spending is straining the marriage.'),
      ((ch.job?.def.stress ?? 40) > 60 ? 1.5 : 0.3, 'İş stresin eve taşındı ve ilişkiniz yıprandı.', 'Work stress followed you home and wore the relationship down.'),
      (ch.children.isNotEmpty ? 1.0 : 0.2, 'Çocuk bakımı yüzünden sürekli geriliyorsunuz.', 'Childcare keeps putting you both on edge.'),
      (ch.flags.contains('forgave') ? 2.5 : 0.0001, 'Geçmişteki güven sorunu ilişkiyi hâlâ zehirliyor.', 'The old breach of trust still poisons the relationship.'),
    ];
    final o = _weighted<(double, String, String)>(opts, (x) => x.$1);
    return b(o.$2, o.$3);
  }

  /// Gizli ilişki sürerken yıllık akış: ortaya çıkma ya da kendiliğinden bitme.
  void _affairYear(Character ch) {
    if (!ch.flags.contains('affair')) return;
    final s = ch.spouse;
    if (s == null) {
      ch.flags.remove('affair');
      ch.affairYears = 0;
      return;
    }
    ch.affairYears++;
    s.bond = _cl(s.bond - 2.5);
    ch.happiness += 1.5;
    if (_p(0.14 + 0.04 * ch.affairYears)) {
      ch.flags
        ..remove('affair')
        ..add('affair_found');
      ch.affairYears = 0;
      ch.social -= 3;
    } else if (ch.affairYears >= 3 && _p(0.3)) {
      ch.flags.remove('affair');
      ch.affairYears = 0;
      ch.happiness -= 3;
      _say(
        ch,
        b('Gizli ilişkin sessizce bitti. Kimse öğrenmedi ama vicdan azabı kaldı.',
            'Your secret affair quietly ended. Nobody found out, but the guilt stayed.'),
        'info',
      );
    }
    _clampStats(ch);
  }

  /// Evlendikten birkaç yıl sonra eşin gizli özelliği ortaya çıkar.
  void _revealTrait(Character ch, Person s) {
    s.traitKnown = true;
    final g = ch.country.gdp;
    switch (s.trait) {
      case 'cheater':
        // Sonucu bir karar olarak sunulur (_spouseCheatDecision).
        s.cheated = true;
        ch.flags.add('spouse_cheat_found');
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

  Person _genPerson(Character ch, {bool? female}) {
    final f = female ?? switch (ch.attraction) {
      'same' => ch.female,
      'both' => _p(0.5),
      _ => !ch.female,
    };
    final okJobs = jobs.where((j) => !j.special && j.minEdu <= min(4, ch.edu + 1)).toList();
    final jd = okJobs[rng.nextInt(okJobs.length)];
    final kind = _cl(55 + _gauss() * 20).round();
    final g = ch.country.gdp;
    final age = max(18, ch.age + _ri(-4, 5));
    final pay = jd.pay * (0.8 + rng.nextDouble() * 0.5);
    // Varlık: çalıştığı yıllar × maaş × rastgele birikim oranı ± borç/miras.
    final working = max(0, age - 21);
    final wealth = _cl(
      g * (pay * working * 0.12 * (0.4 + 1.2 * rng.nextDouble()) + _gauss() * 0.6 - 0.3),
      -1.5 * g,
      20 * g,
    );
    return Person(
      name: _name(ch.country.region, f),
      age: age,
      wealth: wealth,
      female: f,
      looks: _cl(55 + _gauss() * 20).round(),
      smarts: _cl(55 + _gauss() * 20).round(),
      kind: kind,
      jobName: jd.name,
      pay: pay,
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
    if (a == 16 && ch.attrRandom) {
      _say(
        ch,
        switch (ch.attraction) {
          'same' => b('Ergenlikte kendini keşfettin: aynı cinse ilgi duyuyorsun.', 'As a teenager you realised you are attracted to people of your own sex.'),
          'both' => b('Ergenlikte kendini keşfettin: her iki cinse de ilgi duyuyorsun.', 'As a teenager you realised you are attracted to people of any sex.'),
          _ => b('Ergenlikte ilk kez birine gönlün kaydı.', 'As a teenager you felt your first real crush.'),
        },
        'milestone',
      );
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
      _affairExposedDecision(ch) ??
      _spouseCheatDecision(ch) ??
      _divorceDecision(ch) ??
      _temptationDecision(ch) ??
      _marriageDecision(ch) ??
      _partnerDecision(ch) ??
      _childDecision(ch) ??
      _starOfferDecision(ch) ??
      _jobDecision(ch);

  /// Evlilik krizi: çıkma ihtimali [divorceChance] ile ülke istatistiğinden gelir.
  Decision? _divorceDecision(Character ch) {
    final s = ch.spouse;
    if (s == null || s.yearsMarried < 1) return null;
    if (!_p(divorceChance(ch))) return null;
    final g = ch.country.gdp;
    final pct = _lifetimeDivorcePct(ch.country);
    return Decision(
      title: b('Evlilik krizi', 'Marriage crisis'),
      body: '${_crisisReason(ch, s)} ${b('Ülkende evliliklerin yaklaşık %$pct kadarı boşanmayla bitiyor.', 'Roughly $pct% of marriages in your country end in divorce.')}',
      options: [
        DecisionOption(
          label: b('Boşan', 'Get divorced'),
          hint: _termsHint(_terms(ch, s, _faultOf(ch, s), DivorceMode.amicable, false, null)),
          pick: () => _askDivorceMode(ch),
        ),
        DecisionOption(
          label: b('Çift terapisine git', 'Try couples counseling'),
          hint: b('Zaman ve para gerektirir; garantisi yok', 'Costs time and money; no guarantee'),
          pick: () {
            ch.money -= g * 0.1;
            final ok = _p(_cl(0.3 + s.bond / 200 + (s.trait == 'caring' ? 0.1 : 0), 0.15, 0.8));
            if (ok) {
              s.bond = _cl(s.bond + 20);
              ch.happiness += 2;
              _say(ch, b('Terapi işe yaradı; yeniden birbirinizi duymaya başladınız.', 'Counseling worked; you started hearing each other again.'), 'good');
            } else {
              s.bond = _cl(s.bond - 6);
              ch.happiness -= 3;
              _say(ch, b('Terapi pek bir şeyi değiştirmedi.', 'Counseling changed very little.'), 'bad');
            }
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Görmezden gel', 'Ignore it'),
          hint: b('Sorun büyüyebilir', 'The problem may grow'),
          pick: () {
            s.bond = _cl(s.bond - 6);
            ch.happiness -= 2;
            _say(ch, b('Sorunu halının altına süpürdün; mesafe arttı.', 'You swept it under the rug; the distance grew.'), 'info');
            _clampStats(ch);
          },
        ),
      ],
    );
  }

  /// Evliyken karşına çıkan gizli ilişki fırsatı.
  Decision? _temptationDecision(Character ch) {
    final s = ch.spouse;
    if (s == null || s.yearsMarried < 1 || ch.age < 21 || ch.age > 65) return null;
    if (ch.flags.contains('affair') || ch.flags.contains('affair_found')) return null;
    if (ch.age - (ch.seen['temptation'] ?? -9) < 3) return null;
    var p = ch.female ? 0.017 : 0.025;
    p *= 0.7 + ch.looks / 150;
    p *= 0.7 + ch.social / 150;
    if (s.bond < 35) {
      p *= 2.5;
    } else if (s.bond > 75) {
      p *= 0.5;
    }
    if (ch.happiness < 40) p *= 1.4;
    if (!_p(_cl(p, 0, 0.2))) return null;
    ch.seen['temptation'] = ch.age;
    return Decision(
      title: b('Bir fırsat', 'A temptation'),
      body: b('Biri sana beklenmedik bir ilgi gösteriyor. ${s.name} hiçbir şey bilmiyor.',
          'Someone is showing you unexpected interest. ${s.name} knows nothing.'),
      options: [
        DecisionOption(
          label: b('İlişkiye başla', 'Start an affair'),
          hint: b('Yakalanma riski yıllar içinde artar', 'The risk of being caught grows over the years'),
          pick: () {
            ch.flags.add('affair');
            ch.affairs++;
            ch.affairYears = 0;
            ch.happiness += 6;
            _say(ch, b('Gizli bir ilişkiye başladın.', 'You started a secret affair.'), 'info');
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Reddet', 'Turn it down'),
          pick: () {
            s.bond = _cl(s.bond + 2);
            ch.happiness -= 1;
            _say(ch, b('Teklifi reddettin ve evliliğine odaklandın.', 'You turned it down and focused on your marriage.'), 'info');
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Eşinle konuş', 'Talk to your partner'),
          hint: b('Aranızda ne eksik, açıkça konuşursun', 'You talk openly about what is missing'),
          pick: () {
            s.bond = _cl(s.bond + 5);
            _say(ch, b('${s.name} ile açık bir konuşma yaptınız; yakınlaştınız.', 'You had an honest talk with ${s.name} and grew closer.'), 'good');
          },
        ),
      ],
    );
  }

  /// Gizli ilişkin eşine duyuruldu.
  Decision? _affairExposedDecision(Character ch) {
    if (!ch.flags.contains('affair_found')) return null;
    ch.flags.remove('affair_found');
    final s = ch.spouse;
    if (s == null) return null;
    _say(ch, b('${s.name} gizli ilişkini öğrendi.', '${s.name} found out about your affair.'), 'bad');
    return Decision(
      title: b('Sır ortaya çıktı', 'Found out'),
      body: b('${s.name} gizli ilişkini öğrendi. İstatistiklere göre bu durumdaki evliliklerin kabaca yarısı biter.',
          '${s.name} found out about your affair. Roughly half of marriages in this situation end.'),
      options: [
        DecisionOption(
          label: b('Özür dile, ilişkiyi bitir', 'Apologize and end it'),
          hint: b('Affedilme şansı eşinin bağlılığına bağlı', 'Forgiveness depends on how attached your partner is'),
          pick: () {
            if (_p(_cl(0.25 + s.bond / 220 + (s.trait == 'loyal' ? 0.1 : 0), 0.1, 0.7))) {
              s.bond = _cl(s.bond - 12);
              ch.happiness -= 5;
              ch.flags.add('forgave');
              _say(ch, b('${s.name} seni affetti, ama güven eskisi gibi değil.', '${s.name} forgave you, but trust is not what it was.'), 'info');
              _clampStats(ch);
            } else {
              _say(ch, b('${s.name} özrünü kabul etmedi.', '${s.name} did not accept your apology.'), 'bad');
              _divorce(ch, byPartner: true, fault: Fault.player);
            }
          },
        ),
        DecisionOption(
          label: b('İnkâr et', 'Deny everything'),
          hint: b('Riskli: yalan ortaya çıkarsa işler kötüleşir', 'Risky: if the lie falls apart it gets worse'),
          pick: () {
            if (_p(0.25)) {
              s.bond = _cl(s.bond - 10);
              ch.happiness -= 3;
              _say(ch, b('İnkâr ettin; ${s.name} yarı yarıya ikna oldu.', 'You denied it; ${s.name} was half convinced.'), 'info');
              _clampStats(ch);
            } else {
              ch.social -= 4;
              _say(ch, b('Yalanın da ortaya çıktı.', 'Your lie was exposed too.'), 'bad');
              _divorce(ch, byPartner: true, fault: Fault.player);
            }
          },
        ),
        DecisionOption(
          label: b('Boşanmayı kabul et', 'Accept the divorce'),
          hint: _termsHint(_terms(ch, s, Fault.player, DivorceMode.amicable, true, null)),
          pick: () => _askDivorceMode(ch, byPartner: true, fault: Fault.player),
        ),
      ],
    );
  }

  /// Eşin seni aldattı.
  Decision? _spouseCheatDecision(Character ch) {
    if (!ch.flags.contains('spouse_cheat_found')) return null;
    ch.flags.remove('spouse_cheat_found');
    final s = ch.spouse;
    if (s == null) return null;
    final g = ch.country.gdp;
    ch.cheatedOn++;
    // Oyuncu da gizli ilişki yürütüyorsa kusur karşılıklıdır; değilse eşte.
    final cheatFault = ch.flags.contains('affair') ? Fault.none : Fault.partner;
    s.bond = _cl(s.bond - 22);
    ch.happiness -= 10;
    ch.social -= 2;
    _say(ch, b('${s.name} seni aldattı. Evliliğin sarsıldı.', '${s.name} cheated on you. Your marriage is shaken.'), 'bad');
    _clampStats(ch);
    return Decision(
      title: b('Aldatıldın', 'You were cheated on'),
      body: b('${s.name} seni aldattığını itiraf etti. İstatistiklere göre bu durumdaki çiftlerin kabaca yarısı ayrılıyor. Ne yapacaksın?',
          '${s.name} admitted to cheating on you. Roughly half of couples in this situation split up. What will you do?'),
      options: [
        DecisionOption(
          label: b('Boşan', 'Get divorced'),
          hint: _termsHint(_terms(ch, s, cheatFault, DivorceMode.amicable, false, null)),
          pick: () => _askDivorceMode(ch, fault: cheatFault),
        ),
        DecisionOption(
          label: b('Affet ve devam et', 'Forgive and move on'),
          hint: s.trait == 'cheater' ? b('Tekrar edebilir', 'It may happen again') : null,
          pick: () {
            s.bond = _cl(s.bond + 6);
            ch.happiness -= 4;
            ch.flags.add('forgave');
            _say(ch, b('${s.name}\'i affettin; yaranın kapanması zaman alacak.', 'You forgave ${s.name}; healing will take time.'), 'info');
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Yüzleş ve terapiye git', 'Confront and try therapy'),
          hint: b('Zaman ve para gerektirir', 'Costs time and money'),
          pick: () {
            ch.money -= g * 0.15;
            if (_p(_cl(0.3 + s.bond / 200 + (s.trait == 'cheater' ? -0.15 : 0.1), 0.1, 0.75))) {
              s.bond = _cl(s.bond + 15);
              ch.flags.add('forgave');
              _say(ch, b('Terapi sürecinde güveni yeniden inşa etmeye başladınız.', 'In therapy you began to rebuild trust.'), 'good');
            } else {
              s.bond = _cl(s.bond - 8);
              ch.happiness -= 3;
              _say(ch, b('Terapi güveni geri getirmedi.', 'Therapy did not bring the trust back.'), 'bad');
            }
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Sen de aldat', 'Cheat back'),
          hint: b('İntikam: evliliği iyice zedeler', 'Revenge: damages the marriage badly'),
          pick: () {
            s.bond = _cl(s.bond - 12);
            ch.happiness += 3;
            ch.flags.add('affair');
            ch.affairs++;
            ch.affairYears = 0;
            _say(ch, b('İntikam için gizli bir ilişkiye başladın.', 'You started a secret affair out of revenge.'), 'info');
            _clampStats(ch);
          },
        ),
      ],
    );
  }

  /// Evlenmemiş ve ilişkisi olmayan oyuncuya yeni biriyle tanışma fırsatı.
  /// Seçilen kişi önce sevgili olur; ilişki ilerlerse birlikte yaşama / evlilik gelir.
  Decision? _marriageDecision(Character ch) {
    final lo = max(18, ch.country.marriageAge.round() - 6);
    final hi = ch.country.marriageAge.round() + 14;
    if (ch.spouse != null || ch.partner != null || ch.age < lo || ch.age > hi) return null;
    if (ch.age - (ch.seen['marry'] ?? -9) < 2) return null;
    if (!_p(0.14 + (ch.social - 50) / 700)) return null;

    final count = _ri(2, 4);
    final cands = [for (var i = 0; i < count; i++) _genPerson(ch)];
    return Decision(
      title: b('Biriyle tanıştın mı?', 'Met someone?'),
      body: b('Hayatına girebilecek birkaç kişiyle tanıştın. Biriyle çıkmayı denemek ister misin?',
          'You met a few people who could enter your life. Want to try dating someone?'),
      options: [
        for (final p in cands)
          DecisionOption(
            label: '${p.female ? '♀' : '♂'} ${p.name} (${p.age}) · ${loc(p.jobName, lang)}',
            hint: b(
                'Çekicilik ${p.looks} · Zekâ ${p.smarts} · Karakter ${p.kind}\nGelir ~${fmtMoney(ch.country.gdp * p.pay)}/yıl · Varlık ${fmtMoney(p.wealth)} (${_wealthLabel(p.wealth / ch.country.gdp)})',
                'Looks ${p.looks} · Smarts ${p.smarts} · Character ${p.kind}\nIncome ~${fmtMoney(ch.country.gdp * p.pay)}/yr · Assets ${fmtMoney(p.wealth)} (${_wealthLabel(p.wealth / ch.country.gdp)})'),
            pick: () => _startDating(ch, p),
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

  String _wealthLabel(double rel) {
    if (rel < -0.2) return b('borçlu', 'in debt');
    if (rel < 0.6) return b('mütevazı', 'modest');
    if (rel < 2.5) return b('rahat', 'comfortable');
    return b('varlıklı', 'wealthy');
  }

  /// Çıkma teklifi: kabul ihtimali görünüş, zekâ, sosyallik, şans ve para durumuna bağlı.
  void _startDating(Character ch, Person p) {
    ch.seen['marry'] = ch.age;
    final g = ch.country.gdp;
    final myRel = _cl(ch.money / g, -2, 6);
    final hisRel = _cl(p.wealth / g, 0, 8);
    final acc = _cl(
      0.55 +
          (ch.looks + ch.smarts + ch.social) / 700 +
          myRel * 0.02 +
          (ch.luck - 50) / 500 +
          (ch.looks - p.looks) / 400 +
          (myRel - hisRel) * 0.015,
      0.25,
      0.94,
    );
    if (_p(acc)) {
      p.yearsTogether = 0;
      p.living = false;
      ch.partner = p;
      ch.relationships++;
      ch.happiness += 8;
      ch.social += 3;
      _say(ch, b('${p.name} ile çıkmaya başladınız.', 'You started dating ${p.name}.'), 'good');
    } else {
      ch.happiness -= 6;
      _say(ch, b('${p.name} çıkma teklifini reddetti. Canın sıkıldı.', '${p.name} turned you down. It hurt.'), 'bad');
    }
    _clampStats(ch);
  }

  /// Evlilik: sevgili / birlikte yaşanan kişi eş olur; varlık ortak kasaya karışır.
  void _wed(Character ch, Person p, String text) {
    final g = ch.country.gdp;
    ch.partner = null;
    ch.spouse = p;
    p.living = false;
    p.ageAtMarriage = ch.age;
    p.yearsMarried = 0;
    ch.marriages++;
    ch.happiness += 12;
    ch.social += 4;
    ch.flags
      ..remove('widowed')
      ..remove('divorced');
    _say(ch, text, 'good');
    // Düğün masrafı + eşin varlığı (ya da borcu) ortak kasaya karışır.
    ch.money += p.wealth - g * 0.2;
    if (p.wealth >= g * 0.3) {
      _say(ch, b('${p.name}\'in birikimi ortak kasaya katıldı (+${fmtMoney(p.wealth)}).', '${p.name}\'s savings joined the household (+${fmtMoney(p.wealth)}).'), 'good');
    } else if (p.wealth <= -g * 0.2) {
      _say(ch, b('${p.name}\'in borçlarını da üstlendiniz (${fmtMoney(p.wealth)}).', 'You took on ${p.name}\'s debts too (${fmtMoney(p.wealth)}).'), 'bad');
    }
    _clampStats(ch);
  }

  void _moveIn(Character ch, Person p) {
    ch.seen['marry'] = ch.age;
    if (_p(_cl(0.45 + p.bond / 200 + (ch.luck - 50) / 800, 0.3, 0.92))) {
      p.living = true;
      ch.cohabited++;
      ch.happiness += 5;
      _say(ch, b('${p.name} ile birlikte yaşamaya başladınız.', 'You moved in with ${p.name}.'), 'good');
    } else {
      p.bond = _cl(p.bond - 8);
      ch.happiness -= 4;
      _say(ch, b('${p.name} henüz birlikte yaşamaya hazır değil.', '${p.name} is not ready to move in yet.'), 'bad');
    }
    _clampStats(ch);
  }

  void _proposeMarriage(Character ch, Person p) {
    ch.seen['marry'] = ch.age;
    if (_p(_cl(0.35 + p.bond / 150 + (p.living ? 0.1 : 0.0) + (ch.luck - 50) / 800, 0.25, 0.95))) {
      _wed(ch, p, b('${p.name} evlilik teklifini kabul etti, evlendiniz!', '${p.name} said yes and you got married!'));
    } else {
      p.bond = _cl(p.bond - 10);
      ch.happiness -= 6;
      _say(ch, b('${p.name} evlilik teklifini şimdilik reddetti.', '${p.name} turned down your proposal for now.'), 'bad');
      _clampStats(ch);
    }
  }

  void _breakUp(Character ch, Person p, {String? reason}) {
    final wasLiving = p.living;
    ch.partner = null;
    ch.breakups++;
    ch.happiness -= wasLiving ? 9 : 6;
    ch.social -= wasLiving ? 2 : 1;
    ch.seen['marry'] = ch.age;
    final why = reason ?? b('Zamanla birbirinizden koptunuz.', 'You drifted apart.');
    _say(ch, b('${p.name} ile ayrıldınız. $why', 'You broke up with ${p.name}. $why'), 'bad');
    if (wasLiving) {
      ch.money -= ch.country.gdp * 0.1;
      _say(ch, b('Ortak evden ayrıldın; taşınmak masraflı oldu.', 'You left the shared home; moving was costly.'), 'info');
    }
    _clampStats(ch);
  }

  /// Sevgili / birlikte yaşanan kişi için yıllık akış: bağ değişir, ayrılık ya da kayıp olabilir.
  void _partnerYear(Character ch) {
    final p = ch.partner;
    if (p == null) return;
    if (ch.spouse != null) {
      ch.partner = null;
      return;
    }
    p.age++;
    p.yearsTogether++;
    var d = (p.kind - 50) / 50 + _gauss() * 2 + (ch.happiness - 50) / 40 + (ch.money < 0 ? -1.0 : 0.3) - 0.6;
    if (p.trait == 'loyal') d += 1;
    if (p.trait == 'caring') d += 1.2;
    p.bond = _cl(p.bond + d);

    final h = _hazard(p.age, ch.country.lifeExp, ch.country.risk, 60, 50, const {});
    if (p.age > 25 && _p(h)) {
      ch.partner = null;
      ch.happiness -= 18;
      ch.social -= 3;
      ch.seen['marry'] = ch.age;
      _say(ch, b('${p.name} hayatını kaybetti. Büyük bir yas yaşadın.', '${p.name} passed away. You grieved deeply.'), 'bad');
      _clampStats(ch);
      return;
    }
    if (p.trait == 'cheater' && !p.traitKnown && p.yearsTogether >= 2 && _p(0.12)) {
      p.traitKnown = true;
      _breakUp(ch, p, reason: b('${p.name} seni aldattığını itiraf etti.', '${p.name} confessed to cheating on you.'));
      return;
    }
    final chance = (p.living ? 0.03 : 0.07) + (p.bond < 35 ? 0.15 : 0.0) + (p.bond < 20 ? 0.15 : 0.0) - (p.bond > 70 ? 0.03 : 0.0);
    if (_p(_cl(chance, 0.01, 0.6))) _breakUp(ch, p);
  }

  String _bondLabel(double v) => v >= 70
      ? b('çok güçlü', 'very strong')
      : v >= 45
          ? b('sağlam', 'solid')
          : b('sallantıda', 'shaky');

  /// İlişki ilerleyince: birlikte yaşama, evlilik teklifi, aynen devam ya da ayrılık.
  Decision? _partnerDecision(Character ch) {
    final p = ch.partner;
    if (p == null || ch.spouse != null || ch.age < 18) return null;
    final living = p.living;
    final wed = canWed(ch, p);
    // Birlikte yaşıyor ve evlenemiyorsa verilecek yeni bir karar yok.
    if (living && !wed) return null;
    if (p.yearsTogether < (living ? 2 : 1) || !_p(living ? 0.4 : 0.35)) return null;

    final noWed = wed
        ? ''
        : b(' Ülkende aynı cinsler arasında evlilik yasal değil; ama birlikte yaşayabilirsiniz.',
            ' Same-sex marriage is not legal in your country, but you can live together.');
    return Decision(
      title: living ? b('Evlilik düşüncesi', 'Thinking of marriage') : b('İlişkiniz ilerliyor', 'Your relationship is moving on'),
      body: b('${p.name} ile ${p.yearsTogether} yıldır birliktesiniz. Bağınız ${_bondLabel(p.bond)}.$noWed',
          'You and ${p.name} have been together ${p.yearsTogether} years. Your bond is ${_bondLabel(p.bond)}.$noWed'),
      options: [
        if (!living)
          DecisionOption(
            label: b('Birlikte yaşayalım', 'Let\'s move in together'),
            hint: b('Ortak ev: gelir ve giderler paylaşılır; ayrılmak daha masraflı olur.',
                'Shared home: income and costs are shared; breaking up gets costlier.'),
            pick: () => _moveIn(ch, p),
          ),
        if (wed)
          DecisionOption(
            label: b('Evlenme teklif et', 'Propose marriage'),
            pick: () => _proposeMarriage(ch, p),
          ),
        DecisionOption(
          label: b('Böyle devam edelim', 'Keep things as they are'),
          pick: () {
            ch.seen['marry'] = ch.age;
            _say(ch, b('İlişkinizi olduğu gibi sürdürmeyi seçtiniz.', 'You chose to keep the relationship as it is.'), 'info');
          },
        ),
        DecisionOption(
          label: b('İlişkiyi bitir', 'End the relationship'),
          pick: () => _breakUp(ch, p, reason: b('Ayrılma kararını sen verdin.', 'You made the decision.')),
        ),
      ],
    );
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

  /// Oyuncuya uygun iş tekliflerini ağırlıklı seçer: eğitim düzeyi, istatistikler
  /// (zekâ, çekicilik, sosyallik, sağlık) ve geçmiş seçimleri (bayraklar:
  /// spor, sanat/sayısal/sözel alan, evcil hayvan, işletme...) ağırlığı etkiler.
  /// Manken/oyuncu gibi özel işler burada çıkmaz.
  List<JobDef> _pickJobOffers(Character ch, int count) {
    final pool = jobs.where((j) => !j.special && j.minEdu <= ch.edu && j.id != ch.job?.def.id).toList();
    final out = <JobDef>[];
    while (out.length < count && pool.isNotEmpty) {
      final j = _weighted<JobDef>(pool, (x) {
        var w = x.weight;
        if (x.stat != null) w *= 0.5 + _stat(ch, x.stat!) / 60;
        if (x.favor.any(ch.flags.contains)) w *= 4;
        return w;
      });
      out.add(j);
      pool.remove(j);
    }
    return out;
  }

  /// Yıllık "keşfedilme" ihtimali (manken/oyuncu teklifi). Çekicilik 80 altında
  /// 0. Taban: düşük refahlı ülkede %0,001, yüksek refahlı ülkede %0,01 (gelir
  /// arasında doğrusal geçiş). Çekicilik 90 üstünde 10 kat, 95 üstünde 120 kat.
  double starChance(Character ch) {
    if (ch.looks < 80 || ch.age < 18 || ch.age > 42 || ch.retired) return 0;
    if (ch.job?.def.special == true) return 0;
    final w = ((ch.country.gdp - 2) / 13).clamp(0.0, 1.0).toDouble();
    var p = 0.00001 + (0.0001 - 0.00001) * w;
    if (ch.looks > 95) {
      p *= 120;
    } else if (ch.looks > 90) {
      p *= 10;
    }
    return p;
  }

  /// Çok nadir: güzelliğin / yakışıklılığın fark edilir ve manken ya da oyuncu
  /// olarak teklif gelir.
  Decision? _starOfferDecision(Character ch) {
    if (!_p(starChance(ch))) return null;
    final model = _p(ch.female ? 0.55 : 0.4);
    JobDef? def;
    for (final j in jobs) {
      if (j.id == (model ? 'model' : 'actor')) def = j;
    }
    if (def == null) return null;
    final d = def;
    final name = loc(d.name, lang);
    final g = ch.country.gdp;
    return Decision(
      title: b('✨ Keşfedildin', '✨ You were scouted'),
      body: model
          ? b('Sokakta seni gören bir ajans mankenlik teklif ediyor. Bu çok nadir bir fırsat.',
              'An agency spotted you and offers you a modelling career. A very rare chance.')
          : b('Bir yapımcı seni fark etti ve oyunculuk teklif ediyor. Bu çok nadir bir fırsat.',
              'A producer noticed you and offers you an acting career. A very rare chance.'),
      options: [
        DecisionOption(
          label: b('$name olarak başla', 'Start as $name'),
          hint: b('~${fmtMoney(g * d.pay)}/yıl · stres ${d.stress} · hepsi şansa bağlı',
              '~${fmtMoney(g * d.pay)}/yr · stress ${d.stress} · depends on luck'),
          pick: () {
            ch.seen['job'] = ch.age;
            if (_p(_cl(0.8 + (ch.luck - 50) / 400, 0.6, 0.95))) {
              ch.job = Job(d);
              ch.jobsHeld++;
              ch.joblessYears = 0;
              ch.uniUntil = null;
              ch.happiness += 10;
              ch.social += 5;
              ch.flags.add('star_career');
              _say(ch, b('$name olarak çalışmaya başladın; hayatın bir anda değişti.', 'You started working as a $name; your life changed overnight.'), 'milestone');
            } else {
              ch.happiness -= 4;
              _say(ch, b('Deneme çekimi umduğun gibi geçmedi; teklif geri çekildi.', 'The audition did not go as hoped; the offer was withdrawn.'), 'bad');
            }
            _clampStats(ch);
          },
        ),
        DecisionOption(
          label: b('Reddet', 'Turn it down'),
          pick: () {
            ch.happiness -= 1;
            _say(ch, b('Teklifi reddettin; hayatına olduğu gibi devam ettin.', 'You declined and carried on with your life.'), 'info');
          },
        ),
      ],
    );
  }

  Decision? _jobDecision(Character ch) {
    if (ch.retired || ch.age < 18 || ch.age > 60 || ch.uniUntil != null) return null;
    final employed = ch.job != null;
    if (employed) {
      if (ch.age < 22 || ch.age - (ch.seen['job'] ?? -9) < 4 || !_p(0.1)) return null;
    } else if (!_p(0.6)) {
      return null;
    }
    final offers = _pickJobOffers(ch, employed ? 3 : 4);
    if (offers.isEmpty) return null;
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
            hint: b(
                '~${fmtMoney(g * j.pay)}/yıl · stres ${j.stress} · kabul şansı ~%${(100 * _hireChance(ch, j)).round()}',
                '~${fmtMoney(g * j.pay)}/yr · stress ${j.stress} · hire chance ~${(100 * _hireChance(ch, j)).round()}%'),
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

  /// Mülakattan geçme ihtimali. Eskiden ortalama oyuncu için ~%60'tı ve
  /// elenme çok sık oluyordu; artık taban yüksek, deneyim, eğitim fazlalığı ve
  /// uzun süren işsizlik (aranan çaresizlik) ihtimali artırır.
  double _hireChance(Character ch, JobDef j) {
    var p = 0.78 +
        (ch.smarts - 50) / 200 +
        (ch.luck - 50) / 400 +
        (ch.social - 50) / 500 +
        (ch.looks - 50) / 800;
    p += min(2, max(0, ch.edu - j.minEdu)) * 0.05;
    p += min(4, ch.jobsHeld) * 0.02;
    p += min(3, ch.joblessYears) * 0.04;
    p -= max(0, j.minEdu - 2) * 0.03;
    if (ch.famWealth > 70) p += 0.04;
    return _cl(p, 0.45, 0.97);
  }

  void _applyFor(Character ch, JobDef j) {
    ch.seen['job'] = ch.age;
    final name = loc(j.name, lang);
    if (_p(_hireChance(ch, j))) {
      ch.job = Job(j);
      ch.jobsHeld++;
      ch.interviewsPassed++;
      ch.joblessYears = 0;
      ch.happiness += 4;
      _say(ch, b('$name olarak işe girdin.', 'You got a job as: $name.'), 'good');
    } else {
      ch.interviewsFailed++;
      ch.happiness -= 3;
      _say(ch, b('$name mülakatında elendin. Bir dahaki sefere şansın daha yüksek.', 'You were turned down for the $name job. Your odds improve next time.'), 'bad');
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
    if (cond['partnered'] != null && cond['partnered'] != (ch.partner != null)) return false;
    if (cond['canMarry'] == true && !canMarryAnyone(ch)) return false;
    if (cond['hasJob'] != null && cond['hasJob'] != (ch.job != null)) return false;
    if (cond['hasKids'] != null && cond['hasKids'] != ch.children.isNotEmpty) return false;
    if (cond['retired'] != null && cond['retired'] != ch.retired) return false;
    if (cond['student'] != null && cond['student'] != _isStudent(ch)) return false;
    if (cond['fatherAlive'] != null && cond['fatherAlive'] != ch.fatherAlive) return false;
    if (cond['motherAlive'] != null && cond['motherAlive'] != ch.motherAlive) return false;
    if (cond['parentAlive'] != null && cond['parentAlive'] != (ch.fatherAlive || ch.motherAlive)) return false;
    if (cond['hasSiblings'] != null && cond['hasSiblings'] != ch.hasSiblings) return false;
    if (cond['hasGrandkids'] != null && cond['hasGrandkids'] != ch.flags.contains('grandkids')) return false;
    if (cond['status'] != null && !(cond['status'] as List).contains(_civilStatus(ch))) return false;
    if (cond['kidAge'] != null) {
      final r = cond['kidAge'] as List;
      final lo = (r[0] as num).toInt(), hi = (r[1] as num).toInt();
      if (!ch.children.any((k) => k.age >= lo && k.age <= hi)) return false;
    }
    for (final f in (cond['flagsAll'] as List? ?? const [])) {
      if (!ch.flags.contains(f)) return false;
    }
    for (final f in (cond['flagsNone'] as List? ?? const [])) {
      if (ch.flags.contains(f)) return false;
    }
    // {"athlete": 20}: bayrak en az 20 yıl önce konmuş olmalı.
    for (final e in ((cond['flagsAgo'] as Map?) ?? const {}).entries) {
      if (!ch.flags.contains(e.key)) return false;
      if (ch.age - (ch.flagAge[e.key] ?? ch.age) < (e.value as num)) return false;
    }
    return true;
  }

  bool _isStudent(Character ch) => ch.uniUntil != null || (ch.age < 18 && ch.flags.contains('in_school'));

  /// single / married / divorced / widowed
  String _civilStatus(Character ch) {
    if (ch.spouse != null) return 'married';
    if (ch.flags.contains('widowed')) return 'widowed';
    if (ch.flags.contains('divorced')) return 'divorced';
    return 'single';
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
    if (!_p(0.9)) return null;
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
      o.flagW.forEach((f, m) {
        if (ch.flags.contains(f)) w *= m;
      });
      return w;
    });
  }

  void _applyOutcome(Character ch, Outcome o, {dynamic fallback}) {
    _apply(ch, o.effects);
    for (final f in o.setFlags) {
      // İlk konduğu yaş korunur: "20 yıl önce spora başladın" gibi koşullar için.
      if (ch.flags.add(f)) ch.flagAge[f] = ch.age;
    }
    for (final f in o.clearFlags) {
      ch.flags.remove(f);
      ch.flagAge.remove(f);
    }
    for (final l in o.later) {
      if (_p(l.chance)) ch.scheduled.add(Scheduled(ch.age + _ri(l.minYears, max(l.minYears, l.maxYears)), l.outcome));
    }
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
        case 'marry':
          if (v == true && ch.spouse == null && ch.age >= 18) {
            var p = _genPerson(ch);
            // Aynı cinsle evlilik yasal değilse (yönelim 'her ikisi' ise) karşı cinsten biri çıkar.
            if (!canWed(ch, p)) p = _genPerson(ch, female: !ch.female);
            ch.partner = null;
            ch.spouse = p;
            p.ageAtMarriage = ch.age;
            ch.marriages++;
            ch.money += p.wealth;
            ch.flags
              ..remove('widowed')
              ..remove('divorced');
          }
        case 'promote':
          final pj = ch.job;
          if (pj != null) pj.level = min(5, pj.level + (v as num).toInt());
        case 'setJob':
          for (final jd in jobs) {
            if (jd.id == v) {
              ch.job = Job(jd);
              ch.jobsHeld++;
              ch.joblessYears = 0;
              break;
            }
          }
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
    ch.livedIn.add(to.code);
    ch.social -= 6;
    ch.flags.add('emigrated');
    _say(ch, b('${loc(to.name, lang)} ülkesine taşındın.', 'You moved to ${loc(to.name, lang)}.'), 'milestone');
  }
}

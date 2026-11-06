typedef Json = Map<String, dynamic>;

/// {"tr": "...", "en": "..."} yapısından dile göre metin alır.
String loc(dynamic v, String lang) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Map) return (v[lang] ?? v['tr'] ?? v['en'] ?? '').toString();
  return v.toString();
}

/// Para birimi: bin dolar cinsinden değeri "$12k", "$1.2M" gibi gösterir.
String fmtMoney(double k) {
  final a = k.abs();
  final s = a >= 1000
      ? '\$${(a / 1000).toStringAsFixed(1)}M'
      : a >= 10
          ? '\$${a.toStringAsFixed(0)}k'
          : '\$${a.toStringAsFixed(1)}k';
  return k < 0 ? '-$s' : s;
}

class Country {
  Country.fromJson(Json j)
      : code = j['code'] as String,
        flag = j['flag'] as String,
        region = j['region'] as String,
        name = Map<String, dynamic>.from(j['name'] as Map),
        births = (j['births'] as num).toDouble(),
        lifeExp = (j['lifeExp'] as num).toDouble(),
        marriageAge = (j['marriageAge'] as num).toDouble(),
        fertility = (j['fertility'] as num).toDouble(),
        gdp = (j['gdp'] as num).toDouble(),
        edu = (j['edu'] as num).toDouble(),
        risk = (j['risk'] as num).toDouble();

  final String code, flag, region;
  final Json name;
  final double births, lifeExp, marriageAge, fertility, gdp, edu, risk;
}

class Person {
  Person({
    required this.name,
    required this.age,
    required this.female,
    required this.looks,
    required this.smarts,
    required this.kind,
    required this.jobName,
    required this.pay,
    required this.trait,
    required this.bond,
  });

  final String name;
  int age;
  final bool female;
  final int looks, smarts, kind;
  final Json jobName;
  final double pay;

  /// loyal, caring, hardworking, spender, cheater, plain
  final String trait;
  bool traitKnown = false;
  double bond;
  int yearsMarried = 0;
}

class Child {
  Child({required this.name, required this.age, required this.female});
  final String name;
  int age;
  final bool female;
}

class JobDef {
  JobDef.fromJson(Json j)
      : id = j['id'] as String,
        name = Map<String, dynamic>.from(j['name'] as Map),
        minEdu = j['minEdu'] as int,
        pay = (j['pay'] as num).toDouble(),
        stress = j['stress'] as int,
        drain = (j['drain'] as num).toDouble();

  final String id;
  final Json name;
  final int minEdu, stress;
  final double pay, drain;
}

class Job {
  Job(this.def);
  final JobDef def;
  int level = 1;
  int years = 0;
}

class LogEntry {
  const LogEntry(this.age, this.text, this.kind);
  final int age;
  final String text;

  /// info, good, bad, choice, milestone
  final String kind;
}

class DecisionOption {
  DecisionOption({required this.label, this.hint, required this.pick});
  final String label;
  final String? hint;
  final void Function() pick;
}

class Decision {
  Decision({required this.title, required this.body, required this.options});
  final String title, body;
  final List<DecisionOption> options;
}

/// Bir seçimin (ya da otomatik olayın) olası sonuçlarından biri.
class Outcome {
  Outcome.fromJson(Json j)
      : effects = Map<String, dynamic>.from((j['effects'] as Map?) ?? const {}),
        result = j['result'],
        setFlags = List<String>.from((j['setFlags'] as List?) ?? const []),
        clearFlags = List<String>.from((j['clearFlags'] as List?) ?? const []),
        death = j['death'],
        w = (j['w'] as num?)?.toDouble() ?? 1.0,
        lucky = j['lucky'] == true,
        check = j['check'] as String?;

  final Json effects;
  final dynamic result, death;
  final List<String> setFlags, clearFlags;

  /// Birden fazla sonuç varsa ağırlık.
  final double w;

  /// true ise ağırlığı oyuncunun şansıyla çarpılır.
  final bool lucky;

  /// Doluysa ağırlık bu istatistikle (smarts, health...) çarpılır.
  final String? check;
}

class Choice {
  Choice.fromJson(Json j)
      : text = j['text'],
        outcomes = j['outcomes'] != null
            ? [
                for (final o in j['outcomes'] as List)
                  Outcome.fromJson(Map<String, dynamic>.from(o as Map))
              ]
            : [Outcome.fromJson(j)];

  final dynamic text;
  final List<Outcome> outcomes;
}

class GameEvent {
  GameEvent.fromJson(Json j)
      : id = j['id'] as String,
        minAge = (j['minAge'] as int?) ?? 0,
        maxAge = (j['maxAge'] as int?) ?? 120,
        weight = (j['weight'] as num?)?.toDouble() ?? 1.0,
        cooldown = (j['cooldown'] as int?) ?? 3,
        once = j['once'] == true,
        force = j['force'] == true,
        riskScale = j['riskScale'] == true,
        tone = j['tone'] as String?,
        cond = Map<String, dynamic>.from((j['cond'] as Map?) ?? const {}),
        text = j['text'],
        title = j['title'],
        choices = [
          for (final c in (j['choices'] as List? ?? const []))
            Choice.fromJson(Map<String, dynamic>.from(c as Map))
        ],
        autoOutcomes = _autoOutcomes(j);

  static List<Outcome> _autoOutcomes(Json j) {
    if (j['choices'] != null) return [];
    if (j['outcomes'] != null) {
      return [
        for (final o in j['outcomes'] as List)
          Outcome.fromJson(Map<String, dynamic>.from(o as Map))
      ];
    }
    return [Outcome.fromJson(j)];
  }

  final String id;
  final int minAge, maxAge, cooldown;
  final double weight;
  final bool once, force, riskScale;

  /// good / bad: şansa göre görülme sıklığı değişir.
  final String? tone;
  final Json cond;
  final dynamic text, title;
  final List<Choice> choices;
  final List<Outcome> autoOutcomes;
}

class Character {
  Character({
    required this.name,
    required this.female,
    required this.country,
    required this.health,
    required this.happiness,
    required this.smarts,
    required this.looks,
    required this.social,
    required this.luck,
    required this.famWealth,
    required this.retireAge,
  }) : birthCountry = country;

  final String name;
  final bool female;
  final Country birthCountry;
  Country country;
  int age = 0;

  /// 0-100 arası istatistikler. [luck] oyuncudan gizlidir.
  double health, happiness, smarts, looks, social, luck;

  /// Ailenin zenginliği (0-100). 18 yaşındaki başlangıç parasını belirler.
  double famWealth;

  /// Bin dolar cinsinden net varlık ve yıllık gelir.
  double money = 0, income = 0, jobIncome = 0, pension = 0, peakMoney = 0;

  /// 0 yok, 1 ilk, 2 lise, 3 üniversite, 4 yüksek lisans.
  int edu = 0;
  Job? job;
  Person? spouse;
  final List<Child> children = [];
  bool alive = true, retired = false;
  final int retireAge;
  int? uniUntil;
  int uniEdu = 3;
  String? cause;
  final Set<String> flags = {};
  final Map<String, int> seen = {};
  final List<LogEntry> log = [];
  int marriages = 0, jobsHeld = 0, countriesLived = 1;
}

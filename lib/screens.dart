import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'models.dart';

// ───────────────────────── Ana ekran ─────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.engine});
  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final b = engine.b;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🌍', style: TextStyle(fontSize: 72)),
                    const SizedBox(height: 12),
                    Text(
                      b('Hayat Simülasyonu', 'Life Simulator'),
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      b('Rastgele bir ülkede doğ, seçimlerinle ve şansınla bir hayat yaşa.',
                          'Be born in a random country and live a life shaped by your choices and luck.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: engine.loaded
                          ? () {
                              engine.newLife();
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => GameScreen(engine: engine)),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(b('Yeni Hayat', 'New Life')),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'tr', label: Text('Türkçe')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {engine.lang},
                      onSelectionChanged: (s) => engine.setLang(s.first),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Oyun ekranı ─────────────────────────

class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.engine});
  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final ch = engine.c!;
        return Scaffold(
          appBar: AppBar(
            title: Text('${ch.country.flag} ${loc(ch.country.name, engine.lang)}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.translate),
                onPressed: () => engine.setLang(engine.lang == 'tr' ? 'en' : 'tr'),
              ),
            ],
          ),
          body: Column(
            children: [
              _Header(engine: engine),
              Expanded(child: _LogList(entries: ch.log)),
              _Bottom(engine: engine),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.engine});
  final GameEngine engine;

  String _status(Character ch) {
    final b = engine.b;
    if (ch.age < 6) return b('Çocuk', 'Child');
    if (ch.age < 18) return b('Öğrenci', 'Student');
    if (ch.uniUntil != null) return b('Üniversite öğrencisi', 'University student');
    if (ch.retired) return b('Emekli', 'Retired');
    if (ch.job != null) return loc(ch.job!.def.name, engine.lang);
    return b('İşsiz', 'Unemployed');
  }

  @override
  Widget build(BuildContext context) {
    final ch = engine.c!;
    final b = engine.b;
    Widget bar(String label, double v, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 74, child: Text(label, style: const TextStyle(fontSize: 12))),
              Expanded(
                child: LinearProgressIndicator(
                  value: v / 100,
                  minHeight: 8,
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(width: 28, child: Text('${v.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ch.name} · ${ch.age} ${b('yaş', 'y/o')} · ${ch.alive ? _status(ch) : b('Hayatını kaybetti', 'Deceased')}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                Chip(label: Text(engine.eduName(ch.edu)), visualDensity: VisualDensity.compact),
                if (ch.age >= 18) Chip(label: Text('💰 ${fmtMoney(ch.money)}'), visualDensity: VisualDensity.compact),
                if (ch.age >= 16)
                  Chip(
                    label: Text(
                      ch.spouse != null
                          ? '${_maritalIcon(ch.marital)} ${engine.maritalName(ch.marital)} · ${ch.spouse!.name}'
                          : '${_maritalIcon(ch.marital)} ${engine.maritalName(ch.marital)}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                if (ch.age >= 16 || ch.children.isNotEmpty)
                  Chip(
                    label: Text('👶 ${b('Çocuk', 'Kids')}: ${ch.children.length}'),
                    visualDensity: VisualDensity.compact,
                  ),
                if (ch.grandchildren > 0)
                  Chip(
                    label: Text('🧸 ${b('Torun', 'Grandkids')}: ${ch.grandchildren}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ActionChip(
                  avatar: const Text('👨‍👩‍👧'),
                  label: Text('${b('Aile', 'Family')} (${_familyCount(ch)})'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => FamilySheet(engine: engine),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(children: [
                    bar(b('Sağlık', 'Health'), ch.health, Colors.redAccent),
                    bar(b('Mutluluk', 'Happiness'), ch.happiness, Colors.amber),
                    bar(b('Zekâ', 'Smarts'), ch.smarts, Colors.lightBlue),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(children: [
                    bar(b('Çekicilik', 'Looks'), ch.looks, Colors.pinkAccent),
                    bar(b('Sosyal', 'Social'), ch.social, Colors.green),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _maritalIcon(String m) => switch (m) {
      'married' => '💍',
      'divorced' => '💔',
      'widowed' => '🕊️',
      _ => '🧍',
    };

/// Hayatta olan yakınların sayısı (eş + çocuklar + anne/baba/kardeşler).
int _familyCount(Character ch) =>
    (ch.spouse != null ? 1 : 0) + ch.children.length + ch.family.where((r) => r.alive).length;

// ───────────────────────── Aile ekranı ─────────────────────────

class FamilySheet extends StatelessWidget {
  const FamilySheet({super.key, required this.engine});
  final GameEngine engine;

  String _trait(String t) {
    final b = engine.b;
    return switch (t) {
      'loyal' => b('Sadık', 'Loyal'),
      'caring' => b('Şefkatli', 'Caring'),
      'hardworking' => b('Çalışkan', 'Hardworking'),
      'spender' => b('Savurgan', 'Spender'),
      'cheater' => b('Aldatan', 'Unfaithful'),
      _ => b('Sıradan', 'Ordinary'),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final ch = engine.c!;
        final b = engine.b;
        final s = ch.spouse;

        Widget title(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
              child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            );
        Widget line(String icon, String name, String detail, {bool dead = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(decoration: dead ? TextDecoration.lineThrough : null, color: dead ? Colors.grey : null),
                    ),
                  ),
                  Text(detail, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            );
        String ageText(Relative r) =>
            r.alive ? '${r.age} ${b('yaş', 'y/o')}' : '✝ ${r.age}';

        final mother = ch.mother, father = ch.father;
        final sibs = ch.siblings.toList();

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              shrinkWrap: true,
              children: [
                Text(b('Aile', 'Family'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${_maritalIcon(ch.marital)} ${b('Medeni durum', 'Marital status')}: ${engine.maritalName(ch.marital)}'),
                if (ch.marriages > 0) Text('${b('Toplam evlilik', 'Marriages')}: ${ch.marriages}', style: const TextStyle(color: Colors.grey)),
                title(b('Eş', 'Partner')),
                if (s == null)
                  Text(b('Şu an evli değilsin.', 'You are not currently married.'), style: const TextStyle(color: Colors.grey))
                else ...[
                  line(s.female ? '👩' : '👨', s.name, '${s.age} ${b('yaş', 'y/o')} · ${loc(s.jobName, engine.lang)}'),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 74, child: Text(b('İlişki', 'Bond'), style: const TextStyle(fontSize: 12))),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: s.bond / 100,
                            minHeight: 8,
                            color: Colors.pinkAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        SizedBox(width: 32, child: Text('${s.bond.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
                  if (s.traitKnown)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${b('Karakter', 'Trait')}: ${_trait(s.trait)} · ${s.yearsMarried} ${b('yıldır evli', 'years married')}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                ],
                title('${b('Çocuklar', 'Children')} (${ch.children.length})'),
                if (ch.children.isEmpty)
                  Text(b('Henüz çocuğun yok.', 'You have no children yet.'), style: const TextStyle(color: Colors.grey))
                else
                  for (final k in ch.children)
                    line(k.female ? '👧' : '👦', k.name, '${k.age} ${b('yaş', 'y/o')}${k.kids > 0 ? ' · ${k.kids} ${b('çocuk', 'kids')}' : ''}'),
                if (ch.grandchildren > 0) ...[
                  title(b('Torunlar', 'Grandchildren')),
                  line('🧸', '${ch.grandchildren} ${b('torun', 'grandchildren')}', ''),
                ],
                title(b('Anne & Baba', 'Parents')),
                if (mother != null) line('👩', '${b('Anne', 'Mother')}: ${mother.name}', ageText(mother), dead: !mother.alive),
                if (father != null) line('👨', '${b('Baba', 'Father')}: ${father.name}', ageText(father), dead: !father.alive),
                title('${b('Kardeşler', 'Siblings')} (${sibs.length})'),
                if (sibs.isEmpty)
                  Text(b('Tek çocuksun.', 'You are an only child.'), style: const TextStyle(color: Colors.grey))
                else
                  for (final r in sibs) line(r.female ? '👧' : '👦', r.name, ageText(r), dead: !r.alive),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.entries});
  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final rev = entries.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: rev.length,
      itemBuilder: (ctx, i) {
        final e = rev[i];
        Color color;
        switch (e.kind) {
          case 'good':
            color = Colors.green;
          case 'bad':
            color = Colors.redAccent;
          case 'choice':
            color = Theme.of(ctx).colorScheme.primary;
          case 'milestone':
            color = Colors.amber;
          default:
            color = Colors.grey;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${e.age}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.text,
                  style: e.kind == 'choice' ? const TextStyle(fontStyle: FontStyle.italic) : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bottom extends StatelessWidget {
  const _Bottom({required this.engine});
  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    final ch = engine.c!;
    final d = engine.pending;
    final b = engine.b;
    Widget child;
    if (!ch.alive) {
      child = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SummaryScreen(engine: engine)),
          ),
          icon: const Icon(Icons.flag),
          label: Text(b('Hayat Özeti', 'Life Summary')),
        ),
      );
    } else if (d != null) {
      child = _DecisionCard(engine: engine, decision: d);
    } else {
      child = Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: engine.advanceYear,
              child: Text(b('1 yıl ilerle', 'Next year')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: engine.fastForward,
              child: Text(b('Karara kadar', 'Until decision')),
            ),
          ),
        ],
      );
    }
    return SafeArea(
      top: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: child),
    );
  }
}

/// Seçim alanı → (ikon, ad).
(String, String) _catInfo(String cat, String lang) {
  const m = {
    'school': ('🎓', 'Eğitim', 'Education'),
    'career': ('💼', 'Kariyer', 'Career'),
    'family': ('🏡', 'Aile', 'Family'),
    'kids': ('🍼', 'Çocuklar', 'Children'),
    'love': ('💘', 'Aşk & evlilik', 'Love & marriage'),
    'health': ('🩺', 'Sağlık', 'Health'),
    'money': ('💰', 'Para', 'Money'),
    'social': ('🎉', 'Sosyal hayat', 'Social life'),
    'crime': ('⚖️', 'Hukuk & suç', 'Law & crime'),
    'travel': ('✈️', 'Seyahat', 'Travel'),
    'hobby': ('🎨', 'Hobi', 'Hobbies'),
    'home': ('🏠', 'Ev', 'Home'),
    'tech': ('📱', 'Teknoloji', 'Technology'),
    'politics': ('🗳️', 'Toplum & siyaset', 'Society & politics'),
    'values': ('🕊️', 'Değerler', 'Values'),
    'pet': ('🐾', 'Evcil hayvan', 'Pets'),
    'life': ('🌱', 'Hayat', 'Life'),
  };
  final r = m[cat] ?? m['life']!;
  return (r.$1, lang == 'tr' ? r.$2 : r.$3);
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.engine, required this.decision});
  final GameEngine engine;
  final Decision decision;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (decision.cat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_catInfo(decision.cat!, engine.lang).$1} ${_catInfo(decision.cat!, engine.lang).$2}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                Text(decision.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(decision.body),
                const SizedBox(height: 10),
                for (final o in decision.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () => engine.choose(o),
                        child: Column(
                          children: [
                            Text(o.label, textAlign: TextAlign.center),
                            if (o.hint != null)
                              Text(o.hint!, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Hayat özeti ─────────────────────────

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.engine});
  final GameEngine engine;

  String _shareText(Character ch) {
    final b = engine.b;
    final diff = (ch.age - ch.birthCountry.lifeExp).round();
    final cn = loc(ch.birthCountry.name, engine.lang);
    final cmp = diff >= 0
        ? b('ortalamadan $diff yıl fazla', '$diff years above the average')
        : b('ortalamadan ${-diff} yıl az', '${-diff} years below the average');
    return b(
      '${ch.birthCountry.flag} $cn ülkesinde doğdum, ${ch.age} yaşında öldüm ($cmp). '
          'Eğitim: ${engine.eduName(ch.edu)}, çocuk: ${ch.children.length}, ülke sayısı: ${ch.countriesLived}. '
          'Sen nasıl bir hayat yaşardın? #HayatSimülasyonu',
      'Born in $cn ${ch.birthCountry.flag}, died at ${ch.age} ($cmp). '
          'Education: ${engine.eduName(ch.edu)}, children: ${ch.children.length}, countries lived in: ${ch.countriesLived}. '
          'What life would you live? #LifeSimulator',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ch = engine.c!;
    final b = engine.b;
    final diff = (ch.age - ch.birthCountry.lifeExp).round();
    final cn = loc(ch.birthCountry.name, engine.lang);

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: Text(k, style: const TextStyle(color: Colors.grey))),
              Expanded(flex: 5, child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(b('Hayat Özeti', 'Life Summary'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: Text(ch.birthCountry.flag, style: const TextStyle(fontSize: 56))),
          const SizedBox(height: 8),
          Text(
            b('${ch.name}, ${ch.age} yaşında öldü', '${ch.name} died at ${ch.age}'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            diff >= 0
                ? b('$cn yaşam beklentisinden $diff yıl fazla yaşadı.', 'Lived $diff years longer than the life expectancy in $cn.')
                : b('$cn yaşam beklentisinden ${-diff} yıl az yaşadı.', 'Lived ${-diff} years less than the life expectancy in $cn.'),
            textAlign: TextAlign.center,
          ),
          const Divider(height: 28),
          row(b('Ölüm nedeni', 'Cause'), ch.cause ?? '-'),
          row(b('Doğduğu ülke', 'Born in'), cn),
          row(b('Son ülke', 'Last country'), loc(ch.country.name, engine.lang)),
          row(b('Eğitim', 'Education'), engine.eduName(ch.edu)),
          row(b('Evlilik', 'Marriages'), '${ch.marriages}'),
          row(b('Medeni durum', 'Marital status'), engine.maritalName(ch.marital)),
          row(b('Çocuk', 'Children'), '${ch.children.length}'),
          row(b('Torun', 'Grandchildren'), '${ch.grandchildren}'),
          row(b('Kardeş', 'Siblings'), '${ch.siblings.length}'),
          row(b('Tuttuğu iş sayısı', 'Jobs held'), '${ch.jobsHeld}'),
          row(b('Son varlık', 'Final wealth'), fmtMoney(ch.money)),
          row(b('En yüksek varlık', 'Peak wealth'), fmtMoney(ch.peakMoney)),
          row(b('Gizli şans değeri', 'Hidden luck'), '${ch.luck.round()}/100'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _shareText(ch)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(b('Paylaşım metni kopyalandı', 'Share text copied'))),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(b('Sonucu kopyala', 'Copy result')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              engine.newLife();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => GameScreen(engine: engine)),
                (r) => r.isFirst,
              );
            },
            icon: const Icon(Icons.refresh),
            label: Text(b('Yeni Hayat', 'New Life')),
          ),
        ],
      ),
    );
  }
}

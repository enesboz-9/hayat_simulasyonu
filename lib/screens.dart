import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'models.dart';
import 'result_image.dart';

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
              children: [
                Chip(label: Text(engine.eduName(ch.edu)), visualDensity: VisualDensity.compact),
                if (ch.age >= 18) Chip(label: Text('💰 ${fmtMoney(ch.money)}'), visualDensity: VisualDensity.compact),
                if (ch.spouse != null) Chip(label: Text('💍 ${ch.spouse!.name}'), visualDensity: VisualDensity.compact),
                if (ch.children.isNotEmpty) Chip(label: Text('👶 ${ch.children.length}'), visualDensity: VisualDensity.compact),
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

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.engine});
  final GameEngine engine;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  GameEngine get engine => widget.engine;

  String _shareText(Character ch) {
    final b = engine.b;
    final diff = (ch.age - ch.birthCountry.lifeExp).round();
    final cn = loc(ch.birthCountry.name, engine.lang);
    final cmp = diff >= 0
        ? b('ortalamadan $diff yıl fazla', '$diff years above the average')
        : b('ortalamadan ${-diff} yıl az', '${-diff} years below the average');
    final love = ch.marriages == 0
        ? ''
        : b(' Evlilik: ${ch.marriages}, boşanma: ${ch.divorces}.', ' Marriages: ${ch.marriages}, divorces: ${ch.divorces}.');
    return b(
      '${ch.birthCountry.flag} $cn ülkesinde doğdum, ${ch.age} yaşında öldüm ($cmp). '
          'Eğitim: ${engine.eduName(ch.edu)}, çocuk: ${ch.children.length}, ülke sayısı: ${ch.countriesLived}.$love '
          'Sen nasıl bir hayat yaşardın? #HayatSimülasyonu',
      'Born in $cn ${ch.birthCountry.flag}, died at ${ch.age} ($cmp). '
          'Education: ${engine.eduName(ch.edu)}, children: ${ch.children.length}, countries lived in: ${ch.countriesLived}.$love '
          'What life would you live? #LifeSimulator',
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveImage() async {
    if (_busy) return;
    final b = engine.b;
    setState(() => _busy = true);
    try {
      final png = await captureCard(_cardKey);
      if (png == null) {
        _toast(b('Görsel oluşturulamadı', 'Could not create the image'));
      } else {
        await saveToGallery(png);
        _toast(b('Görsel galeriye kaydedildi', 'Image saved to your gallery'));
      }
    } on UnsupportedError {
      _toast(b('Bu platformda galeriye kaydetme desteklenmiyor; Paylaş\'ı dene', 'Saving to gallery is not supported here; try Share'));
    } catch (_) {
      _toast(b('Kaydedilemedi. Galeri iznini kontrol et.', 'Could not save. Check the photo permission.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    final b = engine.b;
    setState(() => _busy = true);
    try {
      final png = await captureCard(_cardKey);
      if (png == null) {
        _toast(b('Görsel oluşturulamadı', 'Could not create the image'));
      } else {
        await shareImage(png, _shareText(engine.c!));
      }
    } on UnsupportedError {
      _toast(b('Bu platformda paylaşım desteklenmiyor', 'Sharing is not supported here'));
    } catch (_) {
      _toast(b('Paylaşılamadı', 'Could not share'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = engine.c!;
    final b = engine.b;
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
          // Bu kart PNG olarak kaydedilir / paylaşılır.
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: ResultCard(engine: engine),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _saveImage,
            icon: const Icon(Icons.download),
            label: Text(b('Görsel olarak kaydet', 'Save as image')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _shareImage,
            icon: const Icon(Icons.ios_share),
            label: Text(b('Görseli paylaş', 'Share image')),
          ),
          const Divider(height: 28),
          row(b('Ölüm nedeni', 'Cause'), ch.cause ?? '-'),
          row(b('Doğduğu ülke', 'Born in'), cn),
          row(b('Son ülke', 'Last country'), loc(ch.country.name, engine.lang)),
          row(b('Eğitim', 'Education'), engine.eduName(ch.edu)),
          row(b('Evlilik', 'Marriages'), '${ch.marriages}'),
          row(b('Boşanma', 'Divorces'), '${ch.divorces}'),
          row(b('Aldatılma', 'Times cheated on'), '${ch.cheatedOn}'),
          row(b('Gizli ilişki', 'Affairs'), '${ch.affairs}'),
          row(b('Çocuk', 'Children'), '${ch.children.length}'),
          row(b('Tuttuğu iş sayısı', 'Jobs held'), '${ch.jobsHeld}'),
          row(b('Mülakat (geçti/elendi)', 'Interviews (passed/failed)'), '${ch.interviewsPassed}/${ch.interviewsFailed}'),
          row(b('Son varlık', 'Final wealth'), fmtMoney(ch.money)),
          row(b('En yüksek varlık', 'Peak wealth'), fmtMoney(ch.peakMoney)),
          row(b('Gizli şans değeri', 'Hidden luck'), '${ch.luck.round()}/100'),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _shareText(ch)));
              _toast(b('Paylaşım metni kopyalandı', 'Share text copied'));
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

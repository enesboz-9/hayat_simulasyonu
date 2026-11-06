import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'achievements.dart';
import 'achievements_screen.dart';
import 'engine.dart';
import 'gender_badge.dart';
import 'models.dart';
import 'relationships.dart';
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
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AchievementsScreen(engine: engine)),
                      ),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: Text(b('Başarılar', 'Achievements') + ' · ${engine.unlockedCount}/${engine.achievementTotal}'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      b('İlgi duyduğun kişiler (yeni hayat için)', 'Attracted to (applies to new lives)'),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final m in kAttractionModes)
                          ChoiceChip(
                            label: Text(attractionLabel(m, b)),
                            selected: engine.orientationSetting == m,
                            onSelected: (_) => engine.setOrientation(m),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
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

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.engine});
  final GameEngine engine;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameEngine get engine => widget.engine;

  /// Ekranın üstünde gösterilen, yeni açılmış başarılar.
  List<Achievement> _banner = const [];
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    engine.addListener(_onEngine);
  }

  @override
  void dispose() {
    engine.removeListener(_onEngine);
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _onEngine() {
    final fresh = engine.takeFreshUnlocks();
    if (fresh.isEmpty || !mounted) return;
    setState(() => _banner = [..._banner, ...fresh].take(3).toList());
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _banner = const []);
    });
  }

  void _openAchievements() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AchievementsScreen(engine: engine)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final ch = engine.c!;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GenderBadge(female: ch.female, size: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${ch.country.flag} ${loc(ch.country.name, engine.lang)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: engine.b('Başarılar', 'Achievements'),
                icon: const Icon(Icons.emoji_events_outlined),
                onPressed: _openAchievements,
              ),
              IconButton(
                icon: const Icon(Icons.translate),
                onPressed: () => engine.setLang(engine.lang == 'tr' ? 'en' : 'tr'),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _Header(engine: engine),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Karar yoksa ekrana dokunmak 1 yıl ilerletir.
                      onTap: ch.alive && engine.pending == null ? engine.advanceYear : null,
                      child: _LogList(entries: ch.log),
                    ),
                  ),
                  _Bottom(engine: engine),
                ],
              ),
              if (_banner.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: UnlockBanner(
                    engine: engine,
                    items: _banner,
                    onTap: () {
                      setState(() => _banner = const []);
                      _openAchievements();
                    },
                  ),
                ),
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
            Row(
              children: [
                GenderBadge(female: ch.female, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${ch.name} · ${ch.age} ${b('yaş', 'y/o')} · ${ch.alive ? _status(ch) : b('Hayatını kaybetti', 'Deceased')}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(engine.eduName(ch.edu)), visualDensity: VisualDensity.compact),
                if (ch.age >= 18) Chip(label: Text('💰 ${fmtMoney(ch.money)}'), visualDensity: VisualDensity.compact),
                if (ch.spouse != null) Chip(label: Text('💍 ${ch.spouse!.name}'), visualDensity: VisualDensity.compact),
                if (ch.partner != null)
                  Chip(
                    label: Text('${ch.partner!.living ? '🏡' : '❤️'} ${ch.partner!.name}'),
                    visualDensity: VisualDensity.compact,
                  ),
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
        // "↩" ile başlayan satırlar eski bir seçimin yıllar sonra geri dönüşüdür.
        final echo = e.text.startsWith('↩');
        if (echo) color = Colors.purpleAccent;
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
                  style: e.kind == 'choice' || echo ? const TextStyle(fontStyle: FontStyle.italic) : null,
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
                        onPressed: () {
                          final messenger = ScaffoldMessenger.of(context);
                          engine.choose(o);
                          showDeltaToast(messenger, engine);
                        },
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
          if (ch.earned.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '🏆 ${b('Bu hayatta kazanılan başarılar', 'Achievements earned this life')} (${ch.earned.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AchievementsScreen(engine: engine)),
                  ),
                  child: Text(b('Tümü', 'All')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in kAchievements.where((x) => ch.earned.contains(x.id)))
                  Chip(
                    avatar: Text(a.emoji),
                    label: Text(a.title(engine.lang) + (ch.firstTime.contains(a.id) ? ' · ${b('yeni', 'new')}' : '')),
                    side: BorderSide(color: tierColor(a.tier)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const Divider(height: 28),
          ],
          if (engine.lifeMarks(ch).isNotEmpty) ...[
            Text(b('Hayatının izleri', 'Marks of your life'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in engine.lifeMarks(ch)) Chip(label: Text(m), visualDensity: VisualDensity.compact),
              ],
            ),
            const Divider(height: 28),
          ],
          row(b('Ölüm nedeni', 'Cause'), ch.cause ?? '-'),
          row(b('Doğduğu ülke', 'Born in'), cn),
          row(b('Son ülke', 'Last country'), loc(ch.country.name, engine.lang)),
          row(b('Eğitim', 'Education'), engine.eduName(ch.edu)),
          row(b('İlgi duyulan', 'Attracted to'), attractionLabel(ch.attraction, b)),
          row(b('İlişki (evlilik dışı)', 'Relationships (non-marital)'), '${ch.relationships}'),
          row(b('Ayrılık', 'Breakups'), '${ch.breakups}'),
          row(b('Birlikte yaşama', 'Lived together'), '${ch.cohabited}'),
          row(b('Evlilik', 'Marriages'), '${ch.marriages}'),
          row(b('Boşanma', 'Divorces'), '${ch.divorces}'),
          row(b('Aldatılma', 'Times cheated on'), '${ch.cheatedOn}'),
          row(b('Gizli ilişki', 'Affairs'), '${ch.affairs}'),
          row(b('Alınan tazminat/nafaka', 'Damages/alimony received'), fmtMoney(ch.compReceived)),
          row(b('Ödenen tazminat/nafaka', 'Damages/alimony paid'), fmtMoney(ch.compPaid)),
          row(b('Cinsiyet', 'Gender'), ch.female ? b('Kadın', 'Female') : b('Erkek', 'Male')),
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


// ───────────────────────── Karar sonrası bildirim ─────────────────────────

/// Kararın etkilerini ("Sağlık -3", "Para +$2k") kısa bir bildirimle gösterir.
void showDeltaToast(ScaffoldMessengerState messenger, GameEngine engine) {
  final deltas = engine.lastDeltas;
  if (deltas.isEmpty) return;
  final b = engine.b;

  String label(String k) => switch (k) {
        'health' => b('Sağlık', 'Health'),
        'happiness' => b('Mutluluk', 'Happiness'),
        'smarts' => b('Zekâ', 'Smarts'),
        'looks' => b('Çekicilik', 'Looks'),
        'social' => b('Sosyal', 'Social'),
        _ => b('Para', 'Money'),
      };

  String value(StatDelta d) {
    final sign = d.amount > 0 ? '+' : '-';
    if (d.key == 'money') return '$sign${fmtMoney(d.amount.abs())}';
    return '$sign${d.amount.abs().round()}';
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2200),
        behavior: SnackBarBehavior.floating,
        content: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final d in deltas)
              Text(
                '${label(d.key)} ${value(d)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: d.amount > 0 ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
          ],
        ),
      ),
    );
}

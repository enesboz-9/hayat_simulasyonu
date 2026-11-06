import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/achievements.dart';
import 'package:hayat_simulasyonu/engine.dart';

Future<GameEngine> _engine({AchievementStorage? storage, int seed = 1}) async {
  final e = GameEngine(random: Random(seed), storage: storage);
  await e.load(reader: (f) => File('assets/data/$f').readAsString());
  return e;
}

void _playOut(GameEngine e, Random pick) {
  final ch = e.c!;
  var guard = 0;
  while (ch.alive && guard++ < 400) {
    final d = e.pending;
    if (d != null) {
      e.choose(d.options[pick.nextInt(d.options.length)]);
    } else {
      e.advanceYear();
    }
  }
}

void main() {
  test('başarı kimlikleri benzersiz ve metinleri dolu', () {
    final ids = kAchievements.map((a) => a.id).toSet();
    expect(ids.length, kAchievements.length);
    for (final a in kAchievements) {
      expect(a.titleTr.isNotEmpty && a.titleEn.isNotEmpty, isTrue, reason: a.id);
      expect(a.descTr.isNotEmpty && a.descEn.isNotEmpty, isTrue, reason: a.id);
    }
  });

  test('istenen örnek hedefler tanımlı: 100 yaş, 3 ülke, manken, boşanıp tazminat', () {
    final ids = kAchievements.map((a) => a.id).toSet();
    expect(ids, containsAll(['age_100', 'three_countries', 'model', 'alimony_win']));
  });

  test('koşullar doğru çalışır', () async {
    final e = await _engine();
    e.newLife();
    final ch = e.c!;
    Achievement a(String id) => kAchievements.firstWhere((x) => x.id == id);

    expect(a('age_100').test(ch), isFalse);
    ch.age = 100;
    expect(a('age_100').test(ch), isTrue);

    expect(a('three_countries').test(ch), isFalse);
    ch.livedIn.addAll(['AA', 'BB']);
    expect(a('three_countries').test(ch), isTrue);

    expect(a('alimony_win').test(ch), isFalse);
    ch.divorces = 1;
    ch.compReceived = 40;
    expect(a('alimony_win').test(ch), isTrue);
    ch.compReceived = 0;
    expect(a('alimony_win').test(ch), isFalse);

    expect(a('model').test(ch), isFalse);
    ch.jobIds.add('model');
    expect(a('model').test(ch), isTrue);
  });

  test('açılan başarı kaydedilir, yeni motor yükleyince geri gelir, tekrar duyurulmaz', () async {
    final storage = MemoryAchievementStorage();
    final e = await _engine(storage: storage);
    e.newLife();
    final ch = e.c!;
    ch.age = 49;
    e.advanceYear(); // 50 yaş → "Yarım Asır" (ölmediyse)
    if (ch.alive) {
      expect(e.unlocked.containsKey('age_50'), isTrue);
      expect(e.takeFreshUnlocks().any((a) => a.id == 'age_50'), isTrue);
      expect(e.takeFreshUnlocks(), isEmpty);
    }
    await Future<void>.delayed(Duration.zero);

    final e2 = await _engine(storage: storage, seed: 2);
    expect(e2.unlockedCount, e.unlockedCount);
    expect(e2.livesStarted, 1);
    if (ch.alive) expect(e2.unlocked['age_50']!.age, 50);
  });

  test('150 hayat: çökmez, başarı oranlarını yazar', () async {
    final e = await _engine(seed: 42);
    final pick = Random(7);
    final counts = <String, int>{};
    const n = 150;
    for (var i = 0; i < n; i++) {
      e.newLife();
      _playOut(e, pick);
      for (final id in e.c!.earned) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final rows = [
      for (final a in kAchievements) (a.id, counts[a.id] ?? 0),
    ]..sort((x, y) => y.$2.compareTo(x.$2));
    // ignore: avoid_print
    print('Başarı oranları ($n hayat, rastgele seçimlerle):');
    for (final r in rows) {
      // ignore: avoid_print
      print('  ${r.$1.padRight(18)} ${(100 * r.$2 / n).toStringAsFixed(0).padLeft(3)}%');
    }
    expect(counts['age_50'] ?? 0, greaterThan(0));
    expect(e.unlockedCount, greaterThan(0));
  });
}

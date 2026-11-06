import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/achievements.dart';
import 'package:hayat_simulasyonu/engine.dart';
import 'package:hayat_simulasyonu/relationships.dart';

Future<GameEngine> _engine(int seed) async {
  final e = GameEngine(random: Random(seed));
  await e.load(reader: (f) => File('assets/data/$f').readAsString());
  return e;
}

/// Bir yönelim ayarıyla [n] hayat oynatır; her adımda tutarlılığı denetler.
/// Dönen liste: [ilişki, birlikte yaşama, ayrılık, evlilik, aynı cins sevgili/eş].
Future<List<int>> _simulate(String mode, int n, void Function(dynamic ch) check) async {
  final e = await _engine(11);
  e.setOrientation(mode);
  final pick = Random(5);
  var rel = 0, live = 0, brk = 0, mar = 0, sameSex = 0;
  for (var i = 0; i < n; i++) {
    e.newLife();
    final ch = e.c!;
    var guard = 0;
    while (ch.alive && guard++ < 400) {
      final hadSpouse = ch.spouse != null;
      final d = e.pending;
      if (d != null) {
        e.choose(d.options[pick.nextInt(d.options.length)]);
      } else {
        e.advanceYear();
      }
      if (!hadSpouse && ch.spouse != null) {
        // Yeni evlilik: aynı cinsse ülke evlilik eşitliğini tanımalı.
        expect(canWed(ch, ch.spouse!), isTrue, reason: '${ch.country.code} ${ch.attraction}');
      }
      for (final p in [ch.partner, ch.spouse]) {
        if (p != null && p.female == ch.female) sameSex++;
      }
      check(ch);
    }
    rel += ch.relationships;
    live += ch.cohabited;
    brk += ch.breakups;
    mar += ch.marriages;
  }
  return [rel, live, brk, mar, sameSex];
}

void main() {
  test('karşı cins ayarı: sevgili ve eşler hep karşı cinsten', () async {
    final r = await _simulate('opposite', 150, (ch) {
      for (final p in [ch.partner, ch.spouse]) {
        if (p != null) expect(p.female, isNot(ch.female));
      }
    });
    // ignore: avoid_print
    print('opposite → ilişki ${r[0]}, birlikte yaşama ${r[1]}, ayrılık ${r[2]}, evlilik ${r[3]}');
    expect(r[0], greaterThan(0));
    expect(r[4], 0);
  });

  test('aynı cins ayarı: sevgili/eş hep aynı cinsten; evlilik yalnızca yasal ülkelerde', () async {
    final r = await _simulate('same', 150, (ch) {
      expect(ch.attraction, 'same');
      for (final p in [ch.partner, ch.spouse]) {
        if (p != null) expect(p.female, ch.female);
      }
    });
    // ignore: avoid_print
    print('same → ilişki ${r[0]}, birlikte yaşama ${r[1]}, ayrılık ${r[2]}, evlilik ${r[3]}');
    expect(r[0], greaterThan(0));
  });

  test('her ikisi ayarı: iki cinsiyet de görülür', () async {
    final r = await _simulate('both', 150, (_) {});
    // ignore: avoid_print
    print('both → ilişki ${r[0]}, aynı cins adım sayısı ${r[4]}');
    expect(r[4], greaterThan(0));
  });

  test('rastgele ayar: yönelim dağılımı yaklaşık beklenen oranlarda', () async {
    final e = await _engine(3);
    e.setOrientation('random');
    var same = 0, both = 0;
    const n = 1000;
    for (var i = 0; i < n; i++) {
      e.newLife();
      if (e.c!.attraction == 'same') same++;
      if (e.c!.attraction == 'both') both++;
    }
    expect(same, inInclusiveRange(10, 90));
    expect(both, inInclusiveRange(40, 130));
  });

  test('yönelim ayarı kaydedilir ve geri yüklenir', () async {
    final storage = MemoryAchievementStorage();
    final a = GameEngine(random: Random(1), storage: storage);
    await a.load(reader: (f) => File('assets/data/$f').readAsString());
    a.setOrientation('both');
    final b = GameEngine(random: Random(2), storage: storage);
    await b.load(reader: (f) => File('assets/data/$f').readAsString());
    expect(b.orientationSetting, 'both');
  });
}

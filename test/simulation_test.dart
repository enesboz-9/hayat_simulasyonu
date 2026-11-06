import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/engine.dart';

/// Denge ayarı için: arayüz olmadan yüzlerce hayatı baştan sona oynatır,
/// kararları rastgele seçer ve ülke bazında ortalama ölüm yaşını yazdırır.
void main() {
  test('800 hayat simülasyonu', () async {
    final e = GameEngine(random: Random(42));
    await e.load(reader: (f) => File('assets/data/$f').readAsString());
    final pick = Random(7);
    const n = 800;
    final byCountry = <String, List<int>>{};
    var total = 0;

    for (var i = 0; i < n; i++) {
      e.newLife();
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
      total += ch.age;
      byCountry.putIfAbsent(ch.birthCountry.code, () => []).add(ch.age);
    }

    final avg = total / n;
    // ignore: avoid_print
    print('Genel ortalama ölüm yaşı: ${avg.toStringAsFixed(1)}');
    final codes = byCountry.keys.toList()..sort((a, b) => byCountry[b]!.length.compareTo(byCountry[a]!.length));
    for (final c in codes) {
      final l = byCountry[c]!;
      // ignore: avoid_print
      print('$c: ${l.length} hayat, ort. ${(l.reduce((a, b) => a + b) / l.length).toStringAsFixed(1)}');
    }
    expect(avg, inInclusiveRange(45, 90));
  });
}

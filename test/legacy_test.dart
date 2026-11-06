import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/engine.dart';

/// Uzun vadeli sonuçlar: bayrak "X yıl önce" koşulları ve gecikmeli sonuçlar
/// söz verdikleri zamanlamayla çalışmalı.
void main() {
  test('geri dönüşler doğru zamanda gelir', () async {
    final e = GameEngine(random: Random(42));
    await e.load(reader: (f) => File('assets/data/$f').readAsString());
    expect(e.events.any((x) => x.id == 'lg_athlete_vital'), isTrue, reason: 'events_legacy.json yüklenmeli');

    final pick = Random(7);
    var refunds = 0, athleteEchoes = 0;
    for (var i = 0; i < 600; i++) {
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
      for (final l in ch.log) {
        if (l.text.contains('dolandırıcı çete yakalandı')) {
          refunds++;
          final diff = l.age - ch.flagAge['scammed']!;
          expect(diff, inInclusiveRange(4, 9));
        }
        if (l.text.contains('Yıllarca spor yapmanın')) {
          athleteEchoes++;
          expect(l.age - ch.flagAge['athlete']!, greaterThanOrEqualTo(20));
        }
      }
    }
    expect(refunds, greaterThan(0));
    expect(athleteEchoes, greaterThan(0));
  });
}

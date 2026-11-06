import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/engine.dart';

/// Denge ayarı için: arayüz olmadan yüzlerce hayatı baştan sona oynatır,
/// kararları rastgele seçer; ülke dağılımını, ortalama ölüm yaşını, boşanma /
/// aldatma oranlarını ve mülakat başarısını yazdırır.
void main() {
  test('800 hayat simülasyonu', () async {
    final e = GameEngine(random: Random(42));
    await e.load(reader: (f) => File('assets/data/$f').readAsString());
    final pick = Random(7);
    const n = 800;
    final byCountry = <String, List<int>>{};
    var total = 0, marriages = 0, divorces = 0, cheatedOn = 0, affairs = 0;
    var married = 0, passed = 0, failed = 0;

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
      marriages += ch.marriages;
      divorces += ch.divorces;
      cheatedOn += ch.cheatedOn;
      affairs += ch.affairs;
      if (ch.marriages > 0) married++;
      passed += ch.interviewsPassed;
      failed += ch.interviewsFailed;
      byCountry.putIfAbsent(ch.birthCountry.code, () => []).add(ch.age);
    }

    final avg = total / n;
    // ignore: avoid_print
    print('Genel ortalama ölüm yaşı: ${avg.toStringAsFixed(1)}');
    // ignore: avoid_print
    print('Evlenen: $married/$n · evlilik: $marriages · boşanma: $divorces '
        '(${marriages == 0 ? 0 : (100 * divorces / marriages).toStringAsFixed(0)}% of marriages)');
    // ignore: avoid_print
    print('Aldatılma: $cheatedOn · gizli ilişki: $affairs');
    // ignore: avoid_print
    print('Mülakat: geçti $passed, elendi $failed '
        '(elenme %${passed + failed == 0 ? 0 : (100 * failed / (passed + failed)).toStringAsFixed(0)})');
    final codes = byCountry.keys.toList()..sort((a, b) => byCountry[b]!.length.compareTo(byCountry[a]!.length));
    // ignore: avoid_print
    print('Farklı doğum ülkesi: ${codes.length}/${e.countries.length}');
    for (final c in codes.take(10)) {
      final l = byCountry[c]!;
      // ignore: avoid_print
      print('$c: ${l.length} hayat, ort. ${(l.reduce((a, b) => a + b) / l.length).toStringAsFixed(1)}');
    }

    expect(avg, inInclusiveRange(45, 90));
    // Ortalama ölüm yaşı, doğum ülkelerinin (doğum oranıyla ağırlıklı) yaşam beklentisine yakın olmalı;
    // eskiden olaylardan biriken sağlık hasarı yüzünden hep belirgin biçimde altında kalıyordu.
    var expSum = 0.0;
    byCountry.forEach((code, ages) {
      final le = e.countries.firstWhere((c) => c.code == code).lifeExp;
      expSum += le * ages.length;
    });
    final meanExp = expSum / n;
    // ignore: avoid_print
    print('Ort. ölüm yaşı ${avg.toStringAsFixed(1)} / ülke beklentisi ${meanExp.toStringAsFixed(1)}');
    expect(avg - meanExp, inInclusiveRange(-3.5, 4.5));
    // Doğum ülkesi gerçek doğum oranlarını izler (Hindistan ~%17).
    expect(codes.length, greaterThanOrEqualTo(50));
    final inShare = (byCountry['IN']?.length ?? 0) / n;
    expect(inShare, inInclusiveRange(0.12, 0.23));
    // Mülakat elenme oranı makul olmalı (eskiden ~%40'tı).
    if (passed + failed > 50) expect(failed / (passed + failed), lessThan(0.3));
  });
}

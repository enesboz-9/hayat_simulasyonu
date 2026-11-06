import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/divorce_law.dart';
import 'package:hayat_simulasyonu/models.dart';

Map<String, Country> _countries() {
  final list = jsonDecode(File('assets/data/countries.json').readAsStringSync()) as List;
  return {
    for (final j in list)
      (j as Map)['code'] as String: Country.fromJson(Map<String, dynamic>.from(j)),
  };
}

Character _player(Country c, {required bool female, double money = 80}) {
  final ch = Character(
    name: 'Test',
    female: female,
    country: c,
    health: 70,
    happiness: 60,
    smarts: 50,
    looks: 50,
    social: 50,
    luck: 50,
    famWealth: 50,
    retireAge: 65,
  );
  ch.money = money;
  return ch;
}

Person _spouse(Character ch, {double wealth = 10}) => Person(
      name: 'Eş',
      age: 35,
      female: !ch.female,
      looks: 60,
      smarts: 60,
      kind: 60,
      jobName: const {'tr': 'Memur', 'en': 'Clerk'},
      pay: 1.0,
      trait: 'plain',
      bond: 30,
      wealth: wealth,
    )..yearsMarried = 10;

void main() {
  final countries = _countries();

  test('Suçsuz oyuncu hiçbir ülkede tazminat/nafaka ödemez, tazminat alır', () {
    for (final c in countries.values) {
      for (final female in [true, false]) {
        for (final mode in DivorceMode.values) {
          for (final inc in [0.0, c.gdp * 0.5, c.gdp * 3]) {
            final ch = _player(c, female: female, money: c.gdp * 4);
            final t = computeDivorceTerms(
              ch: ch,
              spouse: _spouse(ch),
              fault: Fault.partner,
              mode: mode,
              playerIncome: inc,
              spouseIncome: c.gdp,
              byPartner: false,
            );
            expect(t.paidOut, 0, reason: '${c.code} female=$female $mode inc=$inc');
            expect(t.compensation, greaterThan(0), reason: c.code);
          }
        }
      }
    }
  });

  test('Kusurlu oyuncu yalnızca kusur hukuku olan ülkelerde tazminat öder', () {
    for (final c in countries.values) {
      final r = regimeFor(c);
      final ch = _player(c, female: false, money: c.gdp * 4);
      final t = computeDivorceTerms(
        ch: ch,
        spouse: _spouse(ch),
        fault: Fault.player,
        mode: DivorceMode.contested,
        playerIncome: c.gdp,
        spouseIncome: c.gdp,
        byPartner: true,
      );
      if (r.faultLaw) {
        expect(t.compensation, lessThan(0), reason: c.code);
      } else {
        expect(t.compensation, 0, reason: c.code);
      }
    }
  });

  test('Türkiye: kusurlu eş nafaka isteyemez; ABD: kusursuz rejim', () {
    final tr = countries['TR']!;
    final ch = _player(tr, female: true, money: tr.gdp * 4);
    final t = computeDivorceTerms(
      ch: ch,
      spouse: _spouse(ch),
      fault: Fault.player,
      mode: DivorceMode.contested,
      playerIncome: 0,
      spouseIncome: tr.gdp * 2,
      byPartner: true,
    );
    expect(t.support, 0);
    expect(regimeFor(countries['US']!).faultLaw, isFalse);
    expect(regimeFor(tr).faultLaw, isTrue);
  });

  test('İslam hukuku: koca mehir öder, kadın alır; kusurlu kadın mehri yitirir', () {
    final sa = countries['SA']!;
    final man = _player(sa, female: false, money: sa.gdp * 4);
    final woman = _player(sa, female: true, money: sa.gdp * 4);
    final tm = computeDivorceTerms(
      ch: man,
      spouse: _spouse(man),
      fault: Fault.none,
      mode: DivorceMode.amicable,
      playerIncome: sa.gdp,
      spouseIncome: 0,
      byPartner: false,
    );
    final tw = computeDivorceTerms(
      ch: woman,
      spouse: _spouse(woman),
      fault: Fault.none,
      mode: DivorceMode.amicable,
      playerIncome: 0,
      spouseIncome: sa.gdp,
      byPartner: true,
    );
    final twFault = computeDivorceTerms(
      ch: woman,
      spouse: _spouse(woman),
      fault: Fault.player,
      mode: DivorceMode.amicable,
      playerIncome: 0,
      spouseIncome: sa.gdp,
      byPartner: true,
    );
    expect(tm.support, lessThan(0));
    expect(tw.support, greaterThan(0));
    expect(twFault.support, 0);
  });

  test('Ödemeler oyuncunun gücünü aşmaz', () {
    final us = countries['US']!;
    final ch = _player(us, female: false, money: 1);
    final t = computeDivorceTerms(
      ch: ch,
      spouse: _spouse(ch, wealth: 0),
      fault: Fault.none,
      mode: DivorceMode.contested,
      playerIncome: us.gdp * 3,
      spouseIncome: 0,
      byPartner: false,
    );
    expect(t.paidOut, lessThanOrEqualTo(us.gdp * 0.5 + 1));
  });
}

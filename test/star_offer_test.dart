import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayat_simulasyonu/engine.dart';
import 'package:hayat_simulasyonu/models.dart';

Character _p(Country c, double looks, {int age = 25}) {
  final ch = Character(
    name: 'T',
    female: true,
    country: c,
    health: 70,
    happiness: 60,
    smarts: 50,
    looks: looks,
    social: 50,
    luck: 50,
    famWealth: 50,
    retireAge: 65,
  );
  ch.age = age;
  return ch;
}

void main() {
  test('Manken/oyuncu teklifi oranları', () {
    final list = jsonDecode(File('assets/data/countries.json').readAsStringSync()) as List;
    final cs = {for (final j in list) (j as Map)['code'] as String: Country.fromJson(Map<String, dynamic>.from(j))};
    final e = GameEngine();
    final poor = cs['NG']!; // gdp <= ~2
    final rich = cs['US']!; // gdp >= 15
    expect(e.starChance(_p(poor, 79)), 0);
    expect(e.starChance(_p(poor, 85)), closeTo(0.00001 * (poor.gdp <= 2 ? 1 : 1 + 9 * ((poor.gdp - 2) / 13).clamp(0, 1)), 1e-9));
    expect(e.starChance(_p(rich, 85)), closeTo(0.0001, 1e-9));
    expect(e.starChance(_p(rich, 92)), closeTo(0.001, 1e-9));
    expect(e.starChance(_p(rich, 97)), closeTo(0.012, 1e-9));
    expect(e.starChance(_p(rich, 97, age: 50)), 0);
  });
}

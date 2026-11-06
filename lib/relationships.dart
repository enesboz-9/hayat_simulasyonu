import 'models.dart';

/// Yönelim ayarı değerleri: ilgi duyulan cinsiyet. `random` yeni hayatta
/// ihtimallere göre atanır (yaklaşık %88 karşı cins, %4 aynı cins, %8 her ikisi).
const kAttractionModes = ['opposite', 'same', 'both', 'random'];

String attractionLabel(String mode, String Function(String, String) b) => switch (mode) {
      'same' => b('Aynı cins', 'Same sex'),
      'both' => b('Her ikisi', 'Both'),
      'random' => b('Rastgele', 'Random'),
      _ => b('Karşı cins', 'Opposite sex'),
    };

/// Aynı cinsler arasında evliliğin yasal olduğu ülkeler (ISO kodu). Oyun için
/// yaklaşık bir listedir, hukuki bilgi değildir; hukuk değiştikçe güncellenmeli.
/// Buralarda olmayan ülkelerde aynı cins çiftler sevgili olabilir ve birlikte
/// yaşayabilir ama evlenemez.
const marriageEqualityCodes = <String>{
  'AD', 'AR', 'AU', 'AT', 'BE', 'BR', 'CA', 'CL', 'CO', 'CR', 'CU', 'DK', 'EC', 'EE',
  'FI', 'FR', 'DE', 'GR', 'IS', 'IE', 'LI', 'LU', 'MT', 'MX', 'NL', 'NZ', 'NO', 'PT',
  'SI', 'ZA', 'ES', 'SE', 'CH', 'TW', 'GB', 'UY', 'US', 'TH',
};

/// Oyuncu bu kişiyle bulunduğu ülkede evlenebilir mi?
bool canWed(Character ch, Person p) =>
    p.female != ch.female || marriageEqualityCodes.contains(ch.country.code);

/// Oyuncunun yönelimine uyan biriyle bulunduğu ülkede evlenmesi mümkün mü?
/// (Yalnızca aynı cinse ilgi duyan oyuncu, evlilik eşitliği olmayan ülkede evlenemez.)
bool canMarryAnyone(Character ch) =>
    ch.attraction != 'same' || marriageEqualityCodes.contains(ch.country.code);

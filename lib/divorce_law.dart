import 'dart:math';

import 'models.dart';

/// Boşanmada kusur kimde?
/// [player] oyuncu kusurlu (ör. gizli ilişkisi ortaya çıktı),
/// [partner] eş kusurlu (ör. oyuncuyu aldattı), [none] kusur yok / karşılıklı.
enum Fault { player, partner, none }

/// Anlaşmalı boşanma ucuz ve hızlıdır ama tazminat pazarlıkla düşer;
/// çekişmeli boşanma pahalıdır, dava kazanılırsa kazanç büyür, kaybedilirse küçülür.
enum DivorceMode { amicable, contested }

/// Bir ülkenin (yaklaşık) boşanma hukuku. Değerler oyun içindir; gerçek
/// mevzuatın basitleştirilmiş, oyunlaştırılmış halidir, hukuki tavsiye değildir.
///
/// Parasal değerlerin çoğu ülkenin kişi başı gelirinin (`gdp`) katıdır.
class DivorceRegime {
  const DivorceRegime({
    required this.id,
    required this.tr,
    required this.en,
    this.split = 0.5,
    this.separate = false,
    this.alimony = 0.3,
    this.damages = 0.3,
    this.faultLaw = false,
    this.faultBarsAlimony = false,
    this.mahr = 0,
  });

  final String id;

  /// Oyuncuya gösterilen kısa hukuk özeti.
  final String tr, en;

  /// Ortak malların eşe giden payı (uzun evlilikte).
  final double split;

  /// true ise mallar ayrıdır: herkes kendi malını alır (eş, evlilikte
  /// getirdiği varlığı geri alır); ortak mal bölüşümü yoktur.
  final bool separate;

  /// Nafaka: kişi başı gelirin katı (tam süreli evlilik ve tam gelir farkında).
  final double alimony;

  /// Kusursuz eşe ödenen tazminat: kişi başı gelirin katı.
  /// Kusur hukuku olmayan ülkelerde bile suçsuz oyuncu bunu alır (oyun kuralı).
  final double damages;

  /// true ise kusurlu eş gerçekten tazminat öder (hukuken kusur önemlidir).
  final bool faultLaw;

  /// true ise kusurlu eş nafaka isteyemez.
  final bool faultBarsAlimony;

  /// Mehir (kişi başı gelirin katı). 0'dan büyükse koca eşe mehir + iddet nafakası öder.
  final double mahr;

  bool get hasMahr => mahr > 0;
}

const _tr = DivorceRegime(
  id: 'tr',
  tr: 'Türk hukuku: kusurlu eş maddi ve manevi tazminat öder, kusurlu eş nafaka isteyemez; mallar edinilmiş mallara katılma rejimiyle bölüşülür.',
  en: 'Turkish law: the party at fault pays material and moral damages and cannot claim alimony; assets are split under the participation regime.',
  split: 0.5,
  alimony: 0.5,
  damages: 1.2,
  faultLaw: true,
  faultBarsAlimony: true,
);

const _us = DivorceRegime(
  id: 'us',
  tr: 'ABD: çoğu eyalette kusursuz boşanma; mallar hakkaniyetle bölünür, süreye göre nafaka verilebilir.',
  en: 'US: mostly no-fault; assets split equitably and alimony can be awarded depending on length of marriage.',
  split: 0.5,
  alimony: 0.8,
  damages: 0.3,
);

const _common = DivorceRegime(
  id: 'common',
  tr: 'Anglosakson hukuku: kusursuz boşanma; mallar ihtiyaç ve katkıya göre bölünür, nafaka sınırlıdır.',
  en: 'Common-law system: no-fault divorce; assets divided by needs and contribution, alimony is limited.',
  split: 0.5,
  alimony: 0.45,
  damages: 0.25,
);

const _nordic = DivorceRegime(
  id: 'nordic',
  tr: 'İskandinav hukuku: temiz ayrılık; mallar yarı yarıya bölünür, nafaka çok nadirdir.',
  en: 'Nordic law: clean break; assets split evenly and alimony is rare.',
  split: 0.5,
  alimony: 0.1,
  damages: 0.15,
);

const _france = DivorceRegime(
  id: 'fr',
  tr: 'Fransız hukuku: telafi edici ödenek (prestation compensatoire) ve kusurlu eşten tazminat mümkündür.',
  en: 'French law: compensatory allowance and damages from the spouse at fault are possible.',
  split: 0.5,
  alimony: 0.6,
  damages: 0.8,
  faultLaw: true,
);

const _civil = DivorceRegime(
  id: 'civil',
  tr: 'Kıta Avrupası hukuku: mallar yarı yarıya bölünür, nafaka evlilik süresine göre belirlenir.',
  en: 'Continental European law: assets split evenly; alimony depends on the length of marriage.',
  split: 0.5,
  alimony: 0.35,
  damages: 0.35,
);

const _eastern = DivorceRegime(
  id: 'eastern',
  tr: 'Doğu Avrupa / eski SSCB hukuku: mallar eşit bölünür, eş nafakası nadirdir.',
  en: 'Eastern European / post-Soviet law: assets split equally; spousal support is rare.',
  split: 0.5,
  alimony: 0.1,
  damages: 0.2,
);

const _china = DivorceRegime(
  id: 'cn',
  tr: 'Çin hukuku: ortak mal eşit bölünür; bağlılık ihlali olan eş mağdur eşe tazminat öder.',
  en: 'Chinese law: shared property is split; a spouse who breached fidelity compensates the injured spouse.',
  split: 0.5,
  alimony: 0.1,
  damages: 0.9,
  faultLaw: true,
);

const _eastAsiaFault = DivorceRegime(
  id: 'ea',
  tr: 'Doğu Asya hukuku: mal paylaşımı katkıya göre yapılır; aldatan eş “teselli tazminatı” (isharyo / wijaryo) öder.',
  en: 'East Asian law: property is split by contribution; an adulterous spouse pays consolation damages.',
  split: 0.5,
  alimony: 0.1,
  damages: 1.0,
  faultLaw: true,
);

const _seAsia = DivorceRegime(
  id: 'sea',
  tr: 'Güneydoğu Asya hukuku: mal paylaşımı yapılır; kusurlu eş tazminat ödeyebilir.',
  en: 'Southeast Asian law: assets are divided; the party at fault may owe damages.',
  split: 0.5,
  alimony: 0.15,
  damages: 0.5,
  faultLaw: true,
);

const _india = DivorceRegime(
  id: 'in',
  tr: 'Hint hukuku: mallar ayrıdır; ancak ekonomik olarak zayıf eşe sürekli nafaka bağlanır, kusurlu eş tazminat öder.',
  en: 'Indian law: property stays separate, but the financially weaker spouse can get maintenance; the party at fault pays damages.',
  separate: true,
  alimony: 0.6,
  damages: 0.4,
  faultLaw: true,
);

const _islamic = DivorceRegime(
  id: 'islamic',
  tr: 'İslam aile hukuku: mallar ayrıdır; koca eşe mehir ve iddet nafakası öder, kusurlu eş tazminat öder.',
  en: 'Islamic family law: property is separate; the husband pays the mahr and iddah maintenance, and the party at fault pays damages.',
  separate: true,
  alimony: 0.15,
  damages: 0.5,
  faultLaw: true,
  mahr: 0.8,
);

const _latam = DivorceRegime(
  id: 'latam',
  tr: 'Latin Amerika hukuku: mal ortaklığı yaygındır, mallar yarı yarıya bölünür; nafaka sınırlıdır.',
  en: 'Latin American law: community property is common, so assets split evenly; alimony is limited.',
  split: 0.5,
  alimony: 0.2,
  damages: 0.3,
);

const _africa = DivorceRegime(
  id: 'africa',
  tr: 'Afrika hukuku: örf-âdet ve medeni hukuk karışıktır; mal paylaşımı sınırlıdır, kusurlu eş tazminat ödeyebilir.',
  en: 'African law: customary and civil law mix; property sharing is limited and the party at fault may owe damages.',
  split: 0.35,
  alimony: 0.1,
  damages: 0.3,
  faultLaw: true,
);

const _southAfrica = DivorceRegime(
  id: 'za',
  tr: 'Güney Afrika hukuku: mal ortaklığı esastır, kusursuz boşanma; nafaka sınırlıdır.',
  en: 'South African law: community of property, no-fault divorce; limited maintenance.',
  split: 0.5,
  alimony: 0.3,
  damages: 0.2,
);

const _default = DivorceRegime(
  id: 'default',
  tr: 'Genel kural: mallar paylaşılır, kusurlu eş tazminat ödeyebilir.',
  en: 'General rule: assets are shared and the party at fault may owe damages.',
  split: 0.5,
  alimony: 0.25,
  damages: 0.3,
);

const _usCodes = {'US'};
const _commonCodes = {'GB', 'CA', 'AU', 'NZ', 'IE'};
const _nordicCodes = {'SE', 'NO', 'DK', 'FI', 'IS'};
const _franceCodes = {'FR', 'BE', 'LU', 'MC'};
const _easternCodes = {'RU', 'UA', 'BY', 'MD', 'GE', 'AM', 'KZ', 'UZ', 'TM', 'KG', 'AZ', 'EE', 'LV', 'LT'};
const _eaFaultCodes = {'JP', 'KR', 'TW', 'MN', 'KP'};
const _islamicCodes = {
  'EG', 'SA', 'IR', 'MA', 'DZ', 'IQ', 'AF', 'TJ', 'LB', 'SY', 'JO', 'YE', 'OM', 'AE', 'QA', 'KW', 'BH', 'TN', 'LY', 'PS', //
  'PK', 'BD', 'MV', 'ID', 'MY', 'BN', 'SD', 'SO', 'DJ', 'MR', 'KM', 'XK', 'AL',
};

/// Ülkeye göre boşanma rejimi.
DivorceRegime regimeFor(Country c) {
  final code = c.code;
  if (code == 'TR') return _tr;
  if (_usCodes.contains(code)) return _us;
  if (_commonCodes.contains(code)) return _common;
  if (_nordicCodes.contains(code)) return _nordic;
  if (_franceCodes.contains(code)) return _france;
  if (_easternCodes.contains(code)) return _eastern;
  if (code == 'CN') return _china;
  if (_eaFaultCodes.contains(code)) return _eastAsiaFault;
  if (code == 'IN' || code == 'NP' || code == 'LK' || code == 'BT') return _india;
  if (_islamicCodes.contains(code)) return _islamic;
  if (code == 'ZA') return _southAfrica;
  switch (c.region) {
    case 'west':
      return _civil;
    case 'latam':
      return _latam;
    case 'africa':
      return _africa;
    case 'east_asia':
      return _seAsia;
    case 'mena':
      return code == 'IL' ? _civil : _islamic;
    case 'tr':
      return _eastern;
    default:
      return _default;
  }
}

/// Bir boşanmanın parasal sonucu (bin dolar). İşaret oyuncuya göredir:
/// [compensation] ve [support] artıysa oyuncu alır, eksiyse öder.
class DivorceTerms {
  DivorceTerms({
    required this.regime,
    required this.fault,
    required this.mode,
    this.splitPaid = 0,
    this.compensation = 0,
    this.support = 0,
    this.cost = 0,
    this.mahrPart = 0,
  });

  final DivorceRegime regime;
  final Fault fault;
  final DivorceMode mode;

  /// Mal paylaşımı: oyuncudan eşe giden miktar (artı = oyuncu kaybeder).
  final double splitPaid;

  /// Tazminat (maddi/manevi): artı = oyuncu alır, eksi = oyuncu öder.
  final double compensation;

  /// Nafaka / mehir: artı = oyuncu alır, eksi = oyuncu öder.
  final double support;

  /// Dava ve avukat masrafı (oyuncu öder).
  final double cost;

  /// [support] içindeki mehir kısmı (açıklama için).
  final double mahrPart;

  double get net => -splitPaid + compensation + support - cost;

  /// Oyuncunun cebinden çıkan tazminat + nafaka.
  double get paidOut => max(0, -compensation) + max(0, -support);

  /// Oyuncunun aldığı tazminat + nafaka.
  double get received => max(0, compensation) + max(0, support);
}

/// Boşanma şartlarını hesaplar. Saf fonksiyondur (rastgelelik yok).
///
/// Kurallar:
///  * Oyuncu **suçsuz** (eş kusurlu) ise hiçbir koşulda tazminat/nafaka **ödemez**;
///    ülke ne olursa olsun tazminat **alır**.
///  * Oyuncu **kusurlu** ise, kusurun hukuken önemli olduğu ülkelerde
///    ([DivorceRegime.faultLaw]) tazminat öder; kusursuz boşanma ülkelerinde
///    ek tazminat ödemez, olağan mal paylaşımı ve nafaka kuralları işler.
///  * Kusur yoksa ülkenin olağan senaryosu: mal paylaşımı + (gelir farkına göre)
///    nafaka, İslam hukukunda mehir.
///
/// [win] yalnızca çekişmeli boşanmada anlamlıdır: dava oyuncu lehine mi sonuçlandı?
/// `null` ise beklenen değer kullanılır (önizleme).
DivorceTerms computeDivorceTerms({
  required Character ch,
  required Person spouse,
  required Fault fault,
  required DivorceMode mode,
  required double playerIncome,
  required double spouseIncome,
  required bool byPartner,
  bool? win,
}) {
  final r = regimeFor(ch.country);
  final g = ch.country.gdp;
  final years = spouse.yearsMarried;
  final yf = (years / 15).clamp(0.2, 1.0).toDouble();
  final joint = max(0.0, ch.money);

  // Anlaşmalı / çekişmeli çarpanları.
  double damageFactor() {
    if (mode == DivorceMode.amicable) return 0.6;
    if (win == null) return 1.0;
    if (fault == Fault.partner) return win ? 1.35 : 0.7;
    return win ? 0.7 : 1.3;
  }

  // 1) Mal paylaşımı.
  double splitPaid;
  if (r.separate) {
    // Mallar ayrı: eş, evlilikte getirdiği varlığı geri alır.
    splitPaid = min(joint, max(0.0, spouse.wealth));
  } else {
    var sp = r.split * (0.55 + 0.45 * yf);
    if (r.faultLaw && fault == Fault.partner) sp *= 0.8;
    if (r.faultLaw && fault == Fault.player) sp *= 1.1;
    splitPaid = joint * sp;
  }

  // 2) Tazminat.
  final damagesBase = r.damages * g * (0.5 + 0.5 * yf);
  var comp = 0.0;
  if (fault == Fault.partner) {
    comp = damagesBase * damageFactor();
  } else if (fault == Fault.player && r.faultLaw) {
    comp = -damagesBase * damageFactor();
  }

  // 3) Nafaka / mehir.
  var support = 0.0;
  var mahrPart = 0.0;
  if (r.hasMahr) {
    final iddah = r.alimony * g * (0.5 + 0.5 * yf);
    final mahr = r.mahr * g;
    if (!ch.female) {
      // Koca oyuncu: kendisi kusurluysa da, kusursuzsa da mehir + iddet öder.
      // Eş kusurluysa (oyuncu suçsuz) hiçbir şey ödemez.
      if (fault != Fault.partner) {
        mahrPart = -mahr;
        support = -(mahr + iddah);
      }
    } else {
      // Kadın oyuncu: kusurluysa mehir hakkını yitirir; kendi isteğiyle (hul')
      // ayrılıyorsa mehrin yarısını alır.
      if (fault != Fault.player) {
        final m = (!byPartner && fault == Fault.none) ? mahr * 0.5 : mahr;
        mahrPart = m;
        support = m + iddah;
      }
    }
  } else {
    final hi = max(playerIncome, spouseIncome);
    final lo = min(playerIncome, spouseIncome);
    final gap = hi <= 0 ? 0.0 : (hi - lo) / hi;
    if (gap > 0.15) {
      final amount = r.alimony * g * yf * gap;
      final playerHigher = playerIncome >= spouseIncome;
      if (playerHigher) {
        // Suçsuz oyuncu ödemez.
        if (fault != Fault.partner) support = -amount;
      } else {
        // Oyuncu daha az kazanıyor: nafaka alır; kusurluysa ve ülke kusurlu eşe
        // nafaka vermiyorsa alamaz, vermese de kısılır.
        if (fault == Fault.player) {
          support = r.faultBarsAlimony ? 0 : amount * (r.faultLaw ? 0.5 : 1.0);
        } else {
          support = amount;
        }
      }
    }
  }
  if (mode == DivorceMode.amicable) support *= 0.85;

  // 4) Dava masrafı.
  var cost = g * 0.15 * (mode == DivorceMode.amicable ? 0.4 : 1.8);
  if (fault == Fault.partner && r.faultLaw) cost *= 0.3; // masrafı kusurlu eş yüklenir
  if (fault == Fault.player && r.faultLaw && mode == DivorceMode.contested) cost *= 1.2;

  // 5) Ödeme gücü: ödemeler oyuncunun gücünü aşmasın.
  final capacity = joint + g * 0.5;
  final room = max(g * 0.1, capacity - splitPaid - cost);
  final out = max(0.0, -comp) + max(0.0, -support);
  if (out > room && out > 0) {
    final k = room / out;
    if (comp < 0) comp *= k;
    if (support < 0) support *= k;
    mahrPart = mahrPart < 0 ? mahrPart * k : mahrPart;
  }

  return DivorceTerms(
    regime: r,
    fault: fault,
    mode: mode,
    splitPaid: splitPaid,
    compensation: comp,
    support: support,
    cost: cost,
    mahrPart: mahrPart,
  );
}

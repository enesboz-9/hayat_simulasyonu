import 'dart:math';

import 'models.dart';

/// Başarı değeri: bronz kolay, gümüş orta, altın nadir.
enum AchTier { bronze, silver, gold }

/// Başarılar ekranındaki gruplar.
enum AchCategory { life, wealth, love, career, world, fate }

(String, String, String) categoryLabel(AchCategory c) => switch (c) {
      AchCategory.life => ('⏳', 'Ömür ve sağlık', 'Lifespan & health'),
      AchCategory.wealth => ('💰', 'Para', 'Wealth'),
      AchCategory.love => ('💞', 'Aşk ve aile', 'Love & family'),
      AchCategory.career => ('💼', 'Kariyer ve eğitim', 'Career & education'),
      AchCategory.world => ('🌍', 'Dünya', 'World'),
      AchCategory.fate => ('🍀', 'Kader ve alışkanlıklar', 'Fate & habits'),
    };

typedef AchTest = bool Function(Character ch);

/// Tek bir başarı / rozet. [test], hayatın o anki durumuna bakar; motor her yıl
/// ve her karardan sonra çağırır. Hayat boyunca bir kez koşul sağlanması yeter.
class Achievement {
  Achievement({
    required this.id,
    required this.emoji,
    required this.tier,
    required this.category,
    required this.titleTr,
    required this.titleEn,
    required this.descTr,
    required this.descEn,
    required this.test,
    this.hidden = false,
  });

  final String id, emoji;
  final AchTier tier;
  final AchCategory category;
  final String titleTr, titleEn, descTr, descEn;
  final AchTest test;

  /// true ise açılana kadar adı ve açıklaması gizlenir (sürpriz başarı).
  final bool hidden;

  String title(String lang) => lang == 'tr' ? titleTr : titleEn;
  String desc(String lang) => lang == 'tr' ? descTr : descEn;
}

/// Bir başarının ilk açıldığı an (kalıcı olarak saklanır).
class Unlock {
  const Unlock({required this.age, required this.who, required this.flag, required this.at});

  /// Açıldığı yaş, o hayattaki isim ve doğum ülkesinin bayrağı.
  final int age;
  final String who, flag;

  /// ISO-8601 zaman damgası.
  final String at;

  Json toJson() => {'age': age, 'who': who, 'flag': flag, 'at': at};

  factory Unlock.fromJson(Json j) => Unlock(
        age: (j['age'] as num?)?.toInt() ?? 0,
        who: (j['who'] as String?) ?? '',
        flag: (j['flag'] as String?) ?? '',
        at: (j['at'] as String?) ?? '',
      );
}

/// Kalıcı saklama arayüzü. Motor yalnızca bunu bilir; gerçek uygulamada
/// shared_preferences ile, testte bellekte çalışır.
abstract class AchievementStorage {
  Future<String?> read();
  Future<void> write(String data);
}

class MemoryAchievementStorage implements AchievementStorage {
  String? _data;

  @override
  Future<String?> read() async => _data;

  @override
  Future<void> write(String data) async => _data = data;
}

Achievement _a(
  String id,
  String emoji,
  AchTier tier,
  AchCategory cat,
  String titleTr,
  String titleEn,
  String descTr,
  String descEn,
  AchTest test, {
  bool hidden = false,
}) =>
    Achievement(
      id: id,
      emoji: emoji,
      tier: tier,
      category: cat,
      titleTr: titleTr,
      titleEn: titleEn,
      descTr: descTr,
      descEn: descEn,
      test: test,
      hidden: hidden,
    );

const _bronze = AchTier.bronze, _silver = AchTier.silver, _gold = AchTier.gold;

/// Tüm başarılar. Yeni başarı eklemek için listeye bir `_a(...)` satırı yeter;
/// koşul, [Character] üzerindeki alanlara bakan küçük bir fonksiyondur.
final List<Achievement> kAchievements = [
  // ── Ömür ve sağlık ──
  _a('age_50', '🎂', _bronze, AchCategory.life, 'Yarım Asır', 'Half a Century',
      '50 yaşına ulaş.', 'Reach age 50.', (c) => c.age >= 50),
  _a('age_80', '🌳', _silver, AchCategory.life, 'Uzun Ömür', 'Long Life',
      '80 yaşına ulaş.', 'Reach age 80.', (c) => c.age >= 80),
  _a('age_100', '💯', _gold, AchCategory.life, 'Asırlık Çınar', 'Centenarian',
      '100 yaşına ulaş.', 'Reach age 100.', (c) => c.age >= 100),
  _a('age_110', '🏛️', _gold, AchCategory.life, 'Yaşayan Efsane', 'Living Legend',
      '110 yaşına ulaş.', 'Reach age 110.', (c) => c.age >= 110),
  _a('beat_odds', '🎯', _silver, AchCategory.life, 'İstatistiği Ezdin', 'Beat the Odds',
      'Doğduğun ülkenin ortalama ömrünü 20 yıl geçerek yaşa.',
      'Outlive your birth country\'s life expectancy by 20 years.',
      (c) => c.age - c.birthCountry.lifeExp >= 20),
  _a('near_death', '🩹', _bronze, AchCategory.life, 'Kıl Payı', 'Close Call',
      'Ölümden kıl payı kurtul.', 'Narrowly escape death.', (c) => c.nearDeaths >= 1),
  _a('nine_lives', '🐈', _silver, AchCategory.life, 'Dokuz Canlı', 'Nine Lives',
      'Bir hayatta 3 kez ölümden dön.', 'Escape death 3 times in one life.', (c) => c.nearDeaths >= 3),
  _a('iron_body', '🦾', _silver, AchCategory.life, 'Demir Gibi', 'Built Like Iron',
      '70 yaşında hâlâ sağlığın 80 üstünde olsun.', 'Be over 70 with health still above 80.',
      (c) => c.age >= 70 && c.health >= 80),
  _a('joy', '😄', _silver, AchCategory.life, 'Mutluluk Doruğu', 'Peak Happiness',
      'Mutluluğunu 92 üstüne çıkar.', 'Push your happiness above 92.', (c) => c.happiness >= 92),
  _a('smoker_80', '🚬', _silver, AchCategory.life, 'Çatlak Ciğer', 'Lungs of Steel',
      'Sigara içip 80 yaşına ulaş.', 'Smoke and still reach 80.',
      (c) => c.flags.contains('smoker') && c.age >= 80,
      hidden: true),

  // ── Para ──
  _a('millionaire', '💰', _silver, AchCategory.wealth, 'Milyoner', 'Millionaire',
      'Servetin bir noktada \$1M\'ı geçsin.', 'Reach a net worth of \$1M at some point.',
      (c) => c.peakMoney >= 1000),
  _a('multimillionaire', '🏦', _gold, AchCategory.wealth, 'On Milyonluk Servet', 'Ten-Million Fortune',
      'Servetin \$10M\'ı geçsin.', 'Reach a net worth of \$10M.', (c) => c.peakMoney >= 10000),
  _a('rags_to_riches', '🚀', _gold, AchCategory.wealth, 'Sıfırdan Zirveye', 'Rags to Riches',
      'Çok yoksul bir ülkede doğ ve milyoner ol.', 'Be born in a very poor country and become a millionaire.',
      (c) => c.birthCountry.gdp < 3 && c.peakMoney >= 1000),
  _a('homeowner', '🏠', _bronze, AchCategory.wealth, 'Ev Sahibi', 'Homeowner',
      'Kendi evini al.', 'Buy your own home.', (c) => c.flags.contains('owns_home')),
  _a('founder', '💼', _bronze, AchCategory.wealth, 'Patron', 'Founder',
      'Kendi işini kur.', 'Start your own business.',
      (c) => c.flags.contains('business_owner') || c.jobIds.contains('entrepreneur')),
  _a('scammed', '🪤', _bronze, AchCategory.wealth, 'Tuzağa Düştün', 'Fell for It',
      'Dolandırıl.', 'Get scammed.', (c) => c.flags.contains('scammed')),
  _a('scam_savvy', '🛡️', _bronze, AchCategory.wealth, 'Uyanık', 'Street Smart',
      'Dolandırıcılara karşı uyanık ol.', 'Become scam-savvy.', (c) => c.flags.contains('scam_savvy')),
  _a('in_debt', '💸', _bronze, AchCategory.wealth, 'Borç Batağı', 'Drowning in Debt',
      'Yıllık ortalama gelirin 2 katı borca gir.', 'Fall into debt worth 2x the average yearly income.',
      (c) => c.age >= 18 && c.money < -2 * c.country.gdp,
      hidden: true),

  // ── Aşk ve aile ──
  _a('married', '💍', _bronze, AchCategory.love, 'Yuvanı Kurdun', 'Tied the Knot',
      'Evlen.', 'Get married.', (c) => c.marriages >= 1),
  _a('big_family', '👨‍👩‍👧‍👦', _silver, AchCategory.love, 'Kalabalık Aile', 'Big Family',
      '3 çocuk sahibi ol.', 'Have 3 children.', (c) => c.children.length >= 3),
  _a('huge_family', '🏘️', _gold, AchCategory.love, 'Kocaman Aile', 'Huge Family',
      '5 çocuk sahibi ol.', 'Have 5 children.', (c) => c.children.length >= 5),
  _a('grandparent', '👶', _bronze, AchCategory.love, 'Dede / Nine', 'Grandparent',
      'Torun sahibi ol.', 'Become a grandparent.', (c) => c.flags.contains('grandkids')),
  _a('silver_anniv', '🥈', _silver, AchCategory.love, 'Gümüş Yıldönümü', 'Silver Anniversary',
      'Aynı kişiyle 25 yıl evli kal.', 'Stay married to the same person for 25 years.',
      (c) => (c.spouse?.yearsMarried ?? 0) >= 25),
  _a('golden_anniv', '🥇', _gold, AchCategory.love, 'Altın Yıldönümü', 'Golden Anniversary',
      'Aynı kişiyle 50 yıl evli kal.', 'Stay married to the same person for 50 years.',
      (c) => (c.spouse?.yearsMarried ?? 0) >= 50),
  _a('first_love', '❤️', _bronze, AchCategory.love, 'İlk Aşk', 'First Love',
      'Biriyle çıkmaya başla.', 'Start dating someone.', (c) => c.relationships >= 1),
  _a('living_together', '🏡', _bronze, AchCategory.love, 'Ortak Ev', 'Moving In',
      'Sevgilinle birlikte yaşamaya başla.', 'Move in with your partner.', (c) => c.cohabited >= 1),
  _a('heartbreak', '🥀', _silver, AchCategory.love, 'Kırık Kalpler', 'Heartbreaker',
      '3 kez sevgilinden ayrıl.', 'Break up 3 times.', (c) => c.breakups >= 3),
  _a('forever_unmarried', '🫶', _silver, AchCategory.love, 'Kâğıtsız Bağ', 'No Papers Needed',
      'Evlenmeden aynı kişiyle 15 yıl birlikte ol.', 'Stay with the same partner for 15 years without marrying.',
      (c) => c.spouse == null && (c.partner?.yearsTogether ?? 0) >= 15),
  _a('divorced', '💔', _bronze, AchCategory.love, 'Yollar Ayrıldı', 'Ways Parted',
      'Boşan.', 'Get divorced.', (c) => c.divorces >= 1),
  _a('alimony_win', '⚖️', _silver, AchCategory.love, 'Boşan ve Kazan', 'Divorce Dividend',
      'Boşanıp tazminat ya da nafaka kazan.', 'Divorce and come out with damages or alimony.',
      (c) => c.divorces >= 1 && c.compReceived > 0.05),
  _a('jackpot_divorce', '🤑', _gold, AchCategory.love, 'Boşanma Jackpotu', 'Divorce Jackpot',
      'Boşanmalardan toplam \$200k tazminat/nafaka al.', 'Receive \$200k in total damages/alimony from divorces.',
      (c) => c.compReceived >= 200),
  _a('serial_marrier', '💒', _silver, AchCategory.love, 'Üçüncü Kez', 'Third Time Lucky',
      '3 kez evlen.', 'Marry 3 times.', (c) => c.marriages >= 3),
  _a('forgiver', '🕊️', _bronze, AchCategory.love, 'Affedici', 'Forgiver',
      'Eşini affet.', 'Forgive your partner.', (c) => c.flags.contains('forgave')),
  _a('betrayed', '🗡️', _bronze, AchCategory.love, 'Güven Sarsıldı', 'Betrayed',
      'Eşin tarafından aldatıl.', 'Be cheated on by your partner.', (c) => c.cheatedOn >= 1),
  _a('secret_life', '🕶️', _bronze, AchCategory.love, 'Gizli Hayat', 'Double Life',
      'Evliyken gizli bir ilişki yaşa.', 'Have a secret affair while married.',
      (c) => c.affairs >= 1,
      hidden: true),
  _a('lifelong_single', '🧘', _bronze, AchCategory.love, 'Tek Başına Huzur', 'Happily Solo',
      'Hiç evlenmeden 70 yaşına ulaş.', 'Reach 70 without ever marrying.',
      (c) => c.age >= 70 && c.marriages == 0,
      hidden: true),

  // ── Kariyer ve eğitim ──
  _a('first_job', '🧑‍💼', _bronze, AchCategory.career, 'İlk Maaş', 'First Paycheck',
      'İlk işine gir.', 'Land your first job.', (c) => c.jobsHeld >= 1),
  _a('model', '📸', _gold, AchCategory.career, 'Podyumun Yıldızı', 'Runway Star',
      'Manken ol.', 'Become a model.', (c) => c.jobIds.contains('model')),
  _a('actor', '🎬', _gold, AchCategory.career, 'Beyazperde', 'Silver Screen',
      'Oyuncu ol.', 'Become an actor.', (c) => c.jobIds.contains('actor')),
  _a('top_of_ladder', '🪜', _silver, AchCategory.career, 'Zirveye Tırmandın', 'Top of the Ladder',
      'Mesleğinde en üst seviyeye (5) yüksel.', 'Reach the top level (5) in a job.',
      (c) => c.bestJobLevel >= 5),
  _a('job_hopper', '🧳', _silver, AchCategory.career, 'Kariyer Gezgini', 'Job Hopper',
      'Hayatında 6 farklı işte çalış.', 'Hold 6 jobs in one life.', (c) => c.jobsHeld >= 6),
  _a('many_hats', '🎩', _gold, AchCategory.career, 'Çok Yönlü', 'Jack of All Trades',
      '8 farklı meslekte çalış.', 'Work in 8 different professions.', (c) => c.jobIds.length >= 8),
  _a('doctor', '🩺', _silver, AchCategory.career, 'Beyaz Önlük', 'White Coat',
      'Doktor ol.', 'Become a doctor.', (c) => c.jobIds.contains('doctor')),
  _a('pilot', '🛩️', _silver, AchCategory.career, 'Kaptan', 'Captain',
      'Pilot ol.', 'Become a pilot.', (c) => c.jobIds.contains('pilot')),
  _a('pro_athlete', '🏅', _silver, AchCategory.career, 'Profesyonel Sporcu', 'Pro Athlete',
      'Profesyonel sporcu ol.', 'Become a professional athlete.', (c) => c.jobIds.contains('pro_athlete')),
  _a('influencer', '📱', _silver, AchCategory.career, 'Fenomen', 'Influencer',
      'İçerik üreticisi ol.', 'Become a content creator.', (c) => c.jobIds.contains('content_creator')),
  _a('persistent', '🔁', _bronze, AchCategory.career, 'Pes Etmedi', 'Never Give Up',
      '5 mülakatta elen ve yine de devam et.', 'Fail 5 interviews and keep going.',
      (c) => c.interviewsFailed >= 5),
  _a('retired', '🏖️', _bronze, AchCategory.career, 'Hak Edilmiş Dinlenme', 'Well-Earned Rest',
      'Emekli ol.', 'Retire.', (c) => c.retired),
  _a('graduate', '🎓', _bronze, AchCategory.career, 'Mezun', 'Graduate',
      'Üniversiteden mezun ol.', 'Graduate from university.', (c) => c.edu >= 3),
  _a('postgrad', '🧪', _silver, AchCategory.career, 'Akademisyen', 'Academic',
      'Yüksek lisans yap.', 'Earn a postgraduate degree.', (c) => c.edu >= 4),
  _a('genius', '🧠', _silver, AchCategory.career, 'Dâhi', 'Genius',
      'Zekânı 90 üstüne çıkar.', 'Raise your smarts above 90.', (c) => c.smarts >= 90),
  _a('scholar', '🏫', _bronze, AchCategory.career, 'Burslu', 'Scholar',
      'Burs kazan.', 'Win a scholarship.', (c) => c.flags.contains('scholarship')),
  _a('against_odds', '📖', _gold, AchCategory.career, 'Fırsat Eşitsizliğini Yendin', 'Against All Odds',
      'Eğitim erişimi zayıf bir ülkede doğup üniversiteden mezun ol.',
      'Be born where schooling is scarce and still graduate from university.',
      (c) => c.birthCountry.edu < 0.6 && c.edu >= 3),

  // ── Dünya ──
  _a('expat', '🛫', _bronze, AchCategory.world, 'Yurt Dışına Taşındın', 'Moved Abroad',
      'Başka bir ülkeye taşın.', 'Move to another country.', (c) => c.livedIn.length >= 2),
  _a('three_countries', '🌍', _silver, AchCategory.world, '3 Ülke', 'Three Countries',
      '3 farklı ülkede yaşa.', 'Live in 3 different countries.', (c) => c.livedIn.length >= 3),
  _a('five_countries', '🌐', _gold, AchCategory.world, 'Dünya Vatandaşı', 'Citizen of the World',
      '5 farklı ülkede yaşa.', 'Live in 5 different countries.', (c) => c.livedIn.length >= 5),
  _a('immigrant_dream', '🗽', _silver, AchCategory.world, 'Göç Hikâyesi', 'Immigrant Story',
      'Yoksul bir ülkede doğup çok zengin bir ülkeye yerleş.',
      'Be born in a poor country and settle in a very wealthy one.',
      (c) => c.birthCountry.gdp < 5 && c.country.gdp >= 30 && c.livedIn.length >= 2),

  // ── Kader ve alışkanlıklar ──
  _a('athlete', '🏃', _bronze, AchCategory.fate, 'Spor Hayatı', 'Active Life',
      'Düzenli spor yapmaya başla.', 'Take up regular exercise.', (c) => c.flags.contains('athlete')),
  _a('quit_smoking', '🫁', _bronze, AchCategory.fate, 'Nefes Aldın', 'Breathe Easy',
      'Sigarayı bırak.', 'Quit smoking.', (c) => c.flags.contains('ex_smoker')),
  _a('volunteer', '🤝', _bronze, AchCategory.fate, 'Gönüllü', 'Volunteer',
      'Gönüllü çalış.', 'Volunteer.', (c) => c.flags.contains('volunteer')),
  _a('pet_lover', '🐾', _bronze, AchCategory.fate, 'Dört Ayaklı Dost', 'Pet Lover',
      'Bir evcil hayvan edin.', 'Get a pet.', (c) => c.flags.contains('has_pet')),
  _a('lucky', '🍀', _bronze, AchCategory.fate, 'Kader Seni Sevdi', 'Fortune\'s Favourite',
      'Gizli şans değerin 85 üstünde olsun.', 'Have a hidden luck value above 85.',
      (c) => c.luck >= 85,
      hidden: true),
  _a('unlucky', '☔', _bronze, AchCategory.fate, 'Kara Bulut', 'Dark Cloud',
      'Gizli şans değerin 15 altında olsun.', 'Have a hidden luck value below 15.',
      (c) => c.luck <= 15,
      hidden: true),
  _a('perfect_life', '🌟', _gold, AchCategory.fate, 'Mükemmel Hayat', 'A Perfect Life',
      '80 yaşından sonra, mutlu, varlıklı, çocuklu ve üniversite mezunu bir hayatı tamamla.',
      'Finish a life past 80 that was happy, wealthy, with children and a degree.',
      (c) =>
          !c.alive &&
          c.age >= 80 &&
          c.happiness >= 70 &&
          c.peakMoney >= max(500, 4 * c.country.gdp) &&
          c.children.isNotEmpty &&
          c.edu >= 3,
      hidden: true),
];

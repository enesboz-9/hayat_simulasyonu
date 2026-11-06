# Hayat Simülasyonu

Rastgele bir ülkede doğ, seçimlerinle ve şansınla bir hayat yaşa. Flutter, harici paket yok.

## Kurulum

```bash
cd hayat_simulasyonu
flutter create .          # android/ios klasörlerini üretir (lib ve pubspec'e dokunmaz)
flutter pub get
flutter run
flutter test              # 800 hayatı simüle eder, ülke bazında ortalama ölüm yaşını yazar
```

## Nasıl çalışır

- **Doğum:** Ülke, gerçek yıllık doğum sayısıyla orantılı seçilir (`countries.json` → `births`, milyon). Yani bir ülkede doğma ihtimali = ülkenin doğum sayısı / dünya doğum sayısı (Hindistan ≈ %17). `births` = 2022 nüfusu × ham doğum hızı (Dünya Bankası WDI, UN WPP tabanlı); toplam ≈ 136 milyon. Kişi başı gelir (`gdp`) 2022 nominal GSYİH / nüfus. Tayvan ve Dünya Bankası’nda bulunmayan birkaç ülke elle tahminidir; yaşam beklentisi, doğurganlık ve boşanma değerleri hâlâ yaklaşık değerlerdir.
- **Ölüm:** Ülkenin yaşam beklentisine dayalı bir eğri; sağlık, gizli şans ve yaşam tarzıyla (sigara, spor) çarpılır. Ölüm sırasında şansa bağlı "kıl payı kurtulma" ihtimali vardır. Yani ortalama istatistiktir, sonuç değil.
- **Seçimler:** Evlilik adayları, çocuk, iş teklifleri, boşanma (`engine.dart`) ve JSON'daki karar olayları.
- **Evlilik adayları:** Rastgele üretilir (çekicilik, zekâ, karakter, meslek, **gelir ve varlık**). Eşin varlığı (borçluysa borcu) evlilikle senin varlığına karışır; teklifin kabul edilme ihtimalini de etkiler. Gizli bir özellik (sadık, aldatan, savurgan...) birkaç yıl sonra ortaya çıkar.
- **Boşanma:** Yıllık kriz ihtimali `countries.json` → `divorce` (yaklaşık % / evli çift / yıl) değerinden başlar; evlilik süresi, evlenme yaşı, çocuk, para durumu, eğitim, gizli ilişki ve ilişki gücüyle çarpılır (`divorceChance`). Krizde boşan / terapi / görmezden gel seçenekleri çıkar. Değerler oyun için yaklaşık rakamlardır, resmi istatistik değildir.
- **Aldatma:** Evliyken gizli ilişki fırsatı çıkabilir; ilişki yıllar içinde ortaya çıkma riski taşır. Eşin de seni aldatabilir (`cheater` karakterinde çok daha sık). Her iki durumda affet / boşan / terapi / inkâr gibi seçimler çıkar.
- **Mülakat:** Kabul ihtimali `_hireChance` ile hesaplanır ve seçenekte yüzde olarak görünür. Zekâ, şans, sosyallik, eğitim fazlalığı, deneyim ve uzun işsizlik ihtimali artırır.
- **Sonuç görseli:** Hayat bitince özet ekranındaki kart PNG olarak galeriye kaydedilir ya da paylaşılır (`result_image.dart`).
- **Olaylar:** `assets/data/events.json`. Kod değiştirmeden yeni olay eklenir.

## Görsel kaydetme için platform ayarı

`flutter create .` sonrası bir kez yapılır:

- **iOS** → `ios/Runner/Info.plist` içine ekle:
  `<key>NSPhotoLibraryAddUsageDescription</key><string>Hayat özetini galeriye kaydetmek için</string>`
- **Android** → `android/app/build.gradle` içinde `minSdkVersion 21` (veya üstü) olmalı;
  `AndroidManifest.xml` içine
  `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>`
- Web'de galeriye kaydetme desteklenmez.

## Yeni olay eklemek

`events.json` içindeki bir olay:

```json
{
  "id": "gym", "minAge": 18, "maxAge": 60, "weight": 0.8, "cooldown": 8,
  "cond": {"flagsNone": ["athlete"]},
  "text": {"tr": "...", "en": "..."},
  "choices": [
    {"text": {"tr": "Üye ol", "en": "Join"},
     "effects": {"health": 6, "money": -0.1}, "setFlags": ["athlete"],
     "result": {"tr": "...", "en": "..."}}
  ]
}
```

- `choices` yoksa olay otomatiktir; `effects` ve `text` doğrudan olaya yazılır.
- Bir seçimde birden fazla sonuç için `outcomes: [{w, lucky, check, effects, result, death}]` kullan.
  `lucky: true` sonucun ağırlığını oyuncunun şansıyla, `check: "smarts"` ilgili istatistikle çarpar.
- `money` etkisi, ülkenin kişi başı gelirinin katıdır (0.5 = yarım yıllık ortalama gelir).
- `tone: "good" | "bad"`: şans yüksekse iyi olaylar, düşükse kötü olaylar daha sık çıkar.
- `riskScale: true`: ülke riski yüksekse daha sık çıkar. `force: true`: koşul sağlanınca önce bu çıkar.
- Koşullar (`cond`): `minAge`-`maxAge` (olay seviyesinde), `female`, `country`, `region`, `minHealth`/`maxHealth`,
  `minMoney`/`maxMoney`, `minEdu`/`maxEdu`, `married`, `hasJob`, `hasKids`, `retired`, `flagsAll`, `flagsNone`, `minRisk`.
- Metinlerde `{spouse}`, `{child}`, `{job}`, `{country}`, `{name}` kullanılabilir.
- Özel etkiler: `emigrate` ("rich"/"any"), `quitJob`, `retire`, `startUni`, `kids`, `bond`, `loseSpouse`.

## Veriyi büyütmek

`countries.json` şu an 196 ülke içeriyor (193 BM üyesi + Filistin, Tayvan, Kosova). Doğum sayıları yaklaşık değerlerdir; daha doğru oran için BM WPP verisiyle `births` değerlerini güncelle. BM WPP / World Bank verisiyle ülke sayısını artırdıkça oranlar gerçeğe yaklaşır.

## Bilinen eksikler / sonraki adımlar

- Kod henüz bir Flutter derleyicisinde çalıştırılmadı; ilk `flutter pub get` / `flutter run` / `flutter test` çıktısına göre küçük düzeltmeler gerekebilir (özellikle `gal` ve `share_plus` sürümleri).
- Kayıt sistemi yok (Hive / shared_preferences eklenebilir).
- Üniversite sınavı başarısız olursa yeniden deneme olayı yok.
- Eş seçimi şimdilik karşı cinse göre; yönelim ayarı eklenebilir.
- Log metinleri üretildiği dilde saklanır; oyun içinde dil değişince eski satırlar çevrilmez.

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

- **Doğum:** Ülke, yıllık doğum sayısına göre ağırlıklı seçilir (`countries.json` → `births`).
- **Ölüm:** Ülkenin yaşam beklentisine dayalı bir eğri; sağlık, gizli şans ve yaşam tarzıyla (sigara, spor) çarpılır. Ölüm sırasında şansa bağlı "kıl payı kurtulma" ihtimali vardır. Yani ortalama istatistiktir, sonuç değil.
- **Seçimler:** Evlilik adayları, çocuk, iş teklifleri, boşanma (`engine.dart`) ve JSON'daki karar olayları.
- **Evlilik adayları:** Rastgele üretilir (çekicilik, zekâ, karakter, meslek). Gizli bir özellik (sadık, aldatan, savurgan...) birkaç yıl sonra ortaya çıkar.
- **Olaylar:** `assets/data/events.json` ve `events_more.json` (dosya listesi `GameEngine.eventFiles`). Kod değiştirmeden yeni olay eklenir.
- **Seçim sıklığı:** Her yıl ~%62 olasılıkla bir seçim gelir; ~%22 ihtimalle aynı yıl ikinci bir seçim sıraya girer. Aynı `cat` (alan) art arda gelmesin diye son 3 alan ağırlıkça kısılır.
- **Aile:** Doğumda anne, baba ve ülkenin doğurganlığına göre kardeşler üretilir; yaşlanır, ölürler. Çocuklar büyüyünce torun sahibi olursun. Üst paneldeki medeni durum, çocuk ve **Aile** çipi (dokununca aile ekranı) bu verileri gösterir.

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
- `cat`: seçim alanı (`school`, `career`, `family`, `kids`, `love`, `health`, `money`, `social`, `crime`, `travel`, `hobby`, `home`, `tech`, `politics`, `values`, `pet`, `life`). Karar kartında ikon olarak görünür; `title` ({tr,en}) kartın başlığıdır.
- Koşullar (`cond`): `minAge`-`maxAge` (olay seviyesinde), `female`, `country`, `region`, `minHealth`/`maxHealth`,
  `minMoney`/`maxMoney`, `minEdu`/`maxEdu`, `married`, `hasJob`, `hasKids`, `retired`, `flagsAll`, `flagsNone`, `minRisk`,
  `student`, `status` (`["single","married","divorced","widowed"]`), `minKids`/`maxKids`, `kidAge` (`[min,max]`: bu yaşta çocuğun var),
  `parentAlive`/`motherAlive`/`fatherAlive`, `hasSiblings`, `hasGrandkids`, `minJobLevel`.
- Metinlerde `{spouse}`, `{child}`, `{job}`, `{country}`, `{name}`, `{mother}`, `{father}`, `{parent}`, `{sibling}` kullanılabilir.
- Özel etkiler: `emigrate` ("rich"/"any"), `quitJob`, `retire`, `startUni`, `kids`, `bond`, `loseSpouse`,
  `marry` (yeni bir eş üretip evlendirir), `divorce`, `loseParent` ("any"/"mother"/"father"), `promote` (terfi seviyesi), `setJob` (iş id'si).

## Veriyi büyütmek

`countries.json` şu an 28 ülke içeriyor, bu yüzden gerçek dünya yüzdelerinden biraz sapar (Hindistan yüzdesi
yüksek çıkar). BM WPP / World Bank verisiyle ülke sayısını artırdıkça oranlar gerçeğe yaklaşır.

## Bilinen eksikler / sonraki adımlar

- Kod henüz bir Flutter derleyicisinde çalıştırılmadı; ilk `flutter run`/`flutter test` çıktısına göre küçük düzeltmeler gerekebilir.
- Kayıt sistemi yok (Hive / shared_preferences eklenebilir).
- Üniversite sınavı başarısız olursa yeniden deneme olayı yok.
- Eş seçimi şimdilik karşı cinse göre; yönelim ayarı eklenebilir.
- Log metinleri üretildiği dilde saklanır; oyun içinde dil değişince eski satırlar çevrilmez.

import 'package:shared_preferences/shared_preferences.dart';

import 'achievements.dart';

/// Başarıları cihazda (shared_preferences) saklar. Web'de localStorage kullanır.
class PrefsAchievementStorage implements AchievementStorage {
  static const _key = 'achievements_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async {
    await (await SharedPreferences.getInstance()).setString(_key, data);
  }
}

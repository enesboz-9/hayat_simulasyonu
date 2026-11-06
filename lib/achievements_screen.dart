import 'package:flutter/material.dart';

import 'achievements.dart';
import 'engine.dart';

Color tierColor(AchTier t) => switch (t) {
      AchTier.bronze => const Color(0xFFCD7F32),
      AchTier.silver => const Color(0xFFB8C4CC),
      AchTier.gold => const Color(0xFFFFC107),
    };

String tierName(AchTier t, String Function(String, String) b) => switch (t) {
      AchTier.bronze => b('Bronz', 'Bronze'),
      AchTier.silver => b('Gümüş', 'Silver'),
      AchTier.gold => b('Altın', 'Gold'),
    };

/// Yuvarlak rozet: kilitliyse gri ve soluk, açıksa değer rengiyle çerçeveli.
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({super.key, required this.a, required this.unlocked, this.size = 48});
  final Achievement a;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? tierColor(a.tier) : Colors.grey;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(unlocked ? 0.18 : 0.10),
        border: Border.all(color: color.withOpacity(unlocked ? 0.9 : 0.4), width: 2),
      ),
      child: Opacity(
        opacity: unlocked ? 1 : 0.35,
        child: Text(
          unlocked || !a.hidden ? a.emoji : '❓',
          style: TextStyle(fontSize: size * 0.48),
        ),
      ),
    );
  }
}

// ───────────────────────── Başarılar ekranı ─────────────────────────

/// Tüm başarılar: kategorilere göre, açık olanlar renkli, kilitliler soluk.
/// Gizli başarıların adı ve koşulu açılana kadar "???" görünür.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.engine});
  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final b = engine.b;
        final total = engine.achievementTotal;
        final got = engine.unlockedCount;
        final cur = engine.c;

        int count(AchTier t) => kAchievements.where((a) => a.tier == t && engine.unlocked.containsKey(a.id)).length;
        int all(AchTier t) => kAchievements.where((a) => a.tier == t).length;

        return Scaffold(
          appBar: AppBar(title: Text(b('Başarılar', 'Achievements'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🏆 $got / $total',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: total == 0 ? 0 : got / total,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          for (final t in AchTier.values)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 12, color: tierColor(t)),
                                const SizedBox(width: 4),
                                Text('${tierName(t, b)} ${count(t)}/${all(t)}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                        ],
                      ),
                      if (engine.livesStarted > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          b('${engine.livesStarted} hayat yaşandı', '${engine.livesStarted} lives lived'),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              for (final cat in AchCategory.values) ...[
                _CategoryHeader(engine: engine, cat: cat),
                for (final a in kAchievements.where((x) => x.category == cat))
                  _AchievementTile(
                    engine: engine,
                    a: a,
                    // Şu an oynanan hayatta kazanıldıysa küçük bir işaret göster.
                    thisLife: cur != null && cur.earned.contains(a.id),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.engine, required this.cat});
  final GameEngine engine;
  final AchCategory cat;

  @override
  Widget build(BuildContext context) {
    final l = categoryLabel(cat);
    final list = kAchievements.where((x) => x.category == cat);
    final got = list.where((x) => engine.unlocked.containsKey(x.id)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Row(
        children: [
          Text('${l.$1} ${engine.b(l.$2, l.$3)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          Text('$got/${list.length}', style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.engine, required this.a, required this.thisLife});
  final GameEngine engine;
  final Achievement a;
  final bool thisLife;

  @override
  Widget build(BuildContext context) {
    final b = engine.b;
    final u = engine.unlocked[a.id];
    final open = u != null;
    final secret = a.hidden && !open;
    final title = secret ? '???' : a.title(engine.lang);
    final desc = secret ? b('Gizli başarı: keşfetmen gerek.', 'Hidden achievement: you have to discover it.') : a.desc(engine.lang);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: BadgeIcon(a: a, unlocked: open),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: open ? null : Colors.grey),
        ),
        subtitle: Text(desc),
        trailing: open
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thisLife) const Icon(Icons.check_circle, size: 18, color: Colors.greenAccent),
                  Text('${u.flag} ${u.age}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              )
            : Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade600),
      ),
    );
  }
}

// ───────────────────────── Oyun içi "başarı açıldı" bandı ─────────────────────────

/// Yeni açılan başarıları ekranın üstünde kısa süre gösteren bant.
class UnlockBanner extends StatelessWidget {
  const UnlockBanner({super.key, required this.engine, required this.items, required this.onTap});
  final GameEngine engine;
  final List<Achievement> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = engine.b;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in items)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Material(
              elevation: 6,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: tierColor(a.tier), width: 5)),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      BadgeIcon(a: a, unlocked: true, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🏆 ${b('Başarı açıldı', 'Achievement unlocked')} · ${tierName(a.tier, b)}',
                              style: TextStyle(fontSize: 11, color: tierColor(a.tier), fontWeight: FontWeight.bold),
                            ),
                            Text(a.title(engine.lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(a.desc(engine.lang), style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

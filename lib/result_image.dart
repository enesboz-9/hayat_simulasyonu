import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'engine.dart';
import 'models.dart';

/// [key] ile işaretlenmiş RepaintBoundary'yi PNG baytlarına çevirir.
Future<Uint8List?> captureCard(GlobalKey key, {double pixelRatio = 3}) async {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final boundary = ctx.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// PNG'yi galeriye kaydeder. İzin verilmezse ya da platform desteklemiyorsa
/// bir istisna fırlatır.
Future<void> saveToGallery(Uint8List png) async {
  if (kIsWeb) throw UnsupportedError('web');
  if (!await Gal.hasAccess()) {
    if (!await Gal.requestAccess()) throw StateError('no-permission');
  }
  await Gal.putImageBytes(png);
}

/// Sistem paylaşım menüsünü açar (oradan "Resimlere kaydet" de seçilebilir).
Future<void> shareImage(Uint8List png, String text) async {
  if (kIsWeb) throw UnsupportedError('web');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/hayat_ozeti.png');
  await file.writeAsBytes(png);
  await Share.shareXFiles([XFile(file.path)], text: text);
}

/// Hayat sonunda görsel olarak kaydedilen sonuç kartı. Tema bağımsızdır:
/// renkler sabit, bu yüzden her cihazda aynı görüntü çıkar.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.engine});
  final GameEngine engine;

  static const _ink = Color(0xFFF4F7F6);
  static const _muted = Color(0xFF9FB3AE);

  List<LogEntry> _highlights(Character ch) {
    final all = ch.log.where((e) => e.kind != 'choice' && e.kind != 'info').toList();
    if (all.length <= 7) return all;
    final out = <LogEntry>[all.first];
    final step = (all.length - 2) / 5;
    for (var i = 1; i <= 5; i++) {
      out.add(all[(i * step).round()]);
    }
    out.add(all.last);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ch = engine.c!;
    final b = engine.b;
    final cn = loc(ch.birthCountry.name, engine.lang);
    final diff = (ch.age - ch.birthCountry.lifeExp).round();
    final cmp = diff >= 0
        ? b('$cn ortalamasından $diff yıl fazla', '$diff years above the $cn average')
        : b('$cn ortalamasından ${-diff} yıl az', '${-diff} years below the $cn average');

    Widget pill(String emoji, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$emoji $text', style: const TextStyle(color: _ink, fontSize: 12)),
        );

    Widget bar(String label, double v, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text(label, style: const TextStyle(color: _muted, fontSize: 11))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v / 100,
                    minHeight: 6,
                    color: color,
                    backgroundColor: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      width: 340,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2A2A), Color(0xFF12161F)],
        ),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: _ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              b('HAYAT SİMÜLASYONU', 'LIFE SIMULATOR'),
              style: const TextStyle(color: _muted, fontSize: 11, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(ch.birthCountry.flag, style: const TextStyle(fontSize: 44)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ch.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(
                        b('${ch.age} yaşında öldü · ${ch.cause ?? '-'}', 'Died at ${ch.age} · ${ch.cause ?? '-'}'),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(cmp, style: const TextStyle(color: Color(0xFF7FE0CF), fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                pill('🌍', cn),
                if (ch.country.code != ch.birthCountry.code)
                  pill('✈️', loc(ch.country.name, engine.lang)),
                pill('🎓', engine.eduName(ch.edu)),
                pill('💰', fmtMoney(ch.money)),
                if (ch.marriages > 0) pill('💍', b('${ch.marriages} evlilik', '${ch.marriages} marriage(s)')),
                if (ch.divorces > 0) pill('💔', b('${ch.divorces} boşanma', '${ch.divorces} divorce(s)')),
                if (ch.cheatedOn > 0) pill('😔', b('${ch.cheatedOn} kez aldatıldı', 'cheated on ${ch.cheatedOn}x')),
                if (ch.affairs > 0) pill('🤫', b('${ch.affairs} gizli ilişki', '${ch.affairs} affair(s)')),
                if (ch.children.isNotEmpty) pill('👶', b('${ch.children.length} çocuk', '${ch.children.length} child(ren)')),
                pill('💼', b('${ch.jobsHeld} iş', '${ch.jobsHeld} job(s)')),
              ],
            ),
            const SizedBox(height: 14),
            bar(b('Sağlık', 'Health'), ch.health, Colors.redAccent),
            bar(b('Mutluluk', 'Happiness'), ch.happiness, Colors.amber),
            bar(b('Zekâ', 'Smarts'), ch.smarts, Colors.lightBlue),
            bar(b('Çekicilik', 'Looks'), ch.looks, Colors.pinkAccent),
            bar(b('Sosyal', 'Social'), ch.social, Colors.green),
            const SizedBox(height: 14),
            Text(b('Hayat çizgisi', 'Life timeline'), style: const TextStyle(color: _muted, fontSize: 11, letterSpacing: 1)),
            const SizedBox(height: 6),
            for (final e in _highlights(ch))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('${e.age}', style: const TextStyle(color: Color(0xFF7FE0CF), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

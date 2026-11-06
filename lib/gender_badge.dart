import 'package:flutter/material.dart';

/// Oyuncunun cinsiyetini ♂ / ♀ simgesiyle gösteren yuvarlak rozet.
/// Tema bağımsız sabit renkler kullanır; sonuç kartında da aynı görünür.
class GenderBadge extends StatelessWidget {
  const GenderBadge({super.key, required this.female, this.size = 28});

  final bool female;
  final double size;

  static const _maleColor = Color(0xFF3D8BFD);
  static const _femaleColor = Color(0xFFEC4899);

  @override
  Widget build(BuildContext context) {
    final color = female ? _femaleColor : _maleColor;
    return Tooltip(
      message: female ? 'Kadın / Female' : 'Erkek / Male',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.18),
          border: Border.all(color: color, width: 1.6),
        ),
        alignment: Alignment.center,
        child: Icon(female ? Icons.female : Icons.male, color: color, size: size * 0.7),
      ),
    );
  }
}

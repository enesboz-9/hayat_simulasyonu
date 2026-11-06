import 'package:flutter/material.dart';

import 'achievements_storage.dart';
import 'engine.dart';
import 'screens.dart';

void main() => runApp(const LifeApp());

class LifeApp extends StatefulWidget {
  const LifeApp({super.key});

  @override
  State<LifeApp> createState() => _LifeAppState();
}

class _LifeAppState extends State<LifeApp> {
  final engine = GameEngine(storage: PrefsAchievementStorage());

  @override
  void initState() {
    super.initState();
    engine.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Life Simulator',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(engine: engine),
    );
  }
}

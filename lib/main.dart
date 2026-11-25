import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() => runApp(const CcRemoteApp());

class CcRemoteApp extends StatelessWidget {
  const CcRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'CC Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';

import '../auth_gate.dart';
import '../widgets/hive_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Wait 1.5 seconds, then go to AuthGate
    Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HiveBackground(
        child: Center(
          child: SizedBox(
            height: 450,
            width: 450,
            child: Image.asset(
              'assets/images/logo.png',  // <-- TRANSPARENT VERSION
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

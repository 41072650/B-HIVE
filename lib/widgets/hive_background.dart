// lib/widgets/hive_background.dart
import 'package:flutter/material.dart';

class HiveBackground extends StatelessWidget {
  final Widget child;
  const HiveBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 👇 This line forces it to fill the whole available area
      constraints: const BoxConstraints.expand(),

      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/hexBG.jpg'),
          fit: BoxFit.cover,

          // 🎯 Tuned to match dark premium panels
          colorFilter: ColorFilter.mode(
            Color(0xCC0F1115), // deep charcoal (matches panel surfaces)
            BlendMode.multiply,
          ),
        ),
      ),
      child: child,
    );
  }
}

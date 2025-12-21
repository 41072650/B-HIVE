// lib/main.dart
import 'package:flutter/material.dart';
import 'supabase_client.dart';

import 'screens/splash_screen.dart';
import 'screens/post_job_screen.dart'; // 👈 NEW

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ConnectHiveApp());
}

class ConnectHiveApp extends StatelessWidget {
  const ConnectHiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color.fromARGB(255, 241, 178, 70);

    return MaterialApp(
      title: 'B-Hive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false, // keep M2 for nicer AppBar styling

        // ✅ makes screens look cleaner without touching other files
        canvasColor: const Color(0xFF0F1115),

        // ✅ same idea, just slightly refined for nicer dark surfaces
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          primary: seed,
          surface: const Color(0xFF141823),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            shadows: [
              Shadow(
                blurRadius: 6,
                color: Colors.black87,
                offset: Offset(1, 2),
              ),
            ],
          ),
        ),
      ),

      // ⬇️ Always show splash first, then it will push AuthGate
      home: const SplashScreen(),

      // ⬇️ NEW: route for posting a job
      routes: {
        '/post-job': (context) {
          final companyId = ModalRoute.of(context)!.settings.arguments as String;
          return PostJobScreen(companyId: companyId);
        },
      },
    );
  }
}

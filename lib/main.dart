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
    return MaterialApp(
      title: 'B-Hive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false, // keep M2 for nicer AppBar styling

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 241, 178, 70),
          brightness: Brightness.dark,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            shadows: [
              Shadow(
                blurRadius: 4,
                color: Colors.black87,
                offset: Offset(1, 1),
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
          final companyId =
              ModalRoute.of(context)!.settings.arguments as String;
          return PostJobScreen(companyId: companyId);
        },
      },
    );
  }
}

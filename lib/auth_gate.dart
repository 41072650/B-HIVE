// lib/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';
import 'screens/auth_screen.dart';
import 'screens/landing_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _guestMode = false;

  @override
  Widget build(BuildContext context) {
    // If user chose guest mode, bypass auth and show LandingScreen in guest mode
    if (_guestMode) {
      return const LandingScreen(isGuest: true);
    }

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? supabase.auth.currentSession;

        if (session == null) {
          // Not logged in -> show auth screen, with guest callback
          return AuthScreen(
            onContinueAsGuest: () {
              setState(() {
                _guestMode = true;
              });
            },
          );
        }

        // Logged in -> show main app
        return const LandingScreen();
      },
    );
  }
}

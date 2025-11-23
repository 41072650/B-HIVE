// lib/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // <-- brings in AuthState
import 'supabase_client.dart';

import 'screens/landing_screen.dart';
import 'screens/auth_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // current session (from stream, or existing if stream not emitted yet)
        final session = snapshot.data?.session ?? supabase.auth.currentSession;

        if (session == null) {
          // Not logged in -> show auth screen
          return const AuthScreen();
        }

        // Logged in -> show main app
        return const LandingScreen();
      },
    );
  }
}

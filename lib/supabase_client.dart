// lib/supabase_client.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Replace these with your own from Supabase Settings → API
const supabaseUrl = 'https://mvzrjajivsabkwcucish.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12enJqYWppdnNhYmt3Y3VjaXNoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM3MjYxOTQsImV4cCI6MjA3OTMwMjE5NH0.tzw_5eZ0TL06F5eHPISEJII_GwLYQYWTrhX-wog8YQE';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
}

final supabase = Supabase.instance.client;

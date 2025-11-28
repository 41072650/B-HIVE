// lib/services/event_tracker.dart
import 'package:flutter/foundation.dart';
import '../supabase_client.dart';

class EventTracker {
  static Future<void> trackCompanyEvent({
    required String companyId,
    required String eventType,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;

      await supabase.from('company_events').insert({
        'company_id': companyId,
        'user_id': userId,
        'event_type': eventType,
        'meta': meta ?? {},
      });
    } catch (e) {
      // Don't crash the app if tracking fails; just log it
      debugPrint('Error tracking $eventType for company $companyId: $e');
    }
  }
}

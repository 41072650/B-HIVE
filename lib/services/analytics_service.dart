// lib/services/analytics_service.dart
import '../supabase_client.dart';

class AnalyticsService {
  /// action: 'view', 'call', or 'directions'
  static Future<void> trackCompanyAction(String companyId, String action) async {
    try {
      await supabase.rpc(
        'increment_company_stat',
        params: {
          'p_company_id': companyId,
          'p_action': action,
        },
      );
    } catch (e) {
      // You can log this if you want, but don't block the UI on it
      // debugPrint('Failed to track action: $e');
    }
  }
}

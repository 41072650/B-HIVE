// lib/screens/admin_claims_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';
import '../widgets/bhive_inputs.dart';

class AdminClaimsScreen extends StatefulWidget {
  const AdminClaimsScreen({super.key});

  @override
  State<AdminClaimsScreen> createState() => _AdminClaimsScreenState();
}

class _AdminClaimsScreenState extends State<AdminClaimsScreen> {
  bool _checkingAccess = true;
  bool _hasAccess = false;
  String? _accessError;

  bool _loadingClaims = false;
  String? _claimsError;
  List<Map<String, dynamic>> _claims = [];

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  // ─────────────────────────────────────────────────────────────
  // Access control: only admins / developers
  // ─────────────────────────────────────────────────────────────
  Future<void> _checkAdminAccess() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _checkingAccess = false;
        _hasAccess = false;
        _accessError = 'You must be logged in to access admin tools.';
      });
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      final isAdmin = data != null && data['is_admin'] == true;

      setState(() {
        _checkingAccess = false;
        _hasAccess = isAdmin;
        _accessError =
            isAdmin ? null : 'You do not have permission to view this screen.';
      });

      if (isAdmin) {
        _loadPendingClaims();
      }
    } catch (e) {
      setState(() {
        _checkingAccess = false;
        _hasAccess = false;
        _accessError = 'Failed to verify admin access: $e';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Load pending claims
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadPendingClaims() async {
    setState(() {
      _loadingClaims = true;
      _claimsError = null;
    });

    try {
      final data = await supabase
          .from('business_claims')
          .select('''
            id,
            company_id,
            claimant_profile_id,
            evidence,
            status,
            created_at,
            company:company_id (
              id,
              name,
              city,
              category
            ),
            claimant:claimant_profile_id (
              id,
              full_name
            )
          ''')
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      final list = (data as List<dynamic>)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _claims = list;
      });
    } catch (e) {
      setState(() {
        _claimsError = 'Failed to load claims: $e';
      });
    } finally {
      setState(() {
        _loadingClaims = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Approve / Reject
  // ─────────────────────────────────────────────────────────────
  Future<void> _approveClaim(Map<String, dynamic> claim) async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in as admin to approve claims.'),
        ),
      );
      return;
    }

    final companyId = claim['company_id'];
    final claimantId = claim['claimant_profile_id'];
    final claimId = claim['id'];

    if (companyId == null || claimantId == null || claimId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid claim data.'),
        ),
      );
      return;
    }

    try {
      await supabase
          .from('companies')
          .update({'owner_id': claimantId}).eq('id', companyId);

      await supabase
          .from('business_claims')
          .update({
            'status': 'approved',
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': admin.id,
          })
          .eq('id', claimId);

      setState(() {
        _claims.removeWhere((c) => c['id'] == claimId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Claim approved and business owner updated.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error approving claim: $e'),
        ),
      );
    }
  }

  Future<void> _rejectClaim(Map<String, dynamic> claim) async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in as admin to reject claims.'),
        ),
      );
      return;
    }

    final claimId = claim['id'];
    if (claimId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid claim data.'),
        ),
      );
      return;
    }

    try {
      await supabase
          .from('business_claims')
          .update({
            'status': 'rejected',
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': admin.id,
          })
          .eq('id', claimId);

      setState(() {
        _claims.removeWhere((c) => c['id'] == claimId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Claim rejected.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error rejecting claim: $e'),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: _checkingAccess
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : !_hasAccess
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _accessError ??
                              'You do not have permission to view this page.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _buildAdminBody(),
        ),
      ),
    );
  }

  Widget _buildAdminBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Admin – Business Claims',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadingClaims ? null : _loadPendingClaims,
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Reload',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Review and approve or reject business ownership claims. '
                'Only trusted admins should have access to this screen.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),

              if (_loadingClaims)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else if (_claimsError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _claimsError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                )
              else if (_claims.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No pending claims at the moment.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                _buildClaimsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClaimsList() {
    return Column(
      children: _claims.map((claim) {
        final company = claim['company'] as Map<String, dynamic>?;
        final claimant = claim['claimant'] as Map<String, dynamic>?;

        final companyName = company?['name']?.toString() ?? 'Unknown company';
        final companyCity = company?['city']?.toString() ?? '';
        final companyCategory = company?['category']?.toString() ?? '';

        final claimantName =
            claimant?['full_name']?.toString() ?? 'Unknown claimant';

        final createdAt = claim['created_at']?.toString() ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Company info
              Text(
                companyName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (companyCategory.isNotEmpty || companyCity.isNotEmpty)
                Text(
                  '${companyCategory.isNotEmpty ? companyCategory : ''}'
                  '${companyCategory.isNotEmpty && companyCity.isNotEmpty ? ' • ' : ''}'
                  '${companyCity.isNotEmpty ? companyCity : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 8),

              // Claimant info
              Text(
                'Claimed by: $claimantName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Created: $createdAt',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Evidence / explanation:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  claim['evidence']?.toString() ?? '(none provided)',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _rejectClaim(claim),
                    child: const Text(
                      'Reject',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _approveClaim(claim),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

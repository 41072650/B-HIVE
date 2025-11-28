// lib/screens/connections_screen.dart
import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../widgets/hive_background.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late Future<List<Map<String, dynamic>>> _futureContacts;

  @override
  void initState() {
    super.initState();
    _futureContacts = _loadContacts();
  }

  Future<List<Map<String, dynamic>>> _loadContacts() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return [];
    }

    // If you created a foreign key, Supabase can join company data like this
    final response = await supabase
        .from('contacts')
        .select(
          'id, action, status, created_at, company:company_id(id, name, city)',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    // response is List<dynamic>
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _updateStatus(String contactId, String newStatus) async {
    try {
      await supabase
          .from('contacts')
          .update({'status': newStatus})
          .match({'id': contactId});

      // refresh list
      setState(() {
        _futureContacts = _loadContacts();
      });
    } catch (e) {
      debugPrint('Error updating status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Connections'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: HiveBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _futureContacts,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        );
                      }

                      final contacts = snapshot.data ?? [];

                      // 👉 NEW: dedupe so we only keep the latest contact per company
                      final uniqueContacts = <Map<String, dynamic>>[];
                      final seenCompanyIds = <dynamic>{};

                      for (final c in contacts) {
                        final company =
                            c['company'] as Map<String, dynamic>?;
                        final companyId = company?['id'];

                        // If we don't have company data, just include the contact as-is
                        if (companyId == null) {
                          uniqueContacts.add(c);
                          continue;
                        }

                        if (!seenCompanyIds.contains(companyId)) {
                          seenCompanyIds.add(companyId);
                          uniqueContacts.add(c);
                        }
                      }

                      if (uniqueContacts.isEmpty) {
                        return const Center(
                          child: Text(
                            'No connections yet.\nContact a company to start.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: uniqueContacts.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.white24),
                        itemBuilder: (context, index) {
                          final contact = uniqueContacts[index];
                          final company =
                              contact['company'] as Map<String, dynamic>?;
                          final companyName =
                              (company?['name'] ?? 'Unknown company')
                                  .toString();
                          final companyCity =
                              (company?['city'] ?? '').toString();
                          final action = (contact['action'] ?? '').toString();
                          final status = (contact['status'] ?? 'waiting')
                              .toString();

                          // Handle created_at as String or DateTime
                          final rawCreatedAt = contact['created_at'];
                          DateTime? createdAt;
                          if (rawCreatedAt is String) {
                            createdAt = DateTime.tryParse(rawCreatedAt);
                          } else if (rawCreatedAt is DateTime) {
                            createdAt = rawCreatedAt;
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            tileColor: Colors.white10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            title: Text(
                              companyName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (companyCity.isNotEmpty) companyCity,
                                'Action: $action',
                                if (createdAt != null)
                                  'Date: ${createdAt.toLocal().toString().substring(0, 16)}',
                              ].where((s) => s.isNotEmpty).join(' • '),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: status,
                                dropdownColor: const Color(0xFF020617),
                                style: const TextStyle(color: Colors.white),
                                iconEnabledColor: Colors.white,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'waiting',
                                    child: Text('Waiting'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'replied',
                                    child: Text('Replied'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'client',
                                    child: Text('Client'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _updateStatus(
                                      contact['id'] as String,
                                      value,
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

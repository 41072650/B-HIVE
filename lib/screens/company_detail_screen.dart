// lib/screens/company_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';
import 'company_services_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/event_tracker.dart';
import '../services/analytics_service.dart'; // 👈 NEW

class CompanyDetailScreen extends StatefulWidget {
  final Map<String, dynamic> company;

  const CompanyDetailScreen({super.key, required this.company});

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  double _userRating = 0;

  @override
  void initState() {
    super.initState();

    // Track a view once the widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final companyId = widget.company['id'].toString();

      // Detailed event log
      EventTracker.trackCompanyEvent(
        companyId: companyId,
        eventType: 'view',
      );

      // Aggregated daily stats
      AnalyticsService.trackCompanyAction(companyId, 'view');
    });

    _loadMyRating();
  }

  // ---------- Rating logic ----------

  Future<void> _loadMyRating() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('ratings')
          .select('rating')
          .eq('company_id', widget.company['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted || data == null) return;

      setState(() {
        final r = data['rating'];
        _userRating = (r is num) ? r.toDouble() : 0.0;
      });
    } catch (_) {
      // silently ignore
    }
  }

  // ---------- Contacts logging ----------

  Future<void> _logContact(String action) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      // Not logged in – you can show a snackbar or redirect to login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to track contacts')),
      );
      return;
    }

    try {
      await supabase.from('contacts').insert({
        'user_id': user.id,
        'company_id': widget.company['id'],
        'action': action,
        'status': 'waiting', // default when they first contact
      });
    } catch (e) {
      debugPrint('Error logging contact: $e');
    }
  }

  Future<void> _submitRating() async {
    if (_userRating <= 0) return;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to rate.')),
        );
        return;
      }

      final companyId = widget.company['id'];

      // Track rating submission (detailed event)
      await EventTracker.trackCompanyEvent(
        companyId: companyId.toString(),
        eventType: 'rating_submit',
        meta: {
          'rating': _userRating,
        },
      );

      await supabase.from('ratings').upsert(
        {
          'company_id': companyId,
          'user_id': user.id,
          'rating': _userRating,
        },
        onConflict: 'company_id,user_id',
      );

      await supabase.rpc('update_company_rating', params: {
        'company_id_input': companyId.toString(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your rating has been saved.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting rating: $e')),
      );
    }
  }

  // ---------- ACTION BUTTON HELPERS ----------

  Future<void> _callCompany(String? phone) async {
    // log a contact for "call"
    await _logContact('call');

    final companyId = widget.company['id'].toString();

    // Detailed event log
    await EventTracker.trackCompanyEvent(
      companyId: companyId,
      eventType: 'call',
      meta: {
        'phone': phone ?? '',
        'source': 'company_detail_screen',
      },
    );

    // Aggregated daily stats
    AnalyticsService.trackCompanyAction(companyId, 'call');

    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone dialer.')),
      );
    }
  }

  Future<void> _whatsappCompany(String? phone) async {
    // log a contact for "whatsapp"
    await _logContact('whatsapp');

    final companyId = widget.company['id'].toString();

    // Detailed event log
    await EventTracker.trackCompanyEvent(
      companyId: companyId,
      eventType: 'whatsapp',
      meta: {
        'phone': phone ?? '',
        'source': 'company_detail_screen',
      },
    );

    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
      );
      return;
    }

    // very simple normalisation – remove spaces
    final clean = phone.replaceAll(' ', '');
    final uri = Uri.parse('https://wa.me/$clean');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  /// Directions: try maps_url first, then fall back to address + city.
  Future<void> _openDirections(
    String? address,
    String? city,
    String? mapsUrl,
  ) async {
    final companyId = widget.company['id'].toString();

    // Detailed event log
    await EventTracker.trackCompanyEvent(
      companyId: companyId,
      eventType: 'directions',
      meta: {
        'address': address ?? '',
        'city': city ?? '',
        'maps_url': mapsUrl ?? '',
        'source': 'company_detail_screen',
      },
    );

    // Aggregated daily stats
    AnalyticsService.trackCompanyAction(companyId, 'directions');

    Uri? uri;

    // 1️⃣ If we have an explicit Google Maps URL, use that
    if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
      try {
        uri = Uri.parse(mapsUrl.trim());
      } catch (_) {
        uri = null;
      }
    }

    // 2️⃣ Otherwise fall back to address + city search
    if (uri == null) {
      final query = (address != null && address.trim().isNotEmpty)
          ? '$address, ${city ?? ''}'
          : (city ?? '');

      if (query.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No address available for directions.')),
        );
        return;
      }

      final encoded = Uri.encodeComponent(query);
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')),
      );
    }
  }

  Future<void> _shareCompany(Map<String, dynamic> c) async {
    // (we DON'T log this as a contact to avoid breaking the SQL check constraint)

    final companyId = c['id'].toString();

    // Detailed event log
    await EventTracker.trackCompanyEvent(
      companyId: companyId,
      eventType: 'share',
      meta: {
        'source': 'company_detail_screen',
      },
    );

    final name = c['name']?.toString() ?? 'Company';
    final slogan = c['slogan']?.toString() ?? '';
    final city = c['city']?.toString() ?? '';
    final category = c['category']?.toString() ?? '';
    final website = c['website']?.toString() ?? '';
    final phone = c['phone']?.toString() ?? '';
    final mapsUrl = c['maps_url']?.toString() ?? '';

    final text = StringBuffer()
      ..writeln(name)
      ..writeln(slogan.isNotEmpty ? '"$slogan"' : '')
      ..writeln([category, city].where((e) => e.isNotEmpty).join(' • '))
      ..writeln()
      ..writeln('Phone: $phone')
      ..writeln('Website: $website');

    if (mapsUrl.isNotEmpty) {
      text.writeln('Location: $mapsUrl');
    }

    await Share.share(text.toString().trim());
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final c = widget.company;

    final ratingAvg =
        (c['rating_avg'] is num) ? (c['rating_avg'] as num).toDouble() : 0.0;
    final ratingCount =
        (c['rating_count'] is num) ? (c['rating_count'] as num).toInt() : 0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          c['name']?.toString() ?? '',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: HiveBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.business, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (c['slogan'] != null &&
                                    c['slogan'].toString().isNotEmpty)
                                  Text(
                                    c['slogan'].toString(),
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white70,
                                    ),
                                  ),
                                Text(
                                  '${c['category'] ?? ''} • ${c['city'] ?? ''}',
                                  style:
                                      const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Rating summary
                      Row(
                        children: [
                          const Text(
                            'Rating:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (ratingCount == 0)
                            const Text(
                              'No ratings yet',
                              style: TextStyle(color: Colors.white70),
                            )
                          else ...[
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '${ratingAvg.toStringAsFixed(1)} ($ratingCount reviews)',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Description
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        c['description']?.toString() ?? '—',
                        style: const TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 16),

                      // Contact
                      const Text(
                        'Contact',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Email: ${c['email'] ?? '—'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Phone: ${c['phone'] ?? '—'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Website: ${c['website'] ?? '—'}',
                        style: const TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 12),

                      // 🔹 ACTION BUTTONS (call, WhatsApp, directions, share)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                _callCompany(c['phone']?.toString()),
                            icon: const Icon(Icons.call),
                            label: const Text('Call'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _whatsappCompany(c['phone']?.toString()),
                            icon: const FaIcon(FontAwesomeIcons.whatsapp),
                            label: const Text('WhatsApp'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _openDirections(
                              c['address']?.toString(),
                              c['city']?.toString(),
                              c['maps_url']?.toString(),
                            ),
                            icon: const Icon(Icons.directions),
                            label: const Text('Directions'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _shareCompany(c),
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Services & pricing button
                      ElevatedButton.icon(
                        onPressed: () async {
                          // Track viewing services (detailed event)
                          final companyId = c['id'].toString();
                          await EventTracker.trackCompanyEvent(
                            companyId: companyId,
                            eventType: 'view_services',
                            meta: {
                              'source': 'company_detail_screen',
                            },
                          );

                          if (!mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CompanyServicesScreen(company: c),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label: const Text('View services & pricing'),
                      ),

                      const SizedBox(height: 24),
                      Divider(color: Colors.white24),

                      // Rating input
                      const Text(
                        'Rate this company',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DropdownButton<double>(
                            value: _userRating == 0 ? null : _userRating,
                            hint: const Text(
                              'Select rating',
                              style: TextStyle(color: Colors.white70),
                            ),
                            dropdownColor: const Color(0xFF020617),
                            style: const TextStyle(color: Colors.white),
                            iconEnabledColor: Colors.white,
                            items: [1, 2, 3, 4, 5]
                                .map(
                                  (v) => DropdownMenuItem<double>(
                                    value: v.toDouble(),
                                    child: Text('$v ★'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _userRating = value ?? 0;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _userRating == 0 ? null : _submitRating,
                            child: const Text('Submit'),
                          ),
                        ],
                      ),
                    ],
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

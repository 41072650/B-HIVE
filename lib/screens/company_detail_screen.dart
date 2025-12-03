// lib/screens/company_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';
import '../widgets/bhive_inputs.dart';
import 'company_services_screen.dart';
import '../services/event_tracker.dart';
import '../services/analytics_service.dart';

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

    // Track view
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.company['id'].toString();
      EventTracker.trackCompanyEvent(
        companyId: id,
        eventType: 'view',
      );
      AnalyticsService.trackCompanyAction(id, 'view');
    });

    _loadMyRating();
  }

  // -----------------------------------------
  // Load user rating
  // -----------------------------------------
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

      final r = data['rating'];
      setState(() {
        _userRating = (r is num) ? r.toDouble() : 0.0;
      });
    } catch (_) {}
  }

  // -----------------------------------------
  // Contact logging helper
  // -----------------------------------------
  Future<void> _logContact(String action) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
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
        'status': 'waiting',
      });
    } catch (_) {}
  }

  // -----------------------------------------
  // Submit rating
  // -----------------------------------------
  Future<void> _submitRating() async {
    if (_userRating <= 0) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to rate.')),
      );
      return;
    }

    try {
      final id = widget.company['id'];

      await EventTracker.trackCompanyEvent(
        companyId: id.toString(),
        eventType: 'rating_submit',
        meta: {'rating': _userRating},
      );

      await supabase.from('ratings').upsert({
        'company_id': id,
        'user_id': user.id,
        'rating': _userRating,
      });

      await supabase.rpc('update_company_rating', params: {
        'company_id_input': id.toString(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rating saved.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting rating: $e')),
      );
    }
  }

  // -----------------------------------------
  // CALL
  // -----------------------------------------
  Future<void> _callCompany(String? phone) async {
    await _logContact('call');

    final id = widget.company['id'].toString();
    await EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'call',
      meta: {'phone': phone ?? '', 'source': 'detail'},
    );
    AnalyticsService.trackCompanyAction(id, 'call');

    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      return _snack('No phone number available.');
    }

    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('Could not open phone app.');
    }
  }

  // -----------------------------------------
  // WHATSAPP
  // -----------------------------------------
  Future<void> _whatsappCompany(String? phone) async {
    await _logContact('whatsapp');

    final id = widget.company['id'].toString();
    await EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'whatsapp',
      meta: {'phone': phone ?? '', 'source': 'detail'},
    );

    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      return _snack('No phone number available.');
    }

    final clean = phone.replaceAll(' ', '');
    final uri = Uri.parse('https://wa.me/$clean');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open WhatsApp.');
    }
  }

  // -----------------------------------------
  // MAPS / DIRECTIONS
  // -----------------------------------------
  Future<void> _openDirections(
      String? address, String? city, String? url) async {
    final id = widget.company['id'].toString();

    await EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'directions',
      meta: {
        'address': address ?? '',
        'city': city ?? '',
        'maps_url': url ?? ''
      },
    );
    AnalyticsService.trackCompanyAction(id, 'directions');

    Uri? uri;

    if (url != null && url.trim().isNotEmpty) {
      try {
        uri = Uri.parse(url.trim());
      } catch (_) {}
    }

    if (uri == null) {
      final query = address != null && address.trim().isNotEmpty
          ? "$address, ${city ?? ''}"
          : (city ?? '');

      if (query.trim().isEmpty) return _snack('No address available.');

      final encoded = Uri.encodeComponent(query);
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$encoded');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open maps.');
    }
  }

  // -----------------------------------------
  // SHARE
  // -----------------------------------------
  Future<void> _shareCompany(Map<String, dynamic> c) async {
    final id = c['id'].toString();

    await EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'share',
    );

    final buffer = StringBuffer()
      ..writeln(c['name'] ?? 'Company')
      ..writeln(c['slogan'] ?? '')
      ..writeln("${c['category'] ?? ''} • ${c['city'] ?? ''}")
      ..writeln('');

    buffer.writeln("Phone: ${c['phone'] ?? ''}");
    buffer.writeln("Website: ${c['website'] ?? ''}");
    if ((c['maps_url'] ?? '').toString().isNotEmpty) {
      buffer.writeln("Location: ${c['maps_url']}");
    }

    await Share.share(buffer.toString().trim());
  }

  // -----------------------------------------
  // Helper
  // -----------------------------------------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // -----------------------------------------
  // UI
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    final c = widget.company;

    final ratingAvg = (c['rating_avg'] is num)
        ? (c['rating_avg'] as num).toDouble()
        : 0.0;
    final ratingCount =
        (c['rating_count'] is num) ? c['rating_count'] as int : 0;

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
                      // HEADER
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white24,
                            child:
                                Icon(Icons.business, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['name']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if ((c['slogan'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Text(
                                    c['slogan'].toString(),
                                    style: const TextStyle(
                                      fontStyle:
                                          FontStyle.italic,
                                      color: Colors.white70,
                                    ),
                                  ),
                                Text(
                                  '${c['category'] ?? ''} • ${c['city'] ?? ''}',
                                  style: const TextStyle(
                                      color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // RATING SUMMARY
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
                              style:
                                  TextStyle(color: Colors.white70),
                            )
                          else
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  '${ratingAvg.toStringAsFixed(1)} ($ratingCount reviews)',
                                  style: const TextStyle(
                                      color: Colors.white),
                                ),
                              ],
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // DESCRIPTION
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        c['description']?.toString() ?? '—',
                        style:
                            const TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 16),

                      // CONTACT
                      const Text(
                        'Contact',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Email: ${c['email'] ?? '—'}',
                        style:
                            const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Phone: ${c['phone'] ?? '—'}',
                        style:
                            const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Website: ${c['website'] ?? '—'}',
                        style:
                            const TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 12),

                      // CALL ACTION BUTTONS
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                _callCompany(c['phone']),
                            icon: const Icon(Icons.call),
                            label: const Text('Call'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _whatsappCompany(
                                c['phone']),
                            icon: const FaIcon(
                                FontAwesomeIcons.whatsapp),
                            label: const Text('WhatsApp'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _openDirections(
                              c['address'],
                              c['city'],
                              c['maps_url'],
                            ),
                            icon: const Icon(Icons.directions),
                            label: const Text('Directions'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _shareCompany(c),
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // SERVICES BUTTON
                      ElevatedButton.icon(
                        onPressed: () {
                          final id = c['id'].toString();
                          EventTracker.trackCompanyEvent(
                            companyId: id,
                            eventType: 'view_services',
                            meta: {'source': 'detail'},
                          );

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CompanyServicesScreen(
                                      company: c),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label:
                            const Text('View services & pricing'),
                      ),

                      const SizedBox(height: 24),
                      const Divider(color: Colors.white24),

                      // RATING INPUT
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
                            value: _userRating == 0
                                ? null
                                : _userRating,
                            hint: const Text(
                              'Select rating',
                              style:
                                  TextStyle(color: Colors.white70),
                            ),
                            dropdownColor:
                                const Color(0xFF020617),
                            style:
                                const TextStyle(color: Colors.white),
                            iconEnabledColor: Colors.white,
                            items: [1, 2, 3, 4, 5]
                                .map(
                                  (v) =>
                                      DropdownMenuItem<double>(
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
                            onPressed: _userRating == 0
                                ? null
                                : _submitRating,
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

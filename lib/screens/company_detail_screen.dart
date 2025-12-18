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

  // ✅ NEW: Keep rating summary in state so it can refresh instantly
  double _ratingAvg = 0.0;
  int _ratingCount = 0;

  // ✅ ADS
  bool _adsLoading = false;
  String? _adsError;
  final List<String> _adSignedUrls = [];

  @override
  void initState() {
    super.initState();

    // ✅ init rating summary from incoming company map
    _ratingAvg = (widget.company['rating_avg'] is num)
        ? (widget.company['rating_avg'] as num).toDouble()
        : 0.0;
    _ratingCount = (widget.company['rating_count'] is num)
        ? (widget.company['rating_count'] as num).toInt()
        : 0;

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

    // ✅ Always attempt to load ads so everyone can view them
    _loadCompanyAds();
  }

  // ✅ NEW: Refresh rating summary after submit so UI updates immediately
  Future<void> _refreshCompanyRatingSummary() async {
    try {
      final id = widget.company['id'];
      final data = await supabase
          .from('companies')
          .select('rating_avg, rating_count')
          .eq('id', id)
          .maybeSingle();

      if (!mounted || data == null) return;

      setState(() {
        _ratingAvg = (data['rating_avg'] is num)
            ? (data['rating_avg'] as num).toDouble()
            : 0.0;
        _ratingCount = (data['rating_count'] is num)
            ? (data['rating_count'] as num).toInt()
            : 0;
      });
    } catch (_) {}
  }

  // ✅ ADS: Load all ads from storage path: {companyId}/ads/
  Future<void> _loadCompanyAds() async {
    final companyId = widget.company['id']?.toString();
    if (companyId == null || companyId.isEmpty) return;

    setState(() {
      _adsLoading = true;
      _adsError = null;
      _adSignedUrls.clear();
    });

    try {
      // List objects under: {companyId}/ads/
      final objects = await supabase.storage.from('company-ads').list(
            path: '$companyId/ads',
          );

      // Filter only image files
      final imageObjects = objects.where((o) {
        final name = (o.name ?? '').toLowerCase();
        return name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp');
      }).toList();

      // Newest first (best effort: by name if timestamp in filename)
      imageObjects.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));

      // Create signed URLs (1 hour)
      final urls = <String>[];
      for (final o in imageObjects) {
        final filePath = '$companyId/ads/${o.name}';
        final signedUrl = await supabase.storage
            .from('company-ads')
            .createSignedUrl(filePath, 60 * 60);
        urls.add(signedUrl);
      }

      if (!mounted) return;
      setState(() {
        _adSignedUrls.addAll(urls);
        _adsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _adsLoading = false;
        _adsError = 'Failed to load ads: $e';
      });
    }
  }

  // ✅ Instagram-style full screen viewer (swipe + zoom)
  void _openAdPreview(int initialIndex) {
    final companyId = widget.company['id']?.toString() ?? 'company';

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withOpacity(0.95),
      pageBuilder: (_, __, ___) {
        final controller = PageController(initialPage: initialIndex);

        return SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                PageView.builder(
                  controller: controller,
                  itemCount: _adSignedUrls.length,
                  itemBuilder: (context, index) {
                    final url = _adSignedUrls[index];
                    final heroTag = 'ad_$companyId$index';

                    return Center(
                      child: Hero(
                        tag: heroTag,
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'Could not load image.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Close button
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),

                // Simple indicator
                if (_adSignedUrls.length > 1)
                  Positioned(
                    bottom: 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: StatefulBuilder(
                          builder: (context, setInner) {
                            int current = initialIndex;

                            controller.addListener(() {
                              final p = controller.page;
                              if (p == null) return;
                              final idx = p.round();
                              if (idx != current) {
                                current = idx;
                                setInner(() {});
                              }
                            });

                            return Text(
                              '${current + 1} / ${_adSignedUrls.length}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ ADS GRID (to be shown under "Rate this company" section)
  Widget _buildAdsSection() {
    final bool isPaid = widget.company['is_paid'] == true;
    final companyId = widget.company['id']?.toString() ?? 'company';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Advertisements',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            if (isPaid)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amberAccent),
                ),
                child: const Text(
                  'Sponsored',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_adsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (_adsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _adsError!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          )
        else if (_adSignedUrls.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'No ads available yet.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _adSignedUrls.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, i) {
              final url = _adSignedUrls[i];
              final heroTag = 'ad_$companyId$i';

              return GestureDetector(
                onTap: () => _openAdPreview(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.white10,
                    child: Hero(
                      tag: heroTag,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child:
                              Icon(Icons.broken_image, color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 12),
      ],
    );
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
  // Submit rating  ✅ FIXED: use onConflict so it updates instead of duplicate-key error
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

      await supabase.from('ratings').upsert(
        {
          'company_id': id,
          'user_id': user.id,
          'rating': _userRating,
        },
        onConflict: 'user_id,company_id',
      );

      await supabase.rpc('update_company_rating', params: {
        'company_id_input': id.toString(),
      });

      // ✅ NEW: refresh summary so the UI updates instantly
      await _refreshCompanyRatingSummary();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rating saved.')),
      );
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
    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      _snack('No phone number available.');
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone.trim());

    // IMPORTANT: launch first, no awaits before this
    final launched = await launchUrl(uri);

    if (!launched) {
      if (!mounted) return;
      _snack('Could not open phone app.');
      return;
    }

    // Fire-and-forget logging AFTER launch
    _logContact('call');
    final id = widget.company['id'].toString();
    EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'call',
      meta: {'phone': phone, 'source': 'detail'},
    );
    AnalyticsService.trackCompanyAction(id, 'call');
  }

  // -----------------------------------------
  // WHATSAPP
  // -----------------------------------------
  Future<void> _whatsappCompany(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      if (!mounted) return;
      _snack('No phone number available.');
      return;
    }

    final clean = phone.replaceAll(' ', '');
    final uri = Uri.parse('https://wa.me/$clean');

    // IMPORTANT: launch first, no awaits before this
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      if (!mounted) return;
      _snack('Could not open WhatsApp.');
      return;
    }

    // Fire-and-forget logging AFTER launch
    _logContact('whatsapp');
    final id = widget.company['id'].toString();
    EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'whatsapp',
      meta: {'phone': phone, 'source': 'detail'},
    );
  }

  // -----------------------------------------
  // MAPS / DIRECTIONS
  // -----------------------------------------
  Future<void> _openDirections(String? address, String? city, String? url) async {
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

      if (query.trim().isEmpty) {
        if (!mounted) return;
        _snack('No address available.');
        return;
      }

      final encoded = Uri.encodeComponent(query);
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    }

    // IMPORTANT: launch first
    final launched = await launchUrl(
      uri!,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      if (!mounted) return;
      _snack('Could not open maps.');
      return;
    }

    // Log AFTER launch
    final id = widget.company['id'].toString();
    EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'directions',
      meta: {
        'address': address ?? '',
        'city': city ?? '',
        'maps_url': url ?? '',
      },
    );
    AnalyticsService.trackCompanyAction(id, 'directions');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openClaimScreen(Map<String, dynamic> company) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClaimBusinessScreen(company: company),
      ),
    );
  }

  // -----------------------------------------
  // UI
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    final c = widget.company;

    // pull logo_url for header avatar
    final String logoUrl = (c['logo_url'] ?? '').toString();

    // claimed status
    final bool isClaimed = (c['is_claimed'] == true) || (c['owner_id'] != null);

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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white24,
                            radius: 24,
                            backgroundImage:
                                logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                            child: logoUrl.isEmpty
                                ? const Icon(
                                    Icons.business,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c['name']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isClaimed
                                            ? Colors.green.withOpacity(0.2)
                                            : Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isClaimed
                                              ? Colors.greenAccent
                                              : Colors.orangeAccent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isClaimed
                                                ? Icons.verified
                                                : Icons.lock_open,
                                            size: 14,
                                            color: isClaimed
                                                ? Colors.greenAccent
                                                : Colors.orangeAccent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isClaimed ? 'Claimed' : 'Unclaimed',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isClaimed
                                                  ? Colors.greenAccent
                                                  : Colors.orangeAccent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if ((c['slogan'] ?? '').toString().isNotEmpty)
                                  Text(
                                    c['slogan'].toString(),
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white70,
                                    ),
                                  ),
                                Text(
                                  '${c['category'] ?? ''} • ${c['city'] ?? ''}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // CLAIM BANNER (only if unclaimed)
                      if (!isClaimed) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amberAccent,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.how_to_reg,
                                color: Colors.amberAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Is this your business? Claim it to update details and unlock extra features.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => _openClaimScreen(c),
                                child: const Text(
                                  'Claim',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // RATING SUMMARY (now uses state)
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
                          if (_ratingCount == 0)
                            const Text(
                              'No ratings yet',
                              style: TextStyle(color: Colors.white70),
                            )
                          else
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  '${_ratingAvg.toStringAsFixed(1)} ($_ratingCount reviews)',
                                  style: const TextStyle(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white70),
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

                      // CALL ACTION BUTTONS
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _callCompany(c['phone']),
                            icon: const Icon(Icons.call),
                            label: const Text('Call'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _whatsappCompany(c['phone']),
                            icon: const FaIcon(FontAwesomeIcons.whatsapp),
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
                            onPressed: () => _shareCompany(c),
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
                              builder: (_) => CompanyServicesScreen(company: c),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label: const Text('View services & pricing'),
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

                      // ✅ ADS GRID MUST BE BELOW THE RATING DROPDOWN
                      _buildAdsSection(),
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

/// Screen to claim THIS specific business
class ClaimBusinessScreen extends StatefulWidget {
  final Map<String, dynamic> company;

  const ClaimBusinessScreen({super.key, required this.company});

  @override
  State<ClaimBusinessScreen> createState() => _ClaimBusinessScreenState();
}

class _ClaimBusinessScreenState extends State<ClaimBusinessScreen> {
  final TextEditingController _evidenceController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _evidenceController.dispose();
    super.dispose();
  }

  Future<void> _submitClaim() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to claim a business.'),
        ),
      );
      return;
    }

    if (_evidenceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please describe how you are connected to this business.'),
        ),
      );
      return;
    }

    final companyId = widget.company['id'];

    try {
      setState(() {
        _submitting = true;
      });

      await EventTracker.trackCompanyEvent(
        companyId: companyId.toString(),
        eventType: 'claim_submit',
        meta: {'source': 'detail_screen'},
      );

      await supabase.from('business_claims').insert({
        'company_id': companyId,
        'claimant_profile_id': user.id,
        'evidence': _evidenceController.text.trim(),
        // status defaults to 'pending' in DB
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Claim submitted. We will review it and get back to you.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting claim: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.company['name']?.toString() ?? 'Business';

    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Claim $name',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tell us how you are connected to "$name". '
                        'For example: your role, business email, website, social media, or other proof that you represent this business.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _evidenceController,
                        maxLines: 5,
                        style: const TextStyle(color: Colors.white),
                        decoration: bhiveInputDecoration(
                          'Your explanation',
                          hint:
                              'Example: "I am the owner. My official email is info@mybusiness.co.za and our website is www.mybusiness.co.za."',
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _submitting ? null : _submitClaim,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.how_to_reg),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            _submitting ? 'Submitting...' : 'Submit Claim',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
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

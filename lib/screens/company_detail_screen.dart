// lib/screens/company_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// ✅ Video support
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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

  // Rating summary state
  double _ratingAvg = 0.0;
  int _ratingCount = 0;

  // Ads / Media (images + videos)
  bool _adsLoading = false;
  String? _adsError;
  final List<String> _adSignedUrls = [];
  final List<String> _adPaths = []; // keep storage paths (to detect file type)

  // ✅ Live claimed state (so UI always matches DB)
  bool _claimedLoading = true;
  bool _claimedLive = false;

  @override
  void initState() {
    super.initState();

    _ratingAvg = (widget.company['rating_avg'] is num)
        ? (widget.company['rating_avg'] as num).toDouble()
        : 0.0;
    _ratingCount = (widget.company['rating_count'] is num)
        ? (widget.company['rating_count'] as num).toInt()
        : 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.company['id'].toString();
      EventTracker.trackCompanyEvent(companyId: id, eventType: 'view');
      AnalyticsService.trackCompanyAction(id, 'view');
    });

    _loadMyRating();
    _loadCompanyAds();
    _loadClaimedLive(); // ✅ NEW
  }

  // ---------------------------------------------------------------------------
  // ✅ Claim status helpers
  // ---------------------------------------------------------------------------
  bool _isClaimedRow(Map<String, dynamic>? c) {
    if (c == null) return false;

    final isClaimedVal = c['is_claimed'];
    final ownerIdVal = c['owner_id'];

    final boolFlag = (isClaimedVal == true) ||
        (isClaimedVal?.toString().toLowerCase() == 'true');

    final hasOwner = (ownerIdVal ?? '').toString().trim().isNotEmpty;

    return boolFlag || hasOwner;
  }

  Future<void> _loadClaimedLive() async {
    try {
      final companyId = widget.company['id'];
      final data = await supabase
          .from('companies')
          .select('is_claimed, owner_id')
          .eq('id', companyId)
          .maybeSingle();

      final live = data == null ? _isClaimedRow(widget.company) : _isClaimedRow(data);

      if (!mounted) return;
      setState(() {
        _claimedLive = live;
        _claimedLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _claimedLive = _isClaimedRow(widget.company);
        _claimedLoading = false;
      });
    }
  }

  Future<bool> _isCompanyClaimedLive() async {
    try {
      final companyId = widget.company['id'];
      final data = await supabase
          .from('companies')
          .select('is_claimed, owner_id')
          .eq('id', companyId)
          .maybeSingle();

      if (data == null) return _isClaimedRow(widget.company);
      return _isClaimedRow(data);
    } catch (_) {
      return _isClaimedRow(widget.company);
    }
  }

  // ---------------------------------------------------------------------------
  // Ads / Media helpers
  // ---------------------------------------------------------------------------
  bool _isVideoPath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov') || p.endsWith('.webm');
  }

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

  Future<void> _loadCompanyAds() async {
    final companyId = widget.company['id']?.toString();
    if (companyId == null || companyId.isEmpty) return;

    setState(() {
      _adsLoading = true;
      _adsError = null;
      _adSignedUrls.clear();
      _adPaths.clear();
    });

    try {
      final objects = await supabase.storage.from('company-ads').list(
            path: '$companyId/ads',
          );

      final mediaObjects = objects.where((o) {
        final name = (o.name ?? '').toLowerCase();
        return name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp') ||
            name.endsWith('.mp4') ||
            name.endsWith('.mov') ||
            name.endsWith('.webm');
      }).toList();

      mediaObjects.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));

      final urls = <String>[];
      final paths = <String>[];

      for (final o in mediaObjects) {
        final filePath = '$companyId/ads/${o.name}';
        final signedUrl = await supabase.storage
            .from('company-ads')
            .createSignedUrl(filePath, 60 * 60);
        urls.add(signedUrl);
        paths.add(filePath);
      }

      if (!mounted) return;
      setState(() {
        _adSignedUrls.addAll(urls);
        _adPaths.addAll(paths);
        _adsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adsLoading = false;
        _adsError = 'Failed to load ads.';
      });
    }
  }

  Future<void> _openShareSheetForAd(String url) async {
    final c = widget.company;
    final companyName = (c['name'] ?? '').toString().trim().isEmpty
        ? 'B-Hive'
        : (c['name'] ?? '').toString().trim();
    final text = 'Check out this ad from $companyName on B-Hive:\n$url';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              height: 4,
              width: 42,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const ListTile(
              title: Text(
                'Share Ad',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Choose how you want to share this ad.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.ios_share, color: Colors.white),
              title: const Text('Share…', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'System share menu',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Share.share(text);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openAdViewer(int initialIndex) {
    if (_adSignedUrls.isEmpty) return;
    if (initialIndex < 0 || initialIndex >= _adSignedUrls.length) return;

    final pageController = PageController(initialPage: initialIndex);
    int currentIndex = initialIndex;

    final c = widget.company;
    final String logoUrl = (c['logo_url'] ?? '').toString();
    final String companyName = (c['name'] ?? '').toString().trim().isEmpty
        ? 'Company'
        : (c['name'] ?? '').toString().trim();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 720,
                maxHeight: 620,
                minWidth: 320,
                minHeight: 420,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F1A).withOpacity(0.98),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                      child: Row(
                        children: [
                          if (logoUrl.isNotEmpty)
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white10,
                              backgroundImage: NetworkImage(logoUrl),
                            )
                          else
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.business,
                                  color: Colors.white, size: 16),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              companyName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: StatefulBuilder(
                            builder: (context, setInner) {
                              pageController.addListener(() {
                                final p = pageController.page;
                                if (p == null) return;
                                final idx = p.round();
                                if (idx != currentIndex &&
                                    idx >= 0 &&
                                    idx < _adSignedUrls.length) {
                                  currentIndex = idx;
                                  setInner(() {});
                                }
                              });

                              return PageView.builder(
                                controller: pageController,
                                itemCount: _adSignedUrls.length,
                                itemBuilder: (context, index) {
                                  final url = _adSignedUrls[index];
                                  final path = index < _adPaths.length
                                      ? _adPaths[index]
                                      : '';
                                  final isVideo = _isVideoPath(path);

                                  return LayoutBuilder(
                                    builder: (context, constraints) {
                                      if (isVideo) {
                                        return SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: _AdVideoPlayer(url: url),
                                        );
                                      }

                                      return InteractiveViewer(
                                        minScale: 1.0,
                                        maxScale: 4.0,
                                        child: SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: Image.network(
                                            url,
                                            width: constraints.maxWidth,
                                            height: constraints.maxHeight,
                                            fit: BoxFit.contain,
                                            alignment: Alignment.center,
                                            errorBuilder: (_, __, ___) =>
                                                const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Center(
                                                child: Text(
                                                  'Could not load image.',
                                                  style: TextStyle(
                                                      color: Colors.white70),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              final url = _adSignedUrls.isEmpty
                                  ? null
                                  : _adSignedUrls[currentIndex];
                              if (url == null) return;
                              _openShareSheetForAd(url);
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                          const Spacer(),
                          if (_adSignedUrls.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(
                                '${currentIndex + 1} / ${_adSignedUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdsSection() {
    final bool isPaid = widget.company['is_paid'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'Advertisements',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
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
        const SizedBox(height: 8),
        if (_adsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (_adsError != null)
          GestureDetector(
            onTap: _loadCompanyAds,
            child: const Text(
              'Failed to load ads. Tap to retry.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          )
        else if (_adSignedUrls.isEmpty)
          const Text(
            'No ads available yet.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
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
              final path = i < _adPaths.length ? _adPaths[i] : '';
              final isVideo = _isVideoPath(path);

              return GestureDetector(
                onTap: () => _openAdViewer(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.white10,
                    child: isVideo
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: Colors.black.withOpacity(0.3)),
                              const Center(
                                child: Icon(Icons.play_circle_fill,
                                    color: Colors.white70, size: 42),
                              ),
                            ],
                          )
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white54),
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

  Future<void> _callCompany(String? phone) async {
    final p = (phone ?? '').trim();
    if (p.isEmpty) {
      _snack('No phone number available.');
      return;
    }

    final uri = Uri(scheme: 'tel', path: p);
    final launched = await launchUrl(uri);

    if (!launched) {
      _snack('Could not open phone app.');
      return;
    }

    _logContact('call');
    final id = widget.company['id'].toString();
    EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'call',
      meta: {'phone': p, 'source': 'detail'},
    );
    AnalyticsService.trackCompanyAction(id, 'call');
  }

  Future<void> _whatsappCompany(String? phone) async {
    final p = (phone ?? '').trim();
    if (p.isEmpty) {
      _snack('No phone number available.');
      return;
    }

    final clean = p.replaceAll(' ', '');
    final uri = Uri.parse('https://wa.me/$clean');

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _snack('Could not open WhatsApp.');
      return;
    }

    _logContact('whatsapp');
    final id = widget.company['id'].toString();
    EventTracker.trackCompanyEvent(
      companyId: id,
      eventType: 'whatsapp',
      meta: {'phone': p, 'source': 'detail'},
    );
  }

  Future<void> _openDirections(String? address, String? city, String? url) async {
    Uri? uri;

    final u = (url ?? '').trim();
    if (u.isNotEmpty) {
      try {
        uri = Uri.parse(u);
      } catch (_) {}
    }

    if (uri == null) {
      final query = (address ?? '').trim().isNotEmpty
          ? "${address!.trim()}, ${(city ?? '').trim()}"
          : (city ?? '').trim();

      if (query.isEmpty) {
        _snack('No address available.');
        return;
      }

      final encoded = Uri.encodeComponent(query);
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _snack('Could not open maps.');
      return;
    }

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

  Future<void> _shareCompany(Map<String, dynamic> c) async {
    final id = c['id'].toString();
    await EventTracker.trackCompanyEvent(companyId: id, eventType: 'share');

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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ When user returns from claim screen, refresh claimed state
  Future<void> _openClaimScreen(Map<String, dynamic> company) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClaimBusinessScreen(company: company),
      ),
    );
    await _loadClaimedLive();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.company;
    final String logoUrl = (c['logo_url'] ?? '').toString();

    // ✅ use LIVE state for UI
    final bool isClaimed = _claimedLoading ? _isClaimedRow(c) : _claimedLive;

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
                                ? const Icon(Icons.business, color: Colors.white)
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

                                    // ✅ BADGE uses LIVE claimed state
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: isClaimed
                                            ? Colors.green.withOpacity(0.18)
                                            : Colors.orange.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(18),
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
                                          const SizedBox(width: 6),
                                          Text(
                                            isClaimed ? 'Claimed' : 'Unclaimed',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isClaimed
                                                  ? Colors.greenAccent
                                                  : Colors.orangeAccent,
                                              fontWeight: FontWeight.w700,
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

                      // ✅ CLAIM BANNER only if NOT claimed (live)
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

                      const Text(
                        'Description',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        c['description']?.toString() ?? '—',
                        style: const TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Contact',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white),
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

                      const Text(
                        'Rate this company',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white),
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
                              setState(() => _userRating = value ?? 0);
                            },
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _userRating == 0 ? null : _submitRating,
                            child: const Text('Submit'),
                          ),
                        ],
                      ),

                      // ADS / MEDIA
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

// -----------------------------------------------------------------------------
// ✅ Video widget (Chewie wrapper)
// -----------------------------------------------------------------------------
class _AdVideoPlayer extends StatefulWidget {
  final String url;
  const _AdVideoPlayer({required this.url});

  @override
  State<_AdVideoPlayer> createState() => _AdVideoPlayerState();
}

class _AdVideoPlayerState extends State<_AdVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await vc.initialize();
      vc.setLooping(true);

      final cc = ChewieController(
        videoPlayerController: vc,
        autoPlay: false,
        looping: true,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.amberAccent,
          handleColor: Colors.amberAccent,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
      );

      if (!mounted) return;

      setState(() {
        _videoController = vc;
        _chewieController = cc;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_chewieController == null || _videoController == null) {
      return const Center(
        child: Text(
          'Could not load video.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Chewie(controller: _chewieController!);
  }
}

class ClaimBusinessScreen extends StatefulWidget {
  final Map<String, dynamic> company;

  const ClaimBusinessScreen({super.key, required this.company});

  @override
  State<ClaimBusinessScreen> createState() => _ClaimBusinessScreenState();
}

class _ClaimBusinessScreenState extends State<ClaimBusinessScreen> {
  final TextEditingController _evidenceController = TextEditingController();
  bool _submitting = false;

  bool _isClaimedRow(Map<String, dynamic>? c) {
    if (c == null) return false;

    final isClaimedVal = c['is_claimed'];
    final ownerIdVal = c['owner_id'];

    final boolFlag = (isClaimedVal == true) ||
        (isClaimedVal?.toString().toLowerCase() == 'true');

    final hasOwner = (ownerIdVal ?? '').toString().trim().isNotEmpty;

    return boolFlag || hasOwner;
  }

  Future<bool> _isCompanyClaimedLive() async {
    try {
      final companyId = widget.company['id'];
      final data = await supabase
          .from('companies')
          .select('is_claimed, owner_id')
          .eq('id', companyId)
          .maybeSingle();

      if (data == null) return _isClaimedRow(widget.company);
      return _isClaimedRow(data);
    } catch (_) {
      return _isClaimedRow(widget.company);
    }
  }

  @override
  void dispose() {
    _evidenceController.dispose();
    super.dispose();
  }

  Future<void> _submitClaim() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to claim a business.')),
      );
      return;
    }

    // ✅ ALWAYS check live before inserting
    final alreadyClaimedLive = await _isCompanyClaimedLive();
    if (alreadyClaimedLive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This business is already claimed.')),
      );
      return;
    }

    if (_evidenceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe how you are connected to this business.'),
        ),
      );
      return;
    }

    final companyId = widget.company['id'];

    try {
      setState(() => _submitting = true);

      await EventTracker.trackCompanyEvent(
        companyId: companyId.toString(),
        eventType: 'claim_submit',
        meta: {'source': 'detail_screen'},
      );

      await supabase.from('business_claims').insert({
        'company_id': companyId,
        'claimant_profile_id': user.id,
        'evidence': _evidenceController.text.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Claim submitted. We will review it and get back to you.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting claim: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
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

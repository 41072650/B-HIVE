// lib/screens/business_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/hive_background.dart';
import '../supabase_client.dart';

class BusinessStatsScreen extends StatefulWidget {
  /// Optional: open stats already focused on a specific business.
  final String? initialCompanyId;

  const BusinessStatsScreen({
    super.key,
    this.initialCompanyId,
  });

  @override
  State<BusinessStatsScreen> createState() => BusinessStatsScreenState();
}

class BusinessStatsScreenState extends State<BusinessStatsScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selectedCompany;

  // Core stats
  int _viewsLast30 = 0;
  int _actionsLast30 = 0;
  Map<String, int> _eventCounts = {};
  List<_DailyViews> _last7DaysViews = [];

  // Leads (built from company_events + profiles)
  List<_LeadEvent> _leads = [];

  // Peak activity (hours of day, across last 30 days)
  List<_HourBucket> _topHours = [];

  // Competitor benchmarking
  double? _peerAvgViews;
  double? _peerAvgConversion; // actions / views
  double? _viewsPercentile; // 0–100
  double? _conversionPercentile; // 0–100
  int _peerCount = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  /// ✅ Call this from LandingScreen after a business is created/updated.
  Future<void> reloadStats() async {
    await _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be logged in to view business stats.';
      });
      return;
    }

    try {
      // 1) Load companies owned by this user
      final companiesRes = await supabase
          .from('companies')
          .select()
          .eq('owner_id', user.id)
          .order('inserted_at', ascending: false);

      final companies = (companiesRes is List)
          ? companiesRes
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      if (companies.isEmpty) {
        setState(() {
          _loading = false;
          _companies = [];
          _selectedCompany = null;
        });
        return;
      }

      // Prefer initialCompanyId if provided
      Map<String, dynamic> selected = companies.first;
      final preferredId = widget.initialCompanyId;
      if (preferredId != null && preferredId.isNotEmpty) {
        final match = companies.where((c) => c['id']?.toString() == preferredId);
        if (match.isNotEmpty) {
          selected = match.first;
        }
      }

      setState(() {
        _companies = companies;
        _selectedCompany = selected;
      });

      await _loadStatsForCompany(selected['id'].toString());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error loading companies: $e';
      });
    }
  }

  /// Open Paystack subscription for the currently selected company
  Future<void> _openSubscriptionPage() async {
    if (_selectedCompany == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a company first.'),
        ),
      );
      return;
    }

    final companyId = _selectedCompany!['id']?.toString();
    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid company selected.'),
        ),
      );
      return;
    }

    // Must be logged in and have an email
    final user = supabase.auth.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to manage a subscription.'),
        ),
      );
      return;
    }

    try {
      final response = await supabase.functions.invoke(
        'create-paystack-link',
        body: {
          'companyId': companyId,
          'userEmail': user.email,
        },
      );

      final data = response.data as Map<String, dynamic>?;
      final url = data?['authorization_url'] as String?;

      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get subscription link from server.'),
          ),
        );
        return;
      }

      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open subscription page.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening subscription: $e'),
        ),
      );
    }
  }

  Future<void> _loadStatsForCompany(String companyId) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _viewsLast30 = 0;
      _actionsLast30 = 0;
      _eventCounts = {};
      _last7DaysViews = [];
      _leads = [];
      _topHours = [];
      _peerAvgViews = null;
      _peerAvgConversion = null;
      _viewsPercentile = null;
      _conversionPercentile = null;
      _peerCount = 0;
    });

    try {
      final now = DateTime.now();
      final from30 = now.subtract(const Duration(days: 30));
      final from30DateOnly = DateTime(from30.year, from30.month, from30.day);
      final from30Str = from30DateOnly.toIso8601String();

      // ---- 1) Get aggregated daily stats (company_daily_stats) ----
      final dailyStats = await supabase
          .from('company_daily_stats')
          .select('date, views, calls, directions, company_id')
          .eq('company_id', companyId)
          .gte('date', from30Str)
          .order('date');

      int totalViews = 0;
      int totalCalls = 0;
      int totalDirections = 0;
      final Map<DateTime, int> viewsPerDay = {};

      final last7Start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));

      if (dailyStats is List) {
        for (final row in dailyStats) {
          final map = row as Map<String, dynamic>;
          final dateStr = map['date']?.toString();
          if (dateStr == null) continue;

          final date = DateTime.parse(dateStr);

          final views =
              (map['views'] is num) ? (map['views'] as num).toInt() : 0;
          final calls =
              (map['calls'] is num) ? (map['calls'] as num).toInt() : 0;
          final directions = (map['directions'] is num)
              ? (map['directions'] as num).toInt()
              : 0;

          totalViews += views;
          totalCalls += calls;
          totalDirections += directions;

          final dayKey = DateTime(date.year, date.month, date.day);
          viewsPerDay[dayKey] = (viewsPerDay[dayKey] ?? 0) + views;
        }
      }

      // ---- 2) Get detailed events for last 30 days (company_events) ----
      int whatsappCount = 0;
      int shareCount = 0;

      final eventsRes = await supabase
          .from('company_events')
          .select('company_id, user_id, event_type, created_at')
          .eq('company_id', companyId)
          .gte('created_at', from30.toUtc().toIso8601String())
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> events = [];
      if (eventsRes is List) {
        events = eventsRes
            .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map),
            )
            .toList();

        final Map<int, int> hourlyCounts = {};
        for (final map in events) {
          final type = (map['event_type'] ?? '').toString();

          if (type == 'whatsapp') {
            whatsappCount++;
          } else if (type == 'share') {
            shareCount++;
          }

          final createdAtStr = map['created_at']?.toString();
          DateTime createdAt;
          try {
            createdAt = DateTime.parse(
                    createdAtStr ?? DateTime.now().toIso8601String())
                .toLocal();
          } catch (_) {
            createdAt = DateTime.now();
          }

          final hour = createdAt.hour;
          hourlyCounts[hour] = (hourlyCounts[hour] ?? 0) + 1;
        }

        final sortedHours = hourlyCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final top = <_HourBucket>[];
        for (var i = 0; i < sortedHours.length && i < 3; i++) {
          top.add(_HourBucket(hour: sortedHours[i].key, count: sortedHours[i].value));
        }
        _topHours = top;
      }

      // ---- 3) Build last 7 days series from aggregated views ----
      final List<_DailyViews> last7 = [];
      for (int i = 0; i < 7; i++) {
        final day = last7Start.add(Duration(days: i));
        final dayKey = DateTime(day.year, day.month, day.day);
        last7.add(
          _DailyViews(
            date: dayKey,
            views: viewsPerDay[dayKey] ?? 0,
          ),
        );
      }

      // ---- 4) Build totals + breakdown ----
      final int actionsTotal =
          totalCalls + totalDirections + whatsappCount + shareCount;

      final Map<String, int> counts = {
        'view': totalViews,
        'call': totalCalls,
        'directions': totalDirections,
        'whatsapp': whatsappCount,
        'share': shareCount,
      };

      // ---- 5) Build leads from events (lookup profile names) ----
      final leads = await _buildLeadsFromEvents(events);

      // ---- 6) Competitor benchmarking (category-based) ----
      final category = _selectedCompany?['category']?.toString();
      await _loadBenchmarksForCompany(
        companyId: companyId,
        category: category,
        from30: from30DateOnly,
        myViews: totalViews,
        myActions: actionsTotal,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _viewsLast30 = totalViews;
        _actionsLast30 = actionsTotal;
        _eventCounts = counts;
        _last7DaysViews = last7;
        _leads = leads;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error loading stats: $e';
      });
    }
  }

  Future<void> _loadBenchmarksForCompany({
    required String companyId,
    required String? category,
    required DateTime from30,
    required int myViews,
    required int myActions,
  }) async {
    try {
      if (category == null || category.isEmpty) {
        if (!mounted) return;
        setState(() {
          _peerCount = 0;
          _peerAvgViews = null;
          _peerAvgConversion = null;
          _viewsPercentile = null;
          _conversionPercentile = null;
        });
        return;
      }

      final peersRes =
          await supabase.from('companies').select('id').eq('category', category);

      if (peersRes is! List || peersRes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _peerCount = 0;
          _peerAvgViews = null;
          _peerAvgConversion = null;
          _viewsPercentile = null;
          _conversionPercentile = null;
        });
        return;
      }

      final peerIds = <String>[];
      for (final row in peersRes) {
        final map = row as Map<String, dynamic>;
        final id = map['id']?.toString();
        if (id != null && id.isNotEmpty) peerIds.add(id);
      }

      if (peerIds.length < 3) {
        if (!mounted) return;
        setState(() {
          _peerCount = peerIds.length;
          _peerAvgViews = null;
          _peerAvgConversion = null;
          _viewsPercentile = null;
          _conversionPercentile = null;
        });
        return;
      }

      final statsRes = await supabase
          .from('company_daily_stats')
          .select('company_id, views, calls, directions, date')
          .gte('date', from30.toIso8601String())
          .filter('company_id', 'in', peerIds.toList());

      if (statsRes is! List) return;

      final Map<String, _CompanyAgg> aggByCompany = {};
      for (final row in statsRes) {
        final map = row as Map<String, dynamic>;
        final cid = map['company_id']?.toString();
        if (cid == null) continue;

        final views =
            (map['views'] is num) ? (map['views'] as num).toInt() : 0;
        final calls =
            (map['calls'] is num) ? (map['calls'] as num).toInt() : 0;
        final directions = (map['directions'] is num)
            ? (map['directions'] as num).toInt()
            : 0;

        final agg = aggByCompany.putIfAbsent(cid, () => _CompanyAgg());
        agg.views += views;
        agg.actions += calls + directions;
      }

      if (aggByCompany.isEmpty) {
        if (!mounted) return;
        setState(() {
          _peerCount = 0;
          _peerAvgViews = null;
          _peerAvgConversion = null;
          _viewsPercentile = null;
          _conversionPercentile = null;
        });
        return;
      }

      final peerViewsList = <double>[];
      final peerConvList = <double>[];

      double sumViews = 0;
      double sumConv = 0;

      for (final entry in aggByCompany.entries) {
        final v = entry.value.views.toDouble();
        final a = entry.value.actions.toDouble();
        final conv = v == 0 ? 0.0 : a / v;

        sumViews += v;
        sumConv += conv;

        peerViewsList.add(v);
        peerConvList.add(conv);
      }

      final myViewsDouble = myViews.toDouble();
      final myConv = myViews == 0 ? 0.0 : myActions / myViewsDouble;

      int viewsBetterOrEqual = 0;
      int convBetterOrEqual = 0;

      for (int i = 0; i < peerViewsList.length; i++) {
        if (peerViewsList[i] <= myViewsDouble) viewsBetterOrEqual++;
        if (peerConvList[i] <= myConv) convBetterOrEqual++;
      }

      final peerCount = peerViewsList.length;
      final avgViews = sumViews / peerCount;
      final avgConv = sumConv / peerCount;

      if (!mounted) return;
      setState(() {
        _peerCount = peerCount;
        _peerAvgViews = avgViews;
        _peerAvgConversion = avgConv;
        _viewsPercentile = (viewsBetterOrEqual / peerCount) * 100.0;
        _conversionPercentile = (convBetterOrEqual / peerCount) * 100.0;
      });
    } catch (_) {
      // silently skip benchmark
    }
  }

  Future<List<_LeadEvent>> _buildLeadsFromEvents(
      List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return [];

    final userIds = <String>{};
    for (final ev in events) {
      final uid = ev['user_id']?.toString();
      if (uid != null && uid.isNotEmpty) userIds.add(uid);
    }

    final Map<String, String> nameByUserId = {};
    if (userIds.isNotEmpty) {
      final profilesRes = await supabase
          .from('profiles')
          .select('id, full_name')
          .filter('id', 'in', userIds.toList());

      if (profilesRes is List) {
        for (final row in profilesRes) {
          final map = row as Map<String, dynamic>;
          final id = map['id']?.toString();
          if (id == null) continue;
          final name = (map['full_name'] ?? 'B-Hive user').toString().trim();
          nameByUserId[id] = name.isEmpty ? 'B-Hive user' : name;
        }
      }
    }

    final List<_LeadEvent> leads = [];
    for (final ev in events) {
      final type = (ev['event_type'] ?? '').toString();
      final createdAtStr = ev['created_at']?.toString();
      DateTime createdAt;
      try {
        createdAt = DateTime.parse(
                createdAtStr ?? DateTime.now().toIso8601String())
            .toLocal();
      } catch (_) {
        createdAt = DateTime.now();
      }

      final uid = ev['user_id']?.toString();
      final userName =
          uid != null ? (nameByUserId[uid] ?? 'Someone on B-Hive') : null;

      final quality = _computeLeadQuality(type);

      leads.add(
        _LeadEvent(
          userName: userName,
          eventType: type,
          actionLabel: _mapEventTypeToLabel(type),
          createdAt: createdAt,
          qualityScore: quality.score,
          qualityLabel: quality.label,
        ),
      );
    }

    return leads;
  }

  double get _conversionRate {
    if (_viewsLast30 == 0) return 0;
    return _actionsLast30 / _viewsLast30;
  }

  _LeadQuality _computeLeadQuality(String type) {
    switch (type) {
      case 'call':
      case 'whatsapp':
        return _LeadQuality(score: 3, label: 'High intent');
      case 'directions':
      case 'share':
        return _LeadQuality(score: 2, label: 'Interested');
      case 'view':
      default:
        return _LeadQuality(score: 1, label: 'Browsing');
    }
  }

  Color _qualityColor(int score) {
    if (score >= 3) return Colors.greenAccent;
    if (score == 2) return Colors.orangeAccent;
    return Colors.white38;
  }

  String _mapEventTypeToLabel(String type) {
    switch (type) {
      case 'view':
        return 'Viewed your profile';
      case 'call':
        return 'Tapped Call';
      case 'whatsapp':
        return 'Opened WhatsApp chat';
      case 'directions':
        return 'Opened Directions';
      case 'share':
        return 'Shared your profile';
      default:
        return 'Engaged with your business';
    }
  }

  String _formatShortDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    final date =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString()}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date  •  $time';
  }

  String _formatHourRange(int hour) {
    final start = hour % 24;
    final end = (hour + 1) % 24;
    final startStr = '${start.toString().padLeft(2, '0')}:00';
    final endStr = '${end.toString().padLeft(2, '0')}:00';
    return '$startStr – $endStr';
  }

  String _buildInsightsText() {
    if (_viewsLast30 == 0) {
      return 'You have no views in the last 30 days yet.\n\n'
          'Share your profile link or ask customers to search for your business in the app to start seeing stats.';
    }

    final buffer = StringBuffer();

    buffer.writeln('Here are some insights based on the last 30 days:\n');

    buffer.writeln(
        '• Your business had $_viewsLast30 profile views and $_actionsLast30 actions (calls, WhatsApps, directions and shares).');

    if (_conversionRate > 0.3) {
      buffer.writeln(
          '• Your conversion rate is ${(100 * _conversionRate).toStringAsFixed(1)}%. That means a high percentage of people who view your profile also take action — great job!');
    } else if (_conversionRate > 0.1) {
      buffer.writeln(
          '• Your conversion rate is ${(100 * _conversionRate).toStringAsFixed(1)}%. This is decent, but you could improve by making sure your phone, address and description are clear and inviting.');
    } else {
      buffer.writeln(
          '• Your conversion rate is only ${(100 * _conversionRate).toStringAsFixed(1)}%. People are viewing your profile but not taking action.\n  '
          'Consider improving your description, adding a strong slogan, or updating your contact details.');
    }

    final calls = _eventCounts['call'] ?? 0;
    final whatsapp = _eventCounts['whatsapp'] ?? 0;
    final directions = _eventCounts['directions'] ?? 0;
    final shares = _eventCounts['share'] ?? 0;

    if (calls > 0) buffer.writeln('• You received $calls tap(s) on the Call button.');
    if (whatsapp > 0) buffer.writeln('• You received $whatsapp WhatsApp tap(s).');
    if (directions > 0) {
      buffer.writeln('• Directions to your business were opened $directions time(s).');
    }
    if (shares > 0) buffer.writeln('• Your profile was shared $shares time(s).');

    if (calls == 0 && whatsapp == 0 && directions == 0 && shares == 0) {
      buffer.writeln(
          '• People are viewing your profile but not using the action buttons yet. Make sure your contact info is complete and easy to read.');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_companies.isEmpty) {
      return const Center(
        child: Text(
          'No businesses are linked to your account yet.\n\nAdd a business first to see statistics.',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }

    final selected = _selectedCompany!;
    final name = selected['name']?.toString() ?? 'Your business';
    final isPaid = selected['is_paid'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Company selector row
        Row(
          children: [
            const Expanded(
              child: Text(
                'Stats for:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
            if (_companies.length > 1)
              DropdownButton<Map<String, dynamic>>(
                value: _selectedCompany,
                dropdownColor: const Color(0xFF020617),
                style: const TextStyle(color: Colors.white),
                iconEnabledColor: Colors.white,
                items: _companies
                    .map(
                      (c) => DropdownMenuItem<Map<String, dynamic>>(
                        value: c,
                        child: Text(c['name']?.toString() ?? 'Business'),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() {
                    _selectedCompany = value;
                  });
                  await _loadStatsForCompany(value['id'].toString());
                },
              )
            else
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        _buildSubscriptionBanner(isPaid),
        const SizedBox(height: 12),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: isPaid ? _buildPaidDashboard() : _buildFreeDashboard(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionBanner(bool isPaid) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid ? Colors.greenAccent : Colors.amberAccent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPaid ? 'BHive Business — Verified' : 'BHive Business — Free plan',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (isPaid)
                const Icon(
                  Icons.verified,
                  size: 18,
                  color: Colors.greenAccent,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isPaid
                ? 'You have full access to your analytics dashboard and leads.'
                : 'You can see a basic view count. Upgrade to unlock full analytics, conversion stats and leads.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openSubscriptionPage,
              child: Text(
                isPaid ? 'Manage Subscription' : 'Upgrade to unlock full stats',
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPaidDashboard() {
    return [
      Row(
        children: [
          Expanded(
            child: _StatCard(
              title: 'Views (30 days)',
              value: _viewsLast30.toString(),
              subtitle: 'Profile views',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              title: 'Actions (30 days)',
              value: _actionsLast30.toString(),
              subtitle: 'Calls, WhatsApp,\nDirections, Shares',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              title: 'Conversion',
              value: '${(_conversionRate * 100).toStringAsFixed(1)}%',
              subtitle: 'Actions / Views',
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildFunnelCard(),
      const SizedBox(height: 16),
      _buildActionsBreakdownCard(),
      const SizedBox(height: 16),
      _buildViewsHistoryCard(),
      const SizedBox(height: 16),
      _buildPeakTimesCard(),
      const SizedBox(height: 16),
      _buildInsightsCard(),
      const SizedBox(height: 16),
      _buildBenchmarkCard(),
      const SizedBox(height: 16),
      _buildLeadsCard(context),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildFreeDashboard() {
    return [
      Row(
        children: [
          Expanded(
            child: _StatCard(
              title: 'Views (30 days)',
              value: _viewsLast30.toString(),
              subtitle: 'Basic teaser analytics',
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildUpgradeTeaserCard(),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildUpgradeTeaserCard() {
    return _CardContainer(
      title: 'Unlock your full analytics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Upgrade your business to a verified BHive subscription to see:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          SizedBox(height: 8),
          Text(
            '• Conversion funnel from views to actions\n'
            '• Detailed actions breakdown (calls, WhatsApp, directions, shares)\n'
            '• Views history for the last 7 days\n'
            '• Peak times when customers are most active\n'
            '• Category benchmark against similar businesses\n'
            '• A timeline of recent leads with quality indicators',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFunnelCard() {
    final views = _viewsLast30;
    final calls = _eventCounts['call'] ?? 0;
    final whatsapp = _eventCounts['whatsapp'] ?? 0;
    final directions = _eventCounts['directions'] ?? 0;
    final shares = _eventCounts['share'] ?? 0;

    final actionsTotal = _actionsLast30;
    final contactClicks = calls + whatsapp;
    final visitIntent = directions;

    double _rate(int top, int bottom) {
      if (bottom == 0) return 0;
      return (top / bottom) * 100.0;
    }

    return _CardContainer(
      title: 'Conversion funnel (last 30 days)',
      child: Column(
        children: [
          _FunnelRow(
            label: 'Views',
            value: views,
            base: views,
            percentOfPrevious: 100,
          ),
          const SizedBox(height: 8),
          _FunnelRow(
            label: 'Any action',
            value: actionsTotal,
            base: views,
            percentOfPrevious: _rate(actionsTotal, views),
          ),
          const SizedBox(height: 8),
          _FunnelRow(
            label: 'Contact clicks (Call + WhatsApp)',
            value: contactClicks,
            base: actionsTotal == 0 ? views : actionsTotal,
            percentOfPrevious: actionsTotal == 0
                ? _rate(contactClicks, views)
                : _rate(contactClicks, actionsTotal),
          ),
          const SizedBox(height: 8),
          _FunnelRow(
            label: 'Directions opened',
            value: visitIntent,
            base: contactClicks == 0 ? views : contactClicks,
            percentOfPrevious: contactClicks == 0
                ? _rate(visitIntent, views)
                : _rate(visitIntent, contactClicks),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsBreakdownCard() {
    final calls = _eventCounts['call'] ?? 0;
    final whatsapp = _eventCounts['whatsapp'] ?? 0;
    final directions = _eventCounts['directions'] ?? 0;
    final shares = _eventCounts['share'] ?? 0;

    return _CardContainer(
      title: 'Actions breakdown (30 days)',
      child: Column(
        children: [
          _ActionRow(label: 'Calls', value: calls),
          _ActionRow(label: 'WhatsApp', value: whatsapp),
          _ActionRow(label: 'Directions opened', value: directions),
          _ActionRow(label: 'Profile shares', value: shares),
        ],
      ),
    );
  }

  Widget _buildViewsHistoryCard() {
    return _CardContainer(
      title: 'Views (last 7 days)',
      child: _last7DaysViews.isEmpty
          ? const Text(
              'No views in the last 7 days yet.',
              style: TextStyle(color: Colors.white70),
            )
          : Column(
              children: _last7DaysViews
                  .map(
                    (d) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              _formatShortDate(d.date),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _maxViewsInLast7 == 0
                                  ? 0
                                  : d.views / _maxViewsInLast7,
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            d.views.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  int get _maxViewsInLast7 {
    if (_last7DaysViews.isEmpty) return 0;
    int max = 0;
    for (final d in _last7DaysViews) {
      if (d.views > max) max = d.views;
    }
    return max;
  }

  Widget _buildPeakTimesCard() {
    return _CardContainer(
      title: 'Peak activity times (last 30 days)',
      child: _topHours.isEmpty
          ? const Text(
              'We don’t have enough data yet to detect peak times.\n\n'
              'As more people view and interact with your profile, we’ll show you when they are most active.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          : Column(
              children: _topHours
                  .map(
                    (bucket) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              _formatHourRange(bucket.hour),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _maxTopHourCount == 0
                                  ? 0
                                  : bucket.count / _maxTopHourCount,
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${bucket.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  int get _maxTopHourCount {
    if (_topHours.isEmpty) return 0;
    int max = 0;
    for (final h in _topHours) {
      if (h.count > max) max = h.count;
    }
    return max;
  }

  Widget _buildInsightsCard() {
    return _CardContainer(
      title: 'Insights',
      child: Text(
        _buildInsightsText(),
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildBenchmarkCard() {
    if (_peerCount < 3 ||
        _peerAvgViews == null ||
        _peerAvgConversion == null ||
        _viewsPercentile == null ||
        _conversionPercentile == null) {
      return _CardContainer(
        title: 'Category benchmark',
        child: const Text(
          'We will show how you compare to other businesses in your category once there is enough data.\n\n'
          'As more businesses in your category receive views and actions, this section will unlock automatically.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    final myViews = _viewsLast30.toDouble();
    final myConv = _conversionRate;
    final avgViews = _peerAvgViews!;
    final avgConv = _peerAvgConversion!;

    String _relative(double mine, double avg) {
      if (avg == 0) return 'similar to';
      final diff = ((mine - avg) / avg) * 100.0;
      if (diff > 15) return 'higher than';
      if (diff < -15) return 'lower than';
      return 'similar to';
    }

    return _CardContainer(
      title: 'Category benchmark',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Based on $_peerCount businesses in your category:',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _BenchmarkRow(
            label: 'Views (30 days)',
            yourValue: myViews.toStringAsFixed(0),
            avgValue: avgViews.toStringAsFixed(0),
            relativeText: _relative(myViews, avgViews),
            percentile: _viewsPercentile?.toStringAsFixed(0),
          ),
          const SizedBox(height: 6),
          _BenchmarkRow(
            label: 'Conversion rate',
            yourValue: '${(myConv * 100).toStringAsFixed(1)}%',
            avgValue: '${(avgConv * 100).toStringAsFixed(1)}%',
            relativeText: _relative(myConv, avgConv),
            percentile: _conversionPercentile?.toStringAsFixed(0),
          ),
          const SizedBox(height: 8),
          const Text(
            'Percentiles tell you what percentage of businesses you are performing better than.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadsCard(BuildContext context) {
    return _CardContainer(
      title: 'Recent leads (last 30 days)',
      child: _leads.isEmpty
          ? const Text(
              'No leads in the last 30 days yet.\n\n'
              'When people view your profile, call, WhatsApp, get directions or share your business, they will appear here with a lead quality indicator.',
              style: TextStyle(color: Colors.white70),
            )
          : Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _leads.length > 5 ? 5 : _leads.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final lead = _leads[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lead.actionLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDateTime(lead.createdAt),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _qualityColor(lead.qualityScore)
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _qualityColor(lead.qualityScore),
                                  ),
                                ),
                                child: Text(
                                  lead.qualityLabel,
                                  style: TextStyle(
                                    color: _qualityColor(lead.qualityScore),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (lead.userName != null)
                            Text(
                              lead.userName!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                if (_leads.length > 5) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullLeadsScreen(
                              leads: _leads,
                              companyName:
                                  _selectedCompany?['name']?.toString() ??
                                      'Your business',
                            ),
                          ),
                        );
                      },
                      child: Text('View all leads (${_leads.length})'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

// Helper models & widgets

class _DailyViews {
  final DateTime date;
  final int views;

  _DailyViews({
    required this.date,
    required this.views,
  });
}

class _HourBucket {
  final int hour;
  final int count;

  _HourBucket({
    required this.hour,
    required this.count,
  });
}

class _CompanyAgg {
  int views = 0;
  int actions = 0;
}

class _LeadQuality {
  final int score;
  final String label;

  _LeadQuality({
    required this.score,
    required this.label,
  });
}

class _LeadEvent {
  final String? userName;
  final String eventType;
  final String actionLabel;
  final DateTime createdAt;
  final int qualityScore;
  final String qualityLabel;

  _LeadEvent({
    required this.userName,
    required this.eventType,
    required this.actionLabel,
    required this.createdAt,
    required this.qualityScore,
    required this.qualityLabel,
  });
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return _CardContainer(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  final String label;
  final int value;
  final int base;
  final double percentOfPrevious;

  const _FunnelRow({
    super.key,
    required this.label,
    required this.value,
    required this.base,
    required this.percentOfPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = base == 0 ? 0.0 : value / base;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percentOfPrevious.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: Colors.white12,
        ),
      ],
    );
  }
}

class _BenchmarkRow extends StatelessWidget {
  final String label;
  final String yourValue;
  final String avgValue;
  final String relativeText;
  final String? percentile;

  const _BenchmarkRow({
    super.key,
    required this.label,
    required this.yourValue,
    required this.avgValue,
    required this.relativeText,
    this.percentile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'You: $yourValue',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            Text(
              'Category avg: $avgValue',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
            Text(
              'You are $relativeText similar businesses',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
            if (percentile != null)
              Text(
                'You perform better than ~${percentile!}% of businesses',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final int value;

  const _ActionRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  final String title;
  final Widget child;

  const _CardContainer({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class FullLeadsScreen extends StatelessWidget {
  final List<_LeadEvent> leads;
  final String companyName;

  const FullLeadsScreen({
    super.key,
    required this.leads,
    required this.companyName,
  });

  Color _qualityColorForLead(_LeadEvent lead) {
    if (lead.qualityScore >= 3) return Colors.greenAccent;
    if (lead.qualityScore == 2) return Colors.orangeAccent;
    return Colors.white38;
  }

  String _formatDateTimeLocal(DateTime dt) {
    final date =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString()}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date  •  $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Leads — $companyName'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: HiveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: leads.isEmpty
                ? const Center(
                    child: Text(
                      'No leads in the last 30 days yet.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.separated(
                    itemCount: leads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final lead = leads[index];
                      final chipColor = _qualityColorForLead(lead);

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lead.actionLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatDateTimeLocal(lead.createdAt),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chipColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: chipColor),
                                  ),
                                  child: Text(
                                    lead.qualityLabel,
                                    style: TextStyle(
                                      color: chipColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (lead.userName != null)
                              Text(
                                lead.userName!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

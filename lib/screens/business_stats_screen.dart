// lib/screens/business_stats_screen.dart
import 'package:flutter/material.dart';
import '../widgets/hive_background.dart';
import '../supabase_client.dart';

class BusinessStatsScreen extends StatefulWidget {
  const BusinessStatsScreen({super.key});

  @override
  State<BusinessStatsScreen> createState() => _BusinessStatsScreenState();
}

class _BusinessStatsScreenState extends State<BusinessStatsScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _companies = [];
  Map<String, dynamic>? _selectedCompany;

  // Stats
  int _viewsLast30 = 0;
  int _actionsLast30 = 0;
  Map<String, int> _eventCounts = {};
  List<_DailyViews> _last7DaysViews = [];

  // Leads (built from company_events + profiles)
  List<_LeadEvent> _leads = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'You must be logged in to view business stats.';
      });
      return;
    }

    try {
      // 1) Load companies owned by this user
      final companies = await supabase
          .from('companies')
          .select()
          .eq('owner_id', user.id)
          .order('inserted_at', ascending: false);

      if (companies == null || companies.isEmpty) {
        setState(() {
          _loading = false;
          _companies = [];
          _selectedCompany = null;
        });
        return;
      }

      final firstCompany = (companies.first as Map<String, dynamic>);

      setState(() {
        _companies = companies
            .map<Map<String, dynamic>>((e) => e as Map<String, dynamic>)
            .toList();
        _selectedCompany = firstCompany;
      });

      await _loadStatsForCompany(firstCompany['id'].toString());
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error loading companies: $e';
      });
    }
  }

  Future<void> _loadStatsForCompany(String companyId) async {
    setState(() {
      _loading = true;
      _error = null;
      _viewsLast30 = 0;
      _actionsLast30 = 0;
      _eventCounts = {};
      _last7DaysViews = [];
      _leads = [];
    });

    try {
      final now = DateTime.now();
      final from30 = now.subtract(const Duration(days: 30));
      final from30DateOnly =
          DateTime(from30.year, from30.month, from30.day); // strip time
      final from30Str = from30DateOnly.toIso8601String();

      // ---- 1) Get aggregated daily stats (company_daily_stats) ----
      final dailyStats = await supabase
          .from('company_daily_stats')
          .select('date, views, calls, directions')
          .eq('company_id', companyId)
          .gte('date', from30Str)
          .order('date');

      int totalViews = 0;
      int totalCalls = 0;
      int totalDirections = 0;
      final Map<DateTime, int> viewsPerDay = {};

      final last7Start =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

      if (dailyStats is List) {
        for (final row in dailyStats) {
          final map = row as Map<String, dynamic>;
          final dateStr = map['date']?.toString();
          if (dateStr == null) continue;

          // Postgres date often comes as 'YYYY-MM-DD'
          final date = DateTime.parse(dateStr);

          final views = (map['views'] is num) ? (map['views'] as num).toInt() : 0;
          final calls = (map['calls'] is num) ? (map['calls'] as num).toInt() : 0;
          final directions =
              (map['directions'] is num) ? (map['directions'] as num).toInt() : 0;

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
        events = eventsRes.map<Map<String, dynamic>>(
          (e) => Map<String, dynamic>.from(e as Map),
        ).toList();

        for (final map in events) {
          final type = (map['event_type'] ?? '').toString();

          if (type == 'whatsapp') {
            whatsappCount++;
          } else if (type == 'share') {
            shareCount++;
          }
        }
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

      setState(() {
        _loading = false;
        _viewsLast30 = totalViews;
        _actionsLast30 = actionsTotal;
        _eventCounts = counts;
        _last7DaysViews = last7;
        _leads = leads;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error loading stats: $e';
      });
    }
  }

  Future<List<_LeadEvent>> _buildLeadsFromEvents(
      List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return [];

    // Collect user_ids from events
    final userIds = <String>{};
    for (final ev in events) {
      final uid = ev['user_id']?.toString();
      if (uid != null && uid.isNotEmpty) {
        userIds.add(uid);
      }
    }

    // Load profiles for those leads
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

    // Map events → _LeadEvent list (timeline)
    final List<_LeadEvent> leads = [];
    for (final ev in events) {
      final type = (ev['event_type'] ?? '').toString();
      final createdAtStr = ev['created_at']?.toString();
      DateTime createdAt;
      try {
        createdAt = DateTime.parse(createdAtStr ?? DateTime.now().toIso8601String());
      } catch (_) {
        createdAt = DateTime.now();
      }

      final uid = ev['user_id']?.toString();
      final userName = uid != null ? (nameByUserId[uid] ?? 'Someone on B-Hive') : null;

      leads.add(
        _LeadEvent(
          userName: userName,
          eventType: type,
          actionLabel: _mapEventTypeToLabel(type),
          createdAt: createdAt,
        ),
      );
    }

    return leads;
  }

  double get _conversionRate {
    if (_viewsLast30 == 0) return 0;
    return _actionsLast30 / _viewsLast30;
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

    if (calls > 0) {
      buffer.writeln('• You received $calls tap(s) on the Call button.');
    }
    if (whatsapp > 0) {
      buffer.writeln('• You received $whatsapp WhatsApp tap(s).');
    }
    if (directions > 0) {
      buffer.writeln('• Directions to your business were opened $directions time(s).');
    }
    if (shares > 0) {
      buffer.writeln('• Your profile was shared $shares time(s).');
    }

    if (calls == 0 && whatsapp == 0 && directions == 0 && shares == 0) {
      buffer.writeln(
          '• People are viewing your profile but not using the action buttons yet. Make sure your contact info is complete and easy to read.');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final bg = HiveBackground(
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
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Business Stats'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: bg,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Company selector
        Row(
          children: [
            Expanded(
              child: Text(
                'Stats for:',
                style: const TextStyle(
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

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Summary cards row
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
                        value:
                            '${(_conversionRate * 100).toStringAsFixed(1)}%',
                        subtitle: 'Actions / Views',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Actions breakdown
                _buildActionsBreakdownCard(),
                const SizedBox(height: 16),

                // Views over last 7 days
                _buildViewsHistoryCard(),
                const SizedBox(height: 16),

                // Insights
                _buildInsightsCard(),
                const SizedBox(height: 16),

                // 💥 NEW: Leads timeline (dashboard style)
                _buildLeadsCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsBreakdownCard() {
    final calls = _eventCounts['call'] ?? 0;
    final whatsapp = _eventCounts['whatsapp'] ?? 0;
    final directions = _eventCounts['directions'] ?? 0;
    final shares = _eventCounts['share'] ?? 0;

    return _CardContainer(
      title: 'Actions Breakdown (30 days)',
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

  Widget _buildInsightsCard() {
    return _CardContainer(
      title: 'Insights',
      child: Text(
        _buildInsightsText(),
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildLeadsCard() {
    return _CardContainer(
      title: 'Recent leads (last 30 days)',
      child: _leads.isEmpty
          ? const Text(
              'No leads in the last 30 days yet.\n\n'
              'When people view your profile, call, WhatsApp, get directions or share your business, they will appear here.',
              style: TextStyle(color: Colors.white70),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _leads.length,
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
                      // First row: action + time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              lead.actionLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDateTime(lead.createdAt),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
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

class _LeadEvent {
  final String? userName;
  final String eventType;
  final String actionLabel;
  final DateTime createdAt;

  _LeadEvent({
    required this.userName,
    required this.eventType,
    required this.actionLabel,
    required this.createdAt,
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

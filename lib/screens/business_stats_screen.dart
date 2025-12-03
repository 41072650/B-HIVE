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

  // Stats (30 days)
  int _viewsLast30 = 0;
  int _actionsLast30 = 0;
  Map<String, int> _eventCounts = {};

  // Stats (7 days)
  int _viewsLast7 = 0;
  int _actionsLast7 = 0;

  // For small "chart" of last 7 days
  List<_DailyViews> _last7DaysViews = [];

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
      _viewsLast7 = 0;
      _actionsLast7 = 0;
      _eventCounts = {};
      _last7DaysViews = [];
    });

    try {
      final now = DateTime.now();
      final from30 = now.subtract(const Duration(days: 30));
      // Strip time for date-only comparison
      final from30DateOnly = DateTime(from30.year, from30.month, from30.day);
      final from30Str = from30DateOnly.toIso8601String();

      // We'll use this to detect "last 7 days"
      final today = DateTime(now.year, now.month, now.day);
      final last7Start = today.subtract(const Duration(days: 6)); // inclusive

      // ---- 1) Get aggregated daily stats (company_daily_stats) ----
      final dailyStats = await supabase
          .from('company_daily_stats')
          .select('date, views, calls, directions')
          .eq('company_id', companyId)
          .gte('date', from30Str)
          .order('date');

      int totalViews30 = 0;
      int totalCalls30 = 0;
      int totalDirections30 = 0;

      int viewsLast7 = 0;           // views for last 7 days
      int callDirLast7 = 0;         // calls + directions for last 7 days

      final Map<DateTime, int> viewsPerDay = {};

      if (dailyStats is List) {
        for (final row in dailyStats) {
          final map = row as Map<String, dynamic>;
          final dateStr = map['date']?.toString();
          if (dateStr == null) continue;

          // Postgres date often comes as 'YYYY-MM-DD'
          final date = DateTime.parse(dateStr);
          final dayKey = DateTime(date.year, date.month, date.day);

          final views = (map['views'] is num) ? (map['views'] as num).toInt() : 0;
          final calls = (map['calls'] is num) ? (map['calls'] as num).toInt() : 0;
          final directions = (map['directions'] is num)
              ? (map['directions'] as num).toInt()
              : 0;

          totalViews30 += views;
          totalCalls30 += calls;
          totalDirections30 += directions;

          viewsPerDay[dayKey] = (viewsPerDay[dayKey] ?? 0) + views;

          // If this day is within the last 7 days, add to 7-day counters
          if (!dayKey.isBefore(last7Start)) {
            viewsLast7 += views;
            callDirLast7 += (calls + directions);
          }
        }
      }

      // ---- 2) Get WhatsApp + share counts from company_events (last 30 days) ----
      int whatsappCount30 = 0;
      int shareCount30 = 0;

      int whatsappLast7 = 0;
      int shareLast7 = 0;

      final events = await supabase
          .from('company_events')
          .select('event_type, created_at')
          .eq('company_id', companyId)
          .gte('created_at', from30.toUtc().toIso8601String());

      if (events is List) {
        for (final row in events) {
          final map = row as Map<String, dynamic>;
          final type = (map['event_type'] ?? '').toString();
          final createdStr = map['created_at']?.toString();

          DateTime? created;
          if (createdStr != null) {
            // created_at is usually ISO8601; this is fine for comparison
            created = DateTime.tryParse(createdStr);
          }

          bool isInLast7 = false;
          if (created != null) {
            // Compare by date (ignore time)
            final d = DateTime(created.year, created.month, created.day);
            if (!d.isBefore(last7Start)) {
              isInLast7 = true;
            }
          }

          if (type == 'whatsapp') {
            whatsappCount30++;
            if (isInLast7) whatsappLast7++;
          } else if (type == 'share') {
            shareCount30++;
            if (isInLast7) shareLast7++;
          }
        }
      }

      // ---- 3) Build last 7 days series from aggregated views ----
      final List<_DailyViews> last7List = [];
      for (int i = 0; i < 7; i++) {
        final day = last7Start.add(Duration(days: i));
        final dayKey = DateTime(day.year, day.month, day.day);
        last7List.add(
          _DailyViews(
            date: dayKey,
            views: viewsPerDay[dayKey] ?? 0,
          ),
        );
      }

      // ---- 4) Build totals + breakdown ----
      final int actionsTotal30 =
          totalCalls30 + totalDirections30 + whatsappCount30 + shareCount30;

      final int actionsTotal7 =
          callDirLast7 + whatsappLast7 + shareLast7;

      final Map<String, int> counts = {
        'view': totalViews30,
        'call': totalCalls30,
        'directions': totalDirections30,
        'whatsapp': whatsappCount30,
        'share': shareCount30,
      };

      setState(() {
        _loading = false;
        _viewsLast30 = totalViews30;
        _actionsLast30 = actionsTotal30;
        _viewsLast7 = viewsLast7;
        _actionsLast7 = actionsTotal7;
        _eventCounts = counts;
        _last7DaysViews = last7List;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error loading stats: $e';
      });
    }
  }

  double get _conversionRate {
    if (_viewsLast30 == 0) return 0;
    return _actionsLast30 / _viewsLast30;
  }

  double get _conversionRate7 {
    if (_viewsLast7 == 0) return 0;
    return _actionsLast7 / _viewsLast7;
  }

  int get _maxViewsInLast7 {
    if (_last7DaysViews.isEmpty) return 0;
    int max = 0;
    for (final d in _last7DaysViews) {
      if (d.views > max) max = d.views;
    }
    return max;
  }

  String _formatShortDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  String _buildInsightsText() {
    if (_viewsLast30 == 0) {
      return 'You have no views in the last 30 days yet.\n\n'
          'Share your profile link or ask customers to search for your business in the app to start seeing stats.';
    }

    final buffer = StringBuffer();

    buffer.writeln('Here are some insights based on the last 30 days:');
    buffer.writeln('');

    buffer.writeln(
        '• Your business had $_viewsLast30 profile views and $_actionsLast30 actions (calls, WhatsApps, directions and shares).');

    // 1) Conversion quality (30 days)
    if (_conversionRate > 0.3) {
      buffer.writeln(
          '• Your 30-day conversion rate is ${(100 * _conversionRate).toStringAsFixed(1)}%. A high percentage of people who view your profile also take action — great job!');
    } else if (_conversionRate > 0.1) {
      buffer.writeln(
          '• Your 30-day conversion rate is ${(100 * _conversionRate).toStringAsFixed(1)}%. This is decent, but you could improve by making sure your phone, address and description are clear and inviting.');
    } else {
      buffer.writeln(
          '• Your 30-day conversion rate is only ${(100 * _conversionRate).toStringAsFixed(1)}%. People are viewing your profile but not taking action.\n  Consider improving your description, adding a strong slogan, or updating your contact details.');
    }

    // 2) Trend: last 7 days vs 30-day average
    if (_viewsLast7 > 0) {
      final expectedLast7 =
          (_viewsLast30 / 30.0) * 7.0; // if traffic was flat
      double ratio;
      if (expectedLast7 <= 0) {
        ratio = 1.0;
      } else {
        ratio = _viewsLast7 / expectedLast7;
      }

      if (ratio > 1.2) {
        buffer.writeln(
            '• Your traffic is trending UP: the last 7 days had more views than your 30-day average. Keep going — consider sharing your B-Hive profile link with more clients.');
      } else if (ratio < 0.8) {
        buffer.writeln(
            '• Your traffic is trending DOWN: the last 7 days had fewer views than your 30-day average. Try refreshing your business description or sharing your profile to boost visibility.');
      } else {
        buffer.writeln(
            '• Your traffic is fairly STABLE: the last 7 days are close to your 30-day average. Small changes to your profile can still improve results over time.');
      }
    }

    // 3) Recent conversion vs overall
    if (_viewsLast7 > 0 && _actionsLast7 > 0) {
      final conv7 = _conversionRate7 * 100;
      final conv30 = _conversionRate * 100;
      if (conv7 > conv30 + 5) {
        buffer.writeln(
            '• Your recent conversion (last 7 days: ${conv7.toStringAsFixed(1)}%) is HIGHER than your overall 30-day conversion. The changes you made recently might be working — keep them.');
      } else if (conv7 + 5 < conv30) {
        buffer.writeln(
            '• Your recent conversion (last 7 days: ${conv7.toStringAsFixed(1)}%) is LOWER than your 30-day average. Look at what changed in your profile or pricing and adjust if needed.');
      }
    }

    // 4) Action breakdown & tips
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
      buffer.writeln(
          '• Directions to your business were opened $directions time(s).');
    }
    if (shares > 0) {
      buffer.writeln(
          '• Your profile was shared $shares time(s). Word-of-mouth is helping you.');
    }

    if (calls == 0 && whatsapp == 0 && directions == 0 && shares == 0) {
      buffer.writeln(
          '• People are viewing your profile but not using the action buttons yet. Make sure your contact info is complete and easy to read.');
    }

    // 5) Top action type tip
    final Map<String, int> actionMap = {
      'Calls': calls,
      'WhatsApp': whatsapp,
      'Directions': directions,
      'Shares': shares,
    };

    String? topKey;
    int topValue = 0;
    actionMap.forEach((key, value) {
      if (value > topValue) {
        topValue = value;
        topKey = key;
      }
    });

    if (topKey != null && topValue > 0) {
      if (topKey == 'Calls') {
        buffer.writeln(
            '• Most people contact you via Calls. Make sure you answer promptly and consider adding business hours in your description.');
      } else if (topKey == 'WhatsApp') {
        buffer.writeln(
            '• Most people contact you via WhatsApp. You can set up a short welcome message and quick replies to convert leads faster.');
      } else if (topKey == 'Directions') {
        buffer.writeln(
            '• Many people open Directions. Consider adding parking info or landmarks in your description to make it easier to find you.');
      } else if (topKey == 'Shares') {
        buffer.writeln(
            '• Your profile is shared often. Encourage happy clients to keep sharing your B-Hive profile with others.');
      }
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
                // Summary cards row (30 days)
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
                        title: 'Conversion (30d)',
                        value: '${(_conversionRate * 100).toStringAsFixed(1)}%',
                        subtitle: 'Actions / Views',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Summary cards row (7 days)
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Views (7 days)',
                        value: _viewsLast7.toString(),
                        subtitle: 'Recent views',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        title: 'Actions (7 days)',
                        value: _actionsLast7.toString(),
                        subtitle: 'Recent actions',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        title: 'Conversion (7d)',
                        value: '${(_conversionRate7 * 100).toStringAsFixed(1)}%',
                        subtitle: 'Recent Actions / Views',
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

  Widget _buildInsightsCard() {
    return _CardContainer(
      title: 'Insights',
      child: Text(
        _buildInsightsText(),
        style: const TextStyle(color: Colors.white70),
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

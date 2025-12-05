// lib/screens/jobs_screen.dart
import 'package:flutter/material.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';

class JobsScreen extends StatefulWidget {
  final bool isBusiness;

  const JobsScreen({
    super.key,
    required this.isBusiness,
  });

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  bool _loading = true;
  String? _error;

  // 'find' = job search (everyone)
  // 'my'   = my company jobs (business only)
  String _mode = 'find';

  List<Map<String, dynamic>> _jobs = [];
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = supabase.auth.currentUser;

      // 1) Load ALL jobs
      final jobsRes = await supabase.from('jobs').select();
      final allJobs =
          List<Map<String, dynamic>>.from(jobsRes as List<dynamic>);

      // 2) Load ALL companies (id, owner_id, is_paid)
      final companiesRes =
          await supabase.from('companies').select('id, owner_id, is_paid');
      final allCompanies =
          List<Map<String, dynamic>>.from(companiesRes as List<dynamic>);

      // Build maps for quick lookup
      final Map<dynamic, Map<String, dynamic>> companyById = {};
      final Map<dynamic, bool> verifiedMap = {};

      for (final c in allCompanies) {
        final id = c['id'];
        companyById[id] = c;

        // Verified if company is paid
        final isVerified = c['is_paid'] == true;
        verifiedMap[id] = isVerified;
      }

      // 3) Keep only active jobs
      List<Map<String, dynamic>> filtered =
          allJobs.where((j) => j['is_active'] != false).toList();

      // 4) If "My Jobs" mode, keep only jobs whose company.owner_id == user.id
      if (_mode == 'my' && widget.isBusiness && user != null) {
        filtered = filtered.where((j) {
          final company = companyById[j['company_id']];
          if (company == null) return false;
          return company['owner_id'] == user.id;
        }).toList();
      }

      // 5) Search filter (title + location, case-insensitive)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        filtered = filtered.where((j) {
          final title =
              (j['title'] ?? '').toString().toLowerCase();
          final location =
              (j['location'] ?? '').toString().toLowerCase();
          return title.contains(q) || location.contains(q);
        }).toList();
      }

      // 6) Attach verification info from companies
      for (final j in filtered) {
        final cid = j['company_id'];
        j['company_is_verified'] = verifiedMap[cid] ?? false;
      }

      // 7) Sort by created_at DESC (newest first)
      filtered.sort((a, b) {
        final aDate = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      setState(() {
        _jobs = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load jobs: $e';
        _loading = false;
      });
    }
  }

  void _changeMode(String mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _loadJobs();
  }

  Future<void> _goToPostJob() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Load companies and find the first owned by this user
    final companiesRes =
        await supabase.from('companies').select('id, owner_id');
    final companies =
        List<Map<String, dynamic>>.from(companiesRes as List<dynamic>);

    final myCompanies =
        companies.where((c) => c['owner_id'] == user.id).toList();

    if (!mounted) return;

    if (myCompanies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need a business profile before posting jobs.'),
        ),
      );
      return;
    }

    final companyId = myCompanies.first['id'] as String;

    final result = await Navigator.of(context).pushNamed(
      '/post-job',
      arguments: companyId,
    );

    if (result == true) {
      if (widget.isBusiness) {
        setState(() => _mode = 'my');
      }
      _loadJobs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),

              // Mode selector + Post button (top row)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _ModeChip(
                      label: 'Find Jobs',
                      selected: _mode == 'find',
                      onTap: () => _changeMode('find'),
                    ),
                    const SizedBox(width: 8),
                    if (widget.isBusiness)
                      _ModeChip(
                        label: 'My Jobs',
                        selected: _mode == 'my',
                        onTap: () => _changeMode('my'),
                      ),
                    const Spacer(),
                    if (widget.isBusiness)
                      IconButton(
                        onPressed: _goToPostJob,
                        icon: const Icon(Icons.add),
                        tooltip: 'Post a Job',
                      ),
                  ],
                ),
              ),

              // Search bar – styled like company search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (value) {
                    _searchQuery = value.trim();
                    _loadJobs();
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search jobs (title or location)...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.4),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white70),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Content
              Expanded(
                child: _loading
                    ? ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(
                            height: 200,
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    : _error != null
                        ? ListView(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 200,
                                child: Center(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                        color: Colors.redAccent),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _jobs.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: 200,
                                    child: Center(
                                      child: Text(
                                        _mode == 'my'
                                            ? 'You have no job listings yet.'
                                            : 'No jobs found.',
                                        style: const TextStyle(
                                            color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.only(top: 8),
                                itemCount: _jobs.length,
                                itemBuilder: (context, index) {
                                  final job = _jobs[index];
                                  return _JobCard(job: job);
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.isBusiness
          ? FloatingActionButton.extended(
              onPressed: _goToPostJob,
              icon: const Icon(Icons.work_outline),
              label: const Text('Post Job'),
            )
          : null,
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color.fromARGB(255, 241, 178, 70);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? gold : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? gold : Colors.white70,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;

  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final title = job['title'] ?? '';
    final location = job['location'] ?? 'Location not specified';
    final type = job['employment_type'] ?? '';
    final createdAt =
        DateTime.tryParse((job['created_at'] ?? '').toString());

    final isVerified = job['company_is_verified'] == true;

    final subtitleParts = <String>[];
    if (type.isNotEmpty) subtitleParts.add(type);
    subtitleParts.add(location);

    const gold = Color.fromARGB(255, 241, 178, 70);

    // Leading avatar style similar to company list (but briefcase icon)
    final leadingAvatar = const CircleAvatar(
      backgroundColor: Colors.white24,
      child: Icon(Icons.work, color: Colors.white),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVerified ? gold : Colors.white24,
          width: isVerified ? 1.6 : 0.8,
        ),
        color: Colors.black.withOpacity(0.5),
      ),
      child: ListTile(
        leading: leadingAvatar,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitleParts.join(' • '),
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isVerified)
              const Icon(
                Icons.verified,
                size: 18,
                color: Colors.greenAccent, // same as company cards
              ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        onTap: () {
          // TODO: Job detail screen later
        },
      ),
    );
  }
}

// lib/screens/company_list_screen.dart
import 'package:flutter/material.dart';
import '../supabase_client.dart';
import 'company_detail_screen.dart';
import '../widgets/hive_background.dart';

enum CompanySort { newest, rating, name }

class CompanyListScreen extends StatefulWidget {
  const CompanyListScreen({super.key});

  @override
  State<CompanyListScreen> createState() => _CompanyListScreenState();
}

class _CompanyListScreenState extends State<CompanyListScreen> {
  bool _loading = true;
  List<dynamic> _companies = [];

  String _searchQuery = "";
  String _selectedCategoryFilter = 'All';
  CompanySort _sortBy = CompanySort.newest;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _loading = true);

    final response = await supabase
        .from('companies')
        .select()
        .order('inserted_at', ascending: false);

    setState(() {
      _companies = response;
      _loading = false;
    });
  }

  // Build list of categories present in data + "All"
  List<String> get _categoryOptions {
    final set = <String>{};
    for (final c in _companies) {
      final cat = (c['category'] ?? '').toString();
      if (cat.isNotEmpty) set.add(cat);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  DateTime _parseDate(dynamic v) {
    if (v == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  List<dynamic> get _filteredCompanies {
    final query = _searchQuery.trim().toLowerCase();

    // 1) Filter by search and category
    final filtered = _companies.where((company) {
      final name = (company['name'] ?? '').toString().toLowerCase();
      final category = (company['category'] ?? '').toString().toLowerCase();
      final city = (company['city'] ?? '').toString().toLowerCase();

      final matchesSearch = query.isEmpty ||
          name.contains(query) ||
          category.contains(query) ||
          city.contains(query);

      final matchesCategory = _selectedCategoryFilter == 'All' ||
          (company['category'] ?? '') == _selectedCategoryFilter;

      return matchesSearch && matchesCategory;
    }).toList();

    // 2) Sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case CompanySort.newest:
          final da = _parseDate(a['inserted_at']);
          final db = _parseDate(b['inserted_at']);
          return db.compareTo(da); // newest first
        case CompanySort.rating:
          final ra = (a['rating_avg'] ?? 0).toDouble();
          final rb = (b['rating_avg'] ?? 0).toDouble();
          return rb.compareTo(ra); // highest rating first
        case CompanySort.name:
          final na = (a['name'] ?? '').toString().toLowerCase();
          final nb = (b['name'] ?? '').toString().toLowerCase();
          return na.compareTo(nb); // A–Z
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Companies', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _loadCompanies,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: HiveBackground(
        child: Column(
          children: [
            const SizedBox(height: 70), // space under AppBar

            // 🔍 SEARCH BAR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search companies...",
                  hintStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.4),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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

            const SizedBox(height: 10),

            // 🏷 CATEGORY + SORT ROW
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Category filter
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategoryFilter,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle:
                            const TextStyle(color: Colors.white70, fontSize: 12),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.4),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white24),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white70),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      dropdownColor: const Color(0xFF020617),
                      style: const TextStyle(color: Colors.white),
                      items: _categoryOptions
                          .map(
                            (cat) => DropdownMenuItem<String>(
                              value: cat,
                              child: Text(cat),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedCategoryFilter = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Sort dropdown
                  Expanded(
                    child: DropdownButtonFormField<CompanySort>(
                      value: _sortBy,
                      decoration: InputDecoration(
                        labelText: 'Sort by',
                        labelStyle:
                            const TextStyle(color: Colors.white70, fontSize: 12),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.4),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white24),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white70),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      dropdownColor: const Color(0xFF020617),
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(
                          value: CompanySort.newest,
                          child: Text('Newest'),
                        ),
                        DropdownMenuItem(
                          value: CompanySort.rating,
                          child: Text('Top rated'),
                        ),
                        DropdownMenuItem(
                          value: CompanySort.name,
                          child: Text('A–Z'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _sortBy = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // LIST
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _filteredCompanies.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching companies.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: _filteredCompanies.length,
                          itemBuilder: (context, index) {
                            final company = _filteredCompanies[index]
                                as Map<String, dynamic>;
                            final ratingAvg =
                                (company['rating_avg'] ?? 0).toDouble();
                            final ratingCount =
                                (company['rating_count'] ?? 0) as int;

                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.white24,
                                child: Icon(Icons.business,
                                    color: Colors.white),
                              ),
                              title: Text(
                                company['name'] ?? '',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${company['category'] ?? ''} • ${company['city'] ?? ''}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: ratingCount == 0
                                  ? const Text(
                                      'No ratings',
                                      style: TextStyle(color: Colors.white70),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star,
                                            color: Colors.amber, size: 18),
                                        const SizedBox(width: 2),
                                        Text(
                                          ratingAvg.toStringAsFixed(1),
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CompanyDetailScreen(company: company),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

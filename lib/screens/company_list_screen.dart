// lib/screens/company_list_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../supabase_client.dart';
import 'company_detail_screen.dart';
import '../widgets/hive_background.dart';
import '../Constants/category_map.dart'; // must contain: const Map<String, List<String>> kCategoryMap = {...};

enum CompanySort { newest, rating, name, closest }

class CompanyListScreen extends StatefulWidget {
  const CompanyListScreen({super.key});

  @override
  State<CompanyListScreen> createState() => CompanyListScreenState();
}

class CompanyListScreenState extends State<CompanyListScreen> {
  bool _loading = true;
  List<dynamic> _companies = [];

  String _searchQuery = "";
  String _selectedCategoryFilter = 'All';
  String? _selectedSubcategory; // null = "All subcategories"
  CompanySort _sortBy = CompanySort.newest;

  double? _userLat;
  double? _userLon;

  // Can be called from other screens (e.g. after business profile changes)
  Future<void> reloadCompanies() async {
    await _loadCompanies();
  }

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

  // ─────────────── CATEGORY + SUBCATEGORY OPTIONS ───────────────

  /// Categories come from kCategoryMap so they are stable.
  List<String> get _categoryOptions {
    final keys = kCategorySubcategories.keys.toList();

    // Make sure "All" is first if it's present in the map
    keys.sort((a, b) {
      if (a == 'All') return -1;
      if (b == 'All') return 1;
      return a.compareTo(b);
    });

    // If the dev forgot to put "All" in the map, ensure it exists.
    if (!keys.contains('All')) {
      keys.insert(0, 'All');
    }

    return keys;
  }

  /// Subcategories are read from kCategoryMap for the selected category.
  /// We *don't* add "All" here; we handle that as the first chip ourselves.
  List<String> get _availableSubcategories {
    if (_selectedCategoryFilter == 'All') {
      return const <String>[];
    }
    return kCategorySubcategories[_selectedCategoryFilter] ?? const <String>[];
  }

  // ─────────────── HELPERS ───────────────

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

  // Haversine distance in km
  double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<void> _ensureLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Location permission denied. Cannot sort by distance.'),
          ),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _userLat = pos.latitude;
        _userLon = pos.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not get location: $e')),
      );
    }
  }

  // ─────────────── FILTER + SORT ───────────────

  List<dynamic> get _filteredCompanies {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = _companies.where((company) {
      final name = (company['name'] ?? '').toString().toLowerCase();
      final category = (company['category'] ?? '').toString();
      final categoryLower = category.toLowerCase();
      final city = (company['city'] ?? '').toString().toLowerCase();
      final subcategory = (company['subcategory'] ?? '').toString();
      final subLower = subcategory.toLowerCase();

      final matchesSearch = query.isEmpty ||
          name.contains(query) ||
          categoryLower.contains(query) ||
          city.contains(query) ||
          subLower.contains(query);

      final matchesCategory =
          _selectedCategoryFilter == 'All' ||
          category == _selectedCategoryFilter;

      final matchesSubcategory = _selectedSubcategory == null ||
          subcategory == _selectedSubcategory;

      return matchesSearch && matchesCategory && matchesSubcategory;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case CompanySort.newest:
          final da = _parseDate(a['inserted_at']);
          final db = _parseDate(b['inserted_at']);
          return db.compareTo(da); // newest first

        case CompanySort.rating:
          final ra = (a['rating_avg'] as num? ?? 0).toDouble();
          final rb = (b['rating_avg'] as num? ?? 0).toDouble();
          return rb.compareTo(ra); // highest rating first

        case CompanySort.name:
          final na = (a['name'] ?? '').toString().toLowerCase();
          final nb = (b['name'] ?? '').toString().toLowerCase();
          return na.compareTo(nb); // A–Z

        case CompanySort.closest:
          final userLat = _userLat;
          final userLon = _userLon;
          if (userLat == null || userLon == null) {
            return 0; // no location → keep order
          }

          final la = (a['latitude'] as num?)?.toDouble();
          final loa = (a['longitude'] as num?)?.toDouble();
          final lb = (b['latitude'] as num?)?.toDouble();
          final lob = (b['longitude'] as num?)?.toDouble();

          if (la == null || loa == null || lb == null || lob == null) {
            return 0;
          }

          final da = _distanceKm(userLat, userLon, la, loa);
          final db = _distanceKm(userLat, userLon, lb, lob);
          return da.compareTo(db); // closest first
      }
    });

    return filtered;
  }

  // ─────────────── UI BUILD ───────────────

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
            const SizedBox(height: 70),

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

            const SizedBox(height: 8),

            // 🏷 CATEGORY CHIPS
            _buildCategoryBar(),

            // 🔽 SUB-CATEGORY CHIPS
            _buildSubcategoryBar(),

            const SizedBox(height: 8),

            // ↕️ SORT ROW
            _buildSortRow(),

            const SizedBox(height: 8),

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
                                (company['rating_avg'] as num? ?? 0).toDouble();
                            final ratingCount =
                                (company['rating_count'] as int? ?? 0);

                            double? distanceKm;
                            if (_userLat != null &&
                                _userLon != null &&
                                company['latitude'] != null &&
                                company['longitude'] != null) {
                              final lat =
                                  (company['latitude'] as num).toDouble();
                              final lon =
                                  (company['longitude'] as num).toDouble();
                              distanceKm =
                                  _distanceKm(_userLat!, _userLon!, lat, lon);
                            }

                            String subtitleText =
                                '${company['category'] ?? ''} • ${company['city'] ?? ''}';
                            if ((company['subcategory'] ?? '')
                                .toString()
                                .isNotEmpty) {
                              subtitleText =
                                  '${company['subcategory']} • $subtitleText';
                            }
                            if (distanceKm != null) {
                              subtitleText +=
                                  ' • ${distanceKm.toStringAsFixed(1)} km away';
                            }

                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.white24,
                                child:
                                    Icon(Icons.business, color: Colors.white),
                              ),
                              title: Text(
                                company['name'] ?? '',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                subtitleText,
                                style:
                                    const TextStyle(color: Colors.white70),
                              ),
                              trailing: ratingCount == 0
                                  ? const Text(
                                      'No ratings',
                                      style: TextStyle(color: Colors.white70),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          ratingAvg.toStringAsFixed(1),
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ],
                                    ),
                              onTap: () async {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CompanyDetailScreen(company: company),
                                  ),
                                );

                                if (changed == true) {
                                  _loadCompanies();
                                }
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

  // ─────────────── HELPER UI WIDGETS ───────────────

  Widget _buildCategoryBar() {
    final categories = _categoryOptions;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final selected = _selectedCategoryFilter == cat;

          return ChoiceChip(
            label: Text(cat),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedCategoryFilter = cat;
                _selectedSubcategory = null; // reset subcategory
              });
            },
            labelStyle: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 13,
            ),
            selectedColor: const Color.fromARGB(255, 241, 178, 70),
            backgroundColor: Colors.black.withOpacity(0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: selected ? Colors.amber : Colors.white24,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubcategoryBar() {
    final subs = _availableSubcategories;
    if (subs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        scrollDirection: Axis.horizontal,
        itemCount: subs.length + 1, // + "All"
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          String label;
          String? value;
          if (index == 0) {
            label = 'All';
            value = null;
          } else {
            label = subs[index - 1];
            value = label;
          }

          final selected =
              _selectedSubcategory == value ||
              (value == null && _selectedSubcategory == null);

          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedSubcategory = value;
              });
            },
            labelStyle: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12,
            ),
            selectedColor: Colors.amber,
            backgroundColor: Colors.black.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: selected ? Colors.amber : Colors.white24,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text(
            'Sort by',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 8),
          DropdownButton<CompanySort>(
            value: _sortBy,
            dropdownColor: const Color(0xFF020617),
            iconEnabledColor: Colors.white,
            underline: const SizedBox.shrink(),
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
              DropdownMenuItem(
                value: CompanySort.closest,
                child: Text('Closest'),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;

              if (value == CompanySort.closest &&
                  (_userLat == null || _userLon == null)) {
                await _ensureLocation();
              }

              setState(() {
                _sortBy = value;
              });
            },
          ),
        ],
      ),
    );
  }
}

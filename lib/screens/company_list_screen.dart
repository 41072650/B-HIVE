// lib/screens/company_list_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../supabase_client.dart';
import 'company_detail_screen.dart';
import '../widgets/hive_background.dart';
import '../Constants/category_map.dart';

enum CompanySort { newest, rating, name, closest }

class CompanyListScreen extends StatefulWidget {
  const CompanyListScreen({super.key});

  @override
  State<CompanyListScreen> createState() => CompanyListScreenState();
}

class CompanyListScreenState extends State<CompanyListScreen> {
  // -------------------------
  // Pagination (future-proof)
  // -------------------------
  static const int _pageSize = 80; // tweak: 40–120 depending on device + data size
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  String? _error;

  // Raw companies (paged) from Supabase
  final List<Map<String, dynamic>> _companies = [];

  // UI filters
  String _searchQuery = "";
  String _selectedCategoryFilter = 'All';
  String? _selectedSubcategory; // null = "All subcategories"
  CompanySort _sortBy = CompanySort.newest;

  // Location for "closest"
  double? _userLat;
  double? _userLon;

  // Public method for other screens (e.g. LandingScreen) to refresh
  Future<void> reloadCompanies() async {
    await _refreshCompanies();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshCompanies();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    // When user gets near bottom, fetch next page
    if (pos.pixels >= pos.maxScrollExtent - 420) {
      _loadMoreCompanies();
    }
  }

  Future<void> _refreshCompanies() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
      _companies.clear();
    });

    await _loadMoreCompanies(initial: true);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMoreCompanies({bool initial = false}) async {
    if (!_hasMore || _loadingMore) return;

    if (!mounted) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });

    try {
      // We only need enough fields for list rendering.
      // (Future-proof: keep select list short for performance.)
      final from = _companies.length;
      final to = from + _pageSize - 1;

      final response = await supabase
          .from('companies')
          .select(
            'id, name, category, subcategory, city, logo_url, is_paid, rating_avg, rating_count, inserted_at, latitude, longitude',
          )
          .order('inserted_at', ascending: false)
          .range(from, to);

      final rows = ((response as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;

      setState(() {
        _companies.addAll(rows);
        // If we got fewer than pageSize, there is no more
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = 'Failed to load companies: $e';
      });
    }
  }

  // ─────────────── CATEGORY + SUBCATEGORY OPTIONS ───────────────

  List<String> get _categoryOptions {
    final keys = kCategorySubcategories.keys.toList();

    keys.sort((a, b) {
      if (a == 'All') return -1;
      if (b == 'All') return 1;
      return a.compareTo(b);
    });

    if (!keys.contains('All')) keys.insert(0, 'All');
    return keys;
  }

  List<String> get _availableSubcategories {
    if (_selectedCategoryFilter == 'All') return const <String>[];
    return kCategorySubcategories[_selectedCategoryFilter] ?? const <String>[];
  }

  // ─────────────── HELPERS ───────────────

  DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
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
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission denied. Cannot sort by distance.'),
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

  List<Map<String, dynamic>> get _filteredCompanies {
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
          _selectedCategoryFilter == 'All' || category == _selectedCategoryFilter;

      final matchesSubcategory =
          _selectedSubcategory == null || subcategory == _selectedSubcategory;

      return matchesSearch && matchesCategory && matchesSubcategory;
    }).toList();

    // Paid first, then chosen sort
    filtered.sort((a, b) {
      final aa = a['is_paid'] == true ? 1 : 0;
      final bb = b['is_paid'] == true ? 1 : 0;
      if (aa != bb) return bb.compareTo(aa);

      switch (_sortBy) {
        case CompanySort.newest:
          final da = _parseDate(a['inserted_at']);
          final db = _parseDate(b['inserted_at']);
          return db.compareTo(da);

        case CompanySort.rating:
          final ra = ((a['rating_avg'] as num?) ?? 0).toDouble();
          final rb = ((b['rating_avg'] as num?) ?? 0).toDouble();
          return rb.compareTo(ra);

        case CompanySort.name:
          final na = (a['name'] ?? '').toString().toLowerCase();
          final nb = (b['name'] ?? '').toString().toLowerCase();
          return na.compareTo(nb);

        case CompanySort.closest:
          final userLat = _userLat;
          final userLon = _userLon;
          if (userLat == null || userLon == null) return 0;

          final la = (a['latitude'] as num?)?.toDouble();
          final loa = (a['longitude'] as num?)?.toDouble();
          final lb = (b['latitude'] as num?)?.toDouble();
          final lob = (b['longitude'] as num?)?.toDouble();

          // Put companies with coords first when sorting by closest
          final aHas = la != null && loa != null;
          final bHas = lb != null && lob != null;
          if (aHas != bHas) return bHas ? 1 : -1;
          if (!aHas || !bHas) return 0;

          final da = _distanceKm(userLat, userLon, la!, loa!);
          final db = _distanceKm(userLat, userLon, lb!, lob!);
          return da.compareTo(db);
      }
    });

    return filtered;
  }

  // ─────────────── UI BUILD ───────────────

  @override
  Widget build(BuildContext context) {
    final filteredCompanies = _filteredCompanies;

    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),

              // 🔍 SEARCH BAR
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
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
              _buildCategoryBar(),
              _buildSubcategoryBar(),
              const SizedBox(height: 8),
              _buildSortRow(),
              const SizedBox(height: 8),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (_error != null) const SizedBox(height: 8),

              // LIST + PULL-TO-REFRESH + INFINITE SCROLL
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshCompanies,
                  color: Colors.amber,
                  backgroundColor: Colors.black87,
                  child: _buildCompanyList(filteredCompanies),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyList(List<Map<String, dynamic>> filteredCompanies) {
    if (_loading) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ],
      );
    }

    if (filteredCompanies.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'No matching companies.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      );
    }

    // We add one extra item at the end for the loading-more indicator.
    final itemCount = filteredCompanies.length + 1;

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Footer loader row
        if (index == filteredCompanies.length) {
          if (!_hasMore) {
            return const SizedBox(height: 18);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const SizedBox.shrink(),
            ),
          );
        }

        final company = filteredCompanies[index];

        final ratingAvg = ((company['rating_avg'] as num?) ?? 0).toDouble();
        final ratingCount = (company['rating_count'] as int?) ?? 0;
        final isPaid = company['is_paid'] == true;

        final logoUrl = (company['logo_url'] ?? '') as String?;

        double? distanceKm;
        if (_userLat != null &&
            _userLon != null &&
            company['latitude'] != null &&
            company['longitude'] != null) {
          final lat = (company['latitude'] as num).toDouble();
          final lon = (company['longitude'] as num).toDouble();
          distanceKm = _distanceKm(_userLat!, _userLon!, lat, lon);
        }

        String subtitleText =
            '${company['category'] ?? ''} • ${company['city'] ?? ''}';
        if ((company['subcategory'] ?? '').toString().isNotEmpty) {
          subtitleText = '${company['subcategory']} • $subtitleText';
        }
        if (distanceKm != null) {
          subtitleText += ' • ${distanceKm.toStringAsFixed(1)} km away';
        }

        final Widget leadingAvatar;
        if (logoUrl != null && logoUrl.isNotEmpty) {
          leadingAvatar = CircleAvatar(
            backgroundColor: Colors.white10,
            backgroundImage: NetworkImage(logoUrl),
          );
        } else {
          leadingAvatar = const CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(Icons.business, color: Colors.white),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPaid
                  ? const Color.fromARGB(255, 241, 178, 70)
                  : Colors.white24,
              width: isPaid ? 1.6 : 0.8,
            ),
            color: Colors.black.withOpacity(0.5),
          ),
          child: ListTile(
            leading: leadingAvatar,
            title: Text(
              (company['name'] ?? '').toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitleText,
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isPaid)
                  const Icon(
                    Icons.verified,
                    size: 18,
                    color: Colors.greenAccent,
                  ),
                const SizedBox(height: 4),
                if (ratingCount == 0)
                  const Text(
                    'No ratings',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  )
                else
                  Row(
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
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CompanyDetailScreen(company: company),
                ),
              );

              // Refresh so rating updates, etc.
              if (mounted) {
                await _refreshCompanies();
              }
            },
          ),
        );
      },
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
                _selectedSubcategory = null;
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
        itemCount: subs.length + 1,
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

          final selected = _selectedSubcategory == value ||
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

              if (!mounted) return;
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

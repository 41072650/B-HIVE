// lib/screens/landing_screen.dart
import 'package:flutter/material.dart';

import '../supabase_client.dart';
import 'company_list_screen.dart';
import 'edit_profile_screen.dart';
import 'business_stats_screen.dart';
import 'business_profile_screen.dart';
import 'jobs_screen.dart';

class LandingScreen extends StatefulWidget {
  /// If true, the user is browsing as a guest (no Supabase session).
  final bool isGuest;

  const LandingScreen({
    super.key,
    this.isGuest = false,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  // Key to reload company list when needed
  final GlobalKey<CompanyListScreenState> _companyListKey =
      GlobalKey<CompanyListScreenState>();

  // ✅ Key to reload business stats when a business changes
  final GlobalKey<BusinessStatsScreenState> _businessStatsKey =
      GlobalKey<BusinessStatsScreenState>();

  int _selectedIndex = 0;
  bool _isBusiness = false;

  @override
  void initState() {
    super.initState();

    // In guest mode we do NOT touch Supabase
    if (!widget.isGuest) {
      _loadBusinessMode();
    }
  }

  Future<void> _loadBusinessMode() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('profiles')
          .select('is_business')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _isBusiness = (data?['is_business'] as bool?) ?? false;
      });
    } catch (_) {
      // keep default false
    }
  }

  /// Called when a business is created or updated
  void _onBusinessChanged() {
    // Refresh companies list
    _companyListKey.currentState?.reloadCompanies();

    // ✅ Refresh stats (important because IndexedStack keeps it alive)
    _businessStatsKey.currentState?.reloadStats();

    // Jump back to home tab
    setState(() {
      _selectedIndex = 0;
    });
  }

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // ------------------------------------------------
    // GUEST MODE
    // ------------------------------------------------
    if (widget.isGuest) {
      final List<Widget> guestTabs = [
        CompanyListScreen(key: _companyListKey),
        JobsScreen(isBusiness: false),
      ];

      final List<BottomNavigationBarItem> guestItems = const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.work_rounded),
          label: 'Jobs',
        ),
      ];

      int currentIndex = _selectedIndex;
      if (currentIndex >= guestTabs.length) {
        currentIndex = guestTabs.length - 1;
      }

      return Scaffold(
        extendBodyBehindAppBar: true,
        body: IndexedStack(
          index: currentIndex,
          children: guestTabs,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: _onTabTapped,
          backgroundColor: const Color.fromARGB(255, 10, 10, 10),
          selectedItemColor: const Color.fromARGB(255, 241, 178, 70),
          unselectedItemColor: Colors.white60,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          items: guestItems,
        ),
      );
    }

    // ------------------------------------------------
    // LOGGED-IN MODE
    // ------------------------------------------------
    final List<Widget> tabs = [
      CompanyListScreen(key: _companyListKey),
      JobsScreen(isBusiness: _isBusiness),
      if (_isBusiness)
        BusinessProfileScreen(
          onBusinessChanged: _onBusinessChanged,
        ),
      if (_isBusiness)
        BusinessStatsScreen(
          key: _businessStatsKey, // ✅ attach key here
        ),
      EditProfileScreen(
        onBusinessModeChanged: (isBusiness) {
          setState(() {
            _isBusiness = isBusiness;

            // If user just turned off business mode while sitting on business tab,
            // ensure selected index remains valid.
            if (!_isBusiness && _selectedIndex > 2) {
              _selectedIndex = 0;
            }
          });
        },
      ),
    ];

    final List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_rounded),
        label: 'Home',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.work_rounded),
        label: 'Jobs',
      ),
      if (_isBusiness)
        const BottomNavigationBarItem(
          icon: Icon(Icons.storefront_rounded),
          label: 'My Business',
        ),
      if (_isBusiness)
        const BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Stats',
        ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.person_rounded),
        label: 'Profile',
      ),
    ];

    int currentIndex = _selectedIndex;
    if (currentIndex >= tabs.length) {
      currentIndex = tabs.length - 1;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: IndexedStack(
        index: currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: _onTabTapped,
        backgroundColor: const Color.fromARGB(255, 10, 10, 10),
        selectedItemColor: const Color.fromARGB(255, 241, 178, 70),
        unselectedItemColor: Colors.white60,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: items,
      ),
    );
  }
}

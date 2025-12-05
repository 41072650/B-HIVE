// lib/screens/landing_screen.dart
import 'package:flutter/material.dart';

import '../supabase_client.dart';
import 'company_list_screen.dart';
import 'edit_profile_screen.dart';
import 'business_stats_screen.dart';
import 'business_profile_screen.dart';
import 'jobs_screen.dart'; // 👈 NEW

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  // Key to reload company list when needed
  final GlobalKey<CompanyListScreenState> _companyListKey =
      GlobalKey<CompanyListScreenState>();

  int _selectedIndex = 0;
  bool _isBusiness = false;

  @override
  void initState() {
    super.initState();
    _loadBusinessMode();
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
    // ----------------------------
    // TAB SCREENS
    // ----------------------------
    final List<Widget> tabs = [
      // 0: Home (companies list)
      CompanyListScreen(key: _companyListKey),

      // 1: Jobs (everyone sees this)
      JobsScreen(isBusiness: _isBusiness),

      // 2: My Business (only if business mode)
      if (_isBusiness)
        BusinessProfileScreen(
          onBusinessChanged: _onBusinessChanged,
        ),

      // 3: Business stats (only if business mode)
      if (_isBusiness)
        const BusinessStatsScreen(),

      // Last: Profile (always shown)
      EditProfileScreen(
        onBusinessModeChanged: (isBusiness) {
          setState(() {
            _isBusiness = isBusiness;
          });
        },
      ),
    ];

    // ----------------------------
    // BOTTOM NAV ITEMS
    // ----------------------------
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

    // ----------------------------
    // FIX OUT-OF-RANGE INDEX
    // ----------------------------
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

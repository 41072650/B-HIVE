// lib/screens/landing_screen.dart
import 'package:flutter/material.dart';
import 'company_list_screen.dart';
import 'create_company_screen.dart';
import 'edit_profile_screen.dart';
import '../widgets/hive_background.dart';
import '../supabase_client.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  String? _avatarUrl;
  bool _loadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _loadingAvatar = true;
    });

    try {
      final data = await supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _avatarUrl = (data?['avatar_url'] as String?) ?? '';
      });
    } catch (_) {
      // you can log or show an error if you want
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingAvatar = false;
      });
    }
  }

  Widget _buildProfileAvatar() {
    ImageProvider imageProvider;

    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_avatarUrl!);
    } else {
      imageProvider = const AssetImage('assets/default_profile.png');
    }

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
        );
        // reload avatar when coming back from edit screen
        _loadAvatar();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            backgroundImage: imageProvider,
          ),
          if (_loadingAvatar)
            const SizedBox(
              height: 30,
              width: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: HiveBackground(
        child: Stack(
          children: [
            // top-left profile circle
            Positioned(
              top: 50,
              left: 20,
              child: _buildProfileAvatar(),
            ),

            // main landing content
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'B-Hive\nThe lifeline of companies.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '• Discover trusted companies by category & location\n'
                      '• View project history, pricing, and ratings\n'
                      '• Showcase your own company and win more work',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CompanyListScreen(),
                          ),
                        );
                      },
                      child: const Text('Explore Companies'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateCompanyScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                      ),
                      child: const Text(
                        'Create Company Profile',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

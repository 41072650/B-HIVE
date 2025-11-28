// lib/screens/edit_profile_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase_client.dart';
import '../auth_gate.dart';
import '../widgets/hive_background.dart';
import 'connections_screen.dart'; // for navigating to connections

class EditProfileScreen extends StatefulWidget {
  // Callback so LandingScreen can react when business mode changes
  final void Function(bool isBusiness)? onBusinessModeChanged;

  const EditProfileScreen({
    super.key,
    this.onBusinessModeChanged,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Basic profile
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();

  // Extra / professional info
  final _jobTitleController = TextEditingController();
  final _degreeController = TextEditingController();
  final _yearsExperienceController = TextEditingController();
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _avatarUrl; // current avatar URL from Supabase
  Uint8List? _newAvatarBytes; // image picked but not uploaded yet
  String? _newAvatarExt; // "jpg", "png", etc.

  bool _isBusiness = false; // business mode flag

  // 👉 Connections stats
  int _connectionCount = 0; // unique companies contacted
  int _clientCount = 0;     // unique companies marked as client
  bool _contactsLoading = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadContactStats();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _jobTitleController.dispose();
    _degreeController.dispose();
    _yearsExperienceController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'No logged-in user found.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        _nameController.text = (data['full_name'] ?? '') as String;
        _companyController.text = (data['company_name'] ?? '') as String;
        _avatarUrl = data['avatar_url'] as String?;

        _jobTitleController.text = (data['job_title'] ?? '') as String;
        _degreeController.text = (data['degree'] ?? '') as String;

        final years = data['years_experience'];
        _yearsExperienceController.text =
            years == null ? '' : years.toString();

        _locationController.text = (data['location'] ?? '') as String;
        _bioController.text = (data['bio'] ?? '') as String;

        final isBiz = data['is_business'];
        if (isBiz is bool) {
          _isBusiness = isBiz;
          // Optional: also tell parent on first load
          widget.onBusinessModeChanged?.call(_isBusiness);
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load profile: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // 👉 Load connections + clients stats from contacts table
  Future<void> _loadContactStats() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _contactsLoading = true;
    });

    try {
      final data = await supabase
          .from('contacts')
          .select('status, company_id')
          .eq('user_id', user.id);

      final uniqueCompanies = <dynamic>{};
      final clientCompanies = <dynamic>{};

      for (final row in data) {
        final companyId = row['company_id'];
        if (companyId == null) continue;

        uniqueCompanies.add(companyId);

        final status = (row['status'] ?? 'waiting').toString();
        if (status == 'client') {
          clientCompanies.add(companyId);
        }
      }

      if (!mounted) return;
      setState(() {
        _connectionCount = uniqueCompanies.length;
        _clientCount = clientCompanies.length;
      });
    } catch (e) {
      debugPrint('Failed to load contact stats: $e');
    } finally {
      if (mounted) {
        setState(() {
          _contactsLoading = false;
        });
      }
    }
  }

  // Small widget to show a stat tile under avatar
  Widget _buildStatTile(String label, int value, {VoidCallback? onTap}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _contactsLoading ? '...' : value.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: content,
      ),
    );
  }

  Future<void> _pickNewAvatar() async {
    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);

      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();

      setState(() {
        _newAvatarBytes = bytes;
        _newAvatarExt = ext;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to pick image: $e';
      });
    }
  }

  Future<String?> _uploadAvatarIfNeeded(String userId) async {
    if (_newAvatarBytes == null) return _avatarUrl; // no new image chosen

    final fileName =
        'avatars/$userId-${DateTime.now().millisecondsSinceEpoch}.${_newAvatarExt ?? 'jpg'}';

    await supabase.storage.from('avatars').uploadBinary(
          fileName,
          _newAvatarBytes!,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl =
        supabase.storage.from('avatars').getPublicUrl(fileName);

    return publicUrl;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'No logged-in user found.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final avatarUrl = await _uploadAvatarIfNeeded(user.id);

      int? yearsExp;
      final yearsStr = _yearsExperienceController.text.trim();
      if (yearsStr.isNotEmpty) {
        yearsExp = int.tryParse(yearsStr);
      }

      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': _nameController.text.trim(),
        'company_name': _companyController.text.trim(),
        'avatar_url': avatarUrl,
        'job_title': _jobTitleController.text.trim(),
        'degree': _degreeController.text.trim(),
        'years_experience': yearsExp,
        'location': _locationController.text.trim(),
        'bio': _bioController.text.trim(),
        'is_business': _isBusiness,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        setState(() {
          _avatarUrl = avatarUrl;
          _newAvatarBytes = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save profile: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleBusinessMode() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged-in user found')),
      );
      return;
    }

    final newValue = !_isBusiness;
    setState(() {
      _isBusiness = newValue;
    });

    try {
      await supabase
          .from('profiles')
          .update({
            'is_business': newValue,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      // 🔔 Notify parent (LandingScreen) that business mode changed
      widget.onBusinessModeChanged?.call(newValue);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue
                ? 'Switched to business mode'
                : 'Switched to user mode',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // revert on error
      setState(() {
        _isBusiness = !newValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to switch mode: $e')),
      );
    }
  }

  Future<void> _inviteBusiness() async {
    const message =
        'Join me on B-Hive to connect with other businesses: https://www.youtube.com/watch?v=2OTnn33yWj8';
    await Share.share(message);
  }

  Future<void> _giveFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'ejdkbb@gmail.com',
      queryParameters: {
        'subject': '',
        'body': '',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open email app for feedback'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to log out: $e')),
      );
    }
  }

  Widget _buildAvatar() {
    Widget imageWidget;

    if (_newAvatarBytes != null) {
      imageWidget = CircleAvatar(
        radius: 48,
        backgroundImage: MemoryImage(_newAvatarBytes!),
      );
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      imageWidget = CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(_avatarUrl!),
      );
    } else {
      imageWidget = const CircleAvatar(
        radius: 48,
        backgroundImage: AssetImage('assets/default_profile.png'),
      );
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        imageWidget,
        InkWell(
          onTap: _pickNewAvatar,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(6),
            child: const Icon(
              Icons.edit,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: HiveBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAvatar(),
                  const SizedBox(height: 12),

                  // 👉 Simple: Connections & Clients under avatar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatTile(
                        'Connections',
                        _connectionCount,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ConnectionsScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 40),
                      _buildStatTile('Clients', _clientCount),
                    ],
                  ),

                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Basic information',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _companyController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Company Name',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Professional details',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _jobTitleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Job Title',
                            hintText: 'e.g. Electrical Engineer',
                            hintStyle: TextStyle(color: Colors.white38),
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _degreeController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Degree / Qualification',
                            hintText: 'e.g. BEng Computer & Electronic',
                            hintStyle: TextStyle(color: Colors.white38),
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _yearsExperienceController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Years of Work Experience',
                            hintText: 'e.g. 3',
                            hintStyle: TextStyle(color: Colors.white38),
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            if (int.tryParse(value.trim()) == null) {
                              return 'Please enter a valid number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _locationController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Location',
                            hintText: 'e.g. Potchefstroom, South Africa',
                            hintStyle: TextStyle(color: Colors.white38),
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'About you',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _bioController,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Short Bio',
                            hintText:
                                'Tell other businesses a bit about who you are and what you do...',
                            hintStyle: TextStyle(color: Colors.white38),
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _saveProfile,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 12),
                        const Text(
                          'Actions',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _toggleBusinessMode,
                            icon: const Icon(Icons.storefront),
                            label: Text(
                              _isBusiness
                                  ? 'Switch to user mode'
                                  : 'Switch to business mode',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _inviteBusiness,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Invite a business'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _giveFeedback,
                            icon: const Icon(Icons.feedback_outlined),
                            label: const Text('Give feedback'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _logout,
                            icon: const Icon(Icons.logout),
                            label: const Text('Logout'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// lib/screens/edit_profile_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';      // assumes you expose `supabase` here
import '../widgets/hive_background.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _companyController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _avatarUrl;          // current avatar URL from Supabase
  Uint8List? _newAvatarBytes;  // image picked but not uploaded yet
  String? _newAvatarExt;       // "jpg", "png", etc.

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
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

    // Upload as bytes (works on mobile & web)
    await supabase.storage.from('avatars').uploadBinary(
          fileName,
          _newAvatarBytes!,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
          ),
        );

    // Get public URL (or use signed URL logic if you prefer private)
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

      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': _nameController.text.trim(),
        'company_name': _companyController.text.trim(),
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        setState(() {
          _avatarUrl = avatarUrl;
          _newAvatarBytes = null; // clear local image
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

  Widget _buildAvatar() {
    Widget imageWidget;

    if (_newAvatarBytes != null) {
      // New image chosen but not uploaded yet
      imageWidget = CircleAvatar(
        radius: 48,
        backgroundImage: MemoryImage(_newAvatarBytes!),
      );
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      // Existing avatar from Supabase
      imageWidget = CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(_avatarUrl!),
      );
    } else {
      // Default placeholder
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
        foregroundColor: Colors.white, // <-- makes title & back arrow white
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
                      children: [
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

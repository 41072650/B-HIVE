// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/hive_background.dart';
import '../supabase_client.dart';
import '../auth_gate.dart';

// 👇 same folder, so no "../"
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String? _error;

  // Privacy flags (stored in profiles table)
  bool _showProfilePublic = true;
  bool _allowContact = true;

  // Local-only selections (for now)
  String _theme = 'Dark';
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'No logged-in user.';
      });
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select('show_profile_public, allow_contact')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _loading = false;
        _showProfilePublic = (data?['show_profile_public'] as bool?) ?? true;
        _allowContact = (data?['allow_contact'] as bool?) ?? true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load settings: $e';
      });
    }
  }

  Future<void> _updatePrivacy({
    bool? showProfilePublic,
    bool? allowContact,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Optimistic local update
    setState(() {
      if (showProfilePublic != null) {
        _showProfilePublic = showProfilePublic;
      }
      if (allowContact != null) {
        _allowContact = allowContact;
      }
    });

    try {
      final update = <String, dynamic>{};
      if (showProfilePublic != null) {
        update['show_profile_public'] = showProfilePublic;
      }
      if (allowContact != null) {
        update['allow_contact'] = allowContact;
      }

      await supabase.from('profiles').update(update).eq('id', user.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update privacy: $e')),
      );
    }
  }

  Future<void> _changeEmail() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final emailController = TextEditingController(text: user.email ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        bool submitting = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;

              setStateDialog(() => submitting = true);

              try {
                final newEmail = emailController.text.trim();

                await supabase.auth.updateUser(
                  UserAttributes(email: newEmail),
                );

                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email updated.')),
                );
              } catch (e) {
                setStateDialog(() => submitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update email: $e')),
                );
              }
            }

            return AlertDialog(
              title: const Text('Change Email'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'New email',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter an email';
                    }
                    if (!v.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changePassword() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        bool submitting = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;

              setStateDialog(() => submitting = true);

              try {
                final newPassword = passwordController.text.trim();

                await supabase.auth.updateUser(
                  UserAttributes(password: newPassword),
                );

                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated.')),
                );
              } catch (e) {
                setStateDialog(() => submitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update password: $e')),
                );
              }
            }

            return AlertDialog(
              title: const Text('Change Password'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter a password';
                        }
                        if (v.trim().length < 6) {
                          return 'Must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                      ),
                      validator: (v) {
                        if (v != passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'ejdkbb@gmail.com',
      queryParameters: {
        'subject': 'B-Hive support',
        'body': '',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open email app'),
        ),
      );
    }
  }

  Future<void> _pickTheme() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF020617),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Select theme',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              RadioListTile<String>(
                value: 'Dark',
                groupValue: _theme,
                activeColor: Colors.amber,
                title:
                    const Text('Dark', style: TextStyle(color: Colors.white)),
                onChanged: (v) => Navigator.pop(context, v),
              ),
              RadioListTile<String>(
                value: 'Light',
                groupValue: _theme,
                activeColor: Colors.amber,
                title:
                    const Text('Light', style: TextStyle(color: Colors.white)),
                onChanged: (v) => Navigator.pop(context, v),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (chosen != null && mounted) {
      setState(() => _theme = chosen);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Theme set to $_theme (not yet global wired)')),
      );
    }
  }

  Future<void> _pickLanguage() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF020617),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Select language',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              RadioListTile<String>(
                value: 'English',
                groupValue: _language,
                activeColor: Colors.amber,
                title: const Text('English',
                    style: TextStyle(color: Colors.white)),
                onChanged: (v) => Navigator.pop(context, v),
              ),
              RadioListTile<String>(
                value: 'Afrikaans',
                groupValue: _language,
                activeColor: Colors.amber,
                title: const Text('Afrikaans',
                    style: TextStyle(color: Colors.white)),
                onChanged: (v) => Navigator.pop(context, v),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (chosen != null && mounted) {
      setState(() => _language = chosen);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Language set to $_language (UI still EN)')),
      );
    }
  }

  // ───── DELETE ACCOUNT (calls Supabase RPC) ─────

  Future<void> _deleteAccount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1) Ask Supabase to delete all app data for this user
      await supabase.rpc('delete_user_data', params: {
        'p_user_id': user.id,
      });

      // 2) Log the user out
      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Your B-Hive data has been deleted and you are logged out.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: $e')),
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool deleting = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setStateDialog(() => deleting = true);
              await _deleteAccount();
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              }
            }

            return AlertDialog(
              title: const Text('Delete my account & data'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This will delete your B-Hive profile, connections and analytics data. '
                      'Any companies you own will no longer be linked to your personal profile.\n\n'
                      'This action cannot be undone.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Type DELETE in capital letters to confirm:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      validator: (v) {
                        if (v == null || v.trim() != 'DELETE') {
                          return 'Please type DELETE to confirm';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      deleting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                  onPressed: deleting ? null : submit,
                  child: deleting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: HiveBackground(
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // ────────────── ACCOUNT ──────────────
                        const Text(
                          "Account",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        ListTile(
                          leading:
                              const Icon(Icons.email, color: Colors.white),
                          title: const Text(
                            "Change Email",
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: _changeEmail,
                        ),
                        ListTile(
                          leading: const Icon(Icons.lock, color: Colors.white),
                          title: const Text(
                            "Change Password",
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: _changePassword,
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_forever,
                              color: Colors.redAccent),
                          title: const Text(
                            "Delete my account & data",
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          onTap: _confirmDeleteAccount,
                        ),

                        const SizedBox(height: 20),

                        // ────────────── PRIVACY ──────────────
                        const Text(
                          "Privacy",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        SwitchListTile(
                          value: _showProfilePublic,
                          onChanged: (v) =>
                              _updatePrivacy(showProfilePublic: v),
                          activeColor: Colors.amber,
                          title: const Text(
                            "Show my profile publicly",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        SwitchListTile(
                          value: _allowContact,
                          onChanged: (v) =>
                              _updatePrivacy(allowContact: v),
                          activeColor: Colors.amber,
                          title: const Text(
                            "Allow businesses to contact me",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ────────────── APP SETTINGS ──────────────
                        const Text(
                          "App Settings",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        ListTile(
                          leading: const Icon(Icons.color_lens,
                              color: Colors.white),
                          title: const Text(
                            "Theme",
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _theme == 'Dark'
                                ? 'Dark mode (default)'
                                : 'Light mode',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: _pickTheme,
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.language, color: Colors.white),
                          title: const Text(
                            "Language",
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _language,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: _pickLanguage,
                        ),

                        const SizedBox(height: 20),

                        // ────────────── SUPPORT ──────────────
                        const Text(
                          "Support",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        ListTile(
                          leading: const Icon(Icons.help_outline,
                              color: Colors.white),
                          title: const Text(
                            "FAQ",
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () =>
                              _openUrl('https://example.com/faq'), // TODO
                        ),
                        ListTile(
                          leading: const Icon(Icons.privacy_tip,
                              color: Colors.white),
                          title: const Text(
                            "Privacy Policy",
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PrivacyPolicyScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.description,
                              color: Colors.white),
                          title: const Text(
                            "Terms of Service",
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TermsOfServiceScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.support_agent,
                              color: Colors.white),
                          title: const Text(
                            "Contact Support",
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: _contactSupport,
                        ),

                        const SizedBox(height: 20),

                        // ────────────── LOGOUT ──────────────
                        ListTile(
                          leading: const Icon(Icons.logout,
                              color: Colors.redAccent),
                          title: const Text(
                            "Logout",
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          onTap: _logout,
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

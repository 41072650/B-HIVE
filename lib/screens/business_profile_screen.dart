// lib/screens/business_profile_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';
import '../widgets/bhive_inputs.dart';

class BusinessProfileScreen extends StatefulWidget {
  final VoidCallback? onBusinessChanged;

  const BusinessProfileScreen({
    super.key,
    this.onBusinessChanged,
  });

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers (shared for create + edit)
  final _nameController = TextEditingController();
  final _sloganController = TextEditingController();
  final _cityController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _servicesController = TextEditingController();
  final _pricesController = TextEditingController();
  final _imageUrlsController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mapsUrlController = TextEditingController();

  final List<String> _categories = const [
    'Construction',
    'Engineering',
    'Attorneys',
    'IT Services',
    'Manufacturing',
    'Logistics',
    'Consulting',
  ];

  String? _selectedCategory;

  // State
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _myCompanies = [];
  String? _companyId; // null = “creating new”
  bool _isCreatingNew = false;
  bool _isPaid = false; // subscription flag for the selected company

  // ---- Logo upload state ----
  final ImagePicker _picker = ImagePicker();
  Uint8List? _newLogoBytes;
  String? _newLogoExt;
  String? _logoUrl; // current stored logo URL

  @override
  void initState() {
    super.initState();
    _loadMyCompanies();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sloganController.dispose();
    _cityController.dispose();
    _descriptionController.dispose();
    _servicesController.dispose();
    _pricesController.dispose();
    _imageUrlsController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  /// Open Paystack subscription for the currently selected company
  Future<void> _openSubscriptionPage() async {
    // 1) Must have a selected company
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or create a company first.'),
        ),
      );
      return;
    }

    // 2) Must be logged in and have an email
    final user = supabase.auth.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to subscribe.'),
        ),
      );
      return;
    }

    try {
      // 3) Call Supabase Edge Function to get Paystack checkout URL
      final response = await supabase.functions.invoke(
        'create-paystack-link',
        body: {
          'companyId': _companyId,
          'userEmail': user.email,
        },
      );

      final data = response.data as Map<String, dynamic>?;
      final url = data?['authorization_url'] as String?;

      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get subscription link from server.'),
          ),
        );
        return;
      }

      final uri = Uri.parse(url);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open subscription page.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting subscription: $e'),
        ),
      );
    }
  }

  Future<void> _loadMyCompanies() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'You must be logged in to manage a business.';
      });
      return;
    }

    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final data =
          await supabase.from('companies').select().eq('owner_id', user.id);

      if (!mounted) return;

      final list = (data as List<dynamic>)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      _myCompanies = list;

      if (list.isEmpty) {
        // No company yet → default to create mode
        _companyId = null;
        _isCreatingNew = true;
        _isPaid = false;
        _clearForm();
      } else {
        // Have at least one company → start in edit mode with first one
        _isCreatingNew = false;
        _applyCompany(list.first);
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load your businesses: $e';
      });
    }
  }

  void _clearForm() {
    _nameController.clear();
    _sloganController.clear();
    _cityController.clear();
    _descriptionController.clear();
    _servicesController.clear();
    _pricesController.clear();
    _imageUrlsController.clear();
    _emailController.clear();
    _phoneController.clear();
    _mapsUrlController.clear();
    _selectedCategory = null;
    _isPaid = false;
    _logoUrl = null;
    _newLogoBytes = null;
    _newLogoExt = null;
  }

  void _applyCompany(Map<String, dynamic> data) {
    setState(() {
      _companyId = data['id']?.toString();
      _isCreatingNew = false;

      _nameController.text = (data['name'] ?? '') as String;
      _sloganController.text = (data['slogan'] ?? '') as String;
      _selectedCategory = (data['category'] ?? '') as String?;
      _cityController.text = (data['city'] ?? '') as String;
      _descriptionController.text = (data['description'] ?? '') as String;
      _servicesController.text = (data['services'] ?? '') as String;
      _pricesController.text = (data['prices'] ?? '') as String;
      _imageUrlsController.text = (data['image_urls'] ?? '') as String;
      _emailController.text = (data['email'] ?? '') as String;
      _phoneController.text = (data['phone'] ?? '') as String;
      _mapsUrlController.text = (data['maps_url'] ?? '') as String;
      _logoUrl = (data['logo_url'] ?? '') as String?;

      if (_selectedCategory != null &&
          !_categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }

      _isPaid = data['is_paid'] == true;
      _newLogoBytes = null;
      _newLogoExt = null;
    });
  }

  /// Try to extract latitude/longitude from a Google Maps URL.
  /// Supports:
  ///   - .../@LAT,LON,zoom...
  ///   - ...!3dLAT!4dLON...
  Map<String, double>? _extractLatLonFromMapsUrl(String url) {
    if (url.isEmpty) return null;

    // Pattern 1: @lat,lon
    final atPattern = RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)');
    final atMatch = atPattern.firstMatch(url);
    if (atMatch != null && atMatch.groupCount >= 2) {
      final latStr = atMatch.group(1);
      final lonStr = atMatch.group(2);
      if (latStr != null && lonStr != null) {
        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat != null && lon != null) {
          return {'latitude': lat, 'longitude': lon};
        }
      }
    }

    // Pattern 2: !3dLAT!4dLON
    final dPattern = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)');
    final dMatch = dPattern.firstMatch(url);
    if (dMatch != null && dMatch.groupCount >= 2) {
      final latStr = dMatch.group(1);
      final lonStr = dMatch.group(2);
      if (latStr != null && lonStr != null) {
        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (lat != null && lon != null) {
          return {'latitude': lat, 'longitude': lon};
        }
      }
    }

    return null;
  }

  // ─── Logo picking & upload ───

  Future<void> _pickNewLogo() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();

      setState(() {
        _newLogoBytes = bytes;
        _newLogoExt = ext;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick logo: $e')),
      );
    }
  }

  Future<String?> _uploadLogoIfNeeded(String companyId) async {
    if (_newLogoBytes == null) {
      return _logoUrl;
    }

    final ext = _newLogoExt ?? 'jpg';
    final path =
        'logos/$companyId-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await supabase.storage.from('company-logos').uploadBinary(
          path,
          _newLogoBytes!,
          fileOptions: FileOptions(
            contentType: 'image/$ext',
          ),
        );

    final publicUrl = supabase.storage.from('company-logos').getPublicUrl(path);
    return publicUrl;
  }

  Future<void> _createCompany() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to create a company.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final mapsUrl = _mapsUrlController.text.trim();
      final coords = _extractLatLonFromMapsUrl(mapsUrl);

      // Insert without logo first to get company id
      final insertData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'slogan': _sloganController.text.trim(),
        'category': _selectedCategory,
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'services': _servicesController.text.trim(),
        'prices': _pricesController.text.trim(),
        'image_urls': _imageUrlsController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'maps_url': mapsUrl,
        'owner_id': user.id,
        'is_paid': false, // new companies start on free tier
      };

      if (coords != null) {
        insertData['latitude'] = coords['latitude'];
        insertData['longitude'] = coords['longitude'];
      }

      final inserted = await supabase
          .from('companies')
          .insert(insertData)
          .select()
          .maybeSingle();

      if (inserted == null || inserted['id'] == null) {
        throw Exception('Could not create company record.');
      }

      final newCompanyId = inserted['id'].toString();

      // Upload logo if selected
      final logoUrl = await _uploadLogoIfNeeded(newCompanyId);
      if (logoUrl != null && logoUrl.isNotEmpty) {
        await supabase
            .from('companies')
            .update({'logo_url': logoUrl}).eq('id', newCompanyId);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company profile created.')),
      );

      widget.onBusinessChanged?.call();

      // Reload list and switch to edit mode for the new company
      await _loadMyCompanies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating company: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_companyId == null) {
      // Safety: if somehow in edit mode but no id, just create
      return _createCompany();
    }

    setState(() => _saving = true);

    try {
      final mapsUrl = _mapsUrlController.text.trim();

      final updateData = {
        'name': _nameController.text.trim(),
        'slogan': _sloganController.text.trim(),
        'category': _selectedCategory,
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'services': _servicesController.text.trim(),
        'prices': _pricesController.text.trim(),
        'image_urls': _imageUrlsController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'maps_url': mapsUrl,
      };

      // Upload logo if changed
      final logoUrl = await _uploadLogoIfNeeded(_companyId!);
      if (logoUrl != null && logoUrl.isNotEmpty) {
        updateData['logo_url'] = logoUrl;
      }

      await supabase
          .from('companies')
          .update(updateData)
          .eq('id', _companyId!);

      final coords = _extractLatLonFromMapsUrl(mapsUrl);
      if (coords != null) {
        await supabase
            .from('companies')
            .update({
              'latitude': coords['latitude'],
              'longitude': coords['longitude'],
            })
            .eq('id', _companyId!);
      }

      if (!mounted) return;

      _logoUrl = logoUrl ?? _logoUrl;
      _newLogoBytes = null;
      _newLogoExt = null;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business updated.')),
      );

      widget.onBusinessChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating business: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildLogoPreview() {
    Widget content;

    if (_newLogoBytes != null) {
      content = CircleAvatar(
        radius: 32,
        backgroundImage: MemoryImage(_newLogoBytes!),
      );
    } else if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      content = CircleAvatar(
        radius: 32,
        backgroundImage: NetworkImage(_logoUrl!),
      );
    } else {
      content = const CircleAvatar(
        radius: 32,
        backgroundColor: Colors.white24,
        child: Icon(Icons.business, color: Colors.white),
      );
    }

    return Row(
      children: [
        content,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Company logo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Add a logo to stand out in the search results.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _pickNewLogo,
          icon: const Icon(Icons.upload_file, size: 18, color: Colors.amber),
          label: const Text(
            'Upload',
            style: TextStyle(color: Colors.amber),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditingExisting = !_isCreatingNew && _companyId != null;
    final primaryButtonText =
        isEditingExisting ? 'Save Changes' : 'Create Company';

    // Paid companies unlock rich profile editing; free companies get basics only
    final advancedLocked = !_isPaid;

    return Scaffold(
      // No AppBar here – cleaner top, like the companies screen
      body: HiveBackground(
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // ---- SUBSCRIPTION CARD ----
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.amberAccent,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'BHive Business Subscription',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            if (_companyId != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _isPaid
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  _isPaid
                                                      ? 'Verified'
                                                      : 'Free plan',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _isPaid
                                              ? 'Your company is verified. You have full access to rich profile editing, analytics and extra visibility.'
                                              : 'Create a basic listing for free. Upgrade to verify your business and unlock rich profile fields, analytics and extra visibility.',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            onPressed: _openSubscriptionPage,
                                            child: Text(
                                              _isPaid
                                                  ? 'Manage Subscription'
                                                  : 'Upgrade / Verify Business',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Header section: mode & company selector
                                  if (_myCompanies.isNotEmpty) ...[
                                    DropdownButtonFormField<String>(
                                      value:
                                          isEditingExisting ? _companyId : null,
                                      decoration: bhiveInputDecoration(
                                          'Select company'),
                                      dropdownColor: const Color(0xFF020617),
                                      style:
                                          const TextStyle(color: Colors.white),
                                      items: _myCompanies
                                          .map(
                                            (c) => DropdownMenuItem<String>(
                                              value: c['id']?.toString(),
                                              child: Text(
                                                (c['name'] ??
                                                        'Unnamed company')
                                                    .toString(),
                                              ),
                                            ),
                                          )
                                          .toList()
                                        ..insert(
                                          0,
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text('Create new company'),
                                          ),
                                        ),
                                      onChanged: (value) {
                                        if (value == null) {
                                          // Switch to create mode
                                          setState(() {
                                            _isCreatingNew = true;
                                            _companyId = null;
                                            _clearForm();
                                          });
                                        } else {
                                          final company = _myCompanies.firstWhere(
                                            (c) =>
                                                c['id']?.toString() == value,
                                          );
                                          _applyCompany(company);
                                          final name =
                                              (company['name'] ??
                                                      'your company')
                                                  .toString();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content:
                                                  Text('Switched to $name'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                  ] else ...[
                                    const Text(
                                      'Create your first company profile',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Logo upload
                                  _buildLogoPreview(),
                                  const SizedBox(height: 20),

                                  Text(
                                    isEditingExisting
                                        ? 'Edit your business details'
                                        : 'Business details',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // --- FORM FIELDS ---

                                  // Free: always editable
                                  TextFormField(
                                    controller: _nameController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration:
                                        bhiveInputDecoration('Company Name'),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Enter a company name'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),

                                  // Paid: slogan
                                  TextFormField(
                                    controller: _sloganController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    readOnly: advancedLocked,
                                    decoration:
                                        bhiveInputDecoration('Company Slogan')
                                            .copyWith(
                                      helperText: advancedLocked
                                          ? 'Upgrade to add a slogan that stands out in your profile.'
                                          : null,
                                      helperStyle: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                      suffixIcon: advancedLocked
                                          ? const Icon(
                                              Icons.lock,
                                              size: 18,
                                              color: Colors.amberAccent,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Free: category
                                  DropdownButtonFormField<String>(
                                    value: _selectedCategory,
                                    decoration:
                                        bhiveInputDecoration('Category'),
                                    dropdownColor: const Color(0xFF020617),
                                    style:
                                        const TextStyle(color: Colors.white),
                                    items: _categories
                                        .map(
                                          (cat) => DropdownMenuItem(
                                            value: cat,
                                            child: Text(cat),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) => setState(
                                        () => _selectedCategory = value),
                                    validator: (v) => v == null
                                        ? 'Please choose a category'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),

                                  // Free: city
                                  TextFormField(
                                    controller: _cityController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration:
                                        bhiveInputDecoration('City / Area'),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Enter a city'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),

                                  // Paid: Google Maps link
                                  TextFormField(
                                    controller: _mapsUrlController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    readOnly: advancedLocked,
                                    decoration: bhiveInputDecoration(
                                      'Google Maps Link',
                                      hint: advancedLocked
                                          ? 'Upgrade to add a map pin for better local search.'
                                          : 'Paste the full Google Maps URL (with @lat,lon)',
                                    ).copyWith(
                                      suffixIcon: advancedLocked
                                          ? const Icon(
                                              Icons.lock,
                                              size: 18,
                                              color: Colors.amberAccent,
                                            )
                                          : null,
                                    ),
                                    keyboardType: TextInputType.url,
                                  ),
                                  const SizedBox(height: 12),

                                  // Free: short description
                                  TextFormField(
                                    controller: _descriptionController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    maxLines: 3,
                                    decoration: bhiveInputDecoration(
                                      'Short Description',
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Paid: services
                                  TextFormField(
                                    controller: _servicesController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    readOnly: advancedLocked,
                                    decoration: bhiveInputDecoration(
                                      'Services Offered (comma separated)',
                                    ).copyWith(
                                      helperText: advancedLocked
                                          ? 'Upgrade to showcase detailed services on your profile.'
                                          : null,
                                      helperStyle: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                      suffixIcon: advancedLocked
                                          ? const Icon(
                                              Icons.lock,
                                              size: 18,
                                              color: Colors.amberAccent,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Paid: prices
                                  TextFormField(
                                    controller: _pricesController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    maxLines: 3,
                                    readOnly: advancedLocked,
                                    decoration: bhiveInputDecoration(
                                      'Prices (one per line, e.g. "Engine design - R45 000")',
                                    ).copyWith(
                                      helperText: advancedLocked
                                          ? 'Upgrade to list detailed pricing and packages.'
                                          : null,
                                      helperStyle: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                      suffixIcon: advancedLocked
                                          ? const Icon(
                                              Icons.lock,
                                              size: 18,
                                              color: Colors.amberAccent,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Free: images (we’ll only *use* first one on front-end for free)
                                  TextFormField(
                                    controller: _imageUrlsController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: bhiveInputDecoration(
                                      'Project Image URLs (comma separated)',
                                      hint: _isPaid
                                          ? 'Add multiple image URLs, separated by commas.'
                                          : 'Free plan: only your first image will be shown.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Free: contact email
                                  TextFormField(
                                    controller: _emailController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: bhiveInputDecoration(
                                        'Contact Email'),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                  const SizedBox(height: 12),

                                  // Free: contact phone
                                  TextFormField(
                                    controller: _phoneController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: bhiveInputDecoration(
                                        'Contact Phone'),
                                    keyboardType: TextInputType.phone,
                                  ),
                                  const SizedBox(height: 20),

                                  ElevatedButton(
                                    onPressed: _saving
                                        ? null
                                        : () => isEditingExisting
                                            ? _saveChanges()
                                            : _createCompany(),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      child: _saving
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              primaryButtonText,
                                              style:
                                                  const TextStyle(fontSize: 16),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

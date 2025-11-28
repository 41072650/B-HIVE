// lib/screens/edit_business_screen.dart
import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../widgets/hive_background.dart';

class EditBusinessScreen extends StatefulWidget {
  final VoidCallback? onBusinessUpdated;

  const EditBusinessScreen({
    super.key,
    this.onBusinessUpdated,
  });

  @override
  State<EditBusinessScreen> createState() => _EditBusinessScreenState();
}

class _EditBusinessScreenState extends State<EditBusinessScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
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
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // All companies owned by this user
  List<Map<String, dynamic>> _myCompanies = [];

  // Currently selected company id (UUID/string)
  String? _companyId;

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

  Future<void> _loadMyCompanies() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'You must be logged in to edit a business.';
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

      if (list.isEmpty) {
        setState(() {
          _loading = false;
          _myCompanies = [];
          _error =
              'You don\'t have a company yet.\nCreate one first in the "Create" tab.';
        });
        return;
      }

      _myCompanies = list;
      _applyCompany(_myCompanies.first);

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

  void _applyCompany(Map<String, dynamic> data) {
    setState(() {
      _companyId = data['id']?.toString();

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

      if (_selectedCategory != null &&
          !_categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
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

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_companyId == null) return;

    setState(() => _saving = true);

    try {
      final mapsUrl = _mapsUrlController.text.trim();

      final data = {
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

      // 1️⃣ Update normal fields
      await supabase.from('companies').update(data).eq('id', _companyId!);

      // 2️⃣ If we can parse coordinates from the Maps URL, store them too
      final coords = _extractLatLonFromMapsUrl(mapsUrl);
      if (coords != null) {
        final lat = coords['latitude']!;
        final lon = coords['longitude']!;
        debugPrint('Extracted coords from URL: $lat, $lon');

        await supabase
            .from('companies')
            .update({
              'latitude': lat,
              'longitude': lon,
            })
            .eq('id', _companyId!);
      } else {
        debugPrint('No coordinates found in maps_url.');
      }

      if (!mounted) return;

      widget.onBusinessUpdated?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business updated.')),
      );
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

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.black.withOpacity(0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white70, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Edit Business'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
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
                                  if (_myCompanies.length > 1) ...[
                                    const Text(
                                      'Select company to edit',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: _companyId,
                                      dropdownColor: const Color(0xFF020617),
                                      decoration: _inputDecoration('Company'),
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
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        final company = _myCompanies.firstWhere(
                                          (c) =>
                                              c['id']?.toString() == value,
                                        );
                                        _applyCompany(company);

                                        final name = (company['name'] ??
                                                'your company')
                                            .toString();

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Switched to $name',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                  ] else ...[
                                    Text(
                                      'Editing: ${_nameController.text.isEmpty ? 'Your company' : _nameController.text}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  const Text(
                                    'Business details',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  TextFormField(
                                    controller: _nameController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration:
                                        _inputDecoration('Company Name'),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Enter a company name'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _sloganController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration:
                                        _inputDecoration('Company Slogan'),
                                  ),
                                  const SizedBox(height: 12),

                                  DropdownButtonFormField<String>(
                                    value: _selectedCategory,
                                    decoration: _inputDecoration('Category'),
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
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _cityController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration('City'),
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _mapsUrlController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      'Google Maps Link',
                                      hint:
                                          'Paste the full Google Maps URL (with @lat,lon)',
                                    ),
                                    keyboardType: TextInputType.url,
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _descriptionController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    maxLines: 3,
                                    decoration:
                                        _inputDecoration('Short Description'),
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _servicesController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      'Services Offered (comma separated)',
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _pricesController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    maxLines: 3,
                                    decoration: _inputDecoration(
                                      'Prices (one per line, e.g. "Engine design - R45 000")',
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _imageUrlsController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      'Project Image URLs (comma separated)',
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _emailController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration:
                                        _inputDecoration('Contact Email'),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: _phoneController,
                                    style:
                                        const TextStyle(color: Colors.white),
                                    decoration:
                                        _inputDecoration('Contact Phone'),
                                    keyboardType: TextInputType.phone,
                                  ),
                                  const SizedBox(height: 20),

                                  ElevatedButton(
                                    onPressed:
                                        _saving ? null : _saveChanges,
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
                                          : const Text(
                                              'Save Changes',
                                              style: TextStyle(fontSize: 16),
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

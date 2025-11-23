// lib/screens/create_company_screen.dart
import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../widgets/hive_background.dart';

class CreateCompanyScreen extends StatefulWidget {
  const CreateCompanyScreen({super.key});

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _sloganController =
      TextEditingController(text: 'The lifeline of companies');
  final _cityController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _servicesController = TextEditingController();
  final _pricesController = TextEditingController();
  final _imageUrlsController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  final List<String> _categories = [
    'Construction',
    'Engineering',
    'Attorneys',
    'IT Services',
    'Manufacturing',
    'Logistics',
    'Consulting',
  ];

  String? _selectedCategory;
  bool _submitting = false;

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
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
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
      };

      await supabase.from('companies').insert(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company profile created.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving company: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  // 🔹 Common decoration for all inputs so they look consistent & readable
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
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
        title: const Text(
          'Create Company Profile',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: HiveBackground(
        child: SafeArea(
          child: SingleChildScrollView(
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
                        const Text(
                          'Create your company profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Company Name
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration('Company Name'),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter a company name'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // Slogan
                        TextFormField(
                          controller: _sloganController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration('Company Slogan'),
                        ),
                        const SizedBox(height: 12),

                        // Category
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: _inputDecoration('Category'),
                          dropdownColor: const Color(0xFF020617),
                          style: const TextStyle(color: Colors.white),
                          items: _categories
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            _selectedCategory = value;
                          }),
                          validator: (v) =>
                              v == null ? 'Please choose a category' : null,
                        ),
                        const SizedBox(height: 12),

                        // City
                        TextFormField(
                          controller: _cityController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration('City'),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter a city'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // Description
                        TextFormField(
                          controller: _descriptionController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration('Short Description'),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),

                        // Services
                        TextFormField(
                          controller: _servicesController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                              'Services Offered (comma separated)'),
                        ),
                        const SizedBox(height: 12),

                        // Prices
                        TextFormField(
                          controller: _pricesController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            'Prices (one per line, e.g. "Engine design - R45 000")',
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),

                        // Image URLs
                        TextFormField(
                          controller: _imageUrlsController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                              'Project Image URLs (comma separated)'),
                        ),
                        const SizedBox(height: 12),

                        // Email
                        TextFormField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration('Contact Email'),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),

                        // Phone
                        TextFormField(
                          controller: _phoneController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration('Contact Phone'),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 20),

                        ElevatedButton(
                          onPressed: _submitting ? null : _submitForm,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Save Company Profile',
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

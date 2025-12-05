// lib/screens/post_job_screen.dart
import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../widgets/hive_background.dart';

class PostJobScreen extends StatefulWidget {
  final String companyId;

  const PostJobScreen({
    super.key,
    required this.companyId,
  });

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _employmentTypeController = TextEditingController();
  final _salaryMinController = TextEditingController();
  final _salaryMaxController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _employmentTypeController.dispose();
    _salaryMinController.dispose();
    _salaryMaxController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final location = _locationController.text.trim();
      final employmentType = _employmentTypeController.text.trim();
      final salaryMin = int.tryParse(_salaryMinController.text.trim());
      final salaryMax = int.tryParse(_salaryMaxController.text.trim());

      await supabase.from('jobs').insert({
        'company_id': widget.companyId,
        'title': title,
        'description': description,
        'location': location.isEmpty ? null : location,
        'employment_type':
            employmentType.isEmpty ? null : employmentType,
        'salary_min': salaryMin,
        'salary_max': salaryMax,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job posted successfully')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Failed to post job: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Post a Job',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Job title',
                              hintText: 'e.g. Senior Electrician',
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Please enter a job title'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _locationController,
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              hintText: 'e.g. Potchefstroom, North West',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _employmentTypeController,
                            decoration: const InputDecoration(
                              labelText: 'Employment type',
                              hintText: 'Full-time, Part-time, Contract...',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _salaryMinController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Min salary (optional)',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _salaryMaxController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Max salary (optional)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Job description',
                              hintText:
                                  'Responsibilities, requirements, how to apply…',
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty
                                    ? 'Please enter a description'
                                    : null,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(
                                  _saving ? 'Posting…' : 'Post Job Listing'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

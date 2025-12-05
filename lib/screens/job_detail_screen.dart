// lib/screens/job_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';
import 'company_detail_screen.dart';

class JobDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const JobDetailScreen({
    super.key,
    required this.job,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  Map<String, dynamic>? _company;
  bool _loadingCompany = true;
  String? _error;

  static const gold = Color.fromARGB(255, 241, 178, 70);

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final companyId = widget.job['company_id'];
    if (companyId == null) {
      setState(() {
        _loadingCompany = false;
      });
      return;
    }

    try {
      final res = await supabase
          .from('companies')
          .select(
            // IMPORTANT: no "address" here, only existing columns
            'id, name, slogan, city, category, '
            'phone, email, website, maps_url, logo_url, is_paid',
          )
          .eq('id', companyId)
          .maybeSingle();

      setState(() {
        _company = res as Map<String, dynamic>?;
        _loadingCompany = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load company info: $e';
        _loadingCompany = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----------------- CONTACT HELPERS -----------------

  Future<void> _callCompany(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      _snack('No phone number available.');
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('Could not open phone app.');
    }
  }

  Future<void> _whatsappCompany(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      _snack('No phone number available.');
      return;
    }

    final clean = phone.replaceAll(' ', '');
    final uri = Uri.parse('https://wa.me/$clean');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open WhatsApp.');
    }
  }

  Future<void> _openDirections(
    String? address, // we’ll pass null, but keep param for flexibility
    String? city,
    String? mapsUrl,
  ) async {
    Uri? uri;

    if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
      try {
        uri = Uri.parse(mapsUrl.trim());
      } catch (_) {}
    }

    if (uri == null) {
      final query = address != null && address.trim().isNotEmpty
          ? "$address, ${city ?? ''}"
          : (city ?? '');

      if (query.trim().isEmpty) {
        _snack('No address available.');
        return;
      }

      final encoded = Uri.encodeComponent(query);
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$encoded');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open maps.');
    }
  }

  Future<void> _shareJob(
    Map<String, dynamic> job,
    Map<String, dynamic>? company,
  ) async {
    final title = (job['title'] ?? '').toString();
    final location = (job['location'] ?? '').toString();
    final employmentType = (job['employment_type'] ?? '').toString();
    final companyName = company?['name']?.toString() ?? 'Company';

    final buf = StringBuffer()
      ..writeln(title.isEmpty ? 'Job opportunity' : title)
      ..writeln(companyName)
      ..writeln('');

    if (employmentType.isNotEmpty) {
      buf.writeln('Type: $employmentType');
    }
    if (location.isNotEmpty) {
      buf.writeln('Location: $location');
    }

    final description = (job['description'] ?? '').toString();
    if (description.isNotEmpty) {
      buf
        ..writeln('')
        ..writeln(description);
    }

    await Share.share(buf.toString().trim());
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    final job = widget.job;

    final title = (job['title'] ?? '').toString();
    final description = (job['description'] ?? '').toString();
    final location =
        (job['location'] ?? 'Location not specified').toString();
    final employmentType =
        (job['employment_type'] ?? '').toString().trim();

    final salaryMin = job['salary_min'] as int?;
    final salaryMax = job['salary_max'] as int?;
    final createdAt =
        DateTime.tryParse((job['created_at'] ?? '').toString());

    final isVerified = job['company_is_verified'] == true;

    String buildSalaryText() {
      if (salaryMin == null && salaryMax == null) {
        return 'Not specified';
      } else if (salaryMin != null && salaryMax != null) {
        return 'R$salaryMin – R$salaryMax';
      } else if (salaryMin != null) {
        return 'From R$salaryMin';
      } else {
        return 'Up to R$salaryMax';
      }
    }

    final companyName = _company?['name']?.toString();
    final companyCity = _company?['city']?.toString();
    final companyCategory = _company?['category']?.toString();
    final slogan = _company?['slogan']?.toString();
    final phone = _company?['phone']?.toString();
    final email = _company?['email']?.toString();
    final website = _company?['website']?.toString();
    final mapsUrl = _company?['maps_url']?.toString();
    final logoUrl = _company?['logo_url']?.toString();
    final isPaid = _company?['is_paid'] == true;

    Widget buildCompanyAvatar() {
      if (logoUrl != null && logoUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white10,
          backgroundImage: NetworkImage(logoUrl),
        );
      }
      return const CircleAvatar(
        radius: 24,
        backgroundColor: Colors.white24,
        child: Icon(Icons.business, color: Colors.white),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          title.isEmpty ? 'Job details' : title,
          style: const TextStyle(color: Colors.white),
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
                constraints: const BoxConstraints(maxWidth: 700),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // HEADER (job + company)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildCompanyAvatar(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (companyName != null &&
                                    companyName.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        companyName,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (isPaid || isVerified) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.verified,
                                          size: 18,
                                          color: Colors.greenAccent,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                                if (slogan != null &&
                                    slogan.isNotEmpty)
                                  Text(
                                    slogan,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white60,
                                    ),
                                  ),
                                Text(
                                  [
                                    if (companyCategory != null &&
                                        companyCategory.isNotEmpty)
                                      companyCategory,
                                    if (companyCity != null &&
                                        companyCity.isNotEmpty)
                                      companyCity,
                                  ].join(' • '),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // JOB META (chips)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white24,
                            width: 0.8,
                          ),
                          color: Colors.black.withOpacity(0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoChip(
                                  icon: Icons.place_outlined,
                                  label: location,
                                ),
                                if (employmentType.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.work_outline,
                                    label: employmentType,
                                  ),
                                _InfoChip(
                                  icon: Icons.payments_outlined,
                                  label: buildSalaryText(),
                                ),
                                if (createdAt != null)
                                  _InfoChip(
                                    icon: Icons
                                        .calendar_today_outlined,
                                    label:
                                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // DESCRIPTION
                      const Text(
                        'Job description',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white24,
                            width: 0.8,
                          ),
                          color: Colors.black.withOpacity(0.45),
                        ),
                        child: Text(
                          description.isEmpty
                              ? 'No description provided.'
                              : description,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // CONTACT / ACTIONS
                      if (_loadingCompany)
                        const LinearProgressIndicator(minHeight: 2)
                      else if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12),
                        )
                      else if (_company != null) ...[
                        const Text(
                          'Contact / next steps',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if ((email ?? '').isNotEmpty ||
                            (phone ?? '').isNotEmpty ||
                            (website ?? '').isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 8.0),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if ((email ?? '').isNotEmpty)
                                  Text(
                                    'Email: $email',
                                    style: const TextStyle(
                                        color: Colors.white70),
                                  ),
                                if ((phone ?? '').isNotEmpty)
                                  Text(
                                    'Phone: $phone',
                                    style: const TextStyle(
                                        color: Colors.white70),
                                  ),
                                if ((website ?? '').isNotEmpty)
                                  Text(
                                    'Website: $website',
                                    style: const TextStyle(
                                        color: Colors.white70),
                                  ),
                              ],
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: phone == null ||
                                      phone.trim().isEmpty
                                  ? null
                                  : () => _callCompany(phone),
                              icon: const Icon(Icons.call),
                              label: const Text('Call'),
                            ),
                            ElevatedButton.icon(
                              onPressed: phone == null ||
                                      phone.trim().isEmpty
                                  ? null
                                  : () => _whatsappCompany(phone),
                              icon: const FaIcon(
                                FontAwesomeIcons.whatsapp,
                                size: 18,
                              ),
                              label: const Text('WhatsApp'),
                            ),
                            ElevatedButton.icon(
                              onPressed: (companyCity == null ||
                                          companyCity
                                              .trim()
                                              .isEmpty) &&
                                      (mapsUrl == null ||
                                          mapsUrl
                                              .trim()
                                              .isEmpty)
                                  ? null
                                  : () => _openDirections(
                                        null, // no address column
                                        companyCity,
                                        mapsUrl,
                                      ),
                              icon: const Icon(Icons.directions),
                              label: const Text('Directions'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _shareJob(
                                  job, _company),
                              icon: const Icon(Icons.share),
                              label: const Text('Share job'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (_company == null) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CompanyDetailScreen(
                                      company: _company!,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.business),
                              label:
                                  const Text('View company profile'),
                            ),
                          ],
                        ),
                      ],
                    ],
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white10,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

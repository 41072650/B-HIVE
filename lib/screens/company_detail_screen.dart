// lib/screens/company_detail_screen.dart
import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../widgets/hive_background.dart';

class CompanyDetailScreen extends StatefulWidget {
  final Map<String, dynamic> company;

  const CompanyDetailScreen({super.key, required this.company});

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  double _userRating = 0;

  List<String> _splitLines(String? text) {
    if (text == null || text.trim().isEmpty) return [];
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _splitComma(String? text) {
    if (text == null || text.trim().isEmpty) return [];
    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _submitRating() async {
    if (_userRating <= 0) return;

    final company = widget.company;
    final id = company['id'];

    final currentAvg = (company['rating_avg'] ?? 0).toDouble();
    final currentCount = (company['rating_count'] ?? 0) as int;

    final newCount = currentCount + 1;
    final newAvg = ((currentAvg * currentCount) + _userRating) / newCount;

    await supabase
        .from('companies')
        .update({'rating_avg': newAvg, 'rating_count': newCount})
        .eq('id', id);

    setState(() {
      widget.company['rating_avg'] = newAvg;
      widget.company['rating_count'] = newCount;
      _userRating = 0;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks for rating!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.company;
    final ratingAvg = (c['rating_avg'] ?? 0).toDouble();
    final ratingCount = (c['rating_count'] ?? 0) as int;

    final services = _splitComma(c['services'] as String?);
    final prices = _splitLines(c['prices'] as String?);
    final imageUrls = _splitComma(c['image_urls'] as String?);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          c['name'] ?? '',
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
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.business, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['name'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (c['slogan'] != null &&
                                    c['slogan'].toString().isNotEmpty)
                                  Text(
                                    c['slogan'],
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white70,
                                    ),
                                  ),
                                Text(
                                  '${c['category'] ?? ''} • ${c['city'] ?? ''}',
                                  style:
                                      const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'Rating:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (ratingCount == 0)
                            const Text(
                              'No ratings yet',
                              style: TextStyle(color: Colors.white70),
                            )
                          else ...[
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '${ratingAvg.toStringAsFixed(1)} ($ratingCount reviews)',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        c['description'] ?? '—',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Services',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (services.isEmpty)
                        const Text('—',
                            style: TextStyle(color: Colors.white70))
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: services
                              .map(
                                (s) => Text(
                                  '• $s',
                                  style:
                                      const TextStyle(color: Colors.white70),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Prices',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (prices.isEmpty)
                        const Text('—',
                            style: TextStyle(color: Colors.white70))
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: prices
                              .map(
                                (p) => Text(
                                  '• $p',
                                  style:
                                      const TextStyle(color: Colors.white70),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Project History',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (imageUrls.isEmpty)
                        const Text(
                          'No project images yet.',
                          style: TextStyle(color: Colors.white70),
                        )
                      else
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: imageUrls.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final url = imageUrls[index];
                              return AspectRatio(
                                aspectRatio: 4 / 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade800,
                                      child: const Icon(
                                        Icons.broken_image,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Contact',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Email: ${c['email'] ?? '—'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Phone: ${c['phone'] ?? '—'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      Divider(color: Colors.white24),
                      const Text(
                        'Rate this company',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DropdownButton<double>(
                            value: _userRating == 0 ? null : _userRating,
                            hint: const Text(
                              'Select rating',
                              style: TextStyle(color: Colors.white70),
                            ),
                            dropdownColor: const Color(0xFF020617),
                            style: const TextStyle(color: Colors.white),
                            iconEnabledColor: Colors.white,
                            items: [1, 2, 3, 4, 5]
                                .map(
                                  (v) => DropdownMenuItem<double>(
                                    value: v.toDouble(),
                                    child: Text('$v ★'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _userRating = value ?? 0;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _userRating == 0 ? null : _submitRating,
                            child: const Text('Submit'),
                          ),
                        ],
                      ),
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

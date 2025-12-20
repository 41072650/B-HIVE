// lib/screens/business_profile_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../supabase_client.dart';
import '../widgets/hive_background.dart';
import '../widgets/bhive_inputs.dart';
import '../Constants/category_map.dart'; // kCategorySubcategories, kAllCategories

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

  // Category / Subcategory
  String? _selectedCategory;
  String? _selectedSubcategory;

  bool _usingOtherCategory = false;
  bool _usingOtherSubcategory = false;

  final TextEditingController _otherCategoryController = TextEditingController();
  final TextEditingController _otherSubcategoryController =
      TextEditingController();

  // State
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _myCompanies = [];
  String? _companyId; // null = “creating new”
  bool _isCreatingNew = false;
  bool _isPaid = false; // subscription flag for the selected company (used as "Verified" for now)

  // Layout toggle
  bool _showEditForm = false;

  // ---- Logo upload state ----
  final ImagePicker _picker = ImagePicker();
  Uint8List? _newLogoBytes;
  String? _newLogoExt;
  String? _logoUrl; // current stored logo URL

  // Bucket constants
  static const String _bucketCompanyAds = 'company-ads';
  static const String _bucketCompanyLogos = 'company-logos';

  // Ads preview state (My Business)
  bool _myAdsLoading = false;
  String? _myAdsError;

  // Keep existing variable for grid rendering (URLS),
  // but also store the underlying storage path for delete.
  final List<String> _myAdSignedUrls = [];
  final List<String> _myAdPaths = []; // index-aligned with _myAdSignedUrls

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

    _otherCategoryController.dispose();
    _otherSubcategoryController.dispose();

    super.dispose();
  }

  // ---------- helpers ----------
  String _normalizeExt(String ext) {
    final e = ext.trim().toLowerCase();
    if (e == 'jpeg') return 'jpg';
    return e;
  }

  String _contentTypeForExt(String ext) {
    final e = _normalizeExt(ext);
    switch (e) {
      case 'jpg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  bool _isAllowedImageExt(String ext) {
    final e = _normalizeExt(ext);
    return e == 'jpg' || e == 'png' || e == 'webp';
  }

  bool _isAllowedVideoExt(String ext) {
    final e = _normalizeExt(ext);
    return e == 'mp4' || e == 'mov' || e == 'webm';
  }

  bool _isVideoPath(String pathOrName) {
    final n = pathOrName.toLowerCase();
    return n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.webm');
  }

  // ✅ Share options (system only for now)
  Future<void> _openShareSheetForAd(String url) async {
    final companyName = _nameController.text.trim().isEmpty
        ? 'B-Hive'
        : _nameController.text.trim();
    final text = 'Check out this ad from $companyName on B-Hive:\n$url';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              height: 4,
              width: 42,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const ListTile(
              title: Text(
                'Share Ad',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Choose how you want to share this ad.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.ios_share, color: Colors.white),
              title: const Text('Share…', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'System share menu',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Share.share(text);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ✅ Fixed-size Ad Viewer (with Share + Remove for owner)
  void _openAdViewer(int initialIndex) {
    if (_myAdSignedUrls.isEmpty) return;
    if (initialIndex < 0 || initialIndex >= _myAdSignedUrls.length) return;

    final pageController = PageController(initialPage: initialIndex);
    int currentIndex = initialIndex;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 720,
                maxHeight: 620,
                minWidth: 320,
                minHeight: 420,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F1A).withOpacity(0.98),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                      child: Row(
                        children: [
                          if ((_logoUrl ?? '').toString().isNotEmpty)
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white10,
                              backgroundImage: NetworkImage(_logoUrl!),
                            )
                          else
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.business,
                                  color: Colors.white, size: 16),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _nameController.text.trim().isEmpty
                                  ? 'Company'
                                  : _nameController.text.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: StatefulBuilder(
                            builder: (context, setInner) {
                              pageController.addListener(() {
                                final p = pageController.page;
                                if (p == null) return;
                                final idx = p.round();
                                if (idx != currentIndex &&
                                    idx >= 0 &&
                                    idx < _myAdSignedUrls.length) {
                                  currentIndex = idx;
                                  setInner(() {});
                                }
                              });

                              return PageView.builder(
                                controller: pageController,
                                itemCount: _myAdSignedUrls.length,
                                itemBuilder: (context, index) {
                                  final url = _myAdSignedUrls[index];
                                  final path = _myAdPaths[index];
                                  final isVideo = _isVideoPath(path);

                                  return LayoutBuilder(
                                    builder: (context, constraints) {
                                      if (isVideo) {
                                        return SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: _AdVideoPlayer(url: url),
                                        );
                                      }

                                      return InteractiveViewer(
                                        minScale: 1.0,
                                        maxScale: 4.0,
                                        child: SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: Image.network(
                                            url,
                                            width: constraints.maxWidth,
                                            height: constraints.maxHeight,
                                            fit: BoxFit.contain,
                                            alignment: Alignment.center,
                                            errorBuilder: (_, __, ___) =>
                                                const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Center(
                                                child: Text(
                                                  'Could not load image.',
                                                  style: TextStyle(
                                                      color: Colors.white70),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              final url = _myAdSignedUrls.isEmpty
                                  ? null
                                  : _myAdSignedUrls[currentIndex];
                              if (url == null) return;
                              _openShareSheetForAd(url);
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Remove Ad',
                            onPressed: () async {
                              await _confirmAndDeleteAd(
                                index: currentIndex,
                                controller: pageController,
                              );
                            },
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndDeleteAd({
    required int index,
    required PageController controller,
  }) async {
    if (_companyId == null) return;
    if (index < 0 || index >= _myAdPaths.length) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0B0F1A),
        title: const Text('Remove ad',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'Are you sure you want to delete this ad?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final path = _myAdPaths[index];

    try {
      await supabase.storage.from(_bucketCompanyAds).remove([path]);

      if (!mounted) return;

      setState(() {
        _myAdSignedUrls.removeAt(index);
        _myAdPaths.removeAt(index);
      });

      if (_myAdSignedUrls.isEmpty) {
        try {
          await supabase
              .from('companies')
              .update({'has_ads': false}).eq('id', _companyId!);
        } catch (_) {}

        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad deleted.')),
        );
        return;
      }

      final newIndex = index.clamp(0, _myAdSignedUrls.length - 1);
      if (controller.hasClients) {
        controller.jumpToPage(newIndex);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete ad: $e')),
      );
    }
  }

  // ✅ Load my ads for current company (images + videos)
  Future<void> _loadMyAds() async {
    final companyId = _companyId;
    if (companyId == null || companyId.isEmpty) return;

    setState(() {
      _myAdsLoading = true;
      _myAdsError = null;
      _myAdSignedUrls.clear();
      _myAdPaths.clear();
    });

    try {
      final objects = await supabase.storage.from(_bucketCompanyAds).list(
            path: '$companyId/ads',
          );

      final mediaObjects = objects.where((o) {
        final name = (o.name ?? '').toLowerCase();
        return name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp') ||
            name.endsWith('.mp4') ||
            name.endsWith('.mov') ||
            name.endsWith('.webm');
      }).toList();

      mediaObjects.sort((a, b) => (b.name ?? '').compareTo(a.name ?? ''));

      final urls = <String>[];
      final paths = <String>[];

      for (final o in mediaObjects) {
        final filePath = '$companyId/ads/${o.name}';
        final signedUrl = await supabase.storage
            .from(_bucketCompanyAds)
            .createSignedUrl(filePath, 60 * 60);
        urls.add(signedUrl);
        paths.add(filePath);
      }

      if (!mounted) return;
      setState(() {
        _myAdSignedUrls.addAll(urls);
        _myAdPaths.addAll(paths);
        _myAdsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _myAdsLoading = false;
        _myAdsError = 'Failed to load your ads: $e';
      });
    }
  }

  // ✅ Ads grid widget (My Business)
  Widget _buildMyAdsGrid() {
    if (_companyId == null || _isCreatingNew) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'Your Ads',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: _myAdsLoading ? null : _loadMyAds,
              child: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_myAdsLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (_myAdsError != null)
          Text(
            _myAdsError!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          )
        else if (_myAdSignedUrls.isEmpty)
          const Text(
            'No ads uploaded yet.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myAdSignedUrls.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, i) {
              final url = _myAdSignedUrls[i];
              final path = _myAdPaths[i];
              final isVideo = _isVideoPath(path);

              return GestureDetector(
                onTap: () => _openAdViewer(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.white10,
                    child: isVideo
                        ? Stack(
                            fit: StackFit.expand,
                            children: const [
                              Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white70,
                                  size: 42,
                                ),
                              ),
                            ],
                          )
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child:
                                  Icon(Icons.broken_image, color: Colors.white54),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ✅ NEW: Open manual verification screen (no Paystack)
  void _openVerifyScreen() {
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a company first.')),
      );
      return;
    }

    final companyName = _nameController.text.trim().isEmpty
        ? 'Your business'
        : _nameController.text.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerifyBusinessScreen(
          companyId: _companyId!,
          companyName: companyName,
          userEmail: supabase.auth.currentUser?.email ?? '',
        ),
      ),
    );
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
        _companyId = null;
        _isCreatingNew = true;
        _isPaid = false;
        _clearForm();
        _showEditForm = true;
      } else {
        _isCreatingNew = false;
        _applyCompany(list.first);
        _showEditForm = false;
      }

      setState(() => _loading = false);
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
    _selectedSubcategory = null;
    _usingOtherCategory = false;
    _usingOtherSubcategory = false;
    _otherCategoryController.clear();
    _otherSubcategoryController.clear();

    _isPaid = false;
    _logoUrl = null;
    _newLogoBytes = null;
    _newLogoExt = null;

    _myAdSignedUrls.clear();
    _myAdPaths.clear();
    _myAdsError = null;
    _myAdsLoading = false;
  }

  void _applyCompany(Map<String, dynamic> data) {
    final category = (data['category'] ?? '') as String? ?? '';
    final subcategory = (data['subcategory'] ?? '') as String? ?? '';

    setState(() {
      _companyId = data['id']?.toString();
      _isCreatingNew = false;

      _nameController.text = (data['name'] ?? '') as String;
      _sloganController.text = (data['slogan'] ?? '') as String;
      _cityController.text = (data['city'] ?? '') as String;
      _descriptionController.text = (data['description'] ?? '') as String;
      _servicesController.text = (data['services'] ?? '') as String;
      _pricesController.text = (data['prices'] ?? '') as String;
      _imageUrlsController.text = (data['image_urls'] ?? '') as String;
      _emailController.text = (data['email'] ?? '') as String;
      _phoneController.text = (data['phone'] ?? '') as String;
      _mapsUrlController.text = (data['maps_url'] ?? '') as String;
      _logoUrl = (data['logo_url'] ?? '') as String?;

      if (category.isEmpty) {
        _selectedCategory = null;
        _usingOtherCategory = false;
        _otherCategoryController.clear();
      } else if (kAllCategories.contains(category)) {
        _selectedCategory = category;
        _usingOtherCategory = false;
        _otherCategoryController.clear();
      } else {
        _selectedCategory = null;
        _usingOtherCategory = true;
        _otherCategoryController.text = category;
      }

      if (subcategory.isEmpty) {
        _selectedSubcategory = null;
        _usingOtherSubcategory = false;
        _otherSubcategoryController.clear();
      } else {
        final validSubs = _selectedCategory == null || _usingOtherCategory
            ? const <String>[]
            : (kCategorySubcategories[_selectedCategory] ?? const <String>[]);

        if (!_usingOtherCategory && validSubs.contains(subcategory)) {
          _selectedSubcategory = subcategory;
          _usingOtherSubcategory = false;
          _otherSubcategoryController.clear();
        } else {
          _selectedSubcategory = null;
          _usingOtherSubcategory = true;
          _otherSubcategoryController.text = subcategory;
        }
      }

      _isPaid = data['is_paid'] == true; // used as Verified for now
      _newLogoBytes = null;
      _newLogoExt = null;
    });

    Future.microtask(_loadMyAds);
  }

  Map<String, double>? _extractLatLonFromMapsUrl(String url) {
    if (url.isEmpty) return null;

    final atPattern = RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)');
    final atMatch = atPattern.firstMatch(url);
    if (atMatch != null && atMatch.groupCount >= 2) {
      final lat = double.tryParse(atMatch.group(1) ?? '');
      final lon = double.tryParse(atMatch.group(2) ?? '');
      if (lat != null && lon != null) return {'latitude': lat, 'longitude': lon};
    }

    final dPattern = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)');
    final dMatch = dPattern.firstMatch(url);
    if (dMatch != null && dMatch.groupCount >= 2) {
      final lat = double.tryParse(dMatch.group(1) ?? '');
      final lon = double.tryParse(dMatch.group(2) ?? '');
      if (lat != null && lon != null) return {'latitude': lat, 'longitude': lon};
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
      final ext = _normalizeExt(picked.name.split('.').last.toLowerCase());

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
    if (_newLogoBytes == null) return _logoUrl;

    final ext = _normalizeExt(_newLogoExt ?? 'jpg');
    final path = 'logos/$companyId-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await supabase.storage.from(_bucketCompanyLogos).uploadBinary(
          path,
          _newLogoBytes!,
          fileOptions: FileOptions(contentType: _contentTypeForExt(ext)),
        );

    final publicUrl =
        supabase.storage.from(_bucketCompanyLogos).getPublicUrl(path);
    return publicUrl;
  }

  Map<String, dynamic> _buildCategoryPayload() {
    final categoryToSave = _usingOtherCategory
        ? _otherCategoryController.text.trim()
        : (_selectedCategory ?? '');

    String? subcategoryToSave;
    if (_usingOtherSubcategory) {
      final text = _otherSubcategoryController.text.trim();
      subcategoryToSave = text.isEmpty ? null : text;
    } else {
      subcategoryToSave = _selectedSubcategory;
    }

    return {
      'category': categoryToSave.isEmpty ? null : categoryToSave,
      'subcategory': subcategoryToSave,
    };
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
      final categoryPayload = _buildCategoryPayload();

      final insertData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'slogan': _sloganController.text.trim(),
        'category': categoryPayload['category'],
        'subcategory': categoryPayload['subcategory'],
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'services': _servicesController.text.trim(),
        'prices': _pricesController.text.trim(),
        'image_urls': _imageUrlsController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'maps_url': mapsUrl,
        'owner_id': user.id,
        'is_paid': false, // stays false until you manually verify later
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
      await _loadMyCompanies();

      if (mounted) setState(() => _showEditForm = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating company: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_companyId == null) return _createCompany();

    setState(() => _saving = true);

    try {
      final mapsUrl = _mapsUrlController.text.trim();
      final categoryPayload = _buildCategoryPayload();

      final updateData = {
        'name': _nameController.text.trim(),
        'slogan': _sloganController.text.trim(),
        'category': categoryPayload['category'],
        'subcategory': categoryPayload['subcategory'],
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'services': _servicesController.text.trim(),
        'prices': _pricesController.text.trim(),
        'image_urls': _imageUrlsController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'maps_url': mapsUrl,
      };

      final logoUrl = await _uploadLogoIfNeeded(_companyId!);
      if (logoUrl != null && logoUrl.isNotEmpty) updateData['logo_url'] = logoUrl;

      await supabase.from('companies').update(updateData).eq('id', _companyId!);

      final coords = _extractLatLonFromMapsUrl(mapsUrl);
      if (coords != null) {
        await supabase
            .from('companies')
            .update({'latitude': coords['latitude'], 'longitude': coords['longitude']})
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

      setState(() => _showEditForm = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating business: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ✅ Upload media (image OR video) to same bucket/path
  Future<void> _addBusinessMedia() async {
    if (_companyId == null) return;

    try {
      final XFile? picked = await _picker.pickMedia(
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? _normalizeExt(picked.name.split('.').last.toLowerCase())
          : '';

      final isImage = _isAllowedImageExt(ext);
      final isVideo = _isAllowedVideoExt(ext);

      if (!isImage && !isVideo) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only PNG/JPG/WEBP images or MP4/MOV/WEBM videos are allowed.'),
          ),
        );
        return;
      }

      // Optional size limit for videos (30MB)
      if (isVideo && bytes.lengthInBytes > 30 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video too large. Max 30MB.')),
        );
        return;
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_companyId!}/ads/$ts.$ext';

      await supabase.storage.from(_bucketCompanyAds).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: _contentTypeForExt(ext)),
          );

      try {
        await supabase.from('companies').update({'has_ads': true}).eq('id', _companyId!);
      } catch (_) {}

      await _loadMyAds();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isVideo ? 'Video uploaded successfully' : 'Image uploaded successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload media: $e')),
      );
    }
  }

  void _shareBusiness() {
    if (_companyId == null) return;

    final name = _nameController.text.trim().isEmpty
        ? 'my business'
        : _nameController.text.trim();
    final link = 'https://bhive.app/business/$_companyId';
    Share.share('Check out $name on B-Hive 👇\n$link');
  }

  Widget _buildLogoPreview() {
    Widget content;

    if (_newLogoBytes != null) {
      content =
          CircleAvatar(radius: 32, backgroundImage: MemoryImage(_newLogoBytes!));
    } else if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      content = CircleAvatar(radius: 32, backgroundImage: NetworkImage(_logoUrl!));
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Company logo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 2),
              Text(
                'Add a logo to stand out in the search results.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _pickNewLogo,
          icon: const Icon(Icons.upload_file, size: 18, color: Colors.amber),
          label: const Text('Upload', style: TextStyle(color: Colors.amber)),
        ),
      ],
    );
  }

  Widget _buildSubscriptionCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amberAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Business Verification',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (_companyId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isPaid ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isPaid ? 'Verified' : 'Free plan',
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
                ? 'Your business is verified.'
                : 'Want to verify your business? Email us and we will help you get verified.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openVerifyScreen,
              child: Text(_isPaid ? 'Contact support' : 'Email to verify'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySelector() {
    final isEditingExisting = !_isCreatingNew && _companyId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _isCreatingNew = true;
                _companyId = null;
                _clearForm();
                _showEditForm = true;
              });
            },
            child: const Text('Add Business'),
          ),
        ),
        const SizedBox(height: 12),
        if (_myCompanies.isNotEmpty)
          DropdownButtonFormField<String?>(
            value: isEditingExisting ? _companyId : null,
            decoration: bhiveInputDecoration('Select Business'),
            dropdownColor: const Color(0xFF020617),
            style: const TextStyle(color: Colors.white),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Create new company'),
              ),
              ..._myCompanies.map(
                (c) => DropdownMenuItem<String?>(
                  value: c['id']?.toString(),
                  child: Text((c['name'] ?? 'Unnamed company').toString()),
                ),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                setState(() {
                  _isCreatingNew = true;
                  _companyId = null;
                  _clearForm();
                  _showEditForm = true;
                });
              } else {
                final company =
                    _myCompanies.firstWhere((c) => c['id']?.toString() == value);
                _applyCompany(company);
                final name = (company['name'] ?? 'your company').toString();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Switched to $name')));
                setState(() => _showEditForm = false);
              }
            },
          ),
      ],
    );
  }

  Widget _buildBusinessCard() {
    if (_companyId == null || _isCreatingNew) return const SizedBox.shrink();

    final title =
        _nameController.text.isEmpty ? 'Your Business' : _nameController.text;
    final subtitleParts = <String>[];
    final cat = _usingOtherCategory
        ? _otherCategoryController.text.trim()
        : (_selectedCategory ?? '').trim();
    if (cat.isNotEmpty) subtitleParts.add(cat);
    if (_cityController.text.trim().isNotEmpty) {
      subtitleParts.add(_cityController.text.trim());
    }
    final subtitle = subtitleParts.join(' • ');

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_logoUrl != null && _logoUrl!.isNotEmpty)
                CircleAvatar(radius: 18, backgroundImage: NetworkImage(_logoUrl!))
              else
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.business, color: Colors.white, size: 18),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_companyId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isPaid
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isPaid ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                  child: Text(
                    _isPaid ? 'Verified' : 'Free',
                    style: TextStyle(
                      color: _isPaid ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_descriptionController.text.trim().isNotEmpty) ...[
            const Text(
              'Description',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            Text(
              _descriptionController.text.trim(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            'Contact',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          Text(
            'Email: ${_emailController.text.trim().isEmpty ? '—' : _emailController.text.trim()}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            'Phone: ${_phoneController.text.trim().isEmpty ? '—' : _phoneController.text.trim()}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const Text(
            'Website: —',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              // ✅ Upload media (image/video)
              OutlinedButton.icon(
                onPressed: _addBusinessMedia,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Upload Media'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isCreatingNew = false;
                    _showEditForm = true;
                  });
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Info'),
              ),
              OutlinedButton.icon(
                onPressed: _shareBusiness,
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ],
          ),
          _buildMyAdsGrid(),
        ],
      ),
    );
  }

  Widget _buildFormView({
    required List<String> currentSubcategories,
    required bool advancedLocked,
    required bool isEditingExisting,
    required String primaryButtonText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _showEditForm = false),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text('Back', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildLogoPreview(),
        const SizedBox(height: 20),
        Text(
          isEditingExisting ? 'Edit your business details' : 'Business details',
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: bhiveInputDecoration('Company Name'),
          validator: (v) => (v == null || v.isEmpty) ? 'Enter a company name' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _sloganController,
          style: const TextStyle(color: Colors.white),
          readOnly: advancedLocked,
          decoration: bhiveInputDecoration('Company Slogan').copyWith(
            helperText: advancedLocked
                ? 'Upgrade to add a slogan that stands out in your profile.'
                : null,
            helperStyle: const TextStyle(color: Colors.white60, fontSize: 11),
            suffixIcon: advancedLocked
                ? const Icon(Icons.lock, size: 18, color: Colors.amberAccent)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _usingOtherCategory ? 'Other' : _selectedCategory,
          decoration: bhiveInputDecoration('Category'),
          dropdownColor: const Color(0xFF020617),
          style: const TextStyle(color: Colors.white),
          items: [
            ...kAllCategories.map(
              (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
            ),
            const DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              if (value == 'Other') {
                _usingOtherCategory = true;
                _selectedCategory = null;
                _selectedSubcategory = null;
                _usingOtherSubcategory = false;
                _otherSubcategoryController.clear();
                Future.microtask(() => FocusScope.of(context).nextFocus());
              } else {
                _usingOtherCategory = false;
                _selectedCategory = value;
                _selectedSubcategory = null;
                _usingOtherSubcategory = false;
                _otherCategoryController.clear();
                _otherSubcategoryController.clear();
              }
            });
          },
          validator: (_) {
            if (_usingOtherCategory) {
              if (_otherCategoryController.text.trim().isEmpty) {
                return 'Please enter a category';
              }
              return null;
            }
            if (_selectedCategory == null || _selectedCategory!.isEmpty) {
              return 'Please choose a category';
            }
            return null;
          },
        ),
        if (_usingOtherCategory) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _otherCategoryController,
            style: const TextStyle(color: Colors.white),
            decoration: bhiveInputDecoration('Other category')
                .copyWith(hintText: 'Type your category'),
          ),
        ],
        const SizedBox(height: 12),
        if (currentSubcategories.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            value: _usingOtherSubcategory ? 'Other' : _selectedSubcategory,
            decoration: bhiveInputDecoration('Sub-category'),
            dropdownColor: const Color(0xFF020617),
            style: const TextStyle(color: Colors.white),
            items: [
              ...currentSubcategories.map(
                (sub) => DropdownMenuItem(value: sub, child: Text(sub)),
              ),
              const DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                if (value == 'Other') {
                  _usingOtherSubcategory = true;
                  _selectedSubcategory = null;
                  Future.microtask(() => FocusScope.of(context).nextFocus());
                } else {
                  _usingOtherSubcategory = false;
                  _selectedSubcategory = value;
                  _otherSubcategoryController.clear();
                }
              });
            },
            validator: (_) {
              if (_usingOtherSubcategory &&
                  _otherSubcategoryController.text.trim().isEmpty) {
                return 'Please enter a sub-category';
              }
              return null;
            },
          ),
          if (_usingOtherSubcategory) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _otherSubcategoryController,
              style: const TextStyle(color: Colors.white),
              decoration: bhiveInputDecoration('Other sub-category')
                  .copyWith(hintText: 'Type your sub-category'),
            ),
          ],
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _cityController,
          style: const TextStyle(color: Colors.white),
          decoration: bhiveInputDecoration('City / Area'),
          validator: (v) => (v == null || v.isEmpty) ? 'Enter a city' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mapsUrlController,
          style: const TextStyle(color: Colors.white),
          readOnly: advancedLocked,
          decoration: bhiveInputDecoration(
            'Google Maps Link',
            hint: advancedLocked
                ? 'Upgrade to add a map pin for better local search.'
                : 'Paste the full Google Maps URL (with @lat,lon)',
          ).copyWith(
            suffixIcon: advancedLocked
                ? const Icon(Icons.lock, size: 18, color: Colors.amberAccent)
                : null,
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: bhiveInputDecoration('Short Description'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _servicesController,
          style: const TextStyle(color: Colors.white),
          readOnly: advancedLocked,
          decoration: bhiveInputDecoration('Services Offered (comma separated)')
              .copyWith(
            helperText: advancedLocked
                ? 'Upgrade to showcase detailed services on your profile.'
                : null,
            helperStyle: const TextStyle(color: Colors.white60, fontSize: 11),
            suffixIcon: advancedLocked
                ? const Icon(Icons.lock, size: 18, color: Colors.amberAccent)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _pricesController,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          readOnly: advancedLocked,
          decoration: bhiveInputDecoration(
                  'Prices (one per line, e.g. "Engine design - R45 000")')
              .copyWith(
            helperText: advancedLocked
                ? 'Upgrade to list detailed pricing and packages.'
                : null,
            helperStyle: const TextStyle(color: Colors.white60, fontSize: 11),
            suffixIcon: advancedLocked
                ? const Icon(Icons.lock, size: 18, color: Colors.amberAccent)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _imageUrlsController,
          style: const TextStyle(color: Colors.white),
          decoration: bhiveInputDecoration(
            'Project Image URLs (comma separated)',
            hint: _isPaid
                ? 'Add multiple image URLs, separated by commas.'
                : 'Free plan: only your first image will be shown.',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailController,
          style: const TextStyle(color: Colors.white),
          decoration: bhiveInputDecoration('Contact Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          style: const TextStyle(color: Colors.white),
          decoration: bhiveInputDecoration('Contact Phone'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () => isEditingExisting ? _saveChanges() : _createCompany(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(primaryButtonText, style: const TextStyle(fontSize: 16)),
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
    final advancedLocked = !_isPaid;

    final List<String> currentSubcategories = _usingOtherCategory
        ? const <String>[]
        : (_selectedCategory == null
            ? const <String>[]
            : (kCategorySubcategories[_selectedCategory] ?? const <String>[]));

    return Scaffold(
      body: HiveBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
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
                                  _buildSubscriptionCard(),
                                  if (!_showEditForm) ...[
                                    _buildCompanySelector(),
                                    _buildBusinessCard(),
                                  ],
                                  if (_showEditForm) ...[
                                    _buildFormView(
                                      currentSubcategories: currentSubcategories,
                                      advancedLocked: advancedLocked,
                                      isEditingExisting: isEditingExisting,
                                      primaryButtonText: primaryButtonText,
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
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ✅ Video player widget for signed URLs
// -----------------------------------------------------------------------------
class _AdVideoPlayer extends StatefulWidget {
  final String url;
  const _AdVideoPlayer({required this.url});

  @override
  State<_AdVideoPlayer> createState() => _AdVideoPlayerState();
}

class _AdVideoPlayerState extends State<_AdVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: false,
          looping: false,
          allowFullScreen: true,
          allowMuting: true,
        );
        setState(() {});
      });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chewieController == null ||
        _videoController?.value.isInitialized != true) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Chewie(controller: _chewieController!);
  }
}

// -----------------------------------------------------------------------------
// ✅ NEW SCREEN: VerifyBusinessScreen (manual email verification placeholder)
// -----------------------------------------------------------------------------
class VerifyBusinessScreen extends StatelessWidget {
  final String companyId;
  final String companyName;
  final String userEmail;

  const VerifyBusinessScreen({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.userEmail,
  });

  static const String supportEmail = 'support@bhive.app'; // change if needed

  Future<void> _openEmail(BuildContext context) async {
    final subject =
        Uri.encodeComponent('Business verification request - $companyName');
    final body = Uri.encodeComponent(
      'Hi B-Hive team,\n\n'
      'I would like to verify my business on B-Hive.\n\n'
      'Company name: $companyName\n'
      'Business reference: $companyId\n'
      'My login email: ${userEmail.isEmpty ? '—' : userEmail}\n\n'
      'Proof I represent this business:\n'
      '- (Add website/social link)\n'
      '- (Add business email/domain)\n'
      '- (Add registration info, etc.)\n\n'
      'Thanks!\n',
    );

    final uri = Uri.parse('mailto:$supportEmail?subject=$subject&body=$body');
    final ok = await launchUrl(uri);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not open email app. Please copy the email instead.')),
      );
    }
  }

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support email copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Verify your business',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'To verify your business, please email us and include proof that you represent "$companyName".',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Include in your email',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '• Business reference: $companyId\n'
                              '• Business website or social page\n'
                              '• Business email/domain (if available)\n'
                              '• Any proof (registration, invoice header, etc.)',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openEmail(context),
                        icon: const Icon(Icons.email),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text('Email us to verify',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _copyEmail(context),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy support email'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Support email: $supportEmail',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                        textAlign: TextAlign.center,
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

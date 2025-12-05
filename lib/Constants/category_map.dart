// lib/constants/category_map.dart

/// Master list of categories and their sub-categories.
/// These values are used in:
/// - Create Business screen
/// - Edit Business screen
/// - Company List filters
/// - Analytics grouping
///
/// You can safely modify or expand this list as needed.

const Map<String, List<String>> kCategorySubcategories = {
  'Attorneys': [
    'Family Law',
    'Criminal Law',
    'Labour Law',
    'Property / Conveyancing',
    'Commercial & Corporate Law',
    'Litigation & Dispute Resolution',
  ],

  'Construction': [
    'General Contractor',
    'Civil Construction',
    'Electrical Contractor',
    'Plumbing',
    'Roofing',
    'Renovations & Additions',
    'Building Inspection',
  ],

  'Engineering': [
    'Electrical Engineering',
    'Mechanical Engineering',
    'Civil Engineering',
    'Industrial Engineering',
    'Software / IT Engineering',
    'Mechatronics Engineering',
    'Chemical Engineering',
  ],

  'IT Services': [
    'Software Development',
    'Web Design & Hosting',
    'Networking & WiFi',
    'Cybersecurity',
    'IT Support / Helpdesk',
    'Cloud & DevOps',
    'Mobile App Development',
  ],

  'Manufacturing': [
    'Metal Fabrication',
    'Plastics Manufacturing',
    'Electronics Manufacturing',
    'Food & Beverage Production',
    'Woodworking',
    'Textiles & Clothing',
    'Packaging Production',
  ],

  'Accounting & Finance': [
    'Accounting',
    'Tax Practitioner',
    'Bookkeeping',
    'Payroll Services',
    'Financial Advisory',
    'Auditing',
  ],

  'Marketing & Media': [
    'Digital Marketing',
    'Social Media Management',
    'Graphic Design',
    'Video Production',
    'Branding & Printing',
    'Media Buying',
  ],

  'Health & Wellness': [
    'General Practitioners',
    'Physiotherapy',
    'Chiropractic',
    'Psychology / Counselling',
    'Personal Training',
    'Beauty & Skincare',
    'Nutrition Coaching',
  ],

  'Automotive': [
    'Mechanical Workshop',
    'Panel Beating',
    'Auto Electrician',
    'Tyres & Alignment',
    'Car Wash & Detailing',
    'Towing Services',
  ],

  'Cleaning Services': [
    'Residential Cleaning',
    'Commercial Cleaning',
    'Garden Services',
    'Pest Control',
    'Carpet & Upholstery Cleaning',
  ],
};

/// A sorted list of all top-level categories.
/// Useful for dropdowns and chips.
List<String> get kAllCategories {
  final list = kCategorySubcategories.keys.toList();
  list.sort();
  return list;
}

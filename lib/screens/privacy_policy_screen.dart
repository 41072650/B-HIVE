// lib/screens/privacy_policy_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/hive_background.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        height: 1.4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: HiveBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'B-Hive Privacy Policy',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _paragraph(
                        'Last updated: 01 December 2025\n\n'
                        'This Privacy Policy explains how B-Hive ("the App", "we", "us") '
                        'collects, uses, stores and protects your personal information when '
                        'you use our services. We are committed to complying with the '
                        'Protection of Personal Information Act, 4 of 2013 ("POPIA") and '
                        'other applicable data protection laws.',
                      ),

                      _sectionTitle('1. Who we are'),
                      _paragraph(
                        'B-Hive is a platform that helps businesses and professionals connect '
                        'with each other. The App is operated by the B-Hive team. For any '
                        'questions about this policy or your data, you can contact us at '
                        'ejdkbb@gmail.com or heinrich.laufs@gmail.com.',
                      ),

                      _sectionTitle('2. What information we collect'),
                      _paragraph(
                        'We collect and process the following categories of personal information '
                        'when you use B-Hive:',
                      ),
                      const SizedBox(height: 4),
                      _paragraph(
                        '• Account information: name, email address, password (stored securely by Supabase), '
                        'profile photo, company name and basic profile details.\n'
                        '• Business information: business name, description, services, pricing, location, '
                        'contact details and images you choose to upload.\n'
                        '• Location data: approximate or precise location (when you grant permission) to '
                        'sort and display companies by distance.\n'
                        '• Usage data: app interactions such as profile views, calls, WhatsApp clicks, '
                        'direction requests, shares and ratings. These are stored as analytics events and '
                        'aggregated statistics for companies.\n'
                        '• Technical data: device type, basic log data and other information necessary to '
                        'operate, secure and improve the App.',
                      ),

                      _sectionTitle('3. How we use your information'),
                      _paragraph(
                        'We use your personal information to:',
                      ),
                      const SizedBox(height: 4),
                      _paragraph(
                        '• Create and manage your user account and business profiles.\n'
                        '• Help businesses and users discover and contact each other.\n'
                        '• Show analytics to business owners (e.g. views, actions, ratings).\n'
                        '• Improve the App, fix bugs and monitor performance.\n'
                        '• Prevent abuse, fraud and misuse of the platform.\n'
                        '• Communicate with you about updates, security alerts or important changes.',
                      ),

                      _sectionTitle('4. Legal basis and consent (POPIA)'),
                      _paragraph(
                        'Under POPIA, we only process personal information when we have a lawful basis. '
                        'In most cases this is:\n'
                        '• Your consent – for example when you create an account, upload information or enable location services.\n'
                        '• Contractual necessity – to provide you with the B-Hive service you have signed up for.\n'
                        '• Legitimate interests – to secure the platform, prevent abuse, and understand how the App is used.\n\n'
                        'By using B-Hive, you consent to the collection and processing of your personal information '
                        'as described in this policy. You may withdraw your consent at any time by deleting your '
                        'account or contacting us.',
                      ),

                      _sectionTitle('5. How we share your information'),
                      _paragraph(
                        'We do not sell your personal information. We only share it when necessary to provide the service or '
                        'when legally required. Specifically:\n'
                        '• Other users and businesses can see the profile information and business details you choose to make public in the App.\n'
                        '• We use Supabase (a backend platform) to store data and handle authentication. Supabase acts as a data processor on our behalf.\n'
                        '• We may share limited data with service providers that help us operate the App (e.g. email or analytics tools), '
                        'subject to confidentiality and data protection obligations.\n'
                        '• We may disclose information if required by law, court order or authorised authority.',
                      ),

                      _sectionTitle('6. International data transfers'),
                      _paragraph(
                        'Supabase and some of our service providers may store or process data on servers located outside of '
                        'South Africa. Where this happens, we take reasonable steps to ensure that your personal information '
                        'is protected with appropriate safeguards and is treated in line with POPIA principles.',
                      ),

                      _sectionTitle('7. Data retention'),
                      _paragraph(
                        'We keep your personal information only for as long as necessary to provide the B-Hive service and fulfil '
                        'the purposes described in this policy. In general:\n'
                        '• Your profile and business data are kept while your account remains active.\n'
                        '• Analytics and event data may be kept for a reasonable period to analyse trends and improve the service.\n'
                        '• We may keep limited records after account deletion where required by law, to resolve disputes or '
                        'enforce our terms.',
                      ),

                      _sectionTitle('8. Your rights'),
                      _paragraph(
                        'Under POPIA you have the right to:\n'
                        '• Access the personal information we hold about you.\n'
                        '• Request correction of inaccurate or incomplete information.\n'
                        '• Request deletion of your personal information, where legally permitted.\n'
                        '• Object to or restrict certain kinds of processing.\n'
                        '• Withdraw consent where processing is based on consent.\n\n'
                        'You can exercise many of these rights directly in the app (for example by editing your profile or deleting '
                        'content). For anything else, you can contact us using the email below.',
                      ),

                      _sectionTitle('9. Security'),
                      _paragraph(
                        'We use reasonable technical and organisational measures to protect your personal information, '
                        'including secure authentication, role-based access and encrypted connections. However, no online '
                        'service can guarantee absolute security, and you also play a role by using a strong password and '
                        'keeping your login details safe.',
                      ),

                      _sectionTitle('10. Children'),
                      _paragraph(
                        'B-Hive is designed for adults and businesses. We do not knowingly allow persons under 18 to create '
                        'accounts without appropriate consent. If you believe a child has provided us with personal information '
                        'without consent, please contact us so we can investigate and take appropriate action.',
                      ),

                      _sectionTitle('11. Changes to this policy'),
                      _paragraph(
                        'We may update this Privacy Policy from time to time to reflect changes in the App, our practices or '
                        'legal requirements. When we make material changes, we will update the "Last updated" date above and may '
                        'notify you in the app. By continuing to use B-Hive after changes take effect, you accept the updated policy.',
                      ),

                      // -------------------- CONTACT US --------------------
                      _sectionTitle('12. Contact us'),
                      _paragraph(
                        'If you have any questions about this policy, POPIA, or how we handle your personal information, please contact us:',
                      ),
                      const SizedBox(height: 4),

                      // TWO SEPARATE EMAIL LINKS
                      Row(
                        children: [
                          InkWell(
                            onTap: () async {
                              final uri = Uri(
                                scheme: 'mailto',
                                path: 'ejdkbb@gmail.com',
                                queryParameters: {
                                  'subject': 'B-Hive Privacy / POPIA question'
                                },
                              );
                              if (await canLaunchUrl(uri)) launchUrl(uri);
                            },
                            child: const Text(
                              'ejdkbb@gmail.com',
                              style: TextStyle(
                                color: Colors.amber,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const Text('   or   ',
                              style: TextStyle(color: Colors.white70)),
                          InkWell(
                            onTap: () async {
                              final uri = Uri(
                                scheme: 'mailto',
                                path: 'heinrich.laufs@gmail.com',
                                queryParameters: {
                                  'subject': 'B-Hive Privacy / POPIA question'
                                },
                              );
                              if (await canLaunchUrl(uri)) launchUrl(uri);
                            },
                            child: const Text(
                              'heinrich.laufs@gmail.com',
                              style: TextStyle(
                                color: Colors.amber,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),
                      _paragraph(
                        'We will do our best to respond to your request within a reasonable time.',
                      ),

                      const SizedBox(height: 12),
                      _paragraph(
                        'This document is intended as a practical privacy notice and does not constitute formal legal advice. '
                        'You are encouraged to obtain independent legal review if needed.',
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

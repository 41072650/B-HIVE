// lib/screens/terms_of_service_screen.dart
import 'package:flutter/material.dart';
import '../widgets/hive_background.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  Future<void> _email(String address) async {
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      queryParameters: { 'subject': 'B-Hive Terms of Service Question' },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _text(String text) {
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
        title: const Text("Terms of Service"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: HiveBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
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
                        "B-Hive Terms of Service",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _text(
                        "Last Updated: 01 December 2025\n\n"
                        "By using B-Hive, you agree to these Terms of Service. "
                        "If you do not agree, you must stop using the App.",
                      ),

                      _section("1. Who we are"),
                      _text(
                        "B-Hive is a platform that helps businesses and professionals connect. "
                        "For questions about these Terms, contact us.",
                      ),

                      _section("2. Eligibility"),
                      _text("You must be 18 or older and able to enter legal agreements."),

                      _section("3. Your Account"),
                      _text(
                        "You are responsible for your login details and all activity on your account. "
                        "We may suspend accounts that violate these Terms.",
                      ),

                      _section("4. Acceptable Use"),
                      _text(
                        "You may not upload harmful content, impersonate others, harass users, "
                        "spam, hack, or misuse the platform.",
                      ),

                      _section("5. Content & Business Listings"),
                      _text(
                        "You remain responsible for all content you upload. "
                        "By posting content, you grant us a license to display it within the App.",
                      ),

                      _section("6. Communications"),
                      _text(
                        "We may send updates, alerts, and required notifications. "
                        "Other businesses may contact you unless disabled in Settings.",
                      ),

                      _section("7. Payments & Subscriptions"),
                      _text(
                        "Any future paid features will include clear pricing and renewal terms.",
                      ),

                      _section("8. Platform Availability"),
                      _text(
                        "B-Hive is provided 'as is'. We do not guarantee uninterrupted service.",
                      ),

                      _section("9. Limitation of Liability"),
                      _text(
                        "We are not liable for business dealings, losses, or platform downtime.",
                      ),

                      _section("10. Privacy & POPIA"),
                      _text(
                        "Your data is processed according to our Privacy Policy.",
                      ),

                      _section("11. Account Termination"),
                      _text("We may suspend accounts for violations. You may delete your account anytime."),

                      _section("12. Governing Law"),
                      _text(
                        "These Terms are governed by South African law.",
                      ),

                      _section("13. Changes to these Terms"),
                      _text(
                        "We may update these Terms. Continued use means acceptance.",
                      ),

                      _section("14. Contact Us"),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => _email("ejdkbb@gmail.com"),
                            child: const Text(
                              "ejdkbb@gmail.com",
                              style: TextStyle(
                                color: Colors.amber,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const Text("   •   "),
                          InkWell(
                            onTap: () => _email("heinrich.laufs@gmail.com"),
                            child: const Text(
                              "heinrich.laufs@gmail.com",
                              style: TextStyle(
                                color: Colors.amber,
                                decoration: TextDecoration.underline,
                              ),
                            ),
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

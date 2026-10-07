import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'report_issue_screen.dart';

/// Support screen — provides contact options and a link to report issues.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // Design System Colors
  static const Color dBg = Color(0xFFF4F7F2);
  static const Color dSurface = Color(0xFFFFFFFF);
  static const Color dGreen = Color(0xFF0B5A2A);
  static const Color dGold = Color(0xFFF5B800);
  static const Color dMuted = Color(0xFF6E8274);
  static const Color dBorder = Color(0xFFE1E9DD);
  static const Color dText = Color(0xFF13261A);
  static const Color dBlueSoft = Color(0xFFE7EEFB);
  static const Color dBlue = Color(0xFF3D6BE8);
  static const Color dGreenSoft = Color(0xFFE6F2E4);
  static const Color dGoldSoft = Color(0xFFFFF4CC);
  static const Color dRed = Color(0xFFC1443D);
  static const Color dRedSoft = Color(0xFFF8E4E2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dBg,
      appBar: AppBar(
        title: Text(
          'Support',
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            color: dGreen,
            fontSize: 16,
          ),
        ),
        backgroundColor: dSurface,
        elevation: 0,
        foregroundColor: dGreen,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: dBlueSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                color: dBlue,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'How can we help?',
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: dText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Get in touch with our team or report a problem.',
              style: TextStyle(
                color: dMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),

            // --- Section: Report an Issue ---
            Text(
              'Report a Problem',
              style: GoogleFonts.sora(
                color: dText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _reportIssueCard(context),

            const SizedBox(height: 28),

            // --- Section: Contact Support ---
            Text(
              'Contact Support',
              style: GoogleFonts.sora(
                color: dText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _contactCard(
                    context: context,
                    icon: Icons.chat_bubble_outline,
                    label: 'WhatsApp',
                    color: dGreen,
                    bgColor: dGreenSoft,
                    onTap: () => _showContactDialog(
                      context,
                      'WhatsApp Support',
                      '+237 696 713 899',
                      'Tap the number to copy, then open WhatsApp.',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contactCard(
                    context: context,
                    icon: Icons.phone_outlined,
                    label: 'Call Us',
                    color: dGold,
                    bgColor: dGoldSoft,
                    onTap: () => _showContactDialog(
                      context,
                      'Support Hotline',
                      '+237 696 713 899',
                      'Available Mon–Sat, 8 AM – 6 PM.',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contactCard(
                    context: context,
                    icon: Icons.email_outlined,
                    label: 'Email',
                    color: dBlue,
                    bgColor: dBlueSoft,
                    onTap: () => _showContactDialog(
                      context,
                      'Email Support',
                      'support@wastepro.cm',
                      'We typically respond within 24 hours.',
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // App info
            Center(
              child: Text(
                'WastePro v1.0.0',
                style: TextStyle(
                  color: dMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tap to navigate to the Report Issue screen.
  Widget _reportIssueCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportIssueScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: dRedSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: dRed,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report an Issue',
                    style: GoogleFonts.sora(
                      color: dText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Missed collection, damaged bin, or other problem',
                    style: TextStyle(
                      color: dMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: dMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showContactDialog(
    BuildContext context,
    String title,
    String info,
    String subtitle,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: dText,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              info,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: dGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: dMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: info));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: dGreen,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: Text(
              'Copy',
              style: TextStyle(color: dGreen, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: dMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: dSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: dText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

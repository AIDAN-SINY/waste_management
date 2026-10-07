import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';

/// Screen for clients to report waste management issues in their area
/// (overflowing bins, missed collections, illegal dumping, etc.).
class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key, FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  // Design System Colors
  final Color dBg = const Color(0xFFF4F7F2);
  final Color dSurface = const Color(0xFFFFFFFF);
  final Color dGreen = const Color(0xFF0B5A2A);
  final Color dGold = const Color(0xFFF5B800);
  final Color dRed = const Color(0xFFC1443D);
  final Color dMuted = const Color(0xFF6E8274);
  final Color dBorder = const Color(0xFFE1E9DD);
  final Color dText = const Color(0xFF13261A);
  final Color dRedSoft = const Color(0xFFF8E4E2);
  final Color dGoldSoft = const Color(0xFFFFF4CC);
  final Color dGreenSoft = const Color(0xFFE6F2E4);

  String? _selectedCategory;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  FirebaseFirestore get _db => widget._db ?? FirebaseFirestore.instance;

  final List<Map<String, dynamic>> _categories = [
    {
      'icon': Icons.delete_outline,
      'label': 'Overflowing bin',
      'description': 'Bin is full and waste is scattered around',
    },
    {
      'icon': Icons.event_busy_outlined,
      'label': 'Missed collection',
      'description': 'Collector did not come on scheduled day',
    },
    {
      'icon': Icons.report_outlined,
      'label': 'Illegal dumping',
      'description': 'Waste dumped in unauthorized area',
    },
    {
      'icon': Icons.warning_amber_outlined,
      'label': 'Hazardous waste',
      'description': 'Dangerous materials found in collection area',
    },
    {
      'icon': Icons.engineering_outlined,
      'label': 'Damaged bin',
      'description': 'Collection bin is broken or damaged',
    },
    {
      'icon': Icons.more_horiz,
      'label': 'Other issue',
      'description': 'Something else not listed above',
    },
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an issue category.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_descriptionController.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the issue (at least 5 characters).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    try {
      final now = DateTime.now();
      final createdAt =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final id = 'ISS-${now.millisecondsSinceEpoch}';
      await _db.collection('issues').doc(id).set({
        'id': id,
        'client_id': user.phoneNumber,
        'client_name': user.fullName,
        'category': _selectedCategory,
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'status': 'open',
        'created_at': createdAt,
      });

      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: dRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dBg,
      appBar: AppBar(
        title: Text(
          'Report Issue',
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
      body: _submitted ? _buildSuccessView() : _buildFormView(),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: dGreenSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                color: dGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Report Submitted',
              style: GoogleFonts.sora(
                color: dText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thank you for reporting this issue. Your agency will review it and take action.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: dGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Back to Dashboard',
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header icon + text
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: dRedSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: dRed,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What\'s wrong?',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: dText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select the type of issue and provide details so your agency can help.',
            style: TextStyle(
              color: dMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Category selection
          Text(
            'Category',
            style: GoogleFonts.sora(
              color: dText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...(_categories.map((cat) => _buildCategoryTile(cat)).toList()),

          const SizedBox(height: 20),

          // Description
          Text(
            'Description',
            style: GoogleFonts.sora(
              color: dText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: dSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dBorder),
            ),
            child: TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: TextStyle(color: dText, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Describe the issue in detail...',
                hintStyle: TextStyle(color: dMuted, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Location (optional)
          Text(
            'Location (optional)',
            style: GoogleFonts.sora(
              color: dText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: dSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dBorder),
            ),
            child: TextField(
              controller: _locationController,
              style: TextStyle(color: dText, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. Near the market on Rue 1.234',
                hintStyle: TextStyle(color: dMuted, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  color: dMuted,
                  size: 18,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: dGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'SUBMIT REPORT',
                      style: GoogleFonts.sora(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> cat) {
    final isSelected = _selectedCategory == cat['label'];
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = cat['label']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? dGreenSoft : dSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? dGreen : dBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected ? dGreen : dRedSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                cat['icon'] as IconData,
                color: isSelected ? Colors.white : dRed,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat['label'] as String,
                    style: TextStyle(
                      color: dText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cat['description'] as String,
                    style: TextStyle(
                      color: dMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: dGreen, size: 20)
            else
              Icon(Icons.radio_button_unchecked, color: dBorder, size: 20),
          ],
        ),
      ),
    );
  }
}

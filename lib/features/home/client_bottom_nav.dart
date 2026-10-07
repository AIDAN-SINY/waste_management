import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../profile/screens/profile_screen.dart';
import '../subscription/screens/history_screen.dart';
import '../payment/screens/bills_screen.dart';
import '../../providers/navigation_provider.dart';

/// Shared bottom navigation bar for the client screens.
///
/// Identical on the dashboard, history, bills and profile screens so tab
/// switching stays stack-safe (no screen pile-up): tapping the tab of the
/// screen already on top of the navigation stack pops back to the root
/// dashboard instead of pushing yet another copy of the screen.
class ClientBottomNav extends StatelessWidget {
  const ClientBottomNav({super.key});

  static const _dGreen = Color(0xFF0B5A2A);
  static const _dMuted = Color(0xFF6E8274);
  static const _dBorder = Color(0xFFE1E9DD);

  @override
  Widget build(BuildContext context) {
    final navProvider = Provider.of<NavigationProvider>(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: _buildNavItem(
                  context,
                  navProvider: navProvider,
                  icon: Icons.home_rounded,
                  label: "Home",
                  index: 0,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  context,
                  navProvider: navProvider,
                  icon: Icons.history_rounded,
                  label: "History",
                  index: 1,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  context,
                  navProvider: navProvider,
                  icon: Icons.description_rounded,
                  label: "Bill",
                  index: 2,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  context,
                  navProvider: navProvider,
                  icon: Icons.person_rounded,
                  label: "Profile",
                  index: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required NavigationProvider navProvider,
    required IconData icon,
    required String label,
    required int index,
  }) {
    final selected = navProvider.currentIndex == index;
    final color = selected ? _dGreen : _dMuted;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        navProvider.setIndex(index);
        switch (index) {
          case 0:
            // Dashboard is the root — nothing to push.
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillsScreen()),
            );
            break;
          case 3:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
            break;
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? _dGreen.withValues(alpha: 0.10) : null,
                borderRadius: BorderRadius.circular(20),
                border: selected ? Border.all(color: _dBorder) : null,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

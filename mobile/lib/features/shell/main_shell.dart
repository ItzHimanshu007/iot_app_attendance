import 'package:flutter/material.dart';

import '../admin/admin_screen.dart';
import '../attendance/history_screen.dart';
import '../attendance/home_screen.dart';
import '../auth/models.dart';
import '../profile/profile_screen.dart';

/// Bottom-navigation shell for approved staff (Admin tab for administrators).
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.me, this.initialIndex = 0});

  final Me me;
  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.me.profile.isAdmin;
    final pages = <Widget>[
      HomeScreen(me: widget.me, onOpenHistory: () => setState(() => _index = 1)),
      const HistoryScreen(),
      const ProfileScreen(),
      if (isAdmin) const AdminScreen(embedded: true),
    ];
    final index = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Attendance',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
            if (isAdmin)
              const NavigationDestination(
                icon: Icon(Icons.admin_panel_settings_outlined),
                selectedIcon: Icon(Icons.admin_panel_settings_rounded),
                label: 'Admin',
              ),
          ],
        ),
      ),
    );
  }
}

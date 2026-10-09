import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../models/teacher_models.dart';
import '../controllers/teacher_session_controller.dart';
import '../controllers/session_monitor_controller.dart';

/// Redesigned Teacher Session Details screen for Phase 2.2.
/// Fully optimized with rebuild isolation, sticky search, scroll-to-top FAB, and improved typography.
class SessionDetailsScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionDetailsScreen({
    required this.sessionId,
    super.key,
  });

  @override
  ConsumerState<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends ConsumerState<SessionDetailsScreen> {
  Timer? _refreshTimer;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _searchQuery = '';
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionMonitorControllerProvider.notifier).loadAttendance(widget.sessionId);
      _setupTimer();
    });
  }

  void _onScroll() {
    final show = _scrollController.offset > 300;
    if (show != _showScrollToTop) {
      setState(() {
        _showScrollToTop = show;
      });
    }
  }

  void _setupTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    final timetableState = ref.read(timetableControllerProvider);
    if (timetableState is TimetableLoaded) {
      final session = timetableState.sessions.firstWhereOrNull(
        (s) => s.id == widget.sessionId,
      );
      if (session != null && session.status == 'active') {
        _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (mounted) {
            ref.read(sessionMonitorControllerProvider.notifier).refresh();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    ref.read(sessionMonitorControllerProvider.notifier).stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timetableState = ref.watch(timetableControllerProvider);
    final classroomsState = ref.watch(classroomsControllerProvider);

    // Case 2: Provider is loading
    if (timetableState is TimetableLoading || classroomsState is ClassroomsLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
      );
    }

    if (timetableState is TimetableError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session Details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              timetableState.message,
              style: const TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (timetableState is! TimetableLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
      );
    }

    // Safe session lookup
    final session = timetableState.sessions.firstWhereOrNull(
      (s) => s.id == widget.sessionId,
    );

    // Case 3: Session not found
    if (session == null) {
      return const _SessionNotFoundView();
    }

    // Case 1: Session found
    final classroomName = _getClassroomName(session.classroomId, classroomsState);
    final isSessionActive = session.status == 'active';

    // Reactively ensure timer starts if loaded late
    ref.listen<TimetableState>(timetableControllerProvider, (prev, next) {
      if (next is TimetableLoaded && _refreshTimer == null) {
        _setupTimer();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryLight,
        onRefresh: () => ref.read(sessionMonitorControllerProvider.notifier).refresh(),
        child: Hero(
          tag: widget.sessionId,
          child: Material(
            type: MaterialType.transparency,
            child: CustomScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16.0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SessionHeaderCard(
                        session: session,
                        classroomName: classroomName,
                      ),
                      const SizedBox(height: 16),
                      _SessionInfoCard(
                        session: session,
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: AppColors.darkBorder, height: 1),
                      const SizedBox(height: 24),
                      _AttendanceHeader(
                        isSessionActive: isSessionActive,
                      ),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SearchBarPersistentHeaderDelegate(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim().toLowerCase();
                      });
                    },
                    controller: _searchController,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: _AttendanceSectionSliver(
                    searchQuery: _searchQuery,
                    onRetry: () {
                      ref.read(sessionMonitorControllerProvider.notifier).loadAttendance(widget.sessionId);
                    },
                    isSessionActive: isSessionActive,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16.0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 12),
                      const Divider(color: AppColors.darkBorder, height: 1),
                      const SizedBox(height: 24),
                      const _PassivePlaceholderSection(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: AnimatedScale(
        scale: _showScrollToTop ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: FloatingActionButton.small(
          onPressed: () {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            );
          },
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          child: const Icon(Icons.arrow_upward_rounded),
        ),
      ),
    );
  }

  String _getClassroomName(String classroomId, ClassroomsState classroomsState) {
    if (classroomsState is ClassroomsLoaded) {
      final classroom = classroomsState.classrooms.firstWhereOrNull(
        (c) => c.id == classroomId,
      );
      if (classroom != null) {
        return classroom.name;
      }
    }
    
    // Never display UUIDs
    final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    if (uuidRegex.hasMatch(classroomId)) {
      return 'Room unavailable';
    }
    if (classroomsState is ClassroomsLoaded) {
      return 'Room unavailable';
    }
    return classroomId;
  }
}

// ── Private Reusable UI Widgets ──────────────────────────────────────────────

class _SearchBarPersistentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ValueChanged<String> onChanged;
  final TextEditingController controller;

  _SearchBarPersistentHeaderDelegate({
    required this.onChanged,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          final showClear = value.text.isNotEmpty;
          return TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(color: AppColors.darkTextPrimary),
            decoration: InputDecoration(
              hintText: 'Search Student',
              hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
              prefixIcon: const Icon(Icons.search, color: AppColors.darkTextSecondary),
              suffixIcon: showClear
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20, color: AppColors.darkTextSecondary),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.darkSurface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.darkBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.darkBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryLight),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  double get maxExtent => 64.0;

  @override
  double get minExtent => 64.0;

  @override
  bool shouldRebuild(covariant _SearchBarPersistentHeaderDelegate oldDelegate) {
    return oldDelegate.controller != controller;
  }
}

class _AttendanceSectionSliver extends ConsumerWidget {
  final String searchQuery;
  final VoidCallback onRetry;
  final bool isSessionActive;

  const _AttendanceSectionSliver({
    required this.searchQuery,
    required this.onRetry,
    required this.isSessionActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(sessionMonitorControllerProvider);

    if (monitorState is SessionMonitorInitial || monitorState is SessionMonitorLoading) {
      return const SliverToBoxAdapter(
        child: _AttendanceLoadingSkeleton(),
      );
    }

    if (monitorState is SessionMonitorError) {
      final errorMsg = monitorState.message;
      return SliverToBoxAdapter(
        child: _buildErrorView(errorMsg),
      );
    }

    if (monitorState is SessionMonitorLoaded) {
      final entries = monitorState.entries;

      if (entries.isEmpty) {
        return SliverToBoxAdapter(
          child: _AttendanceEmptyState(
            isSessionActive: isSessionActive,
            isSearchEmpty: false,
          ),
        );
      }

      // Filter
      final filtered = entries.where((entry) {
        final name = (entry.studentName ?? '').toLowerCase();
        final roll = entry.studentId.toLowerCase();
        return name.contains(searchQuery) || roll.contains(searchQuery);
      }).toList();

      // Sort: earliest first
      filtered.sort((a, b) => a.markedAt.compareTo(b.markedAt));

      if (filtered.isEmpty) {
        return const SliverToBoxAdapter(
          child: _AttendanceEmptyState(
            isSessionActive: false,
            isSearchEmpty: true,
          ),
        );
      }

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = filtered[index];
            return _AnimatedAttendanceCard(
              key: ValueKey(entry.id),
              entry: entry,
            );
          },
          childCount: filtered.length,
        ),
      );
    }

    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  Widget _buildErrorView(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.darkTextPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              side: const BorderSide(color: AppColors.primaryLight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceHeader extends ConsumerWidget {
  final bool isSessionActive;

  const _AttendanceHeader({
    required this.isSessionActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(sessionMonitorControllerProvider);
    int presentCount = 0;
    String lastCheckInTime = '--';

    if (monitorState is SessionMonitorLoaded) {
      presentCount = monitorState.presentCount;
      final entries = monitorState.entries;
      if (entries.isNotEmpty) {
        final latest = entries.map((e) => e.markedAt).reduce((a, b) => a.isAfter(b) ? a : b);
        lastCheckInTime = _formatTime(latest);
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      alignment: Alignment.centerLeft,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Text(
                    '$presentCount',
                    key: ValueKey(presentCount),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.darkTextSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Present',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.darkTextSecondary,
                  ),
                ),
                if (isSessionActive) ...[
                  const SizedBox(width: 8),
                  _buildLiveIndicator(),
                ],
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'LAST CHECK-IN',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.darkTextSecondary,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              lastCheckInTime,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.darkTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $ampm';
  }

  Widget _buildLiveIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _AttendanceEmptyState extends StatelessWidget {
  final bool isSessionActive;
  final bool isSearchEmpty;

  const _AttendanceEmptyState({
    required this.isSessionActive,
    required this.isSearchEmpty,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String title;
    final String subtitle;

    if (isSearchEmpty) {
      icon = Icons.search_off_rounded;
      title = 'No matching students found';
      subtitle = 'Try another name or roll number.';
    } else {
      icon = Icons.groups_rounded;
      title = 'No students have marked attendance yet.';
      subtitle = isSessionActive
          ? 'Waiting for students...'
          : 'This session ended with no attendance records.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: AppColors.darkTextSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.darkTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.darkTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedAttendanceCard extends StatefulWidget {
  final AttendanceEntry entry;

  const _AnimatedAttendanceCard({
    required this.entry,
    super.key,
  });

  @override
  State<_AnimatedAttendanceCard> createState() => _AnimatedAttendanceCardState();
}

class _AnimatedAttendanceCardState extends State<_AnimatedAttendanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: _AttendanceCard(entry: widget.entry),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final AttendanceEntry entry;

  const _AttendanceCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
      color: AppColors.darkSurface,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          // TODO Phase 3: navigation/detail controls
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.studentName ?? 'Unknown Student',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Roll No. ${entry.studentId}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.darkTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Marked at',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.darkTextSecondary,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatMarkedTime(entry.markedAt),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.darkTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMarkedTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $ampm';
  }
}

class _AttendanceLoadingSkeleton extends StatelessWidget {
  const _AttendanceLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.darkSurfaceVariant,
      highlightColor: AppColors.darkBorder,
      child: Column(
        children: List.generate(3, (index) => const _SkeletonCard()),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
      color: AppColors.darkSurface,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 90,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 70,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionNotFoundView extends StatelessWidget {
  const _SessionNotFoundView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.event_busy_rounded,
                size: 80,
                color: AppColors.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Session not found',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This session is no longer available or could not be loaded.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.darkTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to My Sessions'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  side: const BorderSide(color: AppColors.primaryLight),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionHeaderCard extends StatelessWidget {
  final AttendanceSession session;
  final String classroomName;

  const _SessionHeaderCard({
    required this.session,
    required this.classroomName,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = session.status == 'completed';
    final isCancelled = session.status == 'cancelled';
    
    final badgeColor = isCompleted
        ? AppColors.primaryLight
        : isCancelled
            ? AppColors.error
            : AppColors.darkTextSecondary;
            
    final badgeBg = isCompleted
        ? AppColors.primary.withValues(alpha: 0.15)
        : isCancelled
            ? AppColors.error.withValues(alpha: 0.15)
            : AppColors.darkSurfaceVariant;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
      color: AppColors.darkSurface,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.book_rounded, color: AppColors.primaryLight, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          session.displaySubjectName,
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    session.status.toUpperCase(),
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.meeting_room_rounded, color: AppColors.darkTextSecondary, size: 18),
                const SizedBox(width: 8),
                Text(
                  classroomName,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.darkBorder, height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: isCompleted || isCancelled || session.status != 'active'
                  ? [
                      _buildHeaderMetaItem('Started', _formatTime(session.startedAt)),
                      _buildHeaderMetaItem('Ended', _formatTime(session.expiresAt)),
                      _buildHeaderMetaItem('Duration', '${session.durationMinutes} min'),
                    ]
                  : [
                      _buildHeaderMetaItem('Started', _formatTime(session.startedAt)),
                      _buildHeaderMetaItem('Ends', _formatTime(session.expiresAt)),
                      _buildHeaderMetaItem(
                        'Remaining',
                        '',
                        child: _SessionRemainingCountdown(expiresAt: session.expiresAt),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderMetaItem(String label, String value, {Widget? child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.darkTextSecondary,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        child ?? Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.darkTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $ampm';
  }
}

class _SessionRemainingCountdown extends StatefulWidget {
  final DateTime expiresAt;

  const _SessionRemainingCountdown({required this.expiresAt});

  @override
  State<_SessionRemainingCountdown> createState() => _SessionRemainingCountdownState();
}

class _SessionRemainingCountdownState extends State<_SessionRemainingCountdown> {
  late final ValueNotifier<Duration> _remainingNotifier;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final diff = widget.expiresAt.difference(DateTime.now());
    _remainingNotifier = ValueNotifier(diff.isNegative ? Duration.zero : diff);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentDiff = widget.expiresAt.difference(DateTime.now());
      final remaining = currentDiff.isNegative ? Duration.zero : currentDiff;
      _remainingNotifier.value = remaining;
      if (remaining == Duration.zero) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remainingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _remainingNotifier,
      builder: (context, remaining, child) {
        final minutes = remaining.inMinutes;
        final seconds = remaining.inSeconds % 60;
        final valueStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
        return Text(
          valueStr,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.primaryLight,
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }
}

class _SessionInfoCard extends ConsumerWidget {
  final AttendanceSession session;

  const _SessionInfoCard({
    required this.session,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(sessionMonitorControllerProvider);
    final count = monitorState is SessionMonitorLoaded
        ? monitorState.presentCount
        : session.totalPresent;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder, width: 1),
      ),
      color: AppColors.darkSurface,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildInfoItem(
              icon: Icons.people_alt_rounded,
              value: '$count Present',
            ),
            Container(width: 1, height: 40, color: AppColors.darkBorder),
            _buildInfoItem(
              icon: Icons.timer_rounded,
              value: '${session.durationMinutes} min',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.darkTextSecondary, size: 20),
        const SizedBox(width: 8),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.darkTextPrimary,
          ),
        ),
      ],
    );
  }
}

class _PassivePlaceholderSection extends StatelessWidget {
  const _PassivePlaceholderSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Session Actions',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.darkTextPrimary,
          ),
        ),
        const SizedBox(height: 16),
        
        // TODO Phase 2: Manual Attendance
        _buildPassiveCard(
          icon: Icons.add_moderator_rounded,
          title: 'Manual Attendance',
          description: 'Manually record attendance or override status.',
        ),
        const SizedBox(height: 12),

        // TODO Phase 2: Export
        _buildPassiveCard(
          icon: Icons.share_rounded,
          title: 'Export Records',
          description: 'Export attendance records to CSV or PDF reports.',
        ),
        const SizedBox(height: 12),

        // TODO Phase 2: Analytics
        _buildPassiveCard(
          icon: Icons.analytics_rounded,
          title: 'Session Analytics',
          description: 'Analyze student attendance rates and classroom trends.',
        ),
      ],
    );
  }

  Widget _buildPassiveCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.darkTextSecondary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.darkTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coming in Phase 2',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryLight.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

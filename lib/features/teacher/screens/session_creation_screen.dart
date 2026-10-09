import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../controllers/teacher_session_controller.dart';
import '../models/teacher_models.dart';
import '../widgets/teacher_widgets.dart';

/// Session creation screen — teacher types a subject name, picks a classroom,
/// and sets a duration.
///
/// Converts to [ConsumerStatefulWidget] so that [ref.listen] can react to
/// [TeacherSessionActive] and display the success dialog before navigation.
class SessionCreationScreen extends ConsumerStatefulWidget {
  const SessionCreationScreen({super.key});

  @override
  ConsumerState<SessionCreationScreen> createState() =>
      _SessionCreationScreenState();
}

class _SessionCreationScreenState
    extends ConsumerState<SessionCreationScreen> {
  /// Stores the most-recently submitted request so the success dialog can
  /// display the human-readable subject and classroom names.
  _SubmittedSessionInfo? _lastSubmittedInfo;

  /// Guard against showing the dialog multiple times if the state rebuilds.
  bool _dialogShown = false;

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(teacherSessionControllerProvider);
    final classroomsState = ref.watch(classroomsControllerProvider);

    // ── React to state transitions ──────────────────────────────────────────
    ref.listen<TeacherSessionState>(
      teacherSessionControllerProvider,
      (previous, next) {
        if (next is TeacherSessionActive && !_dialogShown) {
          _dialogShown = true;
          // Show the success dialog after the current frame is rendered.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showSessionSuccessDialog(context, next.session);
            }
          });
        }

        // Reset the guard when the user resets back to idle (e.g. after error
        // dismiss) so a subsequent successful creation can show the dialog.
        if (next is TeacherSessionIdle) {
          _dialogShown = false;
        }
      },
    );

    final isCreating = sessionState is TeacherSessionCreating;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Session'),
      ),
      body: _buildBody(
          context, ref, classroomsState, sessionState, isCreating),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ClassroomsState classroomsState,
    TeacherSessionState sessionState,
    bool isCreating,
  ) {
    // Classrooms loaded — show form
    if (classroomsState is ClassroomsLoaded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (sessionState is TeacherSessionError) ...[
              SessionErrorCard(
                message: sessionState.message,
                isRetryable: sessionState.isRetryable,
                onDismiss: () =>
                    ref.read(teacherSessionControllerProvider.notifier).reset(),
              ),
              const SizedBox(height: 12),
            ],
            SessionCreationCard(
              classrooms: classroomsState.classrooms
                  .where((r) => r.isActive)
                  .toList(),
              isLoading: isCreating,
              onStart: (request) {
                // subjectName comes directly from the TextField — no lookup needed.
                final classroom = classroomsState.classrooms
                    .where((c) => c.id == request.classroomId)
                    .firstOrNull;

                setState(() {
                  _lastSubmittedInfo = _SubmittedSessionInfo(
                    subjectName: request.subjectName,
                    classroomName:
                        classroom?.displayName ?? request.classroomId,
                    durationMinutes: request.durationMinutes,
                  );
                });

                ref
                    .read(teacherSessionControllerProvider.notifier)
                    .createSession(request);
              },
            ),
          ],
        ),
      );
    }

    // Loading
    if (classroomsState is ClassroomsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    final errorMsg = classroomsState is ClassroomsError
        ? classroomsState.message
        : 'Failed to load data';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(errorMsg,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(classroomsControllerProvider.notifier).refresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Success Dialog ──────────────────────────────────────────────────────────

  Future<void> _showSessionSuccessDialog(
    BuildContext context,
    AttendanceSession session,
  ) async {
    final info = _lastSubmittedInfo;

    await showDialog<void>(
      context: context,
      // Prevent accidental dismissal by tapping outside.
      barrierDismissible: false,
      builder: (dialogContext) => _SessionSuccessDialog(
        session: session,
        subjectName: info?.subjectName,
        classroomName: info?.classroomName,
        durationMinutes: info?.durationMinutes ?? session.durationMinutes,
        onGoToDashboard: () {
          Navigator.of(dialogContext).pop();
          // Replace the entire navigation stack up to the root so that
          // pressing Back does not return to the completed form.
          if (mounted) {
            context.go(RoutePaths.teacherDashboard);
          }
        },
      ),
    );
  }
}

// ── Submitted info helper (purely UI-level, not persisted) ────────────────────

class _SubmittedSessionInfo {
  const _SubmittedSessionInfo({
    required this.subjectName,
    required this.classroomName,
    required this.durationMinutes,
  });

  final String subjectName;
  final String classroomName;
  final int durationMinutes;
}

// ── Session Success Dialog ────────────────────────────────────────────────────

/// Professional success dialog shown after the backend confirms session
/// creation. Prevents accidental dismissal and drives the teacher to the
/// dashboard without leaving the creation form in the back-stack.
class _SessionSuccessDialog extends StatelessWidget {
  const _SessionSuccessDialog({
    required this.session,
    required this.onGoToDashboard,
    this.subjectName,
    this.classroomName,
    required this.durationMinutes,
  });

  final AttendanceSession session;
  final VoidCallback onGoToDashboard;
  final String? subjectName;
  final String? classroomName;
  final int durationMinutes;

  @override
  Widget build(BuildContext context) {
    // Short session ID — first 8 chars, upper-cased (matches ActiveSessionCard).
    final shortId = session.id.length >= 8
        ? session.id.substring(0, 8).toUpperCase()
        : session.id.toUpperCase();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Success Icon ───────────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.successGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),

            // ── Title ──────────────────────────────────────────────────────
            Text(
              'Attendance Session\nCreated Successfully',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── Session Details ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  _DialogInfoRow(
                    icon: Icons.book_outlined,
                    label: 'Subject',
                    value: subjectName ?? session.displaySubjectName,
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.meeting_room_outlined,
                    label: 'Classroom',
                    value: classroomName ?? session.classroomId,
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: '$durationMinutes minutes',
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.tag_outlined,
                    label: 'Session ID',
                    value: shortId,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Subtitle ───────────────────────────────────────────────────
            Text(
              'Students can now mark their attendance.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // ── Go to Dashboard Button ─────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onGoToDashboard,
                icon: const Icon(Icons.dashboard_rounded, size: 20),
                label: const Text('Go to Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: AppTypography.labelLarge.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dialog info row ───────────────────────────────────────────────────────────

class _DialogInfoRow extends StatelessWidget {
  const _DialogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.success),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

// ── Timetable Screen ──────────────────────────────────────────────────────────

/// Timetable screen — shows the teacher's session history as a timetable.
///
/// Groups sessions by status. Active sessions appear first.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String _selectedFilter = 'All';

  // Classroom lookup cache to avoid repeated searching
  final Map<String, Classroom> _classroomCache = {};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(timetableControllerProvider.notifier).refresh();
      ref.read(classroomsControllerProvider.notifier).refresh();
      ref.read(subjectsControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getClassroomName(String classroomId, ClassroomsState classroomsState) {
    if (_classroomCache.containsKey(classroomId)) {
      return _classroomCache[classroomId]!.name;
    }
    if (classroomsState is ClassroomsLoaded) {
      final classroom = classroomsState.classrooms.cast<Classroom?>().firstWhere(
        (c) => c?.id == classroomId,
        orElse: () => null,
      );
      if (classroom != null) {
        _classroomCache[classroomId] = classroom;
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
    return classroomId; // Safe fallback during loading for mock human-readable IDs
  }

  String? _getClassroomBuilding(String classroomId, ClassroomsState classroomsState) {
    if (classroomsState is ClassroomsLoaded) {
      final classroom = classroomsState.classrooms.cast<Classroom?>().firstWhere(
        (c) => c?.id == classroomId,
        orElse: () => null,
      );
      if (classroom != null && classroom.building.isNotEmpty) {
        return classroom.building;
      }
    }
    return null;
  }

  String? _getSubjectCode(AttendanceSession session, SubjectsState subjectsState) {
    if (session.subjectId != null && subjectsState is SubjectsLoaded) {
      final subject = subjectsState.subjects.cast<Subject?>().firstWhere(
        (s) => s?.id == session.subjectId,
        orElse: () => null,
      );
      if (subject != null) {
        return subject.code;
      }
    }
    return null;
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryLight
                : AppColors.darkBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected
                ? AppColors.primaryLight
                : AppColors.darkTextSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final local = dt.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  String _getEmptyStateTitle(bool noSessionsAtAll) {
    if (noSessionsAtAll) {
      return "You haven't conducted any sessions yet.";
    } else if (_searchQuery.isNotEmpty) {
      return "No sessions match your search.";
    } else {
      return "No sessions available for this filter.";
    }
  }

  String _getEmptyStateSubtitle(bool noSessionsAtAll) {
    if (noSessionsAtAll) {
      return "Conduct your first session to see it here.";
    } else if (_searchQuery.isNotEmpty) {
      return "Try checking your spelling or using different keywords.";
    } else {
      return "Try switching to another filter tab.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetableState = ref.watch(timetableControllerProvider);
    final classroomsState = ref.watch(classroomsControllerProvider);
    final subjectsState = ref.watch(subjectsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Sessions'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(timetableControllerProvider.notifier).refresh();
          ref.read(classroomsControllerProvider.notifier).refresh();
          ref.read(subjectsControllerProvider.notifier).refresh();
        },
        child: switch (timetableState) {
          TimetableLoading() =>
            const Center(child: CircularProgressIndicator()),

          TimetableError(message: final msg) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(msg,
                            style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: () {
                            ref.read(timetableControllerProvider.notifier).refresh();
                            ref.read(classroomsControllerProvider.notifier).refresh();
                            ref.read(subjectsControllerProvider.notifier).refresh();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

          TimetableLoaded(
            sessions: _,
            activeSessions: final active,
            recentSessions: final recent
          ) =>
            (() {
              // Always sort history by startedAt descending (newest session first)
              final sortedRecent = [...recent]
                ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

              // ── Search & Filter calculations ──────────────────────────────
              final filteredActive = active.where((session) {
                final classroomName = _getClassroomName(session.classroomId, classroomsState);
                final subjectCode = _getSubjectCode(session, subjectsState);
                final classroomCode = _getClassroomBuilding(session.classroomId, classroomsState);

                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  final subject = session.displaySubjectName.toLowerCase();
                  final dateStr = _formatDate(session.startedAt).toLowerCase();
                  
                  final matchSubject = subject.contains(query);
                  final matchCode = subjectCode != null && subjectCode.toLowerCase().contains(query);
                  final matchClassroom = classroomName.toLowerCase().contains(query);
                  final matchClassroomCode = classroomCode != null && classroomCode.toLowerCase().contains(query);
                  final matchDate = dateStr.contains(query);

                  if (!matchSubject && !matchCode && !matchClassroom && !matchClassroomCode && !matchDate) {
                    return false;
                  }
                }
                if (_selectedFilter != 'All' &&
                    _selectedFilter != 'Live' &&
                    _selectedFilter != 'Today' &&
                    _selectedFilter != 'This Week' &&
                    _selectedFilter != 'This Month') {
                  return false;
                }
                return true;
              }).toList();

              final filteredHistory = sortedRecent.where((session) {
                final classroomName = _getClassroomName(session.classroomId, classroomsState);
                final subjectCode = _getSubjectCode(session, subjectsState);
                final classroomCode = _getClassroomBuilding(session.classroomId, classroomsState);

                // Search check
                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  final subject = session.displaySubjectName.toLowerCase();
                  final dateStr = _formatDate(session.startedAt).toLowerCase();
                  
                  final matchSubject = subject.contains(query);
                  final matchCode = subjectCode != null && subjectCode.toLowerCase().contains(query);
                  final matchClassroom = classroomName.toLowerCase().contains(query);
                  final matchClassroomCode = classroomCode != null && classroomCode.toLowerCase().contains(query);
                  final matchDate = dateStr.contains(query);

                  if (!matchSubject && !matchCode && !matchClassroom && !matchClassroomCode && !matchDate) {
                    return false;
                  }
                }

                // Filter check
                switch (_selectedFilter) {
                  case 'Live':
                    return session.status == 'active';
                  case 'Today':
                    final now = DateTime.now();
                    return session.startedAt.year == now.year &&
                        session.startedAt.month == now.month &&
                        session.startedAt.day == now.day;
                  case 'This Week':
                    final now = DateTime.now();
                    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
                    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
                    return session.startedAt.isAfter(start.subtract(const Duration(seconds: 1)));
                  case 'This Month':
                    final now = DateTime.now();
                    return session.startedAt.year == now.year &&
                        session.startedAt.month == now.month;
                  case 'Completed':
                    return session.status == 'completed';
                  default:
                    return true;
                }
              }).toList();

              return CustomScrollView(
                slivers: [
                  // Search & Filter header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.darkSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.darkBorder, width: 1),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: AppColors.darkTextPrimary),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Search subject, classroom, date...',
                                hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
                                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.darkTextSecondary),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, color: AppColors.darkTextSecondary),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip('All'),
                                _buildFilterChip('Live'),
                                _buildFilterChip('Today'),
                                _buildFilterChip('This Week'),
                                _buildFilterChip('This Month'),
                                _buildFilterChip('Completed'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Active sessions section (if running)
                  if (filteredActive.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Active Session', style: AppTypography.headlineSmall),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _MySessionsActiveCard(
                            session: filteredActive[i],
                            classroomName: _getClassroomName(filteredActive[i].classroomId, classroomsState),
                            onTap: () => context.push(RoutePaths.activeSession),
                          ),
                          childCount: filteredActive.length,
                        ),
                      ),
                    ),
                  ],

                  // Session History section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Session History', style: AppTypography.headlineSmall),
                          Text(
                            '${filteredHistory.length} sessions',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (filteredHistory.isEmpty && filteredActive.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: EmptyState(
                          icon: Icons.event_note_outlined,
                          title: _getEmptyStateTitle(recent.isEmpty),
                          subtitle: _getEmptyStateSubtitle(recent.isEmpty),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _MySessionsHistoryCard(
                            session: filteredHistory[i],
                            classroomName: _getClassroomName(filteredHistory[i].classroomId, classroomsState),
                            onTap: () => context.push(
                              RoutePaths.sessionDetails,
                              extra: filteredHistory[i].id,
                            ),
                          ),
                          childCount: filteredHistory.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 32)),
                ],
              );
            }()),
        },
      ),
    );
  }
}

// ── Optimized Active Session Timer Widget ────────────────────────────────────

class ActiveSessionCountdown extends StatefulWidget {
  final DateTime expiresAt;
  final TextStyle style;

  const ActiveSessionCountdown({
    required this.expiresAt,
    required this.style,
    super.key,
  });

  @override
  State<ActiveSessionCountdown> createState() => _ActiveSessionCountdownState();
}

class _ActiveSessionCountdownState extends State<ActiveSessionCountdown> {
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
        final minutes = remaining.inMinutes.toString().padLeft(2, '0');
        final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        return Text(
          '$minutes:$seconds',
          style: widget.style,
        );
      },
    );
  }
}

// ── Redesigned Active Session Card ───────────────────────────────────────────

class _MySessionsActiveCard extends StatelessWidget {
  final AttendanceSession session;
  final String classroomName;
  final VoidCallback onTap;

  const _MySessionsActiveCard({
    required this.session,
    required this.classroomName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: session.id,
      child: Card(
        elevation: 4,
        shadowColor: Colors.black26,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(
            color: AppColors.success,
            width: 1.5,
          ),
        ),
        color: AppColors.darkSurface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: LIVE badge & Started time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // LIVE badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Time
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 14, color: AppColors.darkTextSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Started ${_formatTime(session.startedAt)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.darkTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Subject and classroom
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.book_rounded, size: 18, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session.displaySubjectName,
                        style: AppTypography.headlineSmall.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.meeting_room_rounded, size: 16, color: AppColors.darkTextSecondary),
                    const SizedBox(width: 8),
                    Text(
                      classroomName,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Present count & Remaining Time Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Present Count
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, size: 16, color: AppColors.darkTextSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Students',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.darkTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${session.totalPresent} Students Present',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkTextPrimary,
                          ),
                        ),
                      ],
                    ),
                    // Remaining time
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Remaining',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.darkTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ActiveSessionCountdown(
                          expiresAt: session.expiresAt,
                          style: AppTypography.headlineSmall.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.darkBorder),
                const SizedBox(height: 10),

                // Tap to Monitor indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tap to Monitor',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.primaryLight,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
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

// ── Redesigned Session History Card ──────────────────────────────────────────

class _MySessionsHistoryCard extends StatelessWidget {
  final AttendanceSession session;
  final String classroomName;
  final VoidCallback onTap;

  const _MySessionsHistoryCard({
    required this.session,
    required this.classroomName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = session.status == 'completed';
    final isCancelled = session.status == 'cancelled';
    
    // Status style
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

    return Hero(
      tag: session.id,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(
            color: AppColors.darkBorder,
            width: 1,
          ),
        ),
        color: AppColors.darkSurface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Subject name & Status badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.book_rounded, size: 18, color: AppColors.primaryLight),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              session.displaySubjectName,
                              style: AppTypography.titleMedium.copyWith(
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
                    const SizedBox(width: 8),
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

                // Row 2: Classroom
                Row(
                  children: [
                    const Icon(Icons.meeting_room_rounded, size: 16, color: AppColors.darkTextSecondary),
                    const SizedBox(width: 8),
                    Text(
                      classroomName,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Row 3: Date & Time details
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 16, color: AppColors.darkTextSecondary),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDate(session.startedAt)}  •  ${_formatTime(session.startedAt)}  •  ${session.durationMinutes} min',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppColors.darkBorder, height: 1),
                const SizedBox(height: 12),

                // Row 4: Present count, only show "XX Students Present"
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 16, color: AppColors.darkTextSecondary),
                        const SizedBox(width: 8),
                        Text(
                          '${session.totalPresent} Students Present',
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkTextPrimary,
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.darkTextSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final local = dt.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
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


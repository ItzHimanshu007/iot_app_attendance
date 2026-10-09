@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_attendance/core/api_exception.dart';
import 'package:staff_attendance/core/theme/app_theme.dart';
import 'package:staff_attendance/features/admin/admin_api.dart';
import 'package:staff_attendance/features/admin/admin_screen.dart';
import 'package:staff_attendance/features/attendance/attendance_api.dart';
import 'package:staff_attendance/features/attendance/mark_attendance.dart';
import 'package:staff_attendance/features/auth/login_screen.dart';
import 'package:staff_attendance/features/auth/models.dart';
import 'package:staff_attendance/features/auth/session.dart';
import 'package:staff_attendance/features/auth/signup_screen.dart';
import 'package:staff_attendance/features/beacon/beacon_controller.dart';
import 'package:staff_attendance/features/beacon/beacon_protocol.dart';
import 'package:staff_attendance/features/face/face_capture_screen.dart';
import 'package:staff_attendance/features/onboarding/onboarding_screen.dart';
import 'package:staff_attendance/features/profile/profile_screen.dart';
import 'package:staff_attendance/features/shell/main_shell.dart';

// ── Fonts ─────────────────────────────────────────────────────────────────────

Future<void> _loadFonts() async {
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
  var root = Platform.environment['FLUTTER_ROOT'];
  root ??= File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final material = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> file(String path) async => ByteData.sublistView(await File(path).readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(file('$material/Roboto-$w.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(file('$material/MaterialIcons-Regular.otf'))).load();
  final poppins = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(rootBundle.load('assets/fonts/Poppins-$w.ttf'));
  }
  await poppins.load();
}

// ── Sample data ───────────────────────────────────────────────────────────────

Me _me({String step = 'ready', bool admin = true}) => Me.fromJson({
  'profile': {
    'id': 'u1',
    'email': 'asha.rao@college.edu',
    'full_name': 'Dr. Asha Rao',
    'employee_id': 'SKIT-CS-042',
    'department': 'Computer Science',
    'designation': 'Assistant Professor',
    'phone': '+91 98290 12345',
    'role': admin ? 'admin' : 'staff',
    'status': step == 'ready' ? 'active' : 'pending',
  },
  'device': step == 'register_device'
      ? null
      : {'device_model': 'Pixel 8', 'registered_at': '2026-09-01T09:00:00Z'},
  'face': step == 'ready' ? {'status': 'approved'} : null,
  'onboarding': {
    'device_registered': step != 'register_device',
    'face_enrolled': step == 'ready' || step == 'await_approval',
    'approved': step == 'ready',
    'face_status': step == 'ready' ? 'approved' : null,
    'next_step': step,
  },
});

DateTime _todayAt(int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m);
}

TodayInfo _today({bool checkedIn = false}) => TodayInfo(
  date: DateTime.now(),
  campusName: 'SKIT Jaipur',
  workStart: '09:00:00',
  lateGraceMinutes: 15,
  record: checkedIn
      ? AttendanceRecord(
          id: 'r0',
          date: DateTime.now(),
          status: 'present',
          checkInAt: _todayAt(8, 52),
        )
      : null,
);

List<AttendanceRecord> _history() {
  final out = <AttendanceRecord>[];
  var d = DateTime.now().subtract(const Duration(days: 1));
  var i = 0;
  while (out.length < 18) {
    if (d.weekday != DateTime.sunday) {
      final late = i % 6 == 2;
      final leave = i == 9;
      final inAt = DateTime(d.year, d.month, d.day, late ? 9 : 8, late ? 24 : 40 + (i * 3) % 18);
      out.add(
        AttendanceRecord(
          id: 'h$i',
          date: d,
          status: leave ? 'on_leave' : (late ? 'late' : 'present'),
          checkInAt: leave ? null : inAt,
          checkOutAt: leave ? null : DateTime(d.year, d.month, d.day, 17, 5 + (i * 7) % 40),
          isManual: leave,
          manualReason: leave ? 'Conference — IEEE Ignite' : null,
          flags: i == 4 ? const ['low_gps_accuracy'] : const [],
        ),
      );
      i++;
    }
    d = d.subtract(const Duration(days: 1));
  }
  return out;
}

final _beacon = BeaconAdvertisement(
  beaconId: '43905a99-a513-5a9d-8cb5-e109b98166bb',
  token: '37a4820d05333aa1',
  rssi: -62,
  name: 'Staff Room · Block A',
  seenAt: DateTime.now(),
);

class _FakeMe extends MeNotifier {
  _FakeMe(this.me);
  final Me me;
  @override
  Future<Me?> build() async => me;
}

class _FakeBeacons extends BeaconController {
  _FakeBeacons(this.initial);
  final BeaconState initial;
  @override
  BeaconState build() => initial;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

class _FakeAdminApi implements AdminApi {
  @override
  Future<Json> roster(DateTime day) async {
    const people = [
      ('Dr. Asha Rao', 'SKIT-CS-042', 'present', '08:52', '17:31'),
      ('Prof. Rahul Mehta', 'SKIT-ME-011', 'present', '08:47', null),
      ('Neha Sharma', 'SKIT-EE-027', 'late', '09:24', null),
      ('Vikram Singh', 'SKIT-CE-008', 'present', '08:58', null),
      ('Dr. Kavita Joshi', 'SKIT-IT-019', 'on_leave', null, null),
      ('Arjun Patel', 'SKIT-CS-055', 'not_marked', null, null),
      ('Pooja Verma', 'SKIT-AD-003', 'not_marked', null, null),
    ];
    String? iso(String? hm) {
      if (hm == null) return null;
      final p = hm.split(':');
      return _todayAt(int.parse(p[0]), int.parse(p[1])).toUtc().toIso8601String();
    }

    return {
      'date': '2026-10-09',
      'summary': {
        'present': 22,
        'late': 3,
        'absent': 1,
        'on_leave': 2,
        'not_marked': 4,
        'total': 32,
        'checked_out': 6,
        'flagged': 1,
      },
      'rows': [
        for (final p in people)
          {
            'staff': {
              'id': p.$2,
              'full_name': p.$1,
              'employee_id': p.$2,
              'department': 'Engineering',
            },
            'status': p.$3,
            'attendance': p.$3 == 'not_marked'
                ? null
                : {
                    'check_in_at': iso(p.$4),
                    'check_out_at': iso(p.$5),
                    'flags': p.$1 == 'Neha Sharma' ? ['low_gps_accuracy'] : <String>[],
                    'is_manual': p.$3 == 'on_leave',
                    'manual_reason': p.$3 == 'on_leave' ? 'Medical leave' : null,
                  },
          },
      ],
    };
  }

  @override
  Future<List<Json>> staff({String? status, String? query}) async => [
    {
      'id': 's1',
      'full_name': 'Arjun Patel',
      'employee_id': 'SKIT-CS-055',
      'department': 'Computer Science',
      'email': 'arjun@college.edu',
      'role': 'staff',
      'status': 'pending',
      'next_step': 'await_approval',
      'device': {'device_model': 'Redmi Note 13'},
      'face': {'status': 'pending'},
    },
    {
      'id': 's2',
      'full_name': 'Pooja Verma',
      'employee_id': 'SKIT-AD-003',
      'department': 'Administration',
      'email': 'pooja@college.edu',
      'role': 'staff',
      'status': 'pending',
      'next_step': 'enroll_face',
      'device': {'device_model': 'Galaxy A35'},
      'face': null,
    },
    {
      'id': 's3',
      'full_name': 'Rohit Gupta',
      'employee_id': 'SKIT-ME-031',
      'department': 'Mechanical',
      'email': 'rohit@college.edu',
      'role': 'staff',
      'status': 'pending',
      'next_step': 'register_device',
      'device': null,
      'face': null,
    },
  ];

  @override
  Future<List<Json>> attempts(DateTime day, {bool failedOnly = true}) async {
    String at(int h, int m) => _todayAt(h, m).toUtc().toIso8601String();
    return [
      {
        'reason_code': 'FACE_MISMATCH',
        'staff_name': 'Arjun Patel',
        'employee_id': 'SKIT-CS-055',
        'action': 'submit_check_in',
        'face_score': 0.31,
        'created_at': at(9, 12),
        'message': 'Face did not match your enrolled face.',
      },
      {
        'reason_code': 'MOCK_LOCATION',
        'staff_name': 'Rohit Gupta',
        'employee_id': 'SKIT-ME-031',
        'action': 'submit_check_in',
        'created_at': at(8, 58),
        'message': 'A fake-GPS / mock location app was detected.',
      },
      {
        'reason_code': 'DEVICE_MISMATCH',
        'staff_name': 'Neha Sharma',
        'employee_id': 'SKIT-EE-027',
        'action': 'challenge_check_in',
        'created_at': at(8, 41),
        'message': 'This is not the phone registered to your account.',
      },
    ];
  }

  @override
  Future<List<Json>> beacons() async => [
    {
      'id': 'b1',
      'name': 'Staff Room · Block A',
      'location': 'Ground floor, near HoD office',
      'rssi_threshold': -85,
      'is_active': true,
      'last_used_at': DateTime.now().toIso8601String(),
    },
    {
      'id': 'b2',
      'name': 'Library Staff Desk',
      'location': 'Central library',
      'rssi_threshold': -75,
      'is_active': true,
      'last_used_at': null,
    },
    {
      'id': 'b3',
      'name': 'Workshop Block',
      'location': 'Mechanical workshop',
      'rssi_threshold': -85,
      'is_active': false,
      'last_used_at': null,
    },
  ];

  @override
  Future<Json> campus() async => {
    'campus_name': 'SKIT Jaipur',
    'timezone': 'Asia/Kolkata',
    'latitude': 26.8226,
    'longitude': 75.8644,
    'radius_m': 500,
    'max_location_accuracy_m': 150,
    'late_grace_minutes': 15,
    'geofence_mode': 'flag',
    'face_match_threshold': 0.6,
    'work_start_time': '09:00:00',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Harness ───────────────────────────────────────────────────────────────────

const _size = Size(390, 844);

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget child, {
  List overrides = const [],
  Future<void> Function()? after,
}) async {
  // Draw real elevation shadows (flutter_test normally replaces them with outlines).
  debugDisableShadows = false;
  tester.view.physicalSize = _size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
        adminApiProvider.overrideWithValue(_FakeAdminApi()),
        ...overrides.cast(),
      ],
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.light, home: child),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  if (after != null) await after();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../../docs/screenshots/$name.png'),
  );
  debugDisableShadows = true;
}

void main() {
  setUpAll(_loadFonts);

  final ready = [
    userIdProvider.overrideWithValue('u1'),
    meProvider.overrideWith(() => _FakeMe(_me())),
    historyProvider.overrideWith((ref) async => _history()),
  ];
  final inRange = beaconControllerProvider.overrideWith(
    () => _FakeBeacons(BeaconState(status: BeaconStatus.scanning, beacons: [_beacon])),
  );

  testWidgets('01 login', (t) => _shot(t, '01_login', const LoginScreen()));
  testWidgets('02 signup', (t) => _shot(t, '02_signup', const SignupScreen()));
  testWidgets(
    '03 onboarding',
    (t) => _shot(t, '03_onboarding', OnboardingScreen(me: _me(step: 'enroll_face', admin: false))),
  );
  testWidgets(
    '04 home check-in',
    (t) => _shot(
      t,
      '04_home',
      MainShell(me: _me()),
      overrides: [...ready, inRange, todayProvider.overrideWith((ref) async => _today())],
    ),
  );
  testWidgets(
    '05 home searching',
    (t) => _shot(
      t,
      '05_home_searching',
      MainShell(me: _me()),
      overrides: [
        ...ready,
        beaconControllerProvider.overrideWith(
          () => _FakeBeacons(const BeaconState(status: BeaconStatus.scanning)),
        ),
        todayProvider.overrideWith((ref) async => _today(checkedIn: true)),
      ],
    ),
  );
  testWidgets(
    '06 face',
    (t) => _shot(
      t,
      '06_face_verification',
      const FaceCaptureScreen(
        mode: FaceCaptureMode.verify,
        steps: ['blink', 'smile'],
        previewOnly: true,
      ),
    ),
  );
  testWidgets(
    '07 result',
    (t) => _shot(
      t,
      '07_checked_in',
      AttendanceResultScreen(
        result: SubmitResult(
          action: 'check_in',
          record: AttendanceRecord(
            id: 'r',
            date: DateTime.now(),
            status: 'present',
            checkInAt: _todayAt(8, 52),
          ),
          faceScore: 0.87,
          flags: const [],
          distanceM: 120,
          beaconName: 'Staff Room · Block A',
        ),
      ),
    ),
  );
  testWidgets(
    '08 error',
    (t) => _shot(
      t,
      '08_rejected',
      Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => showVerificationError(
              context,
              const ApiException('Face did not match your enrolled face.', code: 'FACE_MISMATCH'),
            ),
          );
          return MainShell(me: _me());
        },
      ),
      overrides: [...ready, inRange, todayProvider.overrideWith((ref) async => _today())],
    ),
  );
  testWidgets(
    '09 history',
    (t) => _shot(
      t,
      '09_history',
      MainShell(me: _me(), initialIndex: 1),
      overrides: [...ready, inRange, todayProvider.overrideWith((ref) async => _today())],
    ),
  );
  testWidgets(
    '10 profile',
    (t) => _shot(
      t,
      '10_profile',
      MainShell(me: _me(), initialIndex: 2),
      overrides: [...ready, inRange, todayProvider.overrideWith((ref) async => _today())],
    ),
  );
  for (final (i, name) in [
    (0, '11_admin_overview'),
    (1, '12_admin_staff'),
    (2, '13_admin_alerts'),
    (3, '14_admin_beacons'),
    (4, '15_admin_settings'),
  ]) {
    testWidgets(name, (t) => _shot(t, name, AdminScreen(initialTab: i), overrides: ready));
  }
}

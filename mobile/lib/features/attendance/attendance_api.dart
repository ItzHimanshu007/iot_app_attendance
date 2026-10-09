import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/formatters.dart';
import '../beacon/beacon_protocol.dart';
import '../location/location_service.dart';

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.date,
    required this.status,
    this.checkInAt,
    this.checkOutAt,
    this.flags = const [],
    this.isManual = false,
    this.manualReason,
    this.faceScore,
  });

  final String id;
  final DateTime date;
  final String status;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final List<String> flags;
  final bool isManual;
  final String? manualReason;
  final double? faceScore;

  bool get checkedIn => checkInAt != null;
  bool get checkedOut => checkOutAt != null;
  bool get isLockedByAdmin => isManual && (status == 'absent' || status == 'on_leave');

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
    id: json['id'] as String,
    date: DateTime.parse(json['attendance_date'] as String),
    status: json['status'] as String,
    checkInAt: Fmt.parse(json['check_in_at']),
    checkOutAt: Fmt.parse(json['check_out_at']),
    flags: ((json['flags'] as List?) ?? const []).map((e) => e.toString()).toList(),
    isManual: json['is_manual'] == true,
    manualReason: json['manual_reason'] as String?,
    faceScore: (json['check_in_face_score'] as num?)?.toDouble(),
  );
}

class TodayInfo {
  const TodayInfo({
    required this.date,
    this.record,
    this.workStart,
    this.lateGraceMinutes,
    this.campusName,
  });

  final DateTime date;
  final AttendanceRecord? record;
  final String? workStart;
  final int? lateGraceMinutes;
  final String? campusName;

  /// 'check_in', 'check_out' or null when nothing is left to do today.
  String? get nextAction {
    final r = record;
    if (r == null || !r.checkedIn) return r?.isLockedByAdmin == true ? null : 'check_in';
    if (!r.checkedOut) return 'check_out';
    return null;
  }

  factory TodayInfo.fromJson(Map<String, dynamic> json) {
    final campus = (json['campus'] as Map<String, dynamic>?) ?? const {};
    return TodayInfo(
      date: DateTime.parse(json['date'] as String),
      record: json['attendance'] == null
          ? null
          : AttendanceRecord.fromJson(json['attendance'] as Map<String, dynamic>),
      workStart: campus['work_start_time']?.toString(),
      lateGraceMinutes: (campus['late_grace_minutes'] as num?)?.toInt(),
      campusName: campus['campus_name'] as String?,
    );
  }
}

class Challenge {
  const Challenge({
    required this.id,
    required this.action,
    required this.steps,
    required this.expiresAt,
    required this.beaconId,
    this.beaconName,
  });

  final String id;
  final String action;
  final List<String> steps;
  final DateTime expiresAt;
  final String beaconId;
  final String? beaconName;

  factory Challenge.fromJson(Map<String, dynamic> json) {
    final beacon = json['beacon'] as Map<String, dynamic>;
    final ttl = (json['ttl_seconds'] as num?)?.toInt() ?? 120;
    return Challenge(
      id: json['challenge_id'] as String,
      action: json['action'] as String,
      steps: (json['liveness_steps'] as List).map((e) => e.toString()).toList(),
      // Use the phone clock + TTL so a skewed phone clock cannot break the countdown.
      expiresAt: DateTime.now().add(Duration(seconds: ttl - 5)),
      beaconId: beacon['id'] as String,
      beaconName: beacon['name'] as String?,
    );
  }
}

class SubmitResult {
  const SubmitResult({
    required this.action,
    required this.record,
    required this.faceScore,
    required this.flags,
    this.distanceM,
    this.beaconName,
  });

  final String action;
  final AttendanceRecord record;
  final double faceScore;
  final List<String> flags;
  final double? distanceM;
  final String? beaconName;

  factory SubmitResult.fromJson(Map<String, dynamic> json) {
    final v = json['verification'] as Map<String, dynamic>;
    return SubmitResult(
      action: json['action'] as String,
      record: AttendanceRecord.fromJson(json['attendance'] as Map<String, dynamic>),
      faceScore: (v['face_score'] as num).toDouble(),
      flags: ((v['flags'] as List?) ?? const []).map((e) => e.toString()).toList(),
      distanceM: (v['distance_m'] as num?)?.toDouble(),
      beaconName: (v['beacon'] as Map?)?['name'] as String?,
    );
  }
}

class AttendanceApi {
  AttendanceApi(this._api);

  final ApiClient _api;

  Future<TodayInfo> today() async =>
      TodayInfo.fromJson(await _api.get('/attendance/today') as Map<String, dynamic>);

  Future<List<AttendanceRecord>> history({DateTime? from, DateTime? to}) async {
    final data = await _api.get(
      '/attendance/history',
      query: {if (from != null) 'from': Fmt.apiDate(from), if (to != null) 'to': Fmt.apiDate(to)},
    ) as List;
    return data.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Challenge> challenge({
    required String action,
    required BeaconAdvertisement beacon,
    required String fingerprint,
    required bool isPhysicalDevice,
  }) async {
    final data = await _api.post(
      '/attendance/challenge',
      data: {
        'action': action,
        'beacon': beacon.toJson(),
        'device_fingerprint': fingerprint,
        'is_physical_device': isPhysicalDevice,
      },
    );
    return Challenge.fromJson(data as Map<String, dynamic>);
  }

  Future<SubmitResult> submit({
    required Challenge challenge,
    required BeaconAdvertisement beacon,
    required List<double> embedding,
    required List<String> completedSteps,
    required String fingerprint,
    required bool isPhysicalDevice,
    LocationFix? location,
  }) async {
    final data = await _api.post(
      '/attendance/submit',
      data: {
        'challenge_id': challenge.id,
        'beacon': beacon.toJson(),
        'embedding': embedding,
        'completed_steps': completedSteps,
        'device_fingerprint': fingerprint,
        'is_physical_device': isPhysicalDevice,
        'model_version': AppConfig.faceModelVersion,
        if (location != null) 'location': location.toJson(),
      },
    );
    return SubmitResult.fromJson(data as Map<String, dynamic>);
  }
}

final attendanceApiProvider = Provider<AttendanceApi>((ref) {
  return AttendanceApi(ref.watch(apiClientProvider));
});

final todayProvider = FutureProvider<TodayInfo>((ref) {
  return ref.watch(attendanceApiProvider).today();
});

final historyProvider = FutureProvider<List<AttendanceRecord>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(attendanceApiProvider)
      .history(from: now.subtract(const Duration(days: 60)), to: now);
});

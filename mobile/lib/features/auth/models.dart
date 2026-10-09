/// Profile + onboarding state returned by `GET /api/v1/me`.
class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.employeeId,
    this.department,
    this.designation,
    this.phone,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final String status;
  final String? employeeId;
  final String? department;
  final String? designation;
  final String? phone;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory StaffProfile.fromJson(Map<String, dynamic> json) => StaffProfile(
    id: json['id'] as String,
    email: (json['email'] ?? '') as String,
    fullName: (json['full_name'] ?? '') as String,
    role: (json['role'] ?? 'staff') as String,
    status: (json['status'] ?? 'pending') as String,
    employeeId: json['employee_id'] as String?,
    department: json['department'] as String?,
    designation: json['designation'] as String?,
    phone: json['phone'] as String?,
  );
}

class Onboarding {
  const Onboarding({
    required this.deviceRegistered,
    required this.faceEnrolled,
    required this.approved,
    required this.nextStep,
    this.faceStatus,
  });

  final bool deviceRegistered;
  final bool faceEnrolled;
  final bool approved;
  final String? faceStatus;

  /// register_device | enroll_face | await_approval | ready | disabled
  final String nextStep;

  bool get isReady => nextStep == 'ready';

  factory Onboarding.fromJson(Map<String, dynamic> json) => Onboarding(
    deviceRegistered: json['device_registered'] == true,
    faceEnrolled: json['face_enrolled'] == true,
    approved: json['approved'] == true,
    faceStatus: json['face_status'] as String?,
    nextStep: (json['next_step'] ?? 'register_device') as String,
  );
}

class Me {
  const Me({required this.profile, required this.onboarding, this.device, this.face});

  final StaffProfile profile;
  final Onboarding onboarding;
  final Map<String, dynamic>? device;
  final Map<String, dynamic>? face;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    profile: StaffProfile.fromJson(json['profile'] as Map<String, dynamic>),
    onboarding: Onboarding.fromJson(json['onboarding'] as Map<String, dynamic>),
    device: json['device'] as Map<String, dynamic>?,
    face: json['face'] as Map<String, dynamic>?,
  );
}

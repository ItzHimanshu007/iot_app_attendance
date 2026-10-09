import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';

typedef Json = Map<String, dynamic>;

/// Admin endpoints (`/api/v1/admin/...`).
class AdminApi {
  AdminApi(this._api);

  final ApiClient _api;

  Future<List<Json>> staff({String? status, String? query}) async {
    final data = await _api.get(
      '/admin/staff',
      query: {'status': ?status, if (query != null && query.isNotEmpty) 'q': query},
    ) as List;
    return data.cast<Json>();
  }

  Future<void> approve(String id) => _api.post('/admin/staff/$id/approve');
  Future<void> rejectFace(String id, String? reason) =>
      _api.post('/admin/staff/$id/reject-face', data: {'reason': reason});
  Future<void> resetFace(String id) => _api.post('/admin/staff/$id/reset-face');
  Future<void> resetDevice(String id) => _api.post('/admin/staff/$id/reset-device');
  Future<void> setStatus(String id, String status) =>
      _api.post('/admin/staff/$id/status', data: {'status': status});
  Future<void> setRole(String id, String role) =>
      _api.post('/admin/staff/$id/role', data: {'role': role});

  Future<Json> roster(DateTime day) async =>
      await _api.get('/admin/attendance', query: {'date': Fmt.apiDate(day)}) as Json;

  Future<void> manualMark({
    required String staffId,
    required DateTime day,
    required String status,
    required String reason,
    String? checkIn,
    String? checkOut,
  }) => _api.post(
    '/admin/attendance/manual',
    data: {
      'staff_id': staffId,
      'date': Fmt.apiDate(day),
      'status': status,
      'reason': reason,
      'check_in_time': ?checkIn,
      'check_out_time': ?checkOut,
    },
  );

  Future<List<Json>> attempts(DateTime day, {bool failedOnly = true}) async {
    final data = await _api.get(
      '/admin/attempts',
      query: {'date': Fmt.apiDate(day), 'failed_only': failedOnly},
    ) as List;
    return data.cast<Json>();
  }

  Future<List<Json>> beacons() async => (await _api.get('/admin/beacons') as List).cast<Json>();
  Future<Json> createBeacon(String name, String? location, int rssi) async => await _api.post(
    '/admin/beacons',
    data: {'name': name, 'location': location, 'rssi_threshold': rssi},
  ) as Json;
  Future<Json> beaconSecret(String id) async => await _api.get('/admin/beacons/$id/secret') as Json;
  Future<Json> updateBeacon(String id, Json changes) async =>
      await _api.patch('/admin/beacons/$id', data: changes) as Json;
  Future<Json> rotateBeaconSecret(String id) async =>
      await _api.post('/admin/beacons/$id/rotate-secret') as Json;

  Future<Json> campus() async => await _api.get('/admin/campus') as Json;
  Future<Json> saveCampus(Json changes) async =>
      await _api.put('/admin/campus', data: changes) as Json;

  Future<List<int>> exportReport(DateTime from, DateTime to) => _api.getBytes(
    '/admin/reports/export',
    query: {'from': Fmt.apiDate(from), 'to': Fmt.apiDate(to)},
  );
}

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.watch(apiClientProvider)));

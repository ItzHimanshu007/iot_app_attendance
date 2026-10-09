import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:staff_attendance/core/formatters.dart';
import 'package:staff_attendance/features/attendance/attendance_api.dart';
import 'package:staff_attendance/features/beacon/beacon_protocol.dart';
import 'package:staff_attendance/features/face/face_image.dart';
import 'package:staff_attendance/features/face/liveness.dart';

Face face({
  double left = 0.9,
  double right = 0.9,
  double smile = 0.1,
  double yaw = 0,
  double pitch = 0,
  int? id = 1,
}) => Face(
  boundingBox: const Rect.fromLTWH(100, 100, 200, 200),
  landmarks: const {},
  contours: const {},
  leftEyeOpenProbability: left,
  rightEyeOpenProbability: right,
  smilingProbability: smile,
  headEulerAngleY: yaw,
  headEulerAngleX: pitch,
  trackingId: id,
);

void main() {
  group('BeaconProtocol (V3, same layout as the ESP32 firmware)', () {
    final token = [0x37, 0xa4, 0x82, 0x0d, 0x05, 0x33, 0x3a, 0xa1];
    final uuid = [
      0x43, 0x90, 0x5a, 0x99, 0xa5, 0x13, 0x5a, 0x9d, //
      0x8c, 0xb5, 0xe1, 0x09, 0xb9, 0x81, 0x66, 0xbb,
    ];

    test('decodes token and beacon UUID', () {
      final adv = BeaconProtocol.parseBytes([0x03, 0x01, ...token, ...uuid], rssi: -61)!;
      expect(adv.token, '37a4820d05333aa1');
      expect(adv.beaconId, '43905a99-a513-5a9d-8cb5-e109b98166bb');
      expect(adv.toJson(), {
        'beacon_id': '43905a99-a513-5a9d-8cb5-e109b98166bb',
        'token': '37a4820d05333aa1',
        'rssi': -61,
      });
    });

    test('rejects other versions, payload types and short packets', () {
      expect(BeaconProtocol.parseBytes([0x02, 0x01, ...token, ...uuid], rssi: -60), isNull);
      expect(BeaconProtocol.parseBytes([0x03, 0x02, ...token, ...uuid], rssi: -60), isNull);
      expect(BeaconProtocol.parseBytes([0x03, 0x01, ...token], rssi: -60), isNull);
    });
  });

  group('LivenessTracker', () {
    test('blink requires open → closed → open', () {
      final t = LivenessTracker([LivenessStep.blink]);
      expect(t.update(face(left: 0.1, right: 0.1)), isFalse); // closed first: ignored
      expect(t.update(face()), isFalse); // open
      expect(t.update(face(left: 0.05, right: 0.1)), isFalse); // closed
      expect(t.update(face()), isTrue); // open again
      expect(t.isDone, isTrue);
      expect(t.completed, ['blink']);
    });

    test('steps complete in order and smile/turn are detected', () {
      final t = LivenessTracker([LivenessStep.smile, LivenessStep.turnHead]);
      expect(t.update(face(yaw: 30)), isFalse); // turning first does not count
      expect(t.update(face(smile: 0.95)), isTrue);
      expect(t.update(face(yaw: -28)), isFalse);
      expect(t.update(face(yaw: 3)), isTrue);
      expect(t.completed, ['smile', 'turn_head']);
    });

    test('a different face (tracking id) resets progress', () {
      final t = LivenessTracker([LivenessStep.smile, LivenessStep.blink]);
      expect(t.update(face(smile: 0.95, id: 1)), isTrue);
      expect(t.progress, 1);
      t.update(face(id: 2));
      expect(t.progress, 0);
      expect(t.completed, isEmpty);
    });

    test('capture frame must be frontal with open eyes', () {
      expect(LivenessTracker.isGoodCaptureFrame(face()), isTrue);
      expect(LivenessTracker.isGoodCaptureFrame(face(yaw: 25)), isFalse);
      expect(LivenessTracker.isGoodCaptureFrame(face(left: 0.1)), isFalse);
    });

    test('wire names match the backend', () {
      expect(LivenessStep.values.map((s) => s.wire), ['blink', 'smile', 'turn_head']);
      expect(LivenessStep.fromWire('turn_head'), LivenessStep.turnHead);
      expect(LivenessStep.fromWire('fly'), isNull);
    });
  });

  test('preprocessFace crops, resizes and normalises to [-1, 1]', () {
    final photo = img.Image(width: 640, height: 480);
    img.fill(photo, color: img.ColorRgb8(200, 120, 40));
    final file = File(
      '${Directory.systemTemp.path}/face_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync(img.encodeJpg(photo));
    addTearDown(() => file.deleteSync());

    final out = preprocessFace(
      FaceCropRequest(path: file.path, left: 220, top: 120, width: 200, height: 220, size: 112),
    )!;
    expect(out.length, 112 * 112 * 3);
    expect(out.every((v) => v >= -1.0 && v <= 1.0), isTrue);
    // Red channel ≈ (200 - 127.5) / 128
    expect(out[0], closeTo(0.566, 0.05));
    // A box completely outside the image is rejected.
    expect(
      preprocessFace(
        FaceCropRequest(path: file.path, left: 5000, top: 5000, width: 100, height: 100, size: 112),
      ),
      isNull,
    );
  });

  group('TodayInfo.nextAction', () {
    TodayInfo today(Map<String, dynamic>? attendance) => TodayInfo.fromJson({
      'date': '2026-10-09',
      'attendance': attendance,
      'campus': {'work_start_time': '09:00:00', 'late_grace_minutes': 15},
    });

    test('check in → check out → done', () {
      expect(today(null).nextAction, 'check_in');
      final base = {'id': 'a', 'attendance_date': '2026-10-09', 'status': 'present'};
      expect(today({...base, 'check_in_at': '2026-10-09T03:30:00Z'}).nextAction, 'check_out');
      expect(
        today({
          ...base,
          'check_in_at': '2026-10-09T03:30:00Z',
          'check_out_at': '2026-10-09T12:00:00Z',
        }).nextAction,
        isNull,
      );
    });

    test('admin leave locks the day', () {
      expect(
        today({'id': 'a', 'attendance_date': '2026-10-09', 'status': 'on_leave', 'is_manual': true})
            .nextAction,
        isNull,
      );
    });
  });

  group('Names (Indian staff titles)', () {
    test('initials skip honorifics', () {
      expect(Fmt.initials('Dr. Asha Rao'), 'AR');
      expect(Fmt.initials('Prof. Rahul Kumar Mehta'), 'RM');
      expect(Fmt.initials('Smt Kavita'), 'K');
      expect(Fmt.initials('Neha Sharma'), 'NS');
      expect(Fmt.initials('Dr.'), 'D');
      expect(Fmt.initials(''), '?');
    });

    test('short name keeps the title', () {
      expect(Fmt.shortName('Dr. Asha Rao'), 'Dr. Asha');
      expect(Fmt.shortName('Neha Sharma'), 'Neha');
      expect(Fmt.shortName('Mr Vikram Singh'), 'Mr Vikram');
    });
  });
}

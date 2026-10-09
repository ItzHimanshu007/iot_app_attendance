import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  Rect box = const Rect.fromLTWH(100, 100, 200, 200),
}) => Face(
  boundingBox: box,
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

    final t0 = DateTime(2026, 10, 9, 9);
    Duration ms(int v) => Duration(milliseconds: v);

    test('a different face resets progress (long gap or jump across the frame)', () {
      final t = LivenessTracker([LivenessStep.smile, LivenessStep.blink]);
      expect(t.update(face(smile: 0.95, id: 1), t0), isTrue);
      expect(t.progress, 1);
      t.update(face(id: 2), t0.add(ms(2000))); // new id after 2 s
      expect(t.progress, 0);
      expect(t.completed, isEmpty);

      expect(t.update(face(smile: 0.95, id: 2), t0.add(ms(2100))), isTrue);
      final far = face(id: 3, box: const Rect.fromLTWH(400, 100, 200, 200));
      expect(t.sameFace(far, t0.add(ms(2300))), isFalse); // new id, moved 2 face-widths
      expect(t.progress, 0);
    });

    test('ML Kit briefly losing the face (new id, same place) keeps progress', () {
      final t = LivenessTracker([LivenessStep.turnHead, LivenessStep.smile]);
      expect(t.update(face(yaw: 35, id: 1), t0), isFalse);
      // face lost while turned, re-found 0.8 s later with a new id, slightly moved
      final back = face(yaw: 4, id: 7, box: const Rect.fromLTWH(130, 110, 190, 190));
      expect(t.update(back, t0.add(ms(800))), isTrue);
      expect(t.completed, ['turn_head']);
    });

    test('thresholds work with noisy low-end camera values', () {
      final t = LivenessTracker([LivenessStep.blink, LivenessStep.smile, LivenessStep.turnHead]);
      expect(t.update(face(left: 0.5, right: 0.7)), isFalse); // open on average
      expect(t.update(face(left: 0.35, right: 0.2)), isFalse); // closed on average
      expect(t.update(face(left: 0.6, right: 0.55)), isTrue);
      expect(t.update(face(smile: 0.75)), isTrue);
      expect(t.update(face(yaw: 21)), isFalse);
      expect(t.update(face(yaw: 10)), isTrue);
      expect(t.isDone, isTrue);
    });

    test('capture frame must be frontal with open eyes', () {
      expect(LivenessTracker.isGoodCaptureFrame(face()), isTrue);
      expect(LivenessTracker.isGoodCaptureFrame(face(yaw: 12, pitch: 18)), isTrue);
      expect(LivenessTracker.isGoodCaptureFrame(face(yaw: 25)), isFalse);
      expect(LivenessTracker.isGoodCaptureFrame(face(left: 0.1)), isFalse);
    });

    test('wire names match the backend', () {
      expect(LivenessStep.values.map((s) => s.wire), ['blink', 'smile', 'turn_head']);
      expect(LivenessStep.fromWire('turn_head'), LivenessStep.turnHead);
      expect(LivenessStep.fromWire('fly'), isNull);
    });
  });

  group('Face crop from the live NV21 frame', () {
    /// Raw frame whose luma encodes the position: Y = x + 10·y; chroma neutral.
    Nv21Frame grid(int rotation) {
      const w = 6, h = 4;
      final bytes = Uint8List(w * h * 3 ~/ 2)..fillRange(w * h, w * h * 3 ~/ 2, 128);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          bytes[y * w + x] = x + 10 * y;
        }
      }
      return Nv21Frame(bytes: bytes, width: w, height: h, rotation: rotation);
    }

    test('upright (ML Kit) coordinates map back to the right raw pixel', () {
      const w = 6, h = 4;
      final expected = <int, int Function(int i, int j)>{
        0: (i, j) => i + 10 * j,
        90: (i, j) => j + 10 * (h - 1 - i),
        180: (i, j) => (w - 1 - i) + 10 * (h - 1 - j),
        270: (i, j) => (w - 1 - j) + 10 * i,
      };
      expected.forEach((rotation, raw) {
        final f = grid(rotation);
        expect(f.uprightWidth, rotation % 180 == 0 ? w : h);
        for (var j = 0; j < f.uprightHeight; j++) {
          for (var i = 0; i < f.uprightWidth; i++) {
            final (rx, ry) = f.toRaw(i + 0.5, j + 0.5);
            expect(f.lumaAt(rx, ry), raw(i, j), reason: 'rotation $rotation, upright ($i, $j)');
          }
        }
      });
    });

    Nv21Frame solid(
      int w,
      int h,
      int Function(int x, int y) luma, {
      int v = 128,
      int rotation = 0,
    }) {
      final bytes = Uint8List(w * h * 3 ~/ 2);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          bytes[y * w + x] = luma(x, y);
        }
      }
      for (var i = w * h; i < bytes.length; i += 2) {
        bytes[i] = v; // V
        bytes[i + 1] = 128; // U
      }
      return Nv21Frame(bytes: bytes, width: w, height: h, rotation: rotation);
    }

    test('crop is 112×112 RGB in [-1, 1] with brightness evened out', () {
      final dim = cropFace(solid(64, 48, (_, _) => 64), 12, 4, 40, 40, 112)!;
      expect(dim.pixels.length, 112 * 112 * 3);
      expect(dim.meanLuma, closeTo(64, 0.01));
      expect(dim.pixels.every((v) => v.abs() < 0.02), isTrue); // 64 × gain 2 → mid grey

      final red = cropFace(solid(64, 48, (_, _) => 128, v: 200), 12, 4, 40, 40, 112)!;
      expect(red.pixels.every((v) => v >= -1 && v <= 1), isTrue);
      expect(red.pixels[0], closeTo((128 + 1.402 * 72 - 127.5) / 128, 0.02)); // R
      expect(red.pixels[0], greaterThan(red.pixels[1] + 0.5)); // R ≫ G
    });

    test('front-camera frame (rotated 90°) comes out upright', () {
      // Raw left half dark, right half bright → upright top dark, bottom bright.
      final f = solid(64, 48, (x, _) => x < 32 ? 40 : 200, rotation: 90);
      final crop = cropFace(f, 4, 12, 40, 40, 112)!;
      final top = crop.pixels[3 * (5 * 112 + 56)];
      final bottom = crop.pixels[3 * (106 * 112 + 56)];
      expect(top, lessThan(bottom - 0.5));
    });

    test('rejects a box outside the frame or too small', () {
      final f = solid(64, 48, (_, _) => 100);
      expect(cropFace(f, 5000, 5000, 100, 100, 112), isNull);
      expect(cropFace(f, 10, 10, 20, 20, 112), isNull);
    });

    test('3-plane YUV_420_888 (padded rows, pixel stride 2) packs into NV21', () {
      // 4×2 image, Y row stride 6; U/V interleaved views with pixel stride 2.
      final y = Uint8List.fromList([1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0]);
      final u = Uint8List.fromList([20, 0, 21]);
      final v = Uint8List.fromList([30, 0, 31]);
      final nv21 = Nv21Frame.yuv420ToNv21(
        width: 4,
        height: 2,
        y: y,
        yRowStride: 6,
        u: u,
        v: v,
        uvRowStride: 4,
        uvPixelStride: 2,
      );
      expect(nv21, [1, 2, 3, 4, 5, 6, 7, 8, 30, 20, 31, 21]);
    });
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

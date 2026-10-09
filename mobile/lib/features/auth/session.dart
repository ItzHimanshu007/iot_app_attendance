import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api_client.dart';
import 'models.dart';

/// Supabase auth events (sign-in, sign-out, token refresh …).
final authEventsProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Signed-in user id, or null. Only changes when the *user* changes, so a
/// token refresh does not re-fetch everything.
final userIdProvider = Provider<String?>((ref) {
  ref.watch(authEventsProvider);
  return Supabase.instance.client.auth.currentUser?.id;
});

/// `GET /me` — profile, bound device, face status and onboarding step.
class MeNotifier extends AsyncNotifier<Me?> {
  @override
  Future<Me?> build() async {
    final userId = ref.watch(userIdProvider);
    if (userId == null) return null;
    final data = await ref.read(apiClientProvider).get('/me');
    return Me.fromJson(data as Map<String, dynamic>);
  }

  /// Re-fetch without showing a full-screen loader.
  Future<void> reload() async {
    state = await AsyncValue.guard(build);
  }
}

final meProvider = AsyncNotifierProvider<MeNotifier, Me?>(MeNotifier.new);

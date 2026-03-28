// ignore_for_file: avoid_print

/// Password-based Descope authentication for test profiles.
///
/// Complements the browser-based OAuth flow in [browser_auth.dart] with
/// non-interactive password sign-in, enabling CI and automated testing.
///
/// ## Authentication Flow
///
/// 1. Resolve password from GCP Secret Manager
/// 2. POST to Descope `/v1/auth/password/signin`
/// 3. Receive `sessionJwt` + `userId`
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/secret_fetcher.dart';
import '../profiles/test_profiles.dart';
import 'browser_auth.dart' show descopeProjectId;

const _descopeSignInUrl = 'https://api.descope.com/v1/auth/password/signin';

/// Result of a successful Descope password sign-in.
class DescopePasswordAuthResult {
  final String userId;
  final String sessionJwt;
  final String email;

  DescopePasswordAuthResult({required this.userId, required this.sessionJwt, required this.email});
}

/// Resolves the Descope password for a [TestProfile] from GCP Secret Manager.
///
/// Free + Enterprise profiles share `aot-descope-test-user-free-password`.
/// Pro profiles use `aot-descope-pro-password`.
Future<String?> resolvePasswordForProfile(TestProfile profile) async {
  if (TestProfiles.proPasswordProfiles.contains(profile)) {
    return _resolveProPassword();
  }
  return _resolveTestPassword();
}

/// Authenticates a profile via Descope password sign-in.
///
/// Returns null if authentication fails (wrong password, user not found, etc.).
Future<DescopePasswordAuthResult?> authenticateDescopePassword({
  required String email,
  required String password,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c.post(
      Uri.parse(_descopeSignInUrl),
      headers: {'Authorization': 'Bearer $descopeProjectId', 'Content-Type': 'application/json'},
      body: jsonEncode({'loginId': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return DescopePasswordAuthResult(
        userId: (data['user'] as Map<String, dynamic>?)?['userId'] as String? ?? '',
        sessionJwt: data['sessionJwt'] as String? ?? '',
        email: email,
      );
    }
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Authenticates a [TestProfile] end-to-end: resolves password, signs in.
///
/// For Pro profiles, tries the pro password first, then falls back to the
/// free password (all test users may share the same password pattern).
Future<DescopePasswordAuthResult> authenticateProfile(TestProfile profile) async {
  final password = await resolvePasswordForProfile(profile);
  if (password == null) {
    throw StateError(
      'Could not resolve Descope password for ${profile.id} from GCP Secret Manager.\n'
      'Prerequisites:\n'
      '  - gcloud auth application-default login\n'
      '  - Access to GCP project global-cloud-runtime',
    );
  }

  var auth = await authenticateDescopePassword(email: profile.email, password: password);

  if (auth == null && TestProfiles.proPasswordProfiles.contains(profile)) {
    final freePw = await _resolveTestPassword();
    if (freePw != null && freePw != password) {
      auth = await authenticateDescopePassword(email: profile.email, password: freePw);
    }
  }

  if (auth == null) {
    throw StateError(
      'Profile ${profile.id} failed to authenticate.\n'
      'Email: ${profile.email}\n'
      'Tried ${TestProfiles.proPasswordProfiles.contains(profile) ? "pro + free passwords" : "resolved password"}.',
    );
  }

  return auth;
}

Future<String?> _resolveTestPassword() async {
  try {
    final fetcher = await SecretFetcher.create(projectId: 'global-cloud-runtime');
    final secret = await fetcher.fetch('aot-descope-test-user-free-password');
    if (secret.isNotEmpty) return secret;
  } catch (e) {
    print('   Failed to fetch test password from GSM: $e');
  }
  return null;
}

Future<String?> _resolveProPassword() async {
  try {
    final fetcher = await SecretFetcher.create(projectId: 'global-cloud-runtime');
    final secret = await fetcher.fetch('aot-descope-pro-password');
    if (secret.isNotEmpty) return secret;
  } catch (e) {
    print('   Failed to fetch pro password from GSM: $e');
  }
  return null;
}

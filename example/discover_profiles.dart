// ignore_for_file: avoid_print

/// Profile & organization discovery example.
///
/// Iterates ALL test profiles (Free, Pro, Enterprise), authenticates each,
/// provisions credentials (including enterprise BYOK), and dumps the full
/// redacted results.
///
/// This is the standalone equivalent of the engine's
/// `demos/_discover_all_profiles.dart`.
///
/// Prerequisites:
///   - gcloud auth application-default login
///   - Access to GCP project global-cloud-runtime
///
/// Run: dart run example/discover_profiles.dart
import 'dart:convert';

import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  print('');
  print('════════════════════════════════════════════════════════');
  print('  AOT Profile & Organization Discovery');
  print(
    '  Running full provisioning flow for ALL '
    '${TestProfiles.all.length} profiles',
  );
  print('════════════════════════════════════════════════════════');
  print('');

  final succeeded = <TestProfile, _ProfileResult>{};
  final failures = <TestProfile, Object>{};

  for (final profile in TestProfiles.all) {
    print('');
    print('────────────────────────────────────────────────────────');
    print('  Profile: ${profile.displayName}');
    print('  Email:   ${profile.email}');
    print('  Tier:    ${profile.subscription}');
    if (profile.orgId != null) {
      print('  Org ID:  ${profile.orgId}');
    }
    print('────────────────────────────────────────────────────────');
    print('');

    AuthenticatedAOTClient? auth;
    try {
      auth = await AuthenticatedAOTClient.createFromProfile(profile: profile);
      final provisioner = ProvisioningClient(auth);
      final creds = await provisioner.provisionAll();

      // OpenRouter
      print('  OpenRouter:');
      print('    Credential ID: ${creds.credentialId ?? "(none)"}');
      print('    API Key:       ${_mask(creds.openRouterApiKey)}');
      print('    Base URL:      ${creds.baseUrl ?? "(default)"}');

      // Enterprise BYOK
      if (creds.enterpriseCredentials.isNotEmpty) {
        print('');
        print('  Enterprise BYOK (${creds.enterpriseCredentials.length} provider(s)):');
        for (final ec in creds.enterpriseCredentials) {
          print('');
          print('  ┌── ${ec.providerName}');
          print('  │   Org: ${ec.orgName ?? ec.orgId}');
          print('  │   Org ID: ${_mask(ec.orgId)}');
          _printRedactedConfig(ec.decryptedConfig, prefix: '  │   ');
          print('  └──');
        }
      } else {
        print('');
        print('  Enterprise BYOK: (none provisioned for this org)');
      }

      succeeded[profile] = _ProfileResult(
        userId: auth.userId,
        orgId: auth.orgId,
        orKey: creds.openRouterApiKey,
        enterpriseCount: creds.enterpriseCredentials.length,
        enterpriseProviders: creds.enterpriseCredentials.map((c) => c.providerName).toList(),
      );
    } catch (e) {
      failures[profile] = e;
      print('  FAILED: $e');
    } finally {
      await auth?.dispose();
    }
  }

  // ── Summary ──
  print('');
  print('');
  print('════════════════════════════════════════════════════════');
  print('  SUMMARY');
  print('════════════════════════════════════════════════════════');
  print('');
  print('  Succeeded: ${succeeded.length}/${TestProfiles.all.length}');
  print('  Failed:    ${failures.length}/${TestProfiles.all.length}');
  print('');

  for (final entry in succeeded.entries) {
    final p = entry.key;
    final r = entry.value;
    print('  ${p.displayName} (${p.subscription}):');
    print('    User ID:     ${r.userId}');
    print('    OR Key:      ${_mask(r.orKey)}');
    print(
      '    Enterprise:  ${r.enterpriseCount}'
      '${r.enterpriseCount > 0 ? ' (${r.enterpriseProviders.join(", ")})' : ''}',
    );
    print('');
  }

  if (failures.isNotEmpty) {
    print('  Failures:');
    for (final entry in failures.entries) {
      print('    ${entry.key.displayName}: ${entry.value}');
    }
  }

  print('');
}

class _ProfileResult {
  final String userId;
  final String? orgId;
  final String orKey;
  final int enterpriseCount;
  final List<String> enterpriseProviders;

  _ProfileResult({
    required this.userId,
    this.orgId,
    required this.orKey,
    required this.enterpriseCount,
    required this.enterpriseProviders,
  });
}

void _printRedactedConfig(String configJson, {String prefix = ''}) {
  if (configJson.trim().isEmpty) {
    print('${prefix}Config: (empty)');
    return;
  }

  try {
    final parsed = jsonDecode(configJson);
    if (parsed is Map<String, dynamic>) {
      print('${prefix}Config shape (${parsed.length} fields):');
      for (final key in parsed.keys) {
        final v = parsed[key];
        if (v is String) {
          print('$prefix  $key: ${_mask(v)}');
        } else if (v is Map) {
          print('$prefix  $key: {${v.length} fields}');
          for (final subKey in v.keys) {
            final sv = v[subKey];
            if (sv is String) {
              print('$prefix    $subKey: ${_mask(sv)}');
            } else if (sv is List) {
              print('$prefix    $subKey: [${sv.length} items]');
            } else {
              print('$prefix    $subKey: ${sv.runtimeType}');
            }
          }
        } else if (v is List) {
          print('$prefix  $key: [${v.length} items]');
          for (var i = 0; i < v.length && i < 3; i++) {
            final item = v[i];
            if (item is Map) {
              final keys = (item as Map<String, dynamic>).keys.toList();
              print(
                '$prefix    [$i]: {${keys.take(5).join(", ")}'
                '${keys.length > 5 ? ", ..." : ""}}',
              );
            } else if (item is String) {
              print('$prefix    [$i]: ${_mask(item)}');
            } else {
              print('$prefix    [$i]: ${item.runtimeType}');
            }
          }
          if (v.length > 3) print('$prefix    ... and ${v.length - 3} more');
        } else if (v is bool || v is num) {
          print('$prefix  $key: $v');
        } else {
          print('$prefix  $key: ${v.runtimeType}');
        }
      }
    } else {
      print('${prefix}Config: ${configJson.length} bytes (non-object)');
    }
  } catch (_) {
    print('${prefix}Config: ${configJson.length} bytes (parse error)');
  }
}

String _mask(String v) {
  if (v.length < 8) return '***';
  if (v.length < 16) return '${v.substring(0, 3)}...${v.substring(v.length - 3)}';
  return '${v.substring(0, 8)}...${v.substring(v.length - 4)}';
}

// ignore_for_file: avoid_print

/// Enterprise BYOK provisioning example.
///
/// Authenticates the "All Providers" enterprise profile and provisions both
/// the OpenRouter key and all enterprise BYOK credentials (Bedrock, Azure,
/// Gemini, Claude, OpenAI) via the unified `provisionEncryptedCredentials` RPC.
///
/// Shows the decrypted credential shapes (redacted) for each provider.
///
/// Prerequisites:
///   - gcloud auth application-default login
///   - Access to GCP project global-cloud-runtime
///
/// Run: dart run example/provision_enterprise.dart
import 'dart:convert';

import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  print('═══════════════════════════════════════════════════════');
  print('  AOT Provisioning — Enterprise BYOK (All Providers)');
  print('═══════════════════════════════════════════════════════\n');

  AuthenticatedAOTClient? auth;

  try {
    auth = await AuthenticatedAOTClient.createFromProfile(profile: TestProfiles.enterpriseAllProviders);

    final provisioner = ProvisioningClient(auth);
    final result = await provisioner.provisionAll();

    // ── OpenRouter ──
    print('\n┌── OpenRouter');
    print('│   Credential ID: ${result.credentialId ?? "(none)"}');
    print('│   Base URL:      ${result.baseUrl ?? "(default)"}');
    print('│   API Key:       ${_mask(result.openRouterApiKey)}');
    print('└──\n');

    // ── Enterprise BYOK ──
    if (result.enterpriseCredentials.isEmpty) {
      print('No enterprise BYOK credentials provisioned.');
    } else {
      print('Enterprise BYOK (${result.enterpriseCredentials.length} providers):\n');

      for (final cred in result.enterpriseCredentials) {
        print('┌── ${cred.providerName}');
        print('│   Org: ${cred.orgName ?? cred.orgId}');
        print('│   Org ID: ${_mask(cred.orgId)}');
        _printRedactedConfig(cred.decryptedConfig, prefix: '│   ');
        print('└──\n');
      }
    }

    print(
      'Summary: 1 OpenRouter + '
      '${result.enterpriseCredentials.length} enterprise provider(s)',
    );
  } catch (e, stack) {
    print('\nERROR: $e');
    print('\n$stack');
  } finally {
    await auth?.dispose();
  }
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
        } else if (v is List) {
          print('$prefix  $key: [${v.length} items]');
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

// ignore_for_file: avoid_print

/// Basic OpenRouter provisioning example.
///
/// Authenticates the default enterprise profile via Descope password sign-in,
/// then provisions an OpenRouter API key through the gRPC service.
///
/// Prerequisites:
///   - gcloud auth application-default login
///   - Access to GCP project global-cloud-runtime
///
/// Run: dart run example/main.dart
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  print('═══════════════════════════════════════════════════════');
  print('  AOT Provisioning — OpenRouter Key');
  print('═══════════════════════════════════════════════════════\n');

  AuthenticatedAOTClient? auth;

  try {
    // Authenticate using the default enterprise profile (All Providers org).
    auth = await AuthenticatedAOTClient.createFromProfile(profile: TestProfiles.enterpriseAllProviders);

    print('\n───────────────────────────────────────────────────────');
    print('Authenticated as: ${auth.userEmail}');
    print('User ID:          ${auth.userId}');
    print('Org ID:           ${auth.orgId ?? "(none)"}');
    print('───────────────────────────────────────────────────────\n');

    // Provision an OpenRouter API key.
    final provisioner = ProvisioningClient(auth);
    final result = await provisioner.provisionOpenRouter();

    print('\n───────────────────────────────────────────────────────');
    print('Provisioning complete!');
    print('  Credential ID: ${result.credentialId ?? "(none)"}');
    print('  Base URL:      ${result.baseUrl ?? "(default)"}');
    print('  API Key:       ${_mask(result.openRouterApiKey)}');
    print('───────────────────────────────────────────────────────\n');
  } catch (e, stack) {
    print('\nERROR: $e');
    print('\n$stack');
  } finally {
    await auth?.dispose();
  }
}

String _mask(String v) => v.length > 16 ? '${v.substring(0, 12)}...${v.substring(v.length - 4)}' : '***';

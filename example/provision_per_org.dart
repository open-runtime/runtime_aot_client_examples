// ignore_for_file: avoid_print

/// Per-organization provisioning example.
///
/// Demonstrates provisioning credentials against different enterprise org
/// profiles — each has a different set of native provider credentials:
///
/// | Profile | GSM Providers |
/// |---------|---------------|
/// | All Providers | openai, claude, gcp, azure, bedrock |
/// | GAI Studio Only | gcp (API key) |
/// | Vertex SA Only | gcp (service account) |
/// | Vertex SA + Key | gcp (key + SA) |
/// | No Credentials | (none — negative test) |
///
/// All orgs share the same Descope user (aot-automated-testing@pieces.app).
/// The org differentiation happens via `x-org-id` on the gRPC call.
///
/// Prerequisites:
///   - gcloud auth application-default login
///   - Access to GCP project global-cloud-runtime
///
/// Run: dart run example/provision_per_org.dart
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  print('═══════════════════════════════════════════════════════');
  print('  AOT Provisioning — Per-Org Enterprise Profiles');
  print('═══════════════════════════════════════════════════════\n');

  final profiles = [
    TestProfiles.enterpriseAllProviders,
    TestProfiles.enterpriseGaiStudioOnly,
    TestProfiles.enterpriseVertexSaOnly,
    TestProfiles.enterpriseVertexSaPlusKey,
    TestProfiles.enterpriseNoCredentials,
  ];

  for (final profile in profiles) {
    print('────────────────────────────────────────────────────────');
    print('  ${profile.displayName}');
    print('  Org ID:   ${profile.orgId}');
    print('  Expected: ${profile.expectedProviders.isEmpty ? "(none)" : profile.expectedProviders.join(", ")}');
    print('────────────────────────────────────────────────────────');

    AuthenticatedAOTClient? auth;
    try {
      auth = await AuthenticatedAOTClient.createFromProfile(profile: profile);
      final provisioner = ProvisioningClient(auth);
      final result = await provisioner.provisionAll();

      print('  OpenRouter: ${_mask(result.openRouterApiKey)}');

      if (result.enterpriseCredentials.isEmpty) {
        print('  Enterprise: (none)');
      } else {
        for (final ec in result.enterpriseCredentials) {
          print(
            '  Enterprise ${ec.providerName}: '
            '${ec.decryptedConfig.length} bytes decrypted',
          );
        }
      }

      // Verify expected providers match
      final actual = result.enterpriseCredentials.map((c) => c.providerName).toSet();
      final expected = profile.expectedProviders.toSet();
      if (actual.length == expected.length) {
        print('  Match: expected ${expected.length}, got ${actual.length}');
      } else {
        print('  MISMATCH: expected $expected, got $actual');
      }
    } catch (e) {
      print('  FAILED: $e');
    } finally {
      await auth?.dispose();
    }
    print('');
  }
}

String _mask(String v) => v.length > 16 ? '${v.substring(0, 12)}...${v.substring(v.length - 4)}' : '***';

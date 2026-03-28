# Self-Contained AOT Client

A standalone Dart package for authenticating with AOT services and provisioning credentials. Supports both browser-based OAuth and password-based test profile authentication, with full access to the provisioning gRPC service for OpenRouter keys and enterprise BYOK credentials.

## Prerequisites

1. **Dart SDK 3.9+**
2. **GCP credentials** — Run once:
   ```bash
   gcloud auth application-default login
   ```
3. **Pieces account** — For browser authentication (cached ~55 min), or access to GSM test passwords for profile-based auth

## Quick Start

```bash
dart pub get

# Basic OpenRouter provisioning (password auth, no browser)
dart run example/main.dart

# Enterprise BYOK provisioning (all providers)
dart run example/provision_enterprise.dart

# Discover all profiles, orgs, and credentials
dart run example/discover_profiles.dart

# Per-org provisioning comparison
dart run example/provision_per_org.dart
```

## Usage

### Browser-Based Auth (interactive)

```dart
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  final auth = await AuthenticatedAOTClient.create();

  final channel = ClientChannel(
    'your-service-url.run.app',
    port: 443,
    options: ChannelOptions(credentials: ChannelCredentials.secure()),
  );

  final client = YourServiceClient(channel, interceptors: [auth.interceptor]);
  final response = await client.predict(request, options: auth.callOptionsWithOrgId);

  await auth.dispose();
  await channel.shutdown();
}
```

### Test Profile Auth (non-interactive, CI-friendly)

```dart
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  // Authenticate a specific test profile via Descope password sign-in.
  // No browser needed — passwords are fetched from GCP Secret Manager.
  final auth = await AuthenticatedAOTClient.createFromProfile(
    profile: TestProfiles.enterpriseAllProviders,
  );

  print('Authenticated as: ${auth.userEmail}');
  print('Org ID: ${auth.orgId}');
  print('Selected key: ${auth.selectedKey.substring(0, 8)}...');

  await auth.dispose();
}
```

### Provisioning Credentials

```dart
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  final auth = await AuthenticatedAOTClient.createFromProfile(
    profile: TestProfiles.enterpriseAllProviders,
  );
  final provisioner = ProvisioningClient(auth);

  // OpenRouter only
  final orResult = await provisioner.provisionOpenRouter();
  print('OpenRouter key: ${orResult.openRouterApiKey}');

  // OpenRouter + all enterprise BYOK (Bedrock, Azure, Gemini, Claude, OpenAI)
  final allResult = await provisioner.provisionAll();
  print('Enterprise providers: ${allResult.enterpriseCredentials.length}');

  for (final cred in allResult.enterpriseCredentials) {
    print('  ${cred.providerName}: ${cred.decryptedConfig.length} bytes');
  }

  await auth.dispose();
}
```

## Test Profiles

Pre-defined Descope test users at each payment tier:

| Profile | Tier | Org | Expected Providers |
|---------|------|-----|-------------------|
| `alice`, `aliceWork`, `bob`, `charlie` | Free | (none) | — |
| `enterpriseAllProviders` | Enterprise | Primary | openai, claude, gcp, azure, bedrock |
| `enterpriseGaiStudioOnly` | Enterprise | GAI Studio Only | gcp (key) |
| `enterpriseVertexApiKeyOnly` | Enterprise | Vertex API Key Only | gcp (key) |
| `enterpriseVertexSaOnly` | Enterprise | Vertex SA Only | gcp (SA) |
| `enterpriseVertexSaPlusKey` | Enterprise | Vertex SA + Key | gcp (key + SA) |
| `enterpriseNoCredentials` | Enterprise | No Credentials | (none) |
| `aotProTesting` | Pro | — | — |

All enterprise profiles share the same Descope user (`aot-automated-testing@pieces.app`). Org differentiation happens via `x-org-id` on the gRPC call.

### Profile Groupings

```dart
TestProfiles.all                  // Every profile (11)
TestProfiles.freePersonal         // alice, aliceWork, bob, charlie
TestProfiles.enterprise           // All 6 enterprise orgs
TestProfiles.enterpriseWithGcp    // 5 orgs with GCP credentials
TestProfiles.enterpriseWithVertexSa  // 3 orgs with Vertex SA
TestProfiles.enterpriseWithOpenai // 1 org with OpenAI
TestProfiles.enterpriseWithClaude // 1 org with Claude
TestProfiles.enterpriseWithAzure  // 1 org with Azure
TestProfiles.enterpriseWithBedrock // 1 org with Bedrock
```

## API Reference

### AuthenticatedAOTClient

```dart
// Browser auth (interactive)
final auth = await AuthenticatedAOTClient.create();

// Profile auth (non-interactive)
final auth = await AuthenticatedAOTClient.createFromProfile(
  profile: TestProfiles.enterpriseAllProviders,
);

auth.interceptor          // ClientInterceptor for gRPC
auth.callOptionsWithOrgId // CallOptions with x-org-id header
auth.orgId                // Organization ID (String?)
auth.userId               // User's global ID
auth.userEmail            // User's email
auth.accessToken          // Descope JWT
auth.selectedKey          // MindFck key for credential decryption
auth.userKeys             // 13 API keys from user-team-service

await auth.dispose();
await AuthenticatedAOTClient.clearCache();
```

### ProvisioningClient

```dart
final provisioner = ProvisioningClient(auth);

// OpenRouter only (with optional key rotation)
final orResult = await provisioner.provisionOpenRouter(rotate: false);
orResult.openRouterApiKey   // Decrypted sk-or-v1-... key
orResult.credentialId       // OpenRouter key hash
orResult.baseUrl            // Base URL (null = default)

// All credentials (OpenRouter + enterprise BYOK)
final allResult = await provisioner.provisionAll();
allResult.openRouterApiKey
allResult.enterpriseCredentials  // List<EnterpriseProviderCredentials>

for (final cred in allResult.enterpriseCredentials) {
  cred.providerName     // aws-bedrock, azure-openai, gemini, claude, openai
  cred.orgId            // Organization ID
  cred.orgName          // Organization name
  cred.decryptedConfig  // Full decrypted JSON config
}
```

## Examples

| Example | Description |
|---------|-------------|
| `example/main.dart` | Basic OpenRouter provisioning with default enterprise profile |
| `example/provision_enterprise.dart` | Enterprise BYOK with decrypted credential shape inspection |
| `example/discover_profiles.dart` | Full discovery of all profiles, orgs, and credentials |
| `example/provision_per_org.dart` | Per-org provisioning comparison across enterprise orgs |

## Running Tests

### Unit tests (CI-safe, no network)

```bash
dart test test/voxtral_test.dart
dart test test/token_cache_test.dart
```

### Integration tests (requires GCP + network)

The provisioning matrix test exercises the full 11-profile matrix across all 3 tiers and 6 enterprise orgs:

```bash
# Run the full matrix
dart test --tags integration test/provisioning_matrix_test.dart

# Or via preset
dart test --preset integration
```

**Coverage:**

| Group | Tests | What |
|-------|-------|------|
| Profile metadata | 9 | Static assertions on definitions, groupings, uniqueness |
| Password auth | 13 | Descope sign-in per profile, identity isolation |
| OpenRouter provisioning | 13 | `sk-or-` key per profile, cross-org key uniqueness |
| Enterprise BYOK | 10 | Provider count alignment per org, decrypted JSON validity |
| GSM credential shapes | 9 | Per-org JSON structure (api_keys, service_accounts) |
| Cross-org isolation | 3 | Credential boundaries between orgs |
| Credential config shapes | 5 | OpenAI/Claude/Gemini/Azure/Bedrock JSON schemas |
| Client fields | 3 | orgId, callOptions, selectedKey population |

## Troubleshooting

### "Failed to load GCP credentials"

```bash
gcloud auth application-default login
```

### "Could not resolve Descope password"

Ensure you have access to GCP project `global-cloud-runtime` and the test password secrets (`aot-descope-test-user-free-password`, `aot-descope-pro-password`).

### "No apiKeys field found in user data"

Your Pieces account may not be properly set up. Contact the team.

### Browser doesn't open (browser auth)

Check if you're running in a headless environment. Use `createFromProfile()` for non-interactive auth.

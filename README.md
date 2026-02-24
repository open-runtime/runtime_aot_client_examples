# Self-Contained AOT Client

A standalone Dart package for authenticating with AOT services. Handles browser-based OAuth authentication and provides a secure gRPC interceptor for making authenticated requests to AOT Cloud Run services.

## Prerequisites

1. **Dart SDK 3.9+**
2. **GCP credentials** - Run once:
   ```bash
   gcloud auth application-default login
   ```
3. **Pieces account** - For browser authentication (opens once, then cached for ~55 min)

## Quick Start

```bash
# Get dependencies
dart pub get

# Run the example
dart run example/main.dart
```

## Usage

```dart
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/services/service.pbgrpc.dart';

void main() async {
  // 1. Create authenticated client (opens browser if needed)
  final auth = await AuthenticatedAOTClient.create();

  // 2. Create gRPC channel to the service
  final channel = ClientChannel(
    'runtime-native-io-aws-bedrock-inference-grpc-serv-lmuw6mcn3q-ul.a.run.app',
    port: 443,
    options: ChannelOptions(credentials: ChannelCredentials.secure()),
  );

  // 3. Create service client with the auth interceptor
  final client = AWSBedrockInferenceServiceClient(
    channel,
    interceptors: [auth.interceptor],
  );

  // 4. Make authenticated requests
  final response = await client.predict(
    request,
    options: auth.callOptionsWithOrgId,  // Include org-id for enterprise features
  );

  // 5. Clean up
  await auth.dispose();
  await channel.shutdown();
}
```

## How It Works

1. **First run**: Opens browser for Descope OAuth authentication
2. **Subsequent runs**: Uses cached token (valid for ~55 minutes)
3. **Token expires**: Automatically opens browser again

The `AuthenticatedAOTClient.create()` method handles:
- Checking for cached auth token
- Browser OAuth flow with Descope (if needed)
- Fetching user keys from user-team-service
- Fetching org ID for enterprise features
- Creating the secure gRPC interceptor

## API Reference

### AuthenticatedAOTClient

The main entry point for authentication.

```dart
// Create authenticated client
final auth = await AuthenticatedAOTClient.create();

// Access properties
auth.interceptor      // ClientInterceptor for gRPC
auth.callOptionsWithOrgId  // CallOptions with x-org-id header
auth.orgId            // Organization ID (String?)
auth.userId           // User's global ID
auth.userEmail        // User's email

// Clean up
await auth.dispose();

// Clear cache (force re-authentication)
await AuthenticatedAOTClient.clearCache();
```

### Token Cache

Tokens are cached in the system temp directory for ~55 minutes.

```dart
// Check cache status
await logTokenCacheStatus();

// Clear cache manually
await TokenCache.clearCache();
```

## Re-authenticating / Clearing Cache

The client caches your Descope token for ~55 minutes. To force a fresh browser login:

```bash
# Run the cache clear script
dart run bin/clear_auth_cache.dart
```

Or programmatically:
```dart
await AuthenticatedAOTClient.clearCache();
```

The cache file location:
- **Windows**: `%TEMP%\aot_self_contained_token_cache.json`
- **macOS/Linux**: `/tmp/aot_self_contained_token_cache.json`

You can also manually delete this file.

## Running Tests

The package includes CI-safe unit tests for verifying audio transcription request construction:

```bash
# Run the Voxtral request construction tests
dart test test/voxtral_test.dart
```

## Troubleshooting

### "Failed to load GCP credentials"

Run:
```bash
gcloud auth application-default login
```

### "No apiKeys field found in user data"

Your Pieces account may not be properly set up. Contact the team.

### Browser doesn't open

Check if you're running in a headless environment. The package requires a browser for initial authentication.

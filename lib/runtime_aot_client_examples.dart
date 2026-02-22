/// Self-contained AOT client library.
///
/// This library provides everything needed to authenticate with AOT services
/// and make authenticated gRPC requests. It handles:
///
/// - Browser-based OAuth authentication with Descope
/// - Token caching (55 minutes) to avoid repeated logins
/// - Secure request signing and encryption
/// - Organization ID fetching for enterprise features
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';
/// import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/services/service.pbgrpc.dart';
///
/// void main() async {
///   // 1. Create authenticated client (opens browser if needed)
///   final auth = await AuthenticatedAOTClient.create();
///
///   // 2. Create gRPC channel to the service
///   final channel = ClientChannel(
///     'your-service-url.run.app',
///     port: 443,
///     options: ChannelOptions(credentials: ChannelCredentials.secure()),
///   );
///
///   // 3. Create service client with the auth interceptor
///   final client = AWSBedrockInferenceServiceClient(
///     channel,
///     interceptors: [auth.interceptor],
///   );
///
///   // 4. Make authenticated requests
///   final response = await client.predict(
///     request,
///     options: auth.callOptionsWithOrgId,
///   );
///
///   // 5. Clean up
///   await auth.dispose();
///   await channel.shutdown();
/// }
/// ```
///
/// ## Prerequisites
///
/// 1. **Dart SDK 3.9+**
/// 2. **GCP credentials**: Run `gcloud auth application-default login`
/// 3. **Pieces account**: For Descope authentication
library runtime_aot_client_examples;

// Main API
export 'src/client/authenticated_client.dart' show AuthenticatedAOTClient;

// Interceptor (for advanced usage)
export 'src/interceptor/secure_interceptor.dart' show SecureAOTAuthorizationInterceptor, AOTAuthenticationRequired;
export 'src/interceptor/metadata.dart' show AOTAuthorizationInterceptorClientMetadataOptions;

// Auth utilities (for advanced usage)
export 'src/auth/browser_auth.dart' show getDescopeAccessTokenViaBrowser, getDescopeUserInfo, descopeProjectId;
export 'src/auth/token_cache.dart' show TokenCache, logTokenCacheStatus;
export 'src/auth/user_service.dart'
    show fetchUserDataFromService, fetchOrgIdFromAotEndpoint, extractUserKeys, defaultUserTeamServiceUrl;
export 'src/auth/secret_fetcher.dart' show SecretFetcher;

// Re-export grpc types for convenience
export 'package:grpc/grpc.dart' show ClientChannel, ChannelOptions, ChannelCredentials, CallOptions;

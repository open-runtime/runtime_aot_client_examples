/// Self-contained AOT client library.
///
/// Provides everything needed to authenticate with AOT services, provision
/// credentials, and make authenticated gRPC requests. Supports both
/// browser-based OAuth and password-based authentication for test profiles.
///
/// ## Quick Start — Browser Auth
///
/// ```dart
/// import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';
///
/// void main() async {
///   final auth = await AuthenticatedAOTClient.create();
///   // Use auth.interceptor with any gRPC service client.
///   await auth.dispose();
/// }
/// ```
///
/// ## Quick Start — Test Profile Provisioning
///
/// ```dart
/// import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';
///
/// void main() async {
///   final auth = await AuthenticatedAOTClient.createFromProfile(
///     profile: TestProfiles.enterpriseAllProviders,
///   );
///   final provisioner = ProvisioningClient(auth);
///   final creds = await provisioner.provisionAll();
///   print('OpenRouter: ${creds.openRouterApiKey}');
///   print('Enterprise: ${creds.enterpriseCredentials.length} providers');
///   await auth.dispose();
/// }
/// ```
///
/// ## Prerequisites
///
/// 1. **Dart SDK 3.9+**
/// 2. **GCP credentials**: `gcloud auth application-default login`
/// 3. **Pieces account**: For browser auth, or access to GSM test passwords
library;

// Re-export grpc types for convenience
export 'package:grpc/grpc.dart' show CallOptions, ChannelCredentials, ChannelOptions, ClientChannel;

// Auth utilities
export 'src/auth/browser_auth.dart' show descopeProjectId, getDescopeAccessTokenViaBrowser, getDescopeUserInfo;
export 'src/auth/password_auth.dart'
    show DescopePasswordAuthResult, authenticateDescopePassword, authenticateProfile, resolvePasswordForProfile;
export 'src/auth/secret_fetcher.dart' show SecretFetcher;
export 'src/auth/token_cache.dart' show TokenCache, logTokenCacheStatus;
export 'src/auth/user_service.dart'
    show defaultUserTeamServiceUrl, extractUserKeys, fetchOrgIdFromAotEndpoint, fetchUserDataFromService;

// Main API
export 'src/client/authenticated_client.dart' show AuthenticatedAOTClient;

// Test profiles
export 'src/profiles/test_profiles.dart' show TestProfile, TestProfiles;

// Provisioning
export 'src/provisioning/provisioning_client.dart'
    show EnterpriseProviderCredentials, ProvisioningClient, ProvisioningResult;

// Interceptor (for advanced usage)
export 'src/interceptor/metadata.dart' show AOTAuthorizationInterceptorClientMetadataOptions;
export 'src/interceptor/secure_interceptor.dart' show AOTAuthenticationRequired, SecureAOTAuthorizationInterceptor;

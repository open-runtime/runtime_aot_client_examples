// Printing is used for diagnostic output during authentication.
// ignore_for_file: avoid_print

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' show SecretKey;
import 'package:grpc/grpc.dart' show CallOptions, ClientInterceptor;
import 'package:runtime_mindfck/client.dart' show ClientAuthManager;

import '../auth/browser_auth.dart' show getDescopeAccessTokenViaBrowser, getDescopeUserInfo;
import '../auth/secret_fetcher.dart' show SecretFetcher;
import '../auth/token_cache.dart' show TokenCache;
import '../auth/user_service.dart'
    show defaultUserTeamServiceUrl, extractUserKeys, fetchOrgIdFromAotEndpoint, fetchUserDataFromService;
import '../interceptor/metadata.dart' show AOTAuthorizationInterceptorClientMetadataOptions;
import '../interceptor/secure_interceptor.dart' show SecureAOTAuthorizationInterceptor;

/// High-level API for creating authenticated AOT clients.
///
/// This class handles the complete authentication flow:
/// 1. Checks for cached browser auth token (avoids repeated logins)
/// 2. If no cache, opens browser for Descope OAuth authentication
/// 3. Fetches user keys from user-team-service
/// 4. Fetches organization ID for enterprise features
/// 5. Creates a secure gRPC interceptor with all required auth headers
///
/// ## Usage
///
/// ```dart
/// // Create authenticated client (opens browser if not cached)
/// final auth = await AuthenticatedAOTClient.create();
///
/// // Use the interceptor with any AOT gRPC service
/// final channel = ClientChannel(
///   'runtime-native-io-aws-bedrock-inference-grpc-service-...',
///   port: 443,
///   options: ChannelOptions(credentials: ChannelCredentials.secure()),
/// );
///
/// final client = AWSBedrockInferenceServiceClient(
///   channel,
///   interceptors: [auth.interceptor],
/// );
///
/// // Make requests with org-id header for enterprise features
/// final response = await client.predict(
///   request,
///   options: auth.callOptionsWithOrgId,
/// );
///
/// // Clean up when done
/// await auth.dispose();
/// await channel.shutdown();
/// ```
class AuthenticatedAOTClient {
  AuthenticatedAOTClient._({
    required SecureAOTAuthorizationInterceptor interceptor,
    required this.orgId,
    required this.userEmail,
    required this.userId,
    required this.accessToken,
  }) : _interceptor = interceptor;

  /// The secure gRPC interceptor for authenticated requests.
  final SecureAOTAuthorizationInterceptor _interceptor;

  /// The user's organization ID (for enterprise features).
  final String? orgId;

  /// The user's email address.
  final String? userEmail;

  /// The user's global ID.
  final String userId;

  /// The Descope access token.
  final String accessToken;

  /// Creates an authenticated AOT client.
  ///
  /// This method handles the complete authentication flow:
  /// 1. Checks for cached token (55 min validity)
  /// 2. If no cache or expired, opens browser for Descope auth
  /// 3. Fetches user data and encryption keys from user-team-service
  /// 4. Fetches org ID from /aot endpoint
  /// 5. Creates secure interceptor with all auth headers
  ///
  /// Parameters:
  /// - [userTeamServiceUrl]: Override the user-team-service URL (optional)
  ///
  /// Returns an [AuthenticatedAOTClient] ready for making gRPC calls.
  static Future<AuthenticatedAOTClient> create({String? userTeamServiceUrl}) async {
    print('🔐 Starting AOT authentication...');

    // Initialize ClientAuthManager for MindFck header generation
    await ClientAuthManager.initialize();

    // Fetch AOT secrets from GCP Secret Manager
    final secretFetcher = await SecretFetcher.create();
    final secrets = await secretFetcher.fetchAOTSecrets();

    String accessToken;
    String effectiveUserId;
    String? effectiveUserEmail;

    // Check for cached token first
    final cachedData = await TokenCache.getCachedToken();

    if (cachedData != null) {
      print('🚀 Using cached authentication token');
      accessToken = cachedData.accessToken;
      effectiveUserId = cachedData.userId;
      effectiveUserEmail = cachedData.email;

      // Refresh email from Descope if not in cache
      if (effectiveUserEmail == null) {
        try {
          final descopeUserInfo = await getDescopeUserInfo(accessToken);
          effectiveUserEmail = descopeUserInfo.email;
        } on Object catch (e) {
          print('⚠️ Failed to fetch email from Descope: $e');
        }
      }
    } else {
      print('🌐 No cached token - starting browser authentication');

      // Get Descope access token through browser OAuth
      accessToken = await getDescopeAccessTokenViaBrowser();

      // Get user info from Descope token
      final descopeUserInfo = await getDescopeUserInfo(accessToken);
      effectiveUserId = descopeUserInfo.userId;
      effectiveUserEmail = descopeUserInfo.email;

      // Cache the token for future use
      final jwtExpiration = TokenCache.getJwtExpiration(accessToken);
      final validFor = jwtExpiration != null ? jwtExpiration.difference(DateTime.now()) : const Duration(minutes: 55);

      await TokenCache.saveToken(
        accessToken: accessToken,
        userId: effectiveUserId,
        email: effectiveUserEmail,
        validFor: validFor.isNegative ? const Duration(minutes: 55) : validFor,
      );
    }

    // Fetch user data from user-team-service to get global ID and keys
    final effectiveServiceUrl = userTeamServiceUrl ?? defaultUserTeamServiceUrl;

    final userData = await fetchUserDataFromService(
      userTeamServiceUrl: effectiveServiceUrl,
      userId: effectiveUserId,
      accessToken: accessToken,
    );

    // Extract global ID (may be different from Descope user ID)
    final globalUserId =
        userData['globalId']?.toString() ??
        userData['global_id']?.toString() ??
        userData['id']?.toString() ??
        effectiveUserId;

    print('🌐 Using global ID: $globalUserId');

    // Extract email from user-team-service if not from Descope
    final serviceEmail = userData['email']?.toString();
    if (serviceEmail != null && serviceEmail.isNotEmpty) {
      effectiveUserEmail ??= serviceEmail;
    }

    // Extract user keys (13 API keys for MindFck)
    final userKeys = extractUserKeys(userData);

    // Generate MindFck headers
    final mindFckHeaders = await ClientAuthManager.generateRequestHeaders(userKeys: userKeys, userId: globalUserId);

    print('✅ MindFck headers generated');
    print('   Magic number length: ${mindFckHeaders.headers.magicNumber.length}');
    print('   Time header: ${mindFckHeaders.headers.timeHeader}');
    print('   Selected key: ${mindFckHeaders.selectedKey.substring(0, 8)}...');

    // Fetch organization ID for enterprise features
    String? orgId;
    print('📋 Fetching organization ID...');
    final orgData = await fetchOrgIdFromAotEndpoint(accessToken: accessToken, userTeamServiceUrl: effectiveServiceUrl);
    orgId = orgData.orgId;

    // Create authenticated metadata
    final metadata = AOTAuthorizationInterceptorClientMetadataOptions.withDefaults(
      userId: globalUserId,
      userEmail: effectiveUserEmail ?? 'unknown@example.com',
      accessToken: accessToken,
      hmacSigningKey: secrets.hmacSigningKey,
      encryptionKey: secrets.encryptionKey,
      globalKey: mindFckHeaders.selectedKey,
      magicNumber: mindFckHeaders.headers.magicNumber,
      timeHeader: mindFckHeaders.headers.timeHeader,
      apiKey: secrets.apiKey,
    );

    // Create secure interceptor
    final interceptor = SecureAOTAuthorizationInterceptor(
      clientMetadata: metadata,
      signingKey: secrets.hmacSigningKey,
      jwtKey: SecretKey(secrets.apiKey),
      encryptionKey: secrets.encryptionKey,
    );

    print('✅ Authentication complete!');
    print('   User: $effectiveUserEmail');
    print('   Global ID: $globalUserId');
    if (orgId != null) {
      print('   Org ID: $orgId');
    }

    return AuthenticatedAOTClient._(
      interceptor: interceptor,
      orgId: orgId,
      userEmail: effectiveUserEmail,
      userId: globalUserId,
      accessToken: accessToken,
    );
  }

  /// The secure interceptor to use with gRPC clients.
  ///
  /// Use this when creating your service client:
  /// ```dart
  /// final client = YourServiceClient(channel, interceptors: [auth.interceptor]);
  /// ```
  ClientInterceptor get interceptor => _interceptor;

  /// CallOptions with the x-org-id header set.
  ///
  /// Use this when making requests that require enterprise features:
  /// ```dart
  /// final response = await client.predict(request, options: auth.callOptionsWithOrgId);
  /// ```
  CallOptions get callOptionsWithOrgId {
    if (orgId != null && orgId!.isNotEmpty) {
      return CallOptions(metadata: {'x-org-id': orgId!});
    }
    return CallOptions();
  }

  /// Whether this client has an organization ID.
  bool get hasOrgId => orgId != null && orgId!.isNotEmpty;

  /// Clean up authentication resources.
  ///
  /// Call this when you're done using the client.
  Future<void> dispose() async {
    await ClientAuthManager.dispose();
    print('🧹 Authentication resources cleaned up');
  }

  /// Clear the cached authentication token.
  ///
  /// Call this to force re-authentication on next [create] call.
  static Future<void> clearCache() async {
    await TokenCache.clearCache();
  }
}

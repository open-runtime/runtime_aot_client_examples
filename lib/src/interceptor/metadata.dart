/// Metadata options for the AOT authorization interceptor.
///
/// Contains all the authentication data needed by [SecureAOTAuthorizationInterceptor]
/// to sign, encrypt, and authenticate gRPC requests.
///
/// ## Usage
///
/// ```dart
/// final metadata = AOTAuthorizationInterceptorClientMetadataOptions(
///   os: Platform.operatingSystem,
///   userId: 'user-global-id',
///   userEmail: 'user@example.com',
///   accessToken: 'descope-jwt-token',
///   hmacSigningKey: signingKey,
///   encryptionKey: encryptionKey,
///   globalKey: mindFckHeaders.selectedKey,
///   magicNumber: mindFckHeaders.headers.magicNumber,
///   timeHeader: mindFckHeaders.headers.timeHeader,
///   apiKey: apiKey,
///   // ... other fields
/// );
/// ```
class AOTAuthorizationInterceptorClientMetadataOptions {
  /// Operating system identifier.
  final String? os;

  /// User's global ID (from user-team-service).
  final String? userId;

  /// User's email address.
  final String? userEmail;

  /// Client IP address.
  final String? clientIp;

  /// Country name from IP lookup.
  final String? countryIpName;

  /// IP address from country lookup.
  final String? countryIpAddress;

  /// Country code from IP lookup (e.g., 'US').
  final String? countryIpCode;

  /// OS/server version string.
  final String? osServerVersion;

  /// Descope access token (JWT).
  final String? accessToken;

  /// Key for HMAC request signing (any size base64).
  final String hmacSigningKey;

  /// Encryption key (any size - will be hashed to 32 bytes for AES-256).
  final String encryptionKey;

  /// ISR (Internal State Representation) as JSON string.
  final String isrJSONString;

  /// Selected key from user's 13 API keys (used in key derivation).
  final String globalKey;

  /// MindFck magic number for authentication.
  final String magicNumber;

  /// MindFck time header for authentication.
  final String timeHeader;

  /// API key for authentication.
  final String apiKey;

  AOTAuthorizationInterceptorClientMetadataOptions({
    this.os,
    this.userId,
    this.userEmail,
    this.clientIp,
    this.countryIpName,
    this.countryIpAddress,
    this.countryIpCode,
    this.osServerVersion,
    this.accessToken,
    required this.hmacSigningKey,
    required this.encryptionKey,
    required this.isrJSONString,
    required this.globalKey,
    required this.magicNumber,
    required this.timeHeader,
    required this.apiKey,
  });

  /// Creates metadata with default values for optional fields.
  factory AOTAuthorizationInterceptorClientMetadataOptions.withDefaults({
    required String userId,
    required String userEmail,
    required String accessToken,
    required String hmacSigningKey,
    required String encryptionKey,
    required String globalKey,
    required String magicNumber,
    required String timeHeader,
    required String apiKey,
  }) {
    return AOTAuthorizationInterceptorClientMetadataOptions(
      os: '8daf5be6-a57a-4f21-b23e-ac6c2e612e27', // Default OS identifier
      userId: userId,
      userEmail: userEmail,
      clientIp: '127.0.0.1',
      countryIpName: 'United States',
      countryIpAddress: '127.0.0.1',
      countryIpCode: 'US',
      osServerVersion: "12.3.87-staging",
      accessToken: accessToken,
      hmacSigningKey: hmacSigningKey,
      encryptionKey: encryptionKey,
      isrJSONString: '{}', // Empty ISR for client usage
      globalKey: globalKey,
      magicNumber: magicNumber,
      timeHeader: timeHeader,
      apiKey: apiKey,
    );
  }
}

// Printing is used for debug/diagnostic output during authentication.
// ignore_for_file: avoid_print

import 'dart:convert' show base64Decode, base64Encode, utf8;
import 'dart:math' show Random;
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart' show JWT, SecretKey;
import 'package:encrypt/encrypt.dart' show AES, Encrypter, IV, Key;
import 'package:grpc/grpc.dart'
    show
        CallOptions,
        ClientInterceptor,
        ClientMethod,
        ClientStreamingInvoker,
        ClientUnaryInvoker,
        ResponseFuture,
        ResponseStream;
import 'package:uuid/uuid.dart' show Uuid;

import 'metadata.dart' show AOTAuthorizationInterceptorClientMetadataOptions;

/// Exception thrown when authentication is required but not available.
class AOTAuthenticationRequired implements Exception {
  AOTAuthenticationRequired(this.cause);
  final String cause;

  @override
  String toString() => 'AOTAuthenticationRequired: $cause';
}

/// Secure gRPC interceptor for AOT services.
///
/// This interceptor provides:
/// 1. Request signing with HMAC-SHA256
/// 2. Replay attack protection with timestamps and nonces
/// 3. Encrypted JWT tokens
/// 4. API key authentication
/// 5. Payload encryption with AES-256
///
/// ## Usage
///
/// ```dart
/// final interceptor = SecureAOTAuthorizationInterceptor(
///   clientMetadata: metadata,
///   signingKey: metadata.hmacSigningKey,
///   jwtKey: SecretKey(metadata.apiKey),
///   encryptionKey: metadata.encryptionKey,
/// );
///
/// final client = YourServiceClient(channel, interceptors: [interceptor]);
/// ```
class SecureAOTAuthorizationInterceptor extends ClientInterceptor {
  SecureAOTAuthorizationInterceptor({
    required this.clientMetadata,
    required this.signingKey,
    required this.jwtKey,
    required this.encryptionKey,
  });

  /// Client metadata containing auth tokens and keys.
  AOTAuthorizationInterceptorClientMetadataOptions clientMetadata;

  /// Key for HMAC signing.
  final String signingKey;

  /// Key for encrypting sensitive data.
  final String encryptionKey;

  /// Key for signing JWTs.
  final SecretKey jwtKey;

  /// UUID generator for nonces and request IDs.
  final _uuid = const Uuid();

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    // Validate authentication
    if ((clientMetadata.userId ?? '').isEmpty) {
      throw AOTAuthenticationRequired('Authentication is required, however our users userId is empty');
    }

    if (clientMetadata.accessToken == null) {
      throw AOTAuthenticationRequired('Authentication is required, however the user is not authenticated.');
    }

    // Derive encryption keys
    final encryptedJWTKey = sha256.convert(utf8.encode('${jwtKey.key}${clientMetadata.globalKey}jwt_key')).toString();
    final encryptedSigningKey = sha256
        .convert(utf8.encode('$signingKey${clientMetadata.globalKey}signing_key'))
        .toString();
    final encryptedEncryptionKey = sha256
        .convert(utf8.encode('$encryptionKey${clientMetadata.globalKey}encryption_key'))
        .toString();

    // Prepare metadata - START WITH EXISTING METADATA FROM CallOptions
    final metadata = <String, String>{};
    if (options.metadata.isNotEmpty) {
      metadata.addAll(options.metadata);
    }

    // Generate security identifiers
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final nonce = _uuid.v4();
    final requestId = metadata['x-request-id'] ?? _uuid.v4();

    // Generate JWT
    final dynamicJWT = _jwtGenerator(
      payload: {'timestamp': timestamp, 'nonce': nonce, 'request_id': requestId, 'method': method.path},
      encryptedJWTKey: encryptedJWTKey,
    );

    // Add authentication metadata
    metadata['authorization'] = 'Bearer $dynamicJWT';
    metadata['x-request-id'] = requestId;
    metadata['x-timestamp'] = timestamp;
    metadata['x-nonce'] = nonce;

    // Add HMAC signature
    final signature = _createRequestSignature(
      method: method.path,
      timestamp: timestamp,
      nonce: nonce,
      requestBody: request.toString(),
      accessToken: clientMetadata.accessToken ?? '',
      hmacSigningKey: encryptedSigningKey,
    );
    metadata['x-request-signature'] = signature;

    // Encrypt sensitive data
    metadata['x-encrypted-access-token'] = _encryptData(
      data: clientMetadata.accessToken ?? '',
      encryptionKey: encryptedEncryptionKey,
    );
    metadata['x-encrypted-user-email'] = _encryptData(
      data: clientMetadata.userEmail ?? '',
      encryptionKey: encryptedEncryptionKey,
    );
    // NOTE: user id uses the normal encryptionKey (not derived)
    metadata['x-encrypted-user-id'] = _encryptData(
      data: clientMetadata.userId ?? '',
      encryptionKey: clientMetadata.encryptionKey,
    );
    metadata['x-encrypted-isr'] = _encryptData(
      data: clientMetadata.isrJSONString,
      encryptionKey: encryptedEncryptionKey,
    );
    metadata['x-request-runtime-number'] = clientMetadata.magicNumber;
    metadata['x-request-runtime-time'] = clientMetadata.timeHeader;

    // Add non-sensitive metadata
    metadata.addAll({
      'os': clientMetadata.os ?? 'UNKNOWN',
      'client_ip_address': clientMetadata.clientIp ?? 'UNKNOWN',
      'country_ip_code': clientMetadata.countryIpCode ?? 'UNKNOWN',
      'os_server_version': clientMetadata.osServerVersion ?? 'UNKNOWN',
    });

    // Create updated CallOptions
    final updatedOptions = options.mergedWith(
      CallOptions(metadata: metadata, timeout: options.timeout, compression: options.compression),
    );

    return invoker(method, request, updatedOptions);
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    // Validate authentication
    if (clientMetadata.accessToken == null) {
      throw AOTAuthenticationRequired('Authentication is required, however the user is not authenticated.');
    }

    // Derive encryption keys
    final encryptedJWTKey = sha256.convert(utf8.encode('${jwtKey.key}${clientMetadata.globalKey}jwt_key')).toString();
    final encryptedSigningKey = sha256
        .convert(utf8.encode('$signingKey${clientMetadata.globalKey}signing_key'))
        .toString();
    final encryptedEncryptionKey = sha256
        .convert(utf8.encode('$encryptionKey${clientMetadata.globalKey}encryption_key'))
        .toString();

    // Generate security identifiers
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final nonce = _uuid.v4();
    final streamId = _uuid.v4();

    // Generate JWT for stream
    final initialJWT = _jwtGenerator(
      payload: {
        'streamInit': true,
        'timestamp': timestamp,
        'nonce': nonce,
        'stream_id': streamId,
        'method': method.path,
      },
      encryptedJWTKey: encryptedJWTKey,
    );

    // Prepare metadata
    final metadata = <String, String>{};
    if (options.metadata.isNotEmpty) {
      metadata.addAll(options.metadata);
    }

    // Add authentication metadata
    metadata.addAll({
      'authorization': 'Bearer $initialJWT',
      'x-stream-id': streamId,
      'x-timestamp': timestamp,
      'x-nonce': nonce,
    });

    // Add HMAC signature
    final signature = _createRequestSignature(
      method: method.path,
      timestamp: timestamp,
      nonce: nonce,
      requestBody: 'stream:$streamId',
      accessToken: clientMetadata.accessToken ?? '',
      hmacSigningKey: encryptedSigningKey,
    );
    metadata['x-stream-signature'] = signature;

    // Encrypt sensitive data
    metadata['x-encrypted-access-token'] = _encryptData(
      data: clientMetadata.accessToken ?? '',
      encryptionKey: encryptedEncryptionKey,
    );
    metadata['x-encrypted-user-email'] = _encryptData(
      data: clientMetadata.userEmail ?? '',
      encryptionKey: encryptedEncryptionKey,
    );
    metadata['x-encrypted-user-id'] = _encryptData(data: clientMetadata.userId ?? '', encryptionKey: encryptionKey);
    metadata['x-encrypted-isr'] = _encryptData(
      data: clientMetadata.isrJSONString,
      encryptionKey: encryptedEncryptionKey,
    );
    metadata['x-request-runtime-number'] = clientMetadata.magicNumber;
    metadata['x-request-runtime-time'] = clientMetadata.timeHeader;

    // Add non-sensitive metadata
    metadata.addAll({
      'os': clientMetadata.os ?? 'UNKNOWN',
      'os_server_version': clientMetadata.osServerVersion ?? 'UNKNOWN',
    });

    // Create updated CallOptions
    final updatedOptions = options.mergedWith(
      CallOptions(metadata: metadata, timeout: options.timeout, compression: options.compression),
    );

    return invoker(method, requests, updatedOptions);
  }

  /// Creates HMAC-SHA256 signature for request integrity.
  String _createRequestSignature({
    required String method,
    required String timestamp,
    required String nonce,
    required String requestBody,
    required String accessToken,
    required String hmacSigningKey,
  }) {
    // Create canonical string to sign
    final dataToSign = [
      method,
      timestamp,
      nonce,
      sha256.convert(utf8.encode(requestBody)).toString(),
      sha256.convert(utf8.encode(accessToken)).toString(),
    ].join('|');

    // Generate HMAC-SHA256
    final key = utf8.encode(hmacSigningKey);
    final bytes = utf8.encode(dataToSign);
    final hmac = Hmac(sha256, key);
    final signature = hmac.convert(bytes);

    return signature.toString();
  }

  /// Encrypts data using AES-256.
  String _encryptData({required String data, required String encryptionKey}) {
    try {
      // Convert the encryption key to bytes
      List<int> originalKeyBytes;
      try {
        originalKeyBytes = base64Decode(encryptionKey);
      } on Object {
        originalKeyBytes = utf8.encode(encryptionKey);
      }

      // Hash the key to get exactly 32 bytes for AES-256
      final keyBytes = sha256.convert(originalKeyBytes).bytes;

      // Generate a random IV (16 bytes for AES)
      final random = Random.secure();
      final ivBytes = List<int>.generate(16, (i) => random.nextInt(256));

      final key = Key(Uint8List.fromList(keyBytes));
      final iv = IV(Uint8List.fromList(ivBytes));
      final encrypter = Encrypter(AES(key));
      final encrypted = encrypter.encrypt(data, iv: iv);

      return '${encrypted.base64}:${base64Encode(ivBytes)}';
    } on Object catch (e) {
      // If encryption fails, fall back to base64
      print('[WARNING] Encryption failed, falling back to base64: $e');
      return base64Encode(utf8.encode(data));
    }
  }

  /// Generates a signed JWT.
  String _jwtGenerator({required Map<String, Object> payload, required String encryptedJWTKey}) {
    final jwt = JWT(
      payload,
      header: {'os': clientMetadata.os ?? 'UNKNOWN', 'os_server_version': clientMetadata.osServerVersion ?? 'UNKNOWN'},
    );

    return jwt.sign(SecretKey(encryptedJWTKey), expiresIn: const Duration(minutes: 1));
  }
}

// ignore_for_file: avoid_print

import 'dart:convert' show base64Url, json, utf8;
import 'dart:io' show HttpServer, Platform, Process;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

/// Default Descope project ID for Pieces authentication.
const String descopeProjectId = 'P2pgKajh2ElmCO6p7ioSPSpS6qev';

/// Fetches a Descope access token through web browser authentication using PKCE flow.
///
/// This function:
/// 1. Generates PKCE parameters (code verifier and challenge)
/// 2. Starts a local HTTP server to receive the OAuth callback
/// 3. Opens the browser to Descope's authorization endpoint
/// 4. Waits for the user to authenticate
/// 5. Exchanges the authorization code for an access token
///
/// Parameters:
/// - [projectId]: The Descope project ID (defaults to Pieces project)
/// - [redirectUri]: The local callback URL (defaults to localhost:8080)
/// - [scope]: OAuth scopes to request (defaults to 'openid')
///
/// Returns the Descope access token (JWT) on success.
/// Throws an exception if authentication fails.
Future<String> getDescopeAccessTokenViaBrowser({
  String projectId = descopeProjectId,
  String redirectUri = 'http://localhost:8080/callback',
  String scope = 'openid',
}) async {
  print('🔐 Starting Descope browser authentication flow...');

  // Generate state & PKCE verifier/challenge
  final state = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  final codeVerifier = _makeCodeVerifier();
  final codeChallenge = _sha256Base64Url(codeVerifier);

  // Build the authorize URL with PKCE params
  final authorizeUrl = Uri.https('api.descope.com', '/oauth2/v1/authorize', {
    'client_id': projectId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'loginMethod': 'magicLink',
    'scope': scope,
    'state': state,
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
  }).toString();

  // Spin up local HTTP server to catch the callback
  final uri = Uri.parse(redirectUri);
  final server = await HttpServer.bind(uri.host, uri.port);

  print('📡 Local server listening on $redirectUri');
  print('🌐 Opening browser for authentication...');
  print('   URL: $authorizeUrl');

  // Launch browser
  if (Platform.isMacOS) {
    await Process.run('open', [authorizeUrl]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [authorizeUrl]);
  } else if (Platform.isWindows) {
    // Windows: Use rundll32 to open URLs - more reliable than 'start' which has
    // issues with & characters in query strings getting interpreted as command separators.
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', authorizeUrl]);
  } else {
    print('Please open this URL in your browser:\n$authorizeUrl');
  }

  // Wait for the redirect
  print('⏳ Waiting for authentication callback...');
  final request = await server.first;
  final params = request.uri.queryParameters;

  // Send success response to browser
  request.response
    ..statusCode = 200
    ..headers.set('content-type', 'text/html; charset=utf-8')
    ..write('''<!DOCTYPE html>
<html>
<head>
  <title>Authentication Successful</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
    .success { color: #4CAF50; font-size: 24px; }
    .message { margin-top: 20px; }
  </style>
</head>
<body>
  <h1 class="success">✅ Authentication Successful!</h1>
  <p class="message">You can close this tab and return to your application.</p>
</body>
</html>''')
    ..close();

  await server.close();

  // Verify state & extract code
  if (params['state'] != state) {
    throw Exception('State mismatch - possible CSRF attack');
  }

  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw Exception('No authorization code received');
  }

  print('✅ Authorization code received');

  // Exchange code for token using the PKCE verifier
  final tokenEndpoint = Uri.https('api.descope.com', '/oauth2/v1/token');
  final tokenResp = await http.post(
    tokenEndpoint,
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'grant_type': 'authorization_code',
      'client_id': projectId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
    },
  );

  if (tokenResp.statusCode != 200) {
    throw Exception('Token exchange failed: ${tokenResp.statusCode} - ${tokenResp.body}');
  }

  final tokenJson = json.decode(tokenResp.body) as Map<String, dynamic>;
  final accessToken = tokenJson['access_token'] as String?;

  if (accessToken == null) {
    throw Exception('No access token in response');
  }

  print('🎉 Access token obtained successfully');

  return accessToken;
}

/// Gets user information from a Descope access token.
///
/// First tries to extract user info directly from the JWT payload (faster, no network call).
/// Falls back to the OIDC userinfo endpoint if JWT extraction fails.
///
/// Returns a record with userId and optional email.
Future<({String userId, String? email})> getDescopeUserInfo(String accessToken) async {
  // Try to extract from JWT first (faster and more reliable)
  try {
    final jwtInfo = _extractUserInfoFromJwt(accessToken);
    if (jwtInfo != null) {
      print('📋 Extracted user info from JWT:');
      print('   User ID: ${jwtInfo.userId}');
      if (jwtInfo.email != null) {
        print('   Email: ${jwtInfo.email}');
      }
      return jwtInfo;
    }
  } catch (e) {
    print('⚠️ Could not extract user info from JWT: $e');
  }

  // Fall back to OIDC userinfo endpoint
  print('📡 Fetching user info from OIDC endpoint...');
  final userinfoEndpoint = Uri.https('api.descope.com', '/oauth2/v1/userinfo');

  final response = await http.get(userinfoEndpoint, headers: {'Authorization': 'Bearer $accessToken'});

  if (response.statusCode != 200) {
    throw Exception('Failed to get user info: ${response.statusCode} - ${response.body}');
  }

  final userInfo = json.decode(response.body) as Map<String, dynamic>;

  // Descope returns the user ID in the 'sub' field (subject)
  final userId = userInfo['sub'] as String?;

  if (userId == null || userId.isEmpty) {
    throw Exception('No user ID found in Descope token');
  }

  // Extract email if available
  final email = userInfo['email'] as String?;

  print('📋 Retrieved Descope user info:');
  print('   User ID: $userId');
  if (email != null) {
    print('   Email: $email');
  }

  return (userId: userId, email: email);
}

/// Extracts user information directly from the JWT payload without making a network call.
///
/// Returns null if extraction fails (malformed JWT, missing claims, etc.)
({String userId, String? email})? _extractUserInfoFromJwt(String jwt) {
  try {
    // JWT format: header.payload.signature
    final parts = jwt.split('.');
    if (parts.length != 3) return null;

    // Decode the payload (middle part)
    var payload = parts[1];
    // Add padding if needed for base64 decoding
    while (payload.length % 4 != 0) {
      payload += '=';
    }

    final payloadBytes = base64Url.decode(payload);
    final payloadJson = utf8.decode(payloadBytes);
    final claims = json.decode(payloadJson) as Map<String, dynamic>;

    // Extract user ID from 'sub' (subject) claim
    final userId = claims['sub'] as String?;
    if (userId == null || userId.isEmpty) return null;

    // Extract email - Descope may put it in different places
    final email = claims['email'] as String? ?? claims['preferred_username'] as String?;

    return (userId: userId, email: email);
  } catch (e) {
    return null;
  }
}

/// Generate a secure random code verifier for PKCE.
String _makeCodeVerifier() {
  final rand = Random.secure();
  final bytes = List<int>.generate(64, (_) => rand.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Create SHA256 hash and encode as base64url for PKCE challenge.
String _sha256Base64Url(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes).bytes;
  return base64Url.encode(digest).replaceAll('=', '');
}

// ignore_for_file: avoid_print

import 'dart:convert' show base64, json, utf8;
import 'dart:io' show Directory, File;

/// Token cache functionality for avoiding repeated browser authentication.
///
/// Caches the Descope access token locally so users don't have to
/// re-authenticate via browser on every run.
class TokenCache {
  static const _cacheFileName = 'aot_self_contained_token_cache.json';

  /// Get the cache file.
  static Future<File> _getCacheFile() async {
    final tempDir = Directory.systemTemp;
    return File('${tempDir.path}/$_cacheFileName');
  }

  /// Saves authentication data to cache.
  ///
  /// Parameters:
  /// - [accessToken]: The Descope access token (JWT)
  /// - [userId]: The user's Descope user ID
  /// - [email]: Optional email address
  /// - [validFor]: How long the token should be cached (defaults to 55 minutes)
  ///
  /// Note: The default of 55 minutes is chosen to stay within typical JWT
  /// expiration times while avoiding repeated browser authentications.
  static Future<void> saveToken({
    required String accessToken,
    required String userId,
    String? email,
    Duration validFor = const Duration(minutes: 55),
  }) async {
    try {
      final cacheFile = await _getCacheFile();
      final expiresAt = DateTime.now().add(validFor).toIso8601String();

      final cacheData = {
        'access_token': accessToken,
        'user_id': userId,
        'email': email,
        'expires_at': expiresAt,
        'cached_at': DateTime.now().toIso8601String(),
      };

      await cacheFile.writeAsString(json.encode(cacheData));
      print('💾 Token cached successfully until $expiresAt');
    } catch (e) {
      print('⚠️ Failed to cache token: $e');
      // Don't throw - caching is optional
    }
  }

  /// Retrieves cached token if valid.
  ///
  /// Returns a record with accessToken, userId, and optional email,
  /// or null if no valid cache exists.
  static Future<({String accessToken, String userId, String? email})?> getCachedToken() async {
    try {
      final cacheFile = await _getCacheFile();

      if (!await cacheFile.exists()) {
        print('🔍 No token cache found');
        return null;
      }

      final cacheContent = await cacheFile.readAsString();
      final cacheData = json.decode(cacheContent) as Map<String, dynamic>;

      final expiresAtStr = cacheData['expires_at'] as String?;
      if (expiresAtStr == null) {
        print('⚠️ Invalid cache: no expiration time');
        return null;
      }

      final expiresAt = DateTime.parse(expiresAtStr);
      if (DateTime.now().isAfter(expiresAt)) {
        print('⏰ Cached token expired at $expiresAtStr');
        await clearCache();
        return null;
      }

      final accessToken = cacheData['access_token'] as String?;
      final userId = cacheData['user_id'] as String?;
      final email = cacheData['email'] as String?;

      if (accessToken == null || userId == null) {
        print('⚠️ Invalid cache: missing required fields');
        return null;
      }

      print('✅ Found valid cached token (expires at $expiresAtStr)');
      if (email != null) print('   📧 Cached user: $email');
      return (accessToken: accessToken, userId: userId, email: email);
    } catch (e) {
      print('⚠️ Error reading token cache: $e');
      return null;
    }
  }

  /// Clears the token cache.
  static Future<void> clearCache() async {
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        await cacheFile.delete();
        print('🗑️ Token cache cleared');
      }
    } catch (e) {
      print('⚠️ Failed to clear cache: $e');
    }
  }

  /// Parses JWT to extract expiration time.
  ///
  /// Returns the expiration DateTime, or null if parsing fails.
  static DateTime? getJwtExpiration(String token) {
    try {
      // Split the JWT to get the payload
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // Decode the payload
      final payload = parts[1];
      // Add padding if necessary
      final normalized = base64.normalize(payload);
      final decoded = utf8.decode(base64.decode(normalized));
      final claims = json.decode(decoded) as Map<String, dynamic>;

      // Get expiration time (exp claim is in seconds since epoch)
      final exp = claims['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      }
    } catch (e) {
      print('⚠️ Failed to parse JWT expiration: $e');
    }
    return null;
  }

  /// Get the cache file path.
  static Future<String> getCachePath() async {
    final file = await _getCacheFile();
    return file.path;
  }
}

/// Log the token cache status for debugging.
///
/// Shows the cache file location and whether a cached token exists.
Future<void> logTokenCacheStatus() async {
  final tempDir = Directory.systemTemp;
  final cacheLocation = '${tempDir.path}/aot_self_contained_token_cache.json';

  print('📂 Token cache location: $cacheLocation');

  final cacheFile = File(cacheLocation);
  final exists = await cacheFile.exists();

  if (exists) {
    try {
      final content = await cacheFile.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      final expiresAt = data['expires_at'] as String?;
      final email = data['email'] as String?;

      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        final isExpired = DateTime.now().isAfter(expiry);

        if (isExpired) {
          print('   ⏰ Cached token EXPIRED at $expiresAt');
          print('   🌐 Browser authentication will be triggered');
        } else {
          print('   ✅ Found valid cached token (expires at $expiresAt)');
          if (email != null) print('   📧 Cached user: $email');
        }
      }
    } catch (e) {
      print('   ⚠️ Error reading cache: $e');
    }
  } else {
    print('   🌐 No cached token found - browser authentication will be required');
  }
}

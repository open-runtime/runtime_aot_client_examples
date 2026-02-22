// Printing is used for diagnostic output during secret fetching.
// ignore_for_file: avoid_print

import 'dart:convert' show utf8;

import 'package:googleapis/secretmanager/v1.dart' show SecretManagerApi;
import 'package:googleapis_auth/auth_io.dart' show clientViaApplicationDefaultCredentials;

/// GCP project ID containing AOT secrets.
const _defaultGcpProjectId = 'pi3c3s-cloud-server';

/// Scopes required for Secret Manager access.
const _secretManagerScopes = ['https://www.googleapis.com/auth/cloud-platform'];

/// Fetches secrets from Google Cloud Secret Manager.
///
/// This class wraps the googleapis SecretManagerApi to provide easy access
/// to AOT authentication secrets.
///
/// ## Prerequisites
///
/// Before using this class, ensure GCP credentials are configured:
/// ```bash
/// gcloud auth application-default login
/// ```
///
/// ## Usage
///
/// ```dart
/// final fetcher = await SecretFetcher.create();
/// final signingKey = await fetcher.fetch('aot_hmac_signing_key');
/// final encryptionKey = await fetcher.fetch('aot_encryption_key');
/// final apiKey = await fetcher.fetch('aot_grpc_api_key');
/// ```
class SecretFetcher {
  SecretFetcher._({required this.projectId, required SecretManagerApi secretManagerApi})
    : _secretManagerApi = secretManagerApi;

  /// The GCP project ID containing the secrets.
  final String projectId;

  /// The Secret Manager API client.
  late final SecretManagerApi _secretManagerApi;

  /// Creates a SecretFetcher with Application Default Credentials.
  ///
  /// Parameters:
  /// - [projectId]: The GCP project ID (defaults to 'pi3c3s-cloud-server')
  ///
  /// Throws if GCP credentials are not configured.
  static Future<SecretFetcher> create({String? projectId}) async {
    print('🔑 Initializing GCP Secret Manager access...');

    try {
      final client = await clientViaApplicationDefaultCredentials(scopes: _secretManagerScopes);

      print('   ✅ GCP credentials loaded');

      return SecretFetcher._(projectId: projectId ?? _defaultGcpProjectId, secretManagerApi: SecretManagerApi(client));
    } catch (e) {
      print('   ❌ Failed to load GCP credentials');
      print('   Run: gcloud auth application-default login');
      rethrow;
    }
  }

  /// Fetches a secret value from Secret Manager.
  ///
  /// Parameters:
  /// - [name]: The secret name (e.g., 'aot_hmac_signing_key')
  ///
  /// Returns the secret value as a string (trimmed of whitespace).
  /// Throws if the secret cannot be fetched.
  Future<String> fetch(String name) async {
    try {
      final resourceName = 'projects/$projectId/secrets/$name/versions/latest';
      final response = await _secretManagerApi.projects.secrets.versions.access(resourceName);

      if (response.payload?.data == null) {
        throw Exception('No data for secret $name');
      }

      // IMPORTANT: Always trim secrets to remove trailing whitespace/newlines
      // This prevents issues like "FormatException: Invalid HTTP header field value"
      // when secrets are used in Bearer tokens or other HTTP headers.
      final value = utf8.decode(response.payload!.dataAsBytes).trim();

      print('   ✅ Fetched secret: $name');
      return value;
    } catch (e) {
      print('   ❌ Error fetching secret $name: $e');
      rethrow;
    }
  }

  /// Fetches all required AOT authentication secrets.
  ///
  /// Returns a record with:
  /// - hmacSigningKey: For HMAC request signing
  /// - encryptionKey: For AES encryption
  /// - apiKey: For API authentication
  Future<({String hmacSigningKey, String encryptionKey, String apiKey})> fetchAOTSecrets() async {
    print('🔑 Fetching AOT authentication secrets...');

    final hmacSigningKey = await fetch('aot_hmac_signing_key');
    final encryptionKey = await fetch('aot_encryption_key');
    final apiKey = await fetch('aot_grpc_api_key');

    print('✅ All AOT secrets fetched successfully');

    return (hmacSigningKey: hmacSigningKey, encryptionKey: encryptionKey, apiKey: apiKey);
  }
}

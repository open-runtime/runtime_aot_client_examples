// ignore_for_file: avoid_print

import 'dart:convert' show json;

import 'package:http/http.dart' as http;

/// Production user team service URL for fetching user/org data.
const String defaultUserTeamServiceUrl = 'https://user-team-service-226509373556.us-central1.run.app';

/// Fetches user data from the user team service.
///
/// Makes a request to the user team service to get the user's data including
/// their global ID and encryption keys.
///
/// Parameters:
/// - [userTeamServiceUrl]: The user team service URL (defaults to production)
/// - [userId]: The Descope user ID
/// - [accessToken]: The Descope access token for authentication
/// - [useGlobalIdEndpoint]: Whether to use the /user/global_id/ endpoint
///
/// Returns the complete user data object which includes:
/// - globalId: The user's global ID
/// - apiKeys: Array of 13 encryption keys
/// - Other user properties
Future<Map<String, dynamic>> fetchUserDataFromService({
  String? userTeamServiceUrl,
  required String userId,
  required String accessToken,
  bool useGlobalIdEndpoint = false,
}) async {
  final effectiveUrl = userTeamServiceUrl ?? defaultUserTeamServiceUrl;

  // Build the URL for the user endpoint
  final endpoint = useGlobalIdEndpoint ? 'user/global_id' : 'user';
  final userEndpoint = Uri.parse('$effectiveUrl/$endpoint/$userId');

  print('👤 Fetching user data from: $userEndpoint');

  final response = await http.get(
    userEndpoint,
    headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
  );

  if (response.statusCode != 200) {
    throw Exception('Failed to fetch user data: ${response.statusCode} - ${response.body}');
  }

  final userData = json.decode(response.body) as Map<String, dynamic>;

  // Extract and log the global ID
  final globalId = userData['globalId'] ?? userData['global_id'] ?? userData['id'];
  if (globalId != null) {
    print('🆔 User global ID: $globalId');
  }

  return userData;
}

/// Fetches organization ID from the /aot endpoint.
///
/// This is shared logic used by all ML parent auth helpers to fetch
/// the user's organization information for enterprise subscription checks.
///
/// Parameters:
/// - [accessToken]: The Descope access token
/// - [userTeamServiceUrl]: Optional override for the service URL
///
/// Returns a record with orgId, orgName, and active subscription info.
Future<({String? orgId, String? orgName, List<String> activeSubscriptions})> fetchOrgIdFromAotEndpoint({
  required String accessToken,
  String? userTeamServiceUrl,
}) async {
  final effectiveUrl = userTeamServiceUrl ?? defaultUserTeamServiceUrl;

  print('📡 Fetching user profile from /aot to get org ID...');

  try {
    final response = await http
        .get(
          Uri.parse('$effectiveUrl/aot'),
          headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final orgs = data['orgs'] as List<dynamic>?;

      if (orgs != null && orgs.isNotEmpty) {
        final firstOrg = orgs.first as Map<String, dynamic>;
        final orgId = firstOrg['id'] as String?;
        final orgName = firstOrg['name'] as String?;

        print('   ✅ Found org: $orgName (ID: $orgId)');

        // Extract active subscriptions
        final orgSubs = firstOrg['subscriptions'] as List<dynamic>?;
        final activeSubscriptions = <String>[];

        if (orgSubs != null && orgSubs.isNotEmpty) {
          for (final sub in orgSubs) {
            if (sub['active'] == true) {
              final name = sub['name'] as String?;
              if (name != null) activeSubscriptions.add(name);
            }
          }

          if (activeSubscriptions.isNotEmpty) {
            print('   📋 Org has ${activeSubscriptions.length} active subscription(s):');
            for (final sub in activeSubscriptions) {
              print('      - $sub');
            }
          }
        }

        return (orgId: orgId, orgName: orgName, activeSubscriptions: activeSubscriptions);
      } else {
        print('   ⚠️ User has no organizations');
        return (orgId: null, orgName: null, activeSubscriptions: <String>[]);
      }
    } else {
      print('   ⚠️ Failed to fetch /aot: ${response.statusCode}');
      return (orgId: null, orgName: null, activeSubscriptions: <String>[]);
    }
  } catch (e) {
    print('   ⚠️ Error fetching org ID: $e');
    return (orgId: null, orgName: null, activeSubscriptions: <String>[]);
  }
}

/// Extracts user keys from user data object.
///
/// The user-team-service returns 13 API keys in the 'apiKeys' field.
/// These keys are used for MindFck authentication header generation.
///
/// Parameters:
/// - [userData]: The user data map from fetchUserDataFromService
///
/// Returns a list of 13 encryption keys.
/// Throws if keys are missing or in unexpected format.
List<String> extractUserKeys(Map<String, dynamic> userData) {
  // Extract keys from the response - using 'apiKeys' field
  final keysData = userData['apiKeys'];

  if (keysData == null) {
    throw Exception('No apiKeys field found in user data');
  }

  List<String> userKeys;

  if (keysData is List) {
    userKeys = List<String>.from(keysData);
  } else if (keysData is Map) {
    // If keys are returned as a map, extract the values
    userKeys = keysData.values.map((k) => k.toString()).toList();
  } else {
    throw Exception('Unexpected apiKeys format: ${keysData.runtimeType}');
  }

  if (userKeys.length != 13) {
    throw Exception('Expected 13 keys but got ${userKeys.length}');
  }

  print('✅ Successfully fetched ${userKeys.length} user keys');

  return userKeys;
}

/// Fetches user keys from the user team service.
///
/// Convenience function that combines fetchUserDataFromService and extractUserKeys.
///
/// Parameters:
/// - [userTeamServiceUrl]: The user team service URL
/// - [userId]: The Descope user ID
/// - [accessToken]: The Descope access token
/// - [useGlobalIdEndpoint]: Whether to use the global ID endpoint
///
/// Returns a list of 13 encryption keys.
Future<List<String>> fetchUserKeysFromService({
  String? userTeamServiceUrl,
  required String userId,
  required String accessToken,
  bool useGlobalIdEndpoint = false,
}) async {
  // First fetch the complete user data
  final userData = await fetchUserDataFromService(
    userTeamServiceUrl: userTeamServiceUrl,
    userId: userId,
    accessToken: accessToken,
    useGlobalIdEndpoint: useGlobalIdEndpoint,
  );

  // Extract the global ID from user data
  final globalId = userData['globalId'] ?? userData['global_id'] ?? userData['id'];

  // If we have a global ID and haven't already used the global ID endpoint,
  // fetch again using the global ID to ensure we have the correct user data
  if (globalId != null && globalId != userId && !useGlobalIdEndpoint) {
    print('🔄 Fetching user data again using global ID: $globalId');
    final globalUserData = await fetchUserDataFromService(
      userTeamServiceUrl: userTeamServiceUrl,
      userId: globalId,
      accessToken: accessToken,
      useGlobalIdEndpoint: true,
    );
    return extractUserKeys(globalUserData);
  }

  // Extract keys from the current user data
  return extractUserKeys(userData);
}

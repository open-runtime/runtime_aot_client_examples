// ignore_for_file: avoid_print

/// High-level provisioning client for AOT credential provisioning.
///
/// Wraps the gRPC `ProvisioningService` to provide easy access to:
/// - **OpenRouter API key** provisioning (single key, with optional rotation)
/// - **Unified provisioning** (OpenRouter + all enterprise BYOK providers)
///
/// All decryption is handled internally using the authenticated client's
/// `selectedKey` and `accessToken`.
///
/// ## Usage
///
/// ```dart
/// final auth = await AuthenticatedAOTClient.createFromProfile(
///   profile: TestProfiles.enterpriseAllProviders,
/// );
/// final provisioner = ProvisioningClient(auth);
///
/// // Provision OpenRouter only
/// final orCreds = await provisioner.provisionOpenRouter();
///
/// // Provision everything (OpenRouter + enterprise BYOK)
/// final allCreds = await provisioner.provisionAll();
/// ```
library;

import 'dart:io';

import 'package:runtime_isomorphic_library/provisioning/provisioning.dart';

import '../client/authenticated_client.dart';

const _provisioningServiceHost = 'runtime-native-io-provisioning-grpc-service.aot.runtime.services';

/// Safely masks a credential string for logging.
String _mask(String value, {int prefix = 6, int suffix = 4}) {
  if (value.length <= prefix + suffix) {
    return '${value.substring(0, (value.length / 2).floor())}***';
  }
  return '${value.substring(0, prefix)}***${value.substring(value.length - suffix)}';
}

/// Decrypted enterprise provider credentials (one per provider per org).
class EnterpriseProviderCredentials {
  final EnterpriseCredentialProvider provider;
  final String orgId;
  final String? orgName;
  final String decryptedConfig;
  final String? decryptionError;

  const EnterpriseProviderCredentials({
    required this.provider,
    required this.orgId,
    this.orgName,
    required this.decryptedConfig,
    this.decryptionError,
  });

  String get providerName => switch (provider) {
    EnterpriseCredentialProvider.ENTERPRISE_CREDENTIAL_PROVIDER_AWS_BEDROCK => 'aws-bedrock',
    EnterpriseCredentialProvider.ENTERPRISE_CREDENTIAL_PROVIDER_AZURE_OPENAI => 'azure-openai',
    EnterpriseCredentialProvider.ENTERPRISE_CREDENTIAL_PROVIDER_GEMINI => 'gemini',
    EnterpriseCredentialProvider.ENTERPRISE_CREDENTIAL_PROVIDER_CLAUDE => 'claude',
    EnterpriseCredentialProvider.ENTERPRISE_CREDENTIAL_PROVIDER_OPENAI => 'openai',
    _ => provider.name,
  };
}

/// Result of provisioning credentials (OpenRouter + optional enterprise BYOK).
class ProvisioningResult {
  final String openRouterApiKey;
  final String? credentialId;
  final String? baseUrl;
  final List<EnterpriseProviderCredentials> enterpriseCredentials;

  ProvisioningResult({
    required this.openRouterApiKey,
    this.credentialId,
    this.baseUrl,
    this.enterpriseCredentials = const [],
  });

  Map<String, String> get apiKeys => {'OPENROUTER_API_KEY': openRouterApiKey};
}

/// Provisions credentials from the AOT gRPC provisioning service.
class ProvisioningClient {
  final AuthenticatedAOTClient _auth;

  ProvisioningClient(this._auth);

  /// Provisions an OpenRouter API key via gRPC.
  ///
  /// When [rotate] is true, deletes the existing key and creates a fresh one
  /// (OpenRouter only returns the raw key value at creation time).
  Future<ProvisioningResult> provisionOpenRouter({bool rotate = false}) async {
    final channel = ClientChannel(
      _provisioningServiceHost,
      port: 443,
      options: const ChannelOptions(credentials: ChannelCredentials.secure()),
    );

    try {
      final client = ProvisioningServiceClient(channel, interceptors: [_auth.interceptor]);

      final request = OpenRouterUserProvisioningRequest(rotate: rotate);
      final response = await client.provisionOpenRouterCredentials(request, options: _auth.callOptionsWithOrgId);

      print(
        '  Provisioning response: status=${response.status} '
        'credentialId=${response.credentialId}',
      );

      final encryptedPayload = response.encryptedApiKey;
      if (!encryptedPayload.hasEncryptedData() || encryptedPayload.encryptedData.isEmpty) {
        throw StateError('Provisioning returned empty encrypted payload.');
      }

      final apiKey = await encryptedPayload.decryptGcm(selectedUserKey: _auth.selectedKey, jwt: _auth.accessToken);

      if (apiKey.isEmpty || !apiKey.startsWith('sk-or-')) {
        throw StateError(
          'Decrypted API key is invalid: '
          '${apiKey.isEmpty ? "empty" : _mask(apiKey)}',
        );
      }

      print('  Decrypted key: ${_mask(apiKey, prefix: 12, suffix: 4)}');

      return ProvisioningResult(
        openRouterApiKey: apiKey,
        credentialId: response.credentialId,
        baseUrl: response.baseUrl.isEmpty ? null : response.baseUrl,
      );
    } finally {
      await channel.shutdown();
    }
  }

  /// Provisions OpenRouter + all enterprise BYOK credentials in one call.
  ///
  /// Uses the unified `provisionEncryptedCredentials` RPC. Returns both the
  /// OpenRouter key and any enterprise provider credentials (Bedrock, Azure,
  /// Gemini, Claude, OpenAI) configured for the user's organization.
  ///
  /// [providers] filters which enterprise providers to include. Empty list
  /// (default) includes all configured providers.
  Future<ProvisioningResult> provisionAll({List<EnterpriseCredentialProvider> providers = const []}) async {
    final channel = ClientChannel(
      _provisioningServiceHost,
      port: 443,
      options: const ChannelOptions(credentials: ChannelCredentials.secure()),
    );

    try {
      final client = ProvisioningServiceClient(channel, interceptors: [_auth.interceptor]);

      final request = ProvisionEncryptedCredentialsRequest(
        includeOpenRouter: true,
        includeEnterpriseProviders: providers,
        includeModelAccess: false,
      );

      final payload = await client.provisionEncryptedCredentials(request, options: _auth.callOptionsWithOrgId);

      // Decrypt OpenRouter key
      String openRouterApiKey = '';
      String? credentialId;
      String? baseUrl;

      if (payload.hasUserApiKey()) {
        final userKey = payload.userApiKey;
        credentialId = userKey.keyId;
        baseUrl = userKey.baseUrl.isEmpty ? null : userKey.baseUrl;

        if (userKey.hasEncryptedKey() && userKey.encryptedKey.hasEncryptedData()) {
          openRouterApiKey = await userKey.encryptedKey.decryptGcm(
            selectedUserKey: _auth.selectedKey,
            jwt: _auth.accessToken,
          );
          print('  OpenRouter key: ${_mask(openRouterApiKey, prefix: 12, suffix: 4)}');
        }
      }

      if (openRouterApiKey.isEmpty || !openRouterApiKey.startsWith('sk-or-')) {
        throw StateError('Unified provisioning returned no valid OpenRouter key.');
      }

      // Decrypt enterprise credentials
      final enterpriseCreds = <EnterpriseProviderCredentials>[];

      for (final cred in payload.enterpriseCredentials) {
        EncryptedCredentialPayload? encryptedConfig;

        if (cred.hasAwsBedrock()) {
          encryptedConfig = cred.awsBedrock.encryptedConfig;
        } else if (cred.hasAzureOpenai()) {
          encryptedConfig = cred.azureOpenai.encryptedConfig;
        } else if (cred.hasGemini()) {
          encryptedConfig = cred.gemini.encryptedConfig;
        } else if (cred.hasClaude()) {
          encryptedConfig = cred.claude.encryptedConfig;
        } else if (cred.hasOpenai()) {
          encryptedConfig = cred.openai.encryptedConfig;
        }

        if (encryptedConfig == null || !encryptedConfig.hasEncryptedData()) {
          continue;
        }

        try {
          final decrypted = await encryptedConfig.decryptGcm(
            selectedUserKey: _auth.selectedKey,
            jwt: _auth.accessToken,
          );
          final enterpriseCred = EnterpriseProviderCredentials(
            provider: cred.provider,
            orgId: cred.orgId,
            orgName: cred.orgName.isEmpty ? null : cred.orgName,
            decryptedConfig: decrypted,
          );
          enterpriseCreds.add(enterpriseCred);
          print(
            '  Enterprise ${enterpriseCred.providerName}: decrypted '
            '(org: ${_mask(cred.orgId, prefix: 12, suffix: 4)})',
          );
        } catch (e) {
          stderr.writeln(
            '  Warning: failed to decrypt '
            '${cred.provider.name} credentials: $e',
          );
        }
      }

      print('  Total: 1 OpenRouter + ${enterpriseCreds.length} enterprise provider(s)');

      return ProvisioningResult(
        openRouterApiKey: openRouterApiKey,
        credentialId: credentialId,
        baseUrl: baseUrl,
        enterpriseCredentials: enterpriseCreds,
      );
    } finally {
      await channel.shutdown();
    }
  }
}

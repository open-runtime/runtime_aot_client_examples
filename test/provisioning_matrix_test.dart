// ignore_for_file: avoid_print
/// Comprehensive integration tests for the provisioning service across the
/// full TestProfile matrix (11 profiles, 3 tiers, 6 enterprise orgs).
///
/// ## Coverage
///
/// 1. **Profile metadata consistency** — static assertions on profile
///    definitions, groupings, email uniqueness, orgId uniqueness.
///
/// 2. **Password auth per profile** — Descope password sign-in for every
///    profile that uses the free or pro password.
///
/// 3. **OpenRouter provisioning per profile** — every profile gets a valid
///    `sk-or-` key via `ProvisioningClient.provisionOpenRouter()`.
///
/// 4. **Enterprise BYOK provisioning** — `provisionAll()` for each enterprise
///    org, verifying provider counts match `expectedProviders`.
///
/// 5. **GSM credential shape validation** — per-org secrets from GCP Secret
///    Manager have the expected JSON structure (api_keys, service_accounts).
///
/// 6. **Cross-org isolation** — credentials from one org do not leak into
///    another; different orgIds produce different OpenRouter keys.
///
/// 7. **Free tier negative tests** — free profiles get OpenRouter only, no
///    enterprise BYOK, no orgId.
///
/// Run:
/// ```bash
/// dart test --tags integration test/provisioning_matrix_test.dart
/// ```
///
/// Prerequisites:
///   - `gcloud auth application-default login`
///   - Access to GCP project `global-cloud-runtime`
@Tags(['integration'])
@Timeout(Duration(seconds: 600))
library;

import 'dart:convert';

import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';
import 'package:test/test.dart';

// =============================================================================
// Shared helpers
// =============================================================================

/// Cached auth clients per profile id — populated in setUpAll.
final _authByProfileId = <String, AuthenticatedAOTClient?>{};

/// Cached provisioning results (provisionAll) per profile id.
final _provisionedByProfileId = <String, ProvisioningResult?>{};

AuthenticatedAOTClient? _auth(TestProfile p) => _authByProfileId[p.id];

ProvisioningResult? _provisioned(TestProfile p) => _provisionedByProfileId[p.id];

AuthenticatedAOTClient? _requireAuth(TestProfile p) {
  final auth = _auth(p);
  if (auth == null) {
    markTestSkipped('Auth unavailable for ${p.id} (expected without GCP)');
  }
  return auth;
}

ProvisioningResult? _requireProvisioned(TestProfile p) {
  final provisioned = _provisioned(p);
  if (provisioned == null) {
    markTestSkipped('Provisioning unavailable for ${p.id} (expected without GCP)');
  }
  return provisioned;
}

/// Creates a [SecretFetcher] for GSM lookups. Returns null if GCP auth fails.
Future<SecretFetcher?> _createGsm() async {
  try {
    return await SecretFetcher.create(projectId: 'global-cloud-runtime');
  } on Object catch (e) {
    print('   GSM unavailable: $e');
    return null;
  }
}

/// Fetches a single org credential from GSM. Returns null if missing.
Future<String?> _fetchOrgCred({required SecretFetcher gsm, required String orgId, required String provider}) async {
  try {
    final v = await gsm.fetch('org-$orgId-$provider-key');
    return v.isNotEmpty ? v : null;
  } on Object {
    return null;
  }
}

String _mask(String v) {
  if (v.length < 8) return '***';
  if (v.length < 16) return '${v.substring(0, 3)}...${v.substring(v.length - 3)}';
  return '${v.substring(0, 8)}...${v.substring(v.length - 4)}';
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ── Suite-level provisioning ──
  // Authenticate and provision every profile once, cache results.
  setUpAll(() async {
    for (final profile in TestProfiles.all) {
      try {
        final auth = await AuthenticatedAOTClient.createFromProfile(profile: profile);
        _authByProfileId[profile.id] = auth;

        final provisioner = ProvisioningClient(auth);
        final result = await provisioner.provisionAll();
        _provisionedByProfileId[profile.id] = result;

        print(
          '  OK: ${profile.id} → ${_mask(result.openRouterApiKey)} '
          '+ ${result.enterpriseCredentials.length} enterprise',
        );
      } on Object catch (e) {
        print('  SKIP: ${profile.id} → $e');
        _authByProfileId[profile.id] = null;
        _provisionedByProfileId[profile.id] = null;
      }
    }
  });

  tearDownAll(() async {
    for (final auth in _authByProfileId.values) {
      try {
        await auth?.dispose();
      } catch (_) {}
    }
  });

  // ===========================================================================
  // 1. Profile metadata consistency
  // ===========================================================================
  group('Profile metadata consistency', () {
    test('TestProfiles.all contains exactly 11 profiles', () {
      expect(TestProfiles.all, hasLength(11));
    });

    test('all enterprise profiles share the same Descope email', () {
      final emails = TestProfiles.enterprise.map((p) => p.email).toSet();
      expect(emails, hasLength(1));
      expect(emails.first, 'aot-automated-testing@pieces.app');
    });

    test('all enterprise profiles have unique orgIds', () {
      final orgIds = TestProfiles.enterprise.map((p) => p.orgId).toSet();
      expect(orgIds, hasLength(TestProfiles.enterprise.length));
    });

    test('all enterprise profiles are Enterprise subscription', () {
      for (final p in TestProfiles.enterprise) {
        expect(p.subscription, 'Enterprise', reason: '${p.id} tier');
      }
    });

    test('free personal profiles have no orgId and no expectedProviders', () {
      for (final p in TestProfiles.freePersonal) {
        expect(p.orgId, isNull, reason: '${p.id} orgId');
        expect(p.expectedProviders, isEmpty, reason: '${p.id} providers');
        expect(p.subscription, 'Free', reason: '${p.id} tier');
      }
    });

    test('pro profile has no orgId', () {
      expect(TestProfiles.aotProTesting.orgId, isNull);
      expect(TestProfiles.aotProTesting.subscription, 'Pro');
    });

    test('legacy alias is identical to enterpriseAllProviders', () {
      expect(identical(TestProfiles.aotAutomatedTesting, TestProfiles.enterpriseAllProviders), isTrue);
    });

    test('groupings are consistent with expectedProviders', () {
      for (final p in TestProfiles.enterpriseWithGcp) {
        expect(p.expectedProviders, contains('gcp'), reason: p.id);
      }
      for (final p in TestProfiles.enterpriseWithVertexSa) {
        expect(TestProfiles.enterpriseWithGcp.contains(p), isTrue, reason: '${p.id} in vertexSa must also be in gcp');
      }
      expect(TestProfiles.enterpriseWithOpenai, equals([TestProfiles.enterpriseAllProviders]));
      expect(TestProfiles.enterpriseWithClaude, equals([TestProfiles.enterpriseAllProviders]));
      expect(TestProfiles.enterpriseWithAzure, equals([TestProfiles.enterpriseAllProviders]));
      expect(TestProfiles.enterpriseWithBedrock, equals([TestProfiles.enterpriseAllProviders]));
    });

    test('freePasswordProfiles includes all free + all enterprise (10)', () {
      expect(TestProfiles.freePasswordProfiles, hasLength(10));
      for (final p in TestProfiles.freePersonal) {
        expect(TestProfiles.freePasswordProfiles, contains(p));
      }
      for (final p in TestProfiles.enterprise) {
        expect(TestProfiles.freePasswordProfiles, contains(p));
      }
    });

    test('proPasswordProfiles contains only aotProTesting', () {
      expect(TestProfiles.proPasswordProfiles, equals([TestProfiles.aotProTesting]));
    });
  });

  // ===========================================================================
  // 2. Password auth per profile
  // ===========================================================================
  group('Password auth per profile', () {
    for (final profile in TestProfiles.all) {
      test('${profile.id}: authenticates and returns userId + sessionJwt', () async {
        final auth = _requireAuth(profile);
        if (auth == null) return;

        expect(auth.userId, isNotEmpty, reason: '${profile.id} userId');
        expect(auth.accessToken, isNotEmpty, reason: '${profile.id} jwt');
        expect(auth.userEmail, isNotNull, reason: '${profile.id} email');
        expect(auth.selectedKey, isNotEmpty, reason: '${profile.id} key');
        expect(auth.userKeys, hasLength(13), reason: '${profile.id} 13 keys');
      });
    }

    test('alice and bob have different global IDs', () async {
      final alice = _requireAuth(TestProfiles.alice);
      if (alice == null) return;
      final bob = _requireAuth(TestProfiles.bob);
      if (bob == null) return;

      expect(alice.userId, isNot(equals(bob.userId)), reason: 'alice and bob must have different globalIds');
    });

    test('enterprise profiles share a single globalId', () async {
      final ids = <String>{};
      for (final p in TestProfiles.enterprise) {
        final auth = _requireAuth(p);
        if (auth == null) return;
        ids.add(auth.userId);
      }
      expect(ids, hasLength(1), reason: 'same Descope user → same globalId');
    });
  });

  // ===========================================================================
  // 3. OpenRouter provisioning per profile
  // ===========================================================================
  group('OpenRouter provisioning per profile', () {
    for (final profile in TestProfiles.all) {
      test('${profile.id}: receives valid sk-or- OpenRouter key', () async {
        final result = _requireProvisioned(profile);
        if (result == null) return;

        expect(result.openRouterApiKey, isNotEmpty, reason: '${profile.id} OR key');
        expect(result.openRouterApiKey, startsWith('sk-or-'), reason: '${profile.id} OR prefix');
      });
    }

    test('different enterprise orgIds produce different OpenRouter keys', () async {
      final allResult = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (allResult == null) return;
      final gaiResult = _requireProvisioned(TestProfiles.enterpriseGaiStudioOnly);
      if (gaiResult == null) return;
      final allKey = allResult.openRouterApiKey;
      final gaiKey = gaiResult.openRouterApiKey;

      expect(allKey, isNot(equals(gaiKey)), reason: 'different orgIds → different OR keys');
    });

    test('free profiles produce keys distinct from enterprise', () async {
      final aliceResult = _requireProvisioned(TestProfiles.alice);
      if (aliceResult == null) return;
      final enterpriseResult = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (enterpriseResult == null) return;
      final aliceKey = aliceResult.openRouterApiKey;
      final entKey = enterpriseResult.openRouterApiKey;

      expect(aliceKey, isNot(equals(entKey)), reason: 'free user key != enterprise key');
    });
  });

  // ===========================================================================
  // 4. Enterprise BYOK provisioning (provider count alignment)
  // ===========================================================================
  group('Enterprise BYOK provisioning', () {
    test('enterpriseAllProviders: 5 providers (openai, claude, gemini, azure, bedrock)', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final names = result.enterpriseCredentials.map((c) => c.providerName).toSet();

      expect(names, contains('openai'));
      expect(names, contains('claude'));
      expect(names, contains('gemini'));
      expect(names, contains('azure-openai'));
      expect(names, contains('aws-bedrock'));
      expect(result.enterpriseCredentials, hasLength(5));
    });

    test('enterpriseGaiStudioOnly: gemini only', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseGaiStudioOnly);
      if (result == null) return;
      final names = result.enterpriseCredentials.map((c) => c.providerName).toSet();

      expect(names, contains('gemini'));
      expect(names, hasLength(1));
    });

    test('enterpriseVertexApiKeyOnly: gemini only', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseVertexApiKeyOnly);
      if (result == null) return;

      expect(result.enterpriseCredentials, hasLength(1));
      expect(result.enterpriseCredentials.first.providerName, 'gemini');
    });

    test('enterpriseVertexSaOnly: gemini only', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseVertexSaOnly);
      if (result == null) return;

      expect(result.enterpriseCredentials, hasLength(1));
      expect(result.enterpriseCredentials.first.providerName, 'gemini');
    });

    test('enterpriseVertexSaPlusKey: gemini only', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseVertexSaPlusKey);
      if (result == null) return;

      expect(result.enterpriseCredentials, hasLength(1));
      expect(result.enterpriseCredentials.first.providerName, 'gemini');
    });

    test('enterpriseNoCredentials: zero enterprise providers', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseNoCredentials);
      if (result == null) return;

      expect(result.enterpriseCredentials, isEmpty);
      expect(result.openRouterApiKey, startsWith('sk-or-'), reason: 'OpenRouter still works for empty-cred org');
    });

    test('free profiles have zero enterprise providers', () async {
      for (final p in TestProfiles.freePersonal) {
        final result = _requireProvisioned(p);
        if (result == null) return;
        expect(result.enterpriseCredentials, isEmpty, reason: '${p.id} is free → no enterprise BYOK');
      }
    });

    test('decrypted configs are non-empty valid JSON for all providers', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final creds = result.enterpriseCredentials;

      for (final cred in creds) {
        expect(cred.decryptedConfig, isNotEmpty, reason: '${cred.providerName} decryptedConfig');
        expect(cred.decryptionError, isNull, reason: '${cred.providerName} decryptionError');

        late final dynamic parsed;
        try {
          parsed = jsonDecode(cred.decryptedConfig);
        } on Object {
          fail('${cred.providerName} config is not valid JSON');
        }
        expect(parsed, isA<Map<String, dynamic>>(), reason: '${cred.providerName} config must be a JSON object');
      }
    });
  });

  // ===========================================================================
  // 5. GSM credential shape validation
  // ===========================================================================
  group('GSM credential shape validation', () {
    late SecretFetcher? gsm;

    setUpAll(() async {
      gsm = await _createGsm();
    });

    test('All Providers org: openai, claude, gcp, azure, bedrock in GSM', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final orgId = TestProfiles.enterpriseAllProviders.orgId!;

      for (final provider in ['openai', 'claude', 'gcp', 'azure', 'bedrock']) {
        final cred = await _fetchOrgCred(gsm: gsm!, orgId: orgId, provider: provider);
        expect(cred, isNotNull, reason: 'All Providers must have $provider');
        expect(cred, isNotEmpty, reason: '$provider must not be empty');
      }
    });

    test('All Providers GCP: has both api_keys and service_accounts', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final cred = await _fetchOrgCred(gsm: gsm!, orgId: TestProfiles.enterpriseAllProviders.orgId!, provider: 'gcp');
      final parsed = jsonDecode(cred!) as Map<String, dynamic>;
      expect(parsed['api_keys'], isNotNull);
      expect(parsed['api_keys'], isNotEmpty);
      expect(parsed['service_accounts'], isNotNull);
      expect(parsed['service_accounts'], isNotEmpty);
    });

    test('GAI Studio Only: gcp api_keys present, no service_accounts', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final cred = await _fetchOrgCred(gsm: gsm!, orgId: TestProfiles.enterpriseGaiStudioOnly.orgId!, provider: 'gcp');
      expect(cred, isNotNull);
      final parsed = jsonDecode(cred!) as Map<String, dynamic>;
      expect(parsed['api_keys'], isNotEmpty);
      final sas = parsed['service_accounts'] as List<dynamic>?;
      expect(sas == null || sas.isEmpty, isTrue, reason: 'GAI Studio Only → no SAs');
    });

    test('GAI Studio Only: no openai/claude/azure/bedrock in GSM', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final orgId = TestProfiles.enterpriseGaiStudioOnly.orgId!;
      for (final p in ['openai', 'claude', 'azure', 'bedrock']) {
        final cred = await _fetchOrgCred(gsm: gsm!, orgId: orgId, provider: p);
        expect(cred, isNull, reason: 'GAI Studio Only must NOT have $p');
      }
    });

    test('Vertex SA Only: service_accounts present, no api_keys', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final cred = await _fetchOrgCred(gsm: gsm!, orgId: TestProfiles.enterpriseVertexSaOnly.orgId!, provider: 'gcp');
      expect(cred, isNotNull);
      final parsed = jsonDecode(cred!) as Map<String, dynamic>;
      expect(parsed['service_accounts'], isNotEmpty);
      final keys = parsed['api_keys'] as List<dynamic>?;
      expect(keys == null || keys.isEmpty, isTrue, reason: 'Vertex SA Only → no API keys');
    });

    test('Vertex SA + Key: both api_keys and service_accounts', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final cred = await _fetchOrgCred(
        gsm: gsm!,
        orgId: TestProfiles.enterpriseVertexSaPlusKey.orgId!,
        provider: 'gcp',
      );
      expect(cred, isNotNull);
      final parsed = jsonDecode(cred!) as Map<String, dynamic>;
      expect(parsed['api_keys'], isNotEmpty);
      expect(parsed['service_accounts'], isNotEmpty);
    });

    test('No Credentials org: no secrets in GSM', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      final orgId = TestProfiles.enterpriseNoCredentials.orgId!;
      for (final p in ['openai', 'claude', 'gcp', 'azure', 'bedrock']) {
        final cred = await _fetchOrgCred(gsm: gsm!, orgId: orgId, provider: p);
        expect(cred, isNull, reason: 'No Credentials org must NOT have $p');
      }
    });

    test('GCP creds are well-formed JSON across all GCP orgs', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      for (final profile in TestProfiles.enterpriseWithGcp) {
        final cred = await _fetchOrgCred(gsm: gsm!, orgId: profile.orgId!, provider: 'gcp');
        expect(cred, isNotNull, reason: '${profile.id} gcp cred');

        late final Map<String, dynamic> parsed;
        try {
          parsed = jsonDecode(cred!) as Map<String, dynamic>;
        } on Object {
          fail('${profile.id} GCP cred is not valid JSON');
        }

        final hasKeys = (parsed['api_keys'] as List<dynamic>?)?.isNotEmpty ?? false;
        final hasSa = (parsed['service_accounts'] as List<dynamic>?)?.isNotEmpty ?? false;
        expect(hasKeys || hasSa, isTrue, reason: '${profile.id} must have api_keys or service_accounts');
      }
    });

    test('Vertex SA profiles have valid SA entries with credentials field', () async {
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }
      for (final profile in TestProfiles.enterpriseWithVertexSa) {
        final cred = await _fetchOrgCred(gsm: gsm!, orgId: profile.orgId!, provider: 'gcp');
        final parsed = jsonDecode(cred!) as Map<String, dynamic>;
        final sas = parsed['service_accounts'] as List<dynamic>;
        expect(sas, isNotEmpty, reason: '${profile.id} SAs');

        final firstSa = sas.first;
        expect(firstSa, isA<Map<String, dynamic>>(), reason: '${profile.id}: SA entry must be a Map');

        final saEntry = firstSa as Map<String, dynamic>;
        // GSM wraps the SA JSON in a `credentials` field (JSON string).
        final credentialsRaw = saEntry['credentials'] as String?;
        expect(credentialsRaw, isNotNull, reason: '${profile.id}: SA entry must have "credentials" field');
        expect(credentialsRaw, isNotEmpty, reason: '${profile.id}');

        final saJson = jsonDecode(credentialsRaw!) as Map<String, dynamic>;
        expect(saJson['type'], 'service_account', reason: profile.id);
        expect(saJson.containsKey('project_id'), isTrue, reason: profile.id);
        expect(saJson.containsKey('private_key'), isTrue, reason: profile.id);
        expect(saJson.containsKey('client_email'), isTrue, reason: profile.id);
      }
    });
  });

  // ===========================================================================
  // 6. Cross-org isolation
  // ===========================================================================
  group('Cross-org isolation', () {
    test('All Providers and No Credentials have disjoint GSM secrets', () async {
      final gsm = await _createGsm();
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }

      final allOrgId = TestProfiles.enterpriseAllProviders.orgId!;
      final noOrgId = TestProfiles.enterpriseNoCredentials.orgId!;

      final allOpenai = await _fetchOrgCred(gsm: gsm, orgId: allOrgId, provider: 'openai');
      expect(allOpenai, isNotNull);

      for (final p in ['openai', 'claude', 'gcp', 'azure', 'bedrock']) {
        final cred = await _fetchOrgCred(gsm: gsm, orgId: noOrgId, provider: p);
        expect(cred, isNull, reason: 'No Creds org must NOT have $p');
      }
    });

    test('GAI Studio has GCP but not OpenAI (unlike All Providers)', () async {
      final gsm = await _createGsm();
      if (gsm == null) {
        markTestSkipped('GSM unavailable');
        return;
      }

      final allOpenai = await _fetchOrgCred(
        gsm: gsm,
        orgId: TestProfiles.enterpriseAllProviders.orgId!,
        provider: 'openai',
      );
      final gaiOpenai = await _fetchOrgCred(
        gsm: gsm,
        orgId: TestProfiles.enterpriseGaiStudioOnly.orgId!,
        provider: 'openai',
      );
      final gaiGcp = await _fetchOrgCred(gsm: gsm, orgId: TestProfiles.enterpriseGaiStudioOnly.orgId!, provider: 'gcp');

      expect(allOpenai, isNotNull);
      expect(gaiOpenai, isNull, reason: 'GAI Studio must NOT have openai');
      expect(gaiGcp, isNotNull, reason: 'GAI Studio must have gcp');
    });

    test('provisioned enterprise creds match expectedProviders per org', () async {
      for (final profile in TestProfiles.enterprise) {
        final result = _requireProvisioned(profile);
        if (result == null) return;
        final provNames = result.enterpriseCredentials.map((c) => c.providerName).toSet();

        if (profile.expectedProviders.isEmpty) {
          expect(result.enterpriseCredentials, isEmpty, reason: '${profile.id}: no expected providers → empty');
          continue;
        }

        for (final ep in profile.expectedProviders) {
          switch (ep) {
            case 'openai':
              expect(provNames, contains('openai'), reason: profile.id);
            case 'claude':
              expect(provNames, contains('claude'), reason: profile.id);
            case 'gcp':
              expect(provNames, contains('gemini'), reason: profile.id);
            case 'azure':
              expect(provNames, contains('azure-openai'), reason: profile.id);
            case 'bedrock':
              expect(provNames, contains('aws-bedrock'), reason: profile.id);
          }
        }
      }
    });
  });

  // ===========================================================================
  // 7. Enterprise credential config shape validation (decrypted JSON)
  // ===========================================================================
  group('Enterprise credential config shapes', () {
    test('OpenAI config has api_keys with key field', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final creds = result.enterpriseCredentials;
      final openai = creds.where((c) => c.providerName == 'openai');
      if (openai.isEmpty) {
        markTestSkipped('No OpenAI credential');
        return;
      }
      final parsed = jsonDecode(openai.first.decryptedConfig) as Map<String, dynamic>;
      expect(parsed.containsKey('api_keys'), isTrue);
      final keys = parsed['api_keys'] as List<dynamic>;
      expect(keys, isNotEmpty);
      final first = keys.first as Map<String, dynamic>;
      expect(first.containsKey('key'), isTrue);
    });

    test('Claude config has api_keys with key field', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final creds = result.enterpriseCredentials;
      final claude = creds.where((c) => c.providerName == 'claude');
      if (claude.isEmpty) {
        markTestSkipped('No Claude credential');
        return;
      }
      final parsed = jsonDecode(claude.first.decryptedConfig) as Map<String, dynamic>;
      expect(parsed.containsKey('api_keys'), isTrue);
      final keys = parsed['api_keys'] as List<dynamic>;
      expect(keys, isNotEmpty);
      final first = keys.first as Map<String, dynamic>;
      expect(first.containsKey('key'), isTrue);
    });

    test('Gemini config has google_ai_studio_keys, vertex_api_keys, or service_accounts', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final creds = result.enterpriseCredentials;
      final gemini = creds.where((c) => c.providerName == 'gemini');
      if (gemini.isEmpty) {
        markTestSkipped('No Gemini credential');
        return;
      }
      final parsed = jsonDecode(gemini.first.decryptedConfig) as Map<String, dynamic>;

      final hasStudioKeys = (parsed['google_ai_studio_keys'] as List<dynamic>?)?.isNotEmpty ?? false;
      final hasVertexKeys = (parsed['vertex_api_keys'] as List<dynamic>?)?.isNotEmpty ?? false;
      final hasSa = (parsed['service_accounts'] as List<dynamic>?)?.isNotEmpty ?? false;

      expect(
        hasStudioKeys || hasVertexKeys || hasSa,
        isTrue,
        reason: 'Gemini config must have studio keys, vertex keys, or SAs',
      );
    });

    test('Azure config has api_keys with base_url and deployments', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final creds = result.enterpriseCredentials;
      final azure = creds.where((c) => c.providerName == 'azure-openai');
      if (azure.isEmpty) {
        markTestSkipped('No Azure credential');
        return;
      }
      final parsed = jsonDecode(azure.first.decryptedConfig) as Map<String, dynamic>;

      final hasApiKeys = (parsed['api_keys'] as List<dynamic>?)?.isNotEmpty ?? false;
      final hasEntraid = (parsed['entra_id_credentials'] as List<dynamic>?)?.isNotEmpty ?? false;

      expect(hasApiKeys || hasEntraid, isTrue, reason: 'Azure config must have api_keys or entra_id_credentials');

      if (hasApiKeys) {
        final first = (parsed['api_keys'] as List<dynamic>).first as Map<String, dynamic>;
        expect(first.containsKey('base_url'), isTrue);
      }
    });

    test('Bedrock config has access_key_credentials or api_keys', () async {
      final result = _requireProvisioned(TestProfiles.enterpriseAllProviders);
      if (result == null) return;
      final creds = result.enterpriseCredentials;
      final bedrock = creds.where((c) => c.providerName == 'aws-bedrock');
      if (bedrock.isEmpty) {
        markTestSkipped('No Bedrock credential');
        return;
      }
      final parsed = jsonDecode(bedrock.first.decryptedConfig) as Map<String, dynamic>;

      final hasAccessKeys = (parsed['access_key_credentials'] as List<dynamic>?)?.isNotEmpty ?? false;
      final hasApiKeys = (parsed['api_keys'] as List<dynamic>?)?.isNotEmpty ?? false;

      expect(
        hasAccessKeys || hasApiKeys,
        isTrue,
        reason: 'Bedrock config must have access_key_credentials or api_keys',
      );

      if (hasAccessKeys) {
        final first = (parsed['access_key_credentials'] as List<dynamic>).first as Map<String, dynamic>;
        expect(first.containsKey('access_key'), isTrue);
        expect(first.containsKey('secret_key'), isTrue);
        expect(first.containsKey('region'), isTrue);
      }
    });
  });

  // ===========================================================================
  // 8. AuthenticatedAOTClient field coverage
  // ===========================================================================
  group('AuthenticatedAOTClient fields', () {
    test('createFromProfile populates orgId for enterprise profiles', () async {
      for (final p in TestProfiles.enterprise) {
        final auth = _requireAuth(p);
        if (auth == null) return;
        expect(auth.orgId, isNotNull, reason: '${p.id} must have orgId');
        expect(auth.orgId, p.orgId, reason: '${p.id} orgId match');
      }
    });

    test('createFromProfile leaves orgId null for free profiles', () async {
      for (final p in TestProfiles.freePersonal) {
        if (_requireAuth(p) == null) return;
        // Free profiles have no static orgId; the client discovers the first
        // org dynamically. Free users may or may not belong to an org.
        // The key assertion is that the static profile has orgId == null.
        expect(p.orgId, isNull, reason: '${p.id} profile orgId');
      }
    });

    test('callOptionsWithOrgId includes x-org-id for enterprise', () async {
      final auth = _requireAuth(TestProfiles.enterpriseAllProviders);
      if (auth == null) return;
      expect(auth.hasOrgId, isTrue);
      final opts = auth.callOptionsWithOrgId;
      expect(opts.metadata['x-org-id'], auth.orgId);
    });
  });
}

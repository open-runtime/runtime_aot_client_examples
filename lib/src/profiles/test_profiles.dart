// ignore_for_file: avoid_print

/// Pre-defined Descope test user profiles for AOT provisioning.
///
/// Each profile represents a specific user at a payment tier (Free, Pro,
/// Enterprise). Enterprise profiles include an [orgId] to scope gRPC
/// provisioning calls to a specific organization, and [expectedProviders]
/// listing which native BYOK credential providers are configured in GSM.
///
/// Profile data was discovered via `_discover_all_profiles.dart` on 2026-03-25.
library;

/// A Descope test user profile with subscription tier and optional org scope.
class TestProfile {
  final String id;
  final String displayName;
  final String email;

  /// Subscription tier: `Free`, `Pro`, or `Enterprise`.
  final String subscription;

  /// When non-null, this org's `x-org-id` header is sent with gRPC provisioning
  /// calls, scoping the credential to that enterprise organization.
  final String? orgId;

  /// Enterprise credential providers expected for this profile's org.
  final List<String> expectedProviders;

  const TestProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.subscription,
    this.orgId,
    this.expectedProviders = const [],
  });

  @override
  String toString() => '$displayName ($subscription) <$email>';
}

/// All pre-defined test profiles.
///
/// ## Tier Layout
///
/// **Free** (personal, no orgs):
/// [alice], [aliceWork], [bob], [charlie] — all use the shared free password.
///
/// **Enterprise** (aot-automated-testing@pieces.app — 6 orgs):
/// Same Descope user, different org IDs. Each org has a different set of
/// enterprise credentials in GSM.
///
/// | Profile | Org | GSM Providers |
/// |---------|-----|---------------|
/// | [enterpriseAllProviders] | Primary | openai, claude, gcp, azure, bedrock |
/// | [enterpriseGaiStudioOnly] | GAI Studio Only | gcp (key only) |
/// | [enterpriseVertexApiKeyOnly] | Vertex API Key Only | gcp (key only) |
/// | [enterpriseVertexSaOnly] | Vertex SA Only | gcp (SA only) |
/// | [enterpriseVertexSaPlusKey] | Vertex SA + Key | gcp (key + SA) |
/// | [enterpriseNoCredentials] | No Credentials | (none — negative test) |
///
/// **Pro**: [aotProTesting] — tsavoknott@gmail.com.
class TestProfiles {
  TestProfiles._();

  // -- Free tier (personal accounts, no organizations) ----------------------

  static const alice = TestProfile(
    id: 'alice',
    displayName: 'Alice Anderson',
    email: 'ngrok_tunnel_test_alice@gmail.com',
    subscription: 'Free',
  );

  static const aliceWork = TestProfile(
    id: 'alice_work',
    displayName: 'Alice Anderson (Work)',
    email: 'ngrok_tunnel_test_alice@pieces.app',
    subscription: 'Free',
  );

  static const bob = TestProfile(
    id: 'bob',
    displayName: 'Bob Builder',
    email: 'ngrok_tunnel_test_bob@pieces.app',
    subscription: 'Free',
  );

  static const charlie = TestProfile(
    id: 'charlie',
    displayName: 'Charlie Chen',
    email: 'ngrok_tunnel_test_charlie@gmail.com',
    subscription: 'Free',
  );

  // -- Enterprise tier (all use aot-automated-testing@pieces.app) -----------

  /// Primary enterprise org — has ALL provider credential types.
  /// GSM keys: openai, claude, gcp (api_key + service_account), azure, bedrock
  static const enterpriseAllProviders = TestProfile(
    id: 'enterprise_all_providers',
    displayName: 'Enterprise (All Providers)',
    email: 'aot-automated-testing@pieces.app',
    subscription: 'Enterprise',
    orgId: 'org_49887440842814784180278772662899',
    expectedProviders: ['openai', 'claude', 'gcp', 'azure', 'bedrock'],
  );

  /// Enterprise org with Google AI Studio (Gemini) API key only.
  static const enterpriseGaiStudioOnly = TestProfile(
    id: 'enterprise_gai_studio_only',
    displayName: 'Enterprise (GAI Studio Only)',
    email: 'aot-automated-testing@pieces.app',
    subscription: 'Enterprise',
    orgId: 'org_43713733979203801541292149960977',
    expectedProviders: ['gcp'],
  );

  /// Enterprise org with Vertex AI API key only (no service account).
  static const enterpriseVertexApiKeyOnly = TestProfile(
    id: 'enterprise_vertex_api_key_only',
    displayName: 'Enterprise (Vertex API Key Only)',
    email: 'aot-automated-testing@pieces.app',
    subscription: 'Enterprise',
    orgId: 'org_10983279165683593911976049434519',
    expectedProviders: ['gcp'],
  );

  /// Enterprise org with Vertex AI service account only (no API key).
  static const enterpriseVertexSaOnly = TestProfile(
    id: 'enterprise_vertex_sa_only',
    displayName: 'Enterprise (Vertex SA Only)',
    email: 'aot-automated-testing@pieces.app',
    subscription: 'Enterprise',
    orgId: 'org_89351487523071436795108891433509',
    expectedProviders: ['gcp'],
  );

  /// Enterprise org with both Vertex API key AND service account.
  static const enterpriseVertexSaPlusKey = TestProfile(
    id: 'enterprise_vertex_sa_plus_key',
    displayName: 'Enterprise (Vertex SA + Key)',
    email: 'aot-automated-testing@pieces.app',
    subscription: 'Enterprise',
    orgId: 'org_87640824462334190014342663830051',
    expectedProviders: ['gcp'],
  );

  /// Enterprise org with NO enterprise credentials — negative test case.
  static const enterpriseNoCredentials = TestProfile(
    id: 'enterprise_no_credentials',
    displayName: 'Enterprise (No Credentials)',
    email: 'aot-automated-testing@pieces.app',
    subscription: 'Enterprise',
    orgId: 'org_43678905987060956479599951714276',
    expectedProviders: [],
  );

  // -- Pro tier -------------------------------------------------------------

  /// Pro-tier testing profile.
  /// GSM secret: `aot-descope-pro-password`.
  static const aotProTesting = TestProfile(
    id: 'aot_pro_testing',
    displayName: 'AOT Pro Testing',
    email: 'tsavoknott@gmail.com',
    subscription: 'Pro',
  );

  // -- Legacy aliases -------------------------------------------------------

  /// Legacy alias — maps to [enterpriseAllProviders].
  static const aotAutomatedTesting = enterpriseAllProviders;

  // -- Groupings ------------------------------------------------------------

  /// All profiles that use the shared free Descope password.
  static const freePasswordProfiles = [
    alice,
    aliceWork,
    bob,
    charlie,
    enterpriseAllProviders,
    enterpriseGaiStudioOnly,
    enterpriseVertexApiKeyOnly,
    enterpriseVertexSaOnly,
    enterpriseVertexSaPlusKey,
    enterpriseNoCredentials,
  ];

  /// Profiles that use the Pro password.
  static const proPasswordProfiles = [aotProTesting];

  /// Free-tier personal accounts (no org).
  static const freePersonal = [alice, aliceWork, bob, charlie];

  /// All enterprise org profiles (same user, different orgs).
  static const enterprise = [
    enterpriseAllProviders,
    enterpriseGaiStudioOnly,
    enterpriseVertexApiKeyOnly,
    enterpriseVertexSaOnly,
    enterpriseVertexSaPlusKey,
    enterpriseNoCredentials,
  ];

  /// Enterprise profiles that have native GCP/Vertex credentials.
  static const enterpriseWithGcp = [
    enterpriseAllProviders,
    enterpriseGaiStudioOnly,
    enterpriseVertexApiKeyOnly,
    enterpriseVertexSaOnly,
    enterpriseVertexSaPlusKey,
  ];

  /// Enterprise profiles with Vertex service accounts.
  static const enterpriseWithVertexSa = [enterpriseAllProviders, enterpriseVertexSaOnly, enterpriseVertexSaPlusKey];

  /// Enterprise profiles with OpenAI credentials.
  static const enterpriseWithOpenai = [enterpriseAllProviders];

  /// Enterprise profiles with Claude/Anthropic credentials.
  static const enterpriseWithClaude = [enterpriseAllProviders];

  /// Enterprise profiles with Azure OpenAI credentials.
  static const enterpriseWithAzure = [enterpriseAllProviders];

  /// Enterprise profiles with AWS Bedrock credentials.
  static const enterpriseWithBedrock = [enterpriseAllProviders];

  /// Every profile.
  static const all = [
    alice,
    aliceWork,
    bob,
    charlie,
    enterpriseAllProviders,
    enterpriseGaiStudioOnly,
    enterpriseVertexApiKeyOnly,
    enterpriseVertexSaOnly,
    enterpriseVertexSaPlusKey,
    enterpriseNoCredentials,
    aotProTesting,
  ];
}

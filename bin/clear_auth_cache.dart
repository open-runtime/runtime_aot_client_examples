/// Clears the cached authentication token to force re-authentication.
///
/// Run this script to clear the cached Descope token and force a fresh
/// browser login on the next authentication attempt.
///
/// Usage:
///   dart run bin/clear_auth_cache.dart
///
/// Or directly:
///   dart bin/clear_auth_cache.dart
library;

import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

void main() async {
  print('🗑️ Clearing authentication cache...\n');

  await AuthenticatedAOTClient.clearCache();

  print('\n✅ Done! Next authentication will open the browser for login.');
}

// // ignore_for_file: avoid_print

// import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

// // Import the AWS Bedrock service from the isomorphic library
// import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/models.pb.dart'
//     show AWSBedrockInferenceRequest, AWSBedrockModelIdentifier;
// import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/providers/claude.pb.dart'
//     show AWSBedrockClaudeContent, AWSBedrockClaudeMessage, AWSBedrockClaudeRequest;
// import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/providers/claude.pbenum.dart'
//     show AWSBedrockClaudeRole;
// import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/services/service.pbgrpc.dart'
//     show AWSBedrockInferenceServiceClient;

// /// Example: Making authenticated requests to AWS Bedrock via AOT.
// ///
// /// Prerequisites:
// /// 1. Run: gcloud auth application-default login
// /// 2. Have a Pieces account (browser auth will open)
// ///
// /// Run with: dart run example/main.dart
// void main() async {
//   print('═══════════════════════════════════════════════════════');
//   print('  Self-Contained AOT Client - AWS Bedrock Example');
//   print('═══════════════════════════════════════════════════════\n');

//   AuthenticatedAOTClient? auth;
//   ClientChannel? channel;

//   try {
//     // Step 1: Create authenticated client
//     // This will:
//     // - Check for cached token (55 min validity)
//     // - If no cache, open browser for Descope authentication
//     // - Fetch user keys and org ID from user-team-service
//     print('Step 1: Authenticating...\n');
//     auth = await AuthenticatedAOTClient.create();

//     print('\n───────────────────────────────────────────────────────');
//     print('Authentication successful!');
//     print('  User: ${auth.userEmail}');
//     print('  User ID: ${auth.userId}');
//     print('  Org ID: ${auth.orgId ?? "none"}');
//     print('───────────────────────────────────────────────────────\n');

//     // Step 2: Create gRPC channel to AWS Bedrock service
//     print('Step 2: Connecting to AWS Bedrock service...\n');

//     // NOTE: Replace with the actual Cloud Run service URL
//     // You can find this in the GCP Console or ask your team
//     const serviceHost = 'runtime-native-io-aws-bedrock-inference-grpc-serv-lmuw6mcn3q-ul.a.run.app';

//     channel = ClientChannel(
//       serviceHost,
//       port: 443,
//       options: const ChannelOptions(credentials: ChannelCredentials.secure()),
//     );

//     // Step 3: Create service client with auth interceptor
//     final client = AWSBedrockInferenceServiceClient(
//       channel,
//       interceptors: [auth.interceptor],
//     );

//     print('Connected to: $serviceHost\n');

//     // Step 4: Make a request
//     print('Step 3: Making a test request to Claude via AWS Bedrock...\n');

//     // Check if user has org ID (required for AWS Bedrock)
//     if (!auth.hasOrgId) {
//       print('⚠️ Warning: No organization ID found.');
//       print('   AWS Bedrock is enterprise-only and requires x-org-id.');
//       print('   The request may fail without enterprise access.\n');
//     }

//     final request = AWSBedrockInferenceRequest(
//       region: 'us-east-1',
//       modelIdentifier: AWSBedrockModelIdentifier(
//         customModelId: 'anthropic.claude-3-haiku-20240307-v1:0',
//       ),
//       claude: AWSBedrockClaudeRequest(
//         anthropicVersion: 'bedrock-2023-05-31',
//         maxTokens: 100,
//         messages: [
//           AWSBedrockClaudeMessage(
//             role: AWSBedrockClaudeRole.AWS_BEDROCK_CLAUDE_ROLE_USER,
//             content: AWSBedrockClaudeContent(text: 'Say "Hello from AWS Bedrock!" and nothing else.'),
//           ),
//         ],
//       ),
//     );

//     // Make the request with org-id header
//     final response = await client.predict(
//       request,
//       options: auth.callOptionsWithOrgId,
//     );

//     print('───────────────────────────────────────────────────────');
//     print('Response received!');

//     if (response.hasSuccess()) {
//       final success = response.success;
//       if (success.hasClaude()) {
//         final claudeResponse = success.claude;
//         if (claudeResponse.content.isNotEmpty) {
//           final text = claudeResponse.content.first.text;
//           print('Claude says: $text');
//         }
//       }
//     } else if (response.hasFazilure()) {
//       print('Request failed: ${response.failure.message}');
//     }
//     print('───────────────────────────────────────────────────────\n');

//     print('✅ Example completed successfully!');
//   } catch (e, stack) {
//     print('\n❌ Error: $e');
//     print('\nStack trace:\n$stack');
//   } finally {
//     // Clean up
//     print('\nCleaning up...');
//     await channel?.shutdown();
//     await auth?.dispose();
//     print('Done.');
//   }
// }

// /// Example: Streaming responses from AWS Bedrock.
// ///
// /// Uncomment and modify main() to use this instead.
// Future<void> streamingExample() async {
//   final auth = await AuthenticatedAOTClient.create();

//   final channel = ClientChannel(
//     'runtime-native-io-aws-bedrock-inference-grpc-serv-lmuw6mcn3q-ul.a.run.app',
//     port: 443,
//     options: const ChannelOptions(credentials: ChannelCredentials.secure()),
//   );

//   final client = AWSBedrockInferenceServiceClient(
//     channel,
//     interceptors: [auth.interceptor],
//   );

//   final request = AWSBedrockInferenceRequest(
//     region: 'us-east-1',
//     accumulate: true, // Enable streaming accumulation
//     modelIdentifier: AWSBedrockModelIdentifier(
//       customModelId: 'anthropic.claude-3-haiku-20240307-v1:0',
//     ),
//     claude: AWSBedrockClaudeRequest(
//       anthropicVersion: 'bedrock-2023-05-31',
//       maxTokens: 500,
//       messages: [
//         AWSBedrockClaudeMessage(
//           role: AWSBedrockClaudeRole.AWS_BEDROCK_CLAUDE_ROLE_USER,
//           content: AWSBedrockClaudeContent(text: 'Tell me a short joke.'),
//         ),
//       ],
//     ),
//   );

//   print('Streaming response:');
//   print('---');

//   await for (final chunk in client.predictWithStream(request, options: auth.callOptionsWithOrgId)) {
//     if (chunk.hasSuccess() && chunk.success.hasClaude()) {
//       final content = chunk.success.claude.content;
//       if (content.isNotEmpty) {
//         // Print each chunk as it arrives
//         print(content.first.text);
//       }
//     }
//   }

//   print('---');
//   print('Stream complete.');

//   await channel.shutdown();
//   await auth.dispose();
// }

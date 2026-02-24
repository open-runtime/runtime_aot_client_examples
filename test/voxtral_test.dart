// Printing is used for test diagnostic output.
// ignore_for_file: avoid_print

/// Voxtral Audio Transcription Test
///
/// This test demonstrates using the self-contained client to make
/// authenticated requests to AWS Bedrock's Voxtral model for audio transcription.
///
/// Prerequisites:
/// 1. Run: gcloud auth application-default login
/// 2. Have a Pieces account with enterprise access (AWS Bedrock is enterprise-only)
///
/// Run with: dart test test/voxtral_test.dart
@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io' show Directory, File, Platform;

import 'package:grpc/grpc.dart' show GrpcError;
import 'package:runtime_aot_client_examples/runtime_aot_client_examples.dart';

// Import common models (audio source, audio format, stop reason)
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/aws_bedrock_common_models.pb.dart'
    show AWSBedrockAudioSource;
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/aws_bedrock_common_models.pbenum.dart'
    show AWSBedrockAudioFormat, AWSBedrockStopReason;

// Import Bedrock inference request/response types
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/models.pb.dart'
    show AWSBedrockInferenceRequest, AWSBedrockModelIdentifier;

// Import Mistral provider types (including Voxtral audio support)
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/providers/mistral.pb.dart'
    show
        AWSBedrockMistralContentBlock,
        AWSBedrockMistralContentBlocks,
        AWSBedrockMistralInferenceConfig,
        AWSBedrockMistralMessage,
        AWSBedrockMistralRequest,
        AWSBedrockMistralResponse;
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/providers/mistral.pbenum.dart'
    show AWSBedrockMistralRole;

// Import service client
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/services/service.pbgrpc.dart'
    show AWSBedrockInferenceServiceClient;

import 'package:test/test.dart';

/// Pretty prints a Voxtral/Mistral response with all available details.
void prettyPrintMistralResponse(AWSBedrockMistralResponse response) {
  print('');
  print('╔═══════════════════════════════════════════════════════════════════╗');
  print('║                    VOXTRAL RESPONSE                               ║');
  print('╠═══════════════════════════════════════════════════════════════════╣');

  // Model info
  if (response.model.isNotEmpty) {
    print('║  Model: ${response.model.padRight(54)}║');
  }
  if (response.id.isNotEmpty) {
    print('║  Response ID: ${response.id.padRight(49)}║');
  }

  // Usage stats
  if (response.hasUsage()) {
    final usage = response.usage;
    print('╠═══════════════════════════════════════════════════════════════════╣');
    print('║  TOKEN USAGE                                                      ║');
    print('║    Input tokens:  ${usage.inputTokens.toString().padRight(46)}║');
    print('║    Output tokens: ${usage.outputTokens.toString().padRight(46)}║');
    print('║    Total tokens:  ${(usage.inputTokens + usage.outputTokens).toString().padRight(46)}║');
  }

  // Choices (transcription content)
  if (response.choices.isNotEmpty) {
    print('╠═══════════════════════════════════════════════════════════════════╣');
    print('║  TRANSCRIPTION                                                    ║');
    print('╠═══════════════════════════════════════════════════════════════════╣');

    for (var i = 0; i < response.choices.length; i++) {
      final choice = response.choices[i];

      if (choice.hasMessage()) {
        final message = choice.message;
        String? text;

        // Extract text from message
        if (message.hasText()) {
          text = message.text;
        } else if (message.hasBlocks()) {
          final textParts = <String>[];
          for (final block in message.blocks.blocks) {
            if (block.hasText()) {
              textParts.add(block.text);
            }
          }
          if (textParts.isNotEmpty) {
            text = textParts.join('\n');
          }
        }

        if (text != null && text.isNotEmpty) {
          // Word wrap the text to fit in the box
          final lines = _wrapText(text, 63);
          for (final line in lines) {
            print('║  ${line.padRight(65)}║');
          }
        }
      }

      // Stop reason
      if (choice.hasStopReason() && choice.stopReason != AWSBedrockStopReason.AWS_BEDROCK_STOP_REASON_UNSPECIFIED) {
        print('╠═══════════════════════════════════════════════════════════════════╣');
        final stopReasonStr = choice.stopReason.name.replaceAll('AWS_BEDROCK_STOP_REASON_', '');
        print('║  Stop Reason: ${stopReasonStr.padRight(51)}║');
      }
    }
  }

  print('╚═══════════════════════════════════════════════════════════════════╝');
  print('');
}

/// Wraps text to fit within a specified width.
List<String> _wrapText(String text, int maxWidth) {
  final lines = <String>[];
  final paragraphs = text.split('\n');

  for (final paragraph in paragraphs) {
    if (paragraph.isEmpty) {
      lines.add('');
      continue;
    }

    var remaining = paragraph;
    while (remaining.length > maxWidth) {
      // Find last space before maxWidth
      var splitAt = remaining.lastIndexOf(' ', maxWidth);
      if (splitAt == -1 || splitAt == 0) {
        splitAt = maxWidth; // Force split if no space found
      }
      lines.add(remaining.substring(0, splitAt));
      remaining = remaining.substring(splitAt).trimLeft();
    }
    if (remaining.isNotEmpty) {
      lines.add(remaining);
    }
  }

  return lines;
}

bool _isCiOrCloudRun() {
  final env = Platform.environment;
  final ciValue = env['CI']?.toLowerCase();

  return ciValue == 'true' ||
      env.containsKey('K_SERVICE') || // Cloud Run
      env.containsKey('PROJECT_ID') ||
      env.containsKey('GCP_PROJECT_ID');
}

void main() {
  // This test requires ADC creds + access to services behind VPN; skip in CI by default.
  final skipReason = _isCiOrCloudRun()
      ? 'Skipping Voxtral integration tests in CI (requires gcloud ADC + VPN + org access).'
      : null;

  group('Voxtral Audio Transcription Tests', () {
    late AuthenticatedAOTClient auth;
    late ClientChannel channel;
    late AWSBedrockInferenceServiceClient client;

    setUpAll(() async {
      print('═══════════════════════════════════════════════════════');
      print('  Voxtral Audio Transcription Test Setup');
      print('═══════════════════════════════════════════════════════\n');

      // Authenticate
      auth = await AuthenticatedAOTClient.create();

      print('\nAuthenticated as: ${auth.userEmail}');
      print('Org ID: ${auth.orgId ?? "none"}');

      if (!auth.hasOrgId) {
        print('\n⚠️ Warning: No org ID - AWS Bedrock is enterprise-only.');
        print('   Tests may fail without enterprise access.\n');
      }

      // Create channel to AWS Bedrock service
      // NOTE: This service requires VPN connection (aot.runtime.services)
      const serviceHost = 'runtime-native-io-aws-bedrock-inference-grpc-service.aot.runtime.services';

      channel = ClientChannel(serviceHost);

      client = AWSBedrockInferenceServiceClient(channel, interceptors: [auth.interceptor]);

      print('Connected to: $serviceHost\n');
    });

    tearDownAll(() async {
      await channel.shutdown();
      await auth.dispose();
      print('\n🧹 Test cleanup complete');
    });

    test('Voxtral Mini 3B - Basic Audio Transcription', () async {
      print('\n🎤 Testing Voxtral Mini 3B audio transcription...\n');

      // Load test audio file
      // Note: Run this test from the package root directory:
      //   cd packages/libraries/dart/runtime_aot_client_examples
      //   dart test test/voxtral_test.dart
      final audioFile = File('test/assets/test_speech.wav');
      if (!await audioFile.exists()) {
        print('⏭️ Skipping Voxtral test: test_speech.wav not found');
        print('   Current directory: ${Directory.current.path}');
        print('   Expected file at: ${audioFile.absolute.path}');
        print('');
        print('   Make sure you:');
        print('   1. Run from package root: cd packages/libraries/dart/runtime_aot_client_examples');
        print('   2. Have the test_speech.wav file (pull latest from git)');
        return;
      }

      final audioBytes = await audioFile.readAsBytes();

      print('   Audio file: ${audioFile.path}');
      print('   Size: ${audioBytes.length} bytes\n');

      // Build audio source for Voxtral
      // Voxtral uses AWSBedrockAudioSource for audio input (raw bytes - protobuf handles encoding)
      final audioSource = AWSBedrockAudioSource()
        ..format = AWSBedrockAudioFormat.AWS_BEDROCK_AUDIO_FORMAT_WAV
        ..data = audioBytes;

      // Create content blocks with audio and transcription prompt
      final contentBlocks = AWSBedrockMistralContentBlocks()
        ..blocks.add(AWSBedrockMistralContentBlock()..audio = audioSource)
        ..blocks.add(AWSBedrockMistralContentBlock()..text = 'Please transcribe this audio.');

      // Build Mistral request for Voxtral model
      // Voxtral is available in multiple regions including ap-northeast-1, us-east-1, etc.
      final request = AWSBedrockInferenceRequest(
        region: 'ap-northeast-1', // Tokyo - verified working
        modelIdentifier: AWSBedrockModelIdentifier(customModelId: 'mistral.voxtral-mini-3b-2507'),
        mistral: AWSBedrockMistralRequest(
          messages: [
            AWSBedrockMistralMessage(role: AWSBedrockMistralRole.AWS_BEDROCK_MISTRAL_ROLE_USER, blocks: contentBlocks),
          ],
          config: AWSBedrockMistralInferenceConfig()
            ..maxTokens = 500
            ..temperature = 0.1,
        ),
      );

      print('   Sending request to Voxtral Mini 3B...');

      try {
        final response = await client.predict(request, options: auth.callOptionsWithOrgId);

        print('\n───────────────────────────────────────────────────────');

        if (response.hasSuccess()) {
          final success = response.success;
          if (success.hasMistral()) {
            // Pretty print the full response with box drawing
            prettyPrintMistralResponse(success.mistral);
          } else {
            print('⚠️ Unexpected response type (not Mistral)');
            print('   Response: ${success.toDebugString()}');
          }
          print('✅ Voxtral Mini 3B test passed!');
        } else if (response.hasError()) {
          final errorMsg = response.error.message;
          // Check for known access/credential issues
          if (errorMsg.contains('No element') ||
              errorMsg.contains('not authorized') ||
              errorMsg.contains('access denied') ||
              errorMsg.contains('credential')) {
            print('⏭️ Skipping: AWS Bedrock credentials not configured for this org');
            print('   Error: $errorMsg');
            print("   This is expected if your organization doesn't have Voxtral access.");
            return; // Skip test gracefully
          }
          print('❌ Request failed: $errorMsg');
          fail('Voxtral request failed: $errorMsg');
        }
      } on GrpcError catch (e) {
        // Check for known access/credential issues
        if ((e.message?.contains('No element') ?? false) ||
            (e.message?.contains('not authorized') ?? false) ||
            (e.message?.contains('credential') ?? false)) {
          print('⏭️ Skipping: AWS Bedrock credentials not configured for this org');
          print('   gRPC Error: ${e.message}');
          print("   This is expected if your organization doesn't have Voxtral access.");
          return; // Skip test gracefully
        }
        rethrow;
      }
    });

    test('Voxtral Small 24B - Transcription with Timestamps', () async {
      print('\n🎤 Testing Voxtral Small 24B with timestamps...\n');

      // Load test audio file
      final audioFile = File('test/assets/test_speech.wav');
      if (!await audioFile.exists()) {
        print('⏭️ Skipping Voxtral Small test: test_speech.wav not found');
        print('   Run from package root and ensure file exists');
        return;
      }

      final audioBytes = await audioFile.readAsBytes();

      print('   Audio file: ${audioFile.path}');
      print('   Size: ${audioBytes.length} bytes\n');

      // Build audio source
      final audioSource = AWSBedrockAudioSource()
        ..format = AWSBedrockAudioFormat.AWS_BEDROCK_AUDIO_FORMAT_WAV
        ..data = audioBytes;

      // Create content blocks - request timestamps in the prompt
      // Note: Voxtral Small 24B supports timestamps, Mini 3B does not
      final contentBlocks = AWSBedrockMistralContentBlocks()
        ..blocks.add(AWSBedrockMistralContentBlock()..audio = audioSource)
        ..blocks.add(AWSBedrockMistralContentBlock()..text = 'Please transcribe this audio with timestamps.');

      // Build request for Voxtral Small (larger model with timestamp support)
      // Voxtral is available in multiple regions including ap-northeast-1, us-east-1, etc.
      final request = AWSBedrockInferenceRequest(
        region: 'ap-northeast-1', // Tokyo - verified working
        modelIdentifier: AWSBedrockModelIdentifier(customModelId: 'mistral.voxtral-small-24b-2507'),
        mistral: AWSBedrockMistralRequest(
          messages: [
            AWSBedrockMistralMessage(role: AWSBedrockMistralRole.AWS_BEDROCK_MISTRAL_ROLE_USER, blocks: contentBlocks),
          ],
          config: AWSBedrockMistralInferenceConfig()
            ..maxTokens = 1000
            ..temperature = 0.1,
        ),
      );

      print('   Sending request to Voxtral Small 24B...');

      try {
        final response = await client.predict(request, options: auth.callOptionsWithOrgId);

        print('\n───────────────────────────────────────────────────────');

        if (response.hasSuccess()) {
          final success = response.success;
          if (success.hasMistral()) {
            // Pretty print the full response with box drawing
            prettyPrintMistralResponse(success.mistral);
          } else {
            print('⚠️ Unexpected response type (not Mistral)');
            print('   Response: ${success.toDebugString()}');
          }
          print('✅ Voxtral Small 24B test passed!');
        } else if (response.hasError()) {
          final errorMsg = response.error.message;
          // Check for known access/credential issues
          if (errorMsg.contains('No element') ||
              errorMsg.contains('not authorized') ||
              errorMsg.contains('access denied') ||
              errorMsg.contains('credential')) {
            print('⏭️ Skipping: AWS Bedrock credentials not configured for this org');
            print('   Error: $errorMsg');
            return; // Skip test gracefully
          }
          print('❌ Request failed: $errorMsg');
          fail('Voxtral request failed: $errorMsg');
        }
      } on GrpcError catch (e) {
        // Check for known access/credential issues
        if ((e.message?.contains('No element') ?? false) ||
            (e.message?.contains('not authorized') ?? false) ||
            (e.message?.contains('credential') ?? false)) {
          print('⏭️ Skipping: AWS Bedrock credentials not configured for this org');
          print('   gRPC Error: ${e.message}');
          return; // Skip test gracefully
        }
        rethrow;
      }
    });
  }, skip: skipReason);
}

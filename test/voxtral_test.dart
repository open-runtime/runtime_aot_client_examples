import 'dart:typed_data';

import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/aws_bedrock_common_models.pb.dart'
    show AWSBedrockAudioSource;
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/aws_bedrock_common_models.pbenum.dart'
    show AWSBedrockAudioFormat;
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/models.pb.dart'
    show AWSBedrockInferenceRequest, AWSBedrockModelIdentifier;
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/providers/mistral.pb.dart'
    show
        AWSBedrockMistralContentBlock,
        AWSBedrockMistralContentBlocks,
        AWSBedrockMistralInferenceConfig,
        AWSBedrockMistralMessage,
        AWSBedrockMistralRequest;
import 'package:runtime_isomorphic_library/machine_learning/parents/aws_bedrock/root/shared/models/providers/mistral.pbenum.dart'
    show AWSBedrockMistralRole;
import 'package:test/test.dart';

void main() {
  group('Voxtral request construction', () {
    test('builds Voxtral Mini 3B request', () {
      final audioBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);

      final audioSource = AWSBedrockAudioSource()
        ..format = AWSBedrockAudioFormat.AWS_BEDROCK_AUDIO_FORMAT_WAV
        ..data = audioBytes;

      final contentBlocks = AWSBedrockMistralContentBlocks()
        ..blocks.add(AWSBedrockMistralContentBlock()..audio = audioSource)
        ..blocks.add(AWSBedrockMistralContentBlock()..text = 'Please transcribe this audio.');

      final request = AWSBedrockInferenceRequest(
        region: 'ap-northeast-1',
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

      expect(request.region, 'ap-northeast-1');
      expect(request.modelIdentifier.customModelId, 'mistral.voxtral-mini-3b-2507');
      expect(request.mistral.messages, hasLength(1));
      expect(request.mistral.messages.single.role, AWSBedrockMistralRole.AWS_BEDROCK_MISTRAL_ROLE_USER);

      final blocks = request.mistral.messages.single.blocks.blocks;
      expect(blocks, hasLength(2));
      expect(blocks.first.audio.format, AWSBedrockAudioFormat.AWS_BEDROCK_AUDIO_FORMAT_WAV);
      expect(blocks.first.audio.data, audioBytes);
      expect(blocks[1].text, 'Please transcribe this audio.');
    });

    test('builds Voxtral Small 24B request with timestamps prompt', () {
      final audioBytes = Uint8List.fromList([9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);

      final audioSource = AWSBedrockAudioSource()
        ..format = AWSBedrockAudioFormat.AWS_BEDROCK_AUDIO_FORMAT_WAV
        ..data = audioBytes;

      final contentBlocks = AWSBedrockMistralContentBlocks()
        ..blocks.add(AWSBedrockMistralContentBlock()..audio = audioSource)
        ..blocks.add(AWSBedrockMistralContentBlock()..text = 'Please transcribe this audio with timestamps.');

      final request = AWSBedrockInferenceRequest(
        region: 'ap-northeast-1',
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

      expect(request.modelIdentifier.customModelId, 'mistral.voxtral-small-24b-2507');
      expect(request.mistral.messages.single.blocks.blocks[1].text, 'Please transcribe this audio with timestamps.');
    });
  });
}

/// WasteBot AI — answers come from the `chatbot` Cloud Function, which
/// holds the Hugging Face token and the system prompt (never the app).
library;

import 'functions_client.dart';

/// Safe error for UI — never expose provider details or raw API payloads.
class HuggingFaceChatException implements Exception {
  const HuggingFaceChatException({
    required this.code,
    required this.userMessageFr,
    required this.userMessageEn,
  });

  final String code;
  final String userMessageFr;
  final String userMessageEn;

  String messageFor({required bool french}) =>
      french ? userMessageFr : userMessageEn;

  @override
  String toString() => 'HuggingFaceChatException($code)';
}

class HuggingFaceChatService {
  HuggingFaceChatService({FunctionsClient? functions})
      : _functions = functions;

  final FunctionsClient? _functions;

  /// The token lives on the server: the app always tries, and the
  /// function answers `not_configured` if it is missing.
  bool get isConfigured => true;

  /// Ask the model. [history] items are `{role: user|assistant, content: ...}`.
  Future<String> chat({
    required String userMessage,
    required bool french,
    List<Map<String, String>> history = const [],
  }) async {
    final Map<String, dynamic> data;
    try {
      data = await (_functions ?? FunctionsClient()).post('chatbot', {
        'message': userMessage,
        'french': french,
        'history': history,
      });
    } on FunctionsException catch (e) {
      throw _errorFor(e);
    } catch (_) {
      throw _errorFor(const FunctionsException(0, ''));
    }
    final answer = (data['answer'] as String? ?? '').trim();
    if (answer.isEmpty) throw _errorFor(const FunctionsException(502, ''));
    return answer;
  }

  HuggingFaceChatException _errorFor(FunctionsException e) {
    if (e.statusCode == 0) {
      return const HuggingFaceChatException(
        code: 'network',
        userMessageFr:
            'Impossible de joindre le service IA pour le moment. Reessaie dans un instant.',
        userMessageEn:
            'Could not reach the AI service right now. Please try again shortly.',
      );
    }
    if (e.statusCode == 429) {
      return const HuggingFaceChatException(
        code: 'rate_limit',
        userMessageFr:
            'Trop de questions pour le moment. Attends un peu puis reessaie.',
        userMessageEn:
            'Too many questions right now. Please wait a moment and try again.',
      );
    }
    return const HuggingFaceChatException(
      code: 'upstream',
      userMessageFr:
          'Le service IA WasteBot est temporairement indisponible. Pose ta question autrement ou contacte le support.',
      userMessageEn:
          'WasteBot AI is temporarily unavailable. Try rephrasing or contact support.',
    );
  }
}

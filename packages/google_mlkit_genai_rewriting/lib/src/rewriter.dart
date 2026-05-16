import 'dart:async';

import 'package:flutter/services.dart';

/// Output type for rewriting.
enum RewritingOutputType {
  /// Formal output type.
  formal,

  /// Concise output type.
  concise,

  /// Emoji output type.
  emoji,
}

/// Language for rewriting.
enum RewritingLanguage {
  /// English language.
  english,

  /// Japanese language.
  japanese,

  /// Korean language.
  korean,
}

/// Feature status for GenAI APIs.
enum FeatureStatus {
  /// Feature is unavailable.
  unavailable,

  /// Feature is downloadable.
  downloadable,

  /// Feature is currently downloading.
  downloading,

  /// Feature is available.
  available,
}

/// A rewriter that rewrites text in different styles.
class Rewriter {
  static const MethodChannel _channel = MethodChannel(
    'google_mlkit_genai_rewriting',
  );

  static const Duration _timeout = Duration(seconds: 10);

  /// Instance id.
  final String id = DateTime.now().microsecondsSinceEpoch.toString();

  /// Output type for rewriting.
  final RewritingOutputType outputType;

  /// Language for rewriting.
  final RewritingLanguage language;

  /// Constructor to create an instance of [Rewriter].
  Rewriter({required this.outputType, required this.language});

  Future<T> _invokeMethod<T>(String method, Map<String, dynamic> args) async {
    try {
      final result = await _channel.invokeMethod(method, args).timeout(_timeout);
      return result as T;
    } on PlatformException catch (e) {
      final details = e.details is Map ? e.details as Map : null;
      final errorCode = details?['errorCode'] as int?;
      final message =
          details?['errorMessage'] as String? ?? e.message ?? 'Unknown error';
      throw GenAiException(errorCode ?? -1, message);
    }
  }

  /// Checks the feature status.
  Future<FeatureStatus> checkFeatureStatus() async {
    final result =
        await _invokeMethod<int>('genai#checkFeatureStatus', {
      'id': id,
      'outputType': outputType.index,
      'language': language.index,
    });
    return FeatureStatus.values[result];
  }

  /// Downloads the feature if needed.
  Future<void> downloadFeature() async {
    await _invokeMethod<void>('genai#downloadFeature', {
      'id': id,
      'outputType': outputType.index,
      'language': language.index,
    });
  }

  /// Runs inference with streaming response.
  Stream<String> runInferenceStreaming(String text) {
    final controller = StreamController<String>();
    _channel
        .invokeMethod('genai#runInferenceStreaming', {'id': id, 'text': text})
        .timeout(_timeout)
        .then((_) {
          // In a real implementation, this would use an event channel
          // to stream the results incrementally.
        })
        .catchError((error) {
          controller.addError(error);
        });
    return controller.stream;
  }

  /// Runs inference with non-streaming response.
  Future<String> runInference(String text) async {
    final result = await _invokeMethod<Map<dynamic, dynamic>>(
      'genai#runInference',
      {'id': id, 'text': text},
    );
    return result['text'] as String;
  }

  /// Closes the rewriter and releases its resources.
  Future<void> close() =>
      _invokeMethod<void>('genai#closeRewriter', {'id': id});
}

/// Exception thrown by GenAI APIs.
class GenAiException implements Exception {
  /// Error code.
  final int code;

  /// Error message.
  final String message;

  /// Constructor to create an instance of [GenAiException].
  GenAiException(this.code, this.message);

  @override
  String toString() => 'GenAiException(code: $code, message: $message)';
}

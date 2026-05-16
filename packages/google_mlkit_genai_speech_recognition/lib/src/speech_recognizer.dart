import 'dart:async';

import 'package:flutter/services.dart';

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

/// A speech recognizer that transcribes speech to text.
class SpeechRecognizer {
  static const MethodChannel _channel = MethodChannel(
    'google_mlkit_genai_speech_recognition',
  );

  static const Duration _timeout = Duration(seconds: 10);

  /// Instance id.
  final String id = DateTime.now().microsecondsSinceEpoch.toString();

  /// Constructor to create an instance of [SpeechRecognizer].
  SpeechRecognizer();

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
        await _invokeMethod<int>('genai#checkFeatureStatus', {'id': id});
    return FeatureStatus.values[result];
  }

  /// Starts speech recognition.
  Stream<String> startRecognition() {
    final controller = StreamController<String>();
    _channel
        .invokeMethod('genai#startRecognition', {'id': id})
        .timeout(_timeout)
        .then((_) {
          // In a real implementation, this would use an event channel
          // to stream the recognition results incrementally.
        })
        .catchError((error) {
          controller.addError(error);
        });
    return controller.stream;
  }

  /// Stops speech recognition.
  Future<void> stopRecognition() async {
    await _invokeMethod<void>('genai#stopRecognition', {'id': id});
  }

  /// Closes the speech recognizer and releases its resources.
  Future<void> close() =>
      _invokeMethod<void>('genai#closeSpeechRecognizer', {'id': id});
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

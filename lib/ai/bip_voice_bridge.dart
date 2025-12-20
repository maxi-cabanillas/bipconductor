import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Callback cuando el STT reconoce texto.
typedef BipSpeechCallback = void Function(String text, bool isFinal);

/// Voz (TTS) + reconocimiento (STT).
/// - TTS: habla con awaitSpeakCompletion
/// - STT: escucha comandos "BIP ..."
class BipVoiceBridge {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();

  bool _ttsReady = false;
  bool _sttReady = false;

  BipSpeechCallback? _onSpeech;

  final ValueNotifier<bool> isListening = ValueNotifier(false);
  final ValueNotifier<String> lastHeard = ValueNotifier('');
  final ValueNotifier<String> lastSpoken = ValueNotifier('');

  Completer<void>? _speakingCompleter;

  Future<void> init() async {
    if (!_ttsReady) {
      try {
        await _tts.awaitSpeakCompletion(true);

        // Intentar español Argentina primero, sino español general.
        try {
          await _tts.setLanguage('es-AR');
        } catch (_) {
          await _tts.setLanguage('es-ES');
        }

        await _tts.setSpeechRate(0.48);
        await _tts.setPitch(1.0);
        await _tts.setVolume(1.0);

        _tts.setStartHandler(() {
          _speakingCompleter = Completer<void>();
        });

        _tts.setCompletionHandler(() {
          if (_speakingCompleter != null && !_speakingCompleter!.isCompleted) {
            _speakingCompleter!.complete();
          }
        });

        _tts.setErrorHandler((msg) {
          if (_speakingCompleter != null && !_speakingCompleter!.isCompleted) {
            _speakingCompleter!.complete();
          }
        });

        _ttsReady = true;
      } catch (_) {
        _ttsReady = false;
      }
    }

    if (!_sttReady) {
      try {
        _sttReady = await _stt.initialize(
          onStatus: (s) {
            if (kDebugMode) {
              // debugPrint('BIP STT status: $s');
            }
          },
          onError: (e) {
            if (kDebugMode) {
              // debugPrint('BIP STT error: $e');
            }
          },
        );
      } catch (_) {
        _sttReady = false;
      }
    }
  }

  void setOnSpeech(BipSpeechCallback cb) => _onSpeech = cb;

  Future<void> speak(String text, {bool interrupt = true}) async {
    await init();
    if (!_ttsReady) return;

    try {
      if (interrupt) await _tts.stop();
      lastSpoken.value = text;
      await _tts.speak(text);

      // Esperar final si el plugin lo soporta
      final c = _speakingCompleter;
      if (c != null) {
        await c.future.timeout(const Duration(seconds: 12), onTimeout: () {});
      }
    } catch (_) {}
  }

  Future<void> startListening({Duration listenFor = const Duration(seconds: 6)}) async {
    await init();
    if (!_sttReady) return;

    try {
      if (_stt.isListening) await _stt.stop();

      lastHeard.value = '';
      isListening.value = true;

      _stt.listen(
        listenFor: listenFor,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        onResult: (r) {
          final w = r.recognizedWords.trim();
          if (w.isEmpty) return;
          lastHeard.value = w;
          _onSpeech?.call(w, r.finalResult);
          if (r.finalResult) isListening.value = false;
        },
      );

      // safety: apagar flag si se cuelga
      Future.delayed(listenFor + const Duration(seconds: 1), () {
        if (isListening.value) isListening.value = false;
      });
    } catch (_) {
      isListening.value = false;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_stt.isListening) await _stt.stop();
    } catch (_) {}
    isListening.value = false;
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

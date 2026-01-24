import 'package:flutter_tts/flutter_tts.dart';

/// Voz TTS (Español Argentino) con anti-spam (cooldown por key).
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  DateTime? _lastAt;
  String? _lastKey;

  Future<void> init() async {
    // Idioma / estilo
    await _tts.setLanguage("es-AR");
    await _tts.setSpeechRate(0.45); // suave
    await _tts.setPitch(1.05);      // un toque más “amable”
    await _tts.setVolume(1.0);

    // Intentar elegir una voz es-AR si el dispositivo la tiene
    final voices = await _tts.getVoices;
    if (voices is List) {
      final esAr = voices.where((v) {
        if (v is Map) {
          final locale = (v['locale'] ?? v['language'] ?? '').toString().toLowerCase();
          return locale.contains('es-ar');
        }
        return false;
      }).toList();

      if (esAr.isNotEmpty) {
        await _tts.setVoice(Map<String, String>.from(esAr.first));
      }
    }

    _ready = true;
  }

  Future<void> speak(
    String text, {
    required String key,
    int cooldownMs = 1500,
  }) async {
    if (!_ready) return;

    final now = DateTime.now();

    // Evita repetir por jitter (streams múltiples / updates seguidos)
    if (_lastKey == key && _lastAt != null) {
      final diff = now.difference(_lastAt!).inMilliseconds;
      if (diff < cooldownMs) return;
    }

    _lastKey = key;
    _lastAt = now;

    // Cortar cualquier frase anterior y hablar
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}

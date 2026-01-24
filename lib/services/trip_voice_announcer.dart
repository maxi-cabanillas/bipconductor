import 'package:geolocator/geolocator.dart';
import 'tts_service.dart';

/// Reglas de avisos de voz por viaje (una vez por evento).
///
/// Eventos cubiertos:
/// - Nuevo viaje
/// - Cancelación
/// - 150m antes de pickup (aceptado y no iniciado)
/// - 150m antes de destino (viaje iniciado)
/// - 50m antes de destino (viaje iniciado)
class TripVoiceAnnouncer {
  final TtsService tts;
  TripVoiceAnnouncer(this.tts);

  String? _tripId;

  bool _saidNew = false;
  bool _saidCancel = false;
  bool _said150Pickup = false;
  bool _said150Drop = false;
  bool _said50Drop = false;

  void resetForTrip(String tripId) {
    _tripId = tripId;
    _saidNew = false;
    _saidCancel = false;
    _said150Pickup = false;
    _said150Drop = false;
    _said50Drop = false;
  }

  /// Llamar cuando llega un pedido nuevo.
  Future<void> onNewTrip(String tripId) async {
    if (_tripId != tripId) resetForTrip(tripId);
    if (_saidNew) return;
    _saidNew = true;

    await tts.speak("Nuevo viaje.", key: "new_$tripId");
  }

  /// Llamar cuando el pasajero cancela el viaje.
  Future<void> onCancelled() async {
    if (_tripId == null) return;
    if (_saidCancel) return;
    _saidCancel = true;

    await tts.speak("El pasajero canceló el viaje.", key: "cancel_${_tripId!}");
  }

  /// Llamar en cada update de ubicación (ideal: cada 1–2s o cada 10–15m).
  ///
  /// accepted: viaje aceptado
  /// tripStarted: viaje iniciado
  Future<void> onLocationUpdate({
    required double myLat,
    required double myLng,
    required double pickLat,
    required double pickLng,
    required double dropLat,
    required double dropLng,
    required bool accepted,
    required bool tripStarted,
  }) async {
    if (_tripId == null) return;

    // 150m antes de pickup (solo cuando aceptó y aún NO inició)
    if (accepted && !tripStarted) {
      final dPick = Geolocator.distanceBetween(myLat, myLng, pickLat, pickLng);
      if (dPick <= 150 && !_said150Pickup) {
        _said150Pickup = true;
        await tts.speak(
          "Estás por llegar a buscar al pasajero.",
          key: "p150_${_tripId!}",
        );
      }
      return;
    }

    // 150m y 50m antes de destino (solo con viaje iniciado)
    if (tripStarted) {
      final dDrop = Geolocator.distanceBetween(myLat, myLng, dropLat, dropLng);

      if (dDrop <= 150 && !_said150Drop) {
        _said150Drop = true;
        await tts.speak(
          "Estás por finalizar el viaje.",
          key: "d150_${_tripId!}",
        );
      }

      if (dDrop <= 50 && !_said50Drop) {
        _said50Drop = true;
        await tts.speak(
          "Por favor, recordá revisar tus pertenencias.",
          key: "d50_${_tripId!}",
        );
      }
    }
  }
}

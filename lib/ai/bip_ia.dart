// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'bip_memory_store.dart';

typedef MapGetter = Map<String, dynamic> Function();
typedef AsyncAction = Future<dynamic> Function();
typedef SetOtpFn = void Function(String otp);
typedef NavOpener = Future<void> Function(double lat, double lng);

enum _AutoListenMode { none, acceptReject, navYesNo, startupNavPick }
enum _NavTarget { pickup, drop }
enum _YesNo { yes, no, unknown }

class BipIA {
  BipIA._();
  static final BipIA instance = BipIA._();

  // ======= Inyección desde map_page.dart =======
  MapGetter? _getUserDetails;
  MapGetter? _getDriverReq;

  AsyncAction? _acceptTrip;
  AsyncAction? _rejectTrip;
  AsyncAction? _driverArrived;
  AsyncAction? _startTripOtp;
  AsyncAction? _startTripNoOtp;
  AsyncAction? _endTrip;

  SetOtpFn? _setDriverOtp;

  NavOpener? _openGoogleMaps;
  NavOpener? _openWazeMap;

  // ======= Voz / STT =======
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();

  bool _ttsReady = false;
  bool _sttReady = false;
  bool _speaking = false;

  // ======= Enabled flag (DEFAULT OFF) =======
  bool _enabled = false;

  // ======= Estado de conductor / viaje =======
  String? _driverId;
  String? _lastTripId;
  int _lastTripStateHash = 0;

  // Anti-repetición de pregunta de navegador por (tripId + target)
  final Set<String> _navAnsweredKeys = <String>{};

  // Poll de request
  Timer? _pollTimer;

  // Auto-listen (solo en momentos clave)
  _AutoListenMode _autoMode = _AutoListenMode.none;
  Timer? _autoRestartTimer;

  int _restartCount = 0;
  DateTime _restartWindowStart = DateTime.fromMillisecondsSinceEpoch(0);

  // PTT (botón)
  String _pttBuffer = '';
  DateTime _pttStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Flujos
  bool _awaitingAcceptReject = false;
  bool _awaitingNavYesNo = false;
  bool _awaitingStartupNavPick = false;

  _PendingNav? _pendingNav;

  // Reintentos (máx 3)
  int _triesAcceptReject = 0;
  int _triesNav = 0;
  int _triesStartupNav = 0;

  Timer? _remindTimer;

  // Aprendizaje automático
  String? _learnCandidatePhrase;

  // Anti-spam de voz
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenText = '';

  bool _greeted = false;
  bool _startupNavChecked = false;

  final BipMemoryStore _mem = BipMemoryStore.instance;

  // UI notifiers
  final ValueNotifier<bool> isListening = ValueNotifier(false);
  final ValueNotifier<String> lastHeard = ValueNotifier('');
  final ValueNotifier<String> uiHint = ValueNotifier('BIP listo');

  // ================================================================
  // Bind (debe coincidir con map_page.dart)
  // ================================================================
  void bind({
    required MapGetter getUserDetails,
    required MapGetter getDriverReq,
    required AsyncAction acceptTrip,
    required AsyncAction rejectTrip,
    required AsyncAction driverArrived,
    required AsyncAction startTripOtp,
    required AsyncAction startTripNoOtp,
    required AsyncAction endTrip,
    required SetOtpFn setDriverOtp,

    NavOpener? openGoogleMaps,
    NavOpener? openWazeMap,

    // aliases por compat
    NavOpener? openGoogle,
    NavOpener? openWaze,
    NavOpener? openMap,
  }) {
    _getUserDetails = getUserDetails;
    _getDriverReq = getDriverReq;

    _acceptTrip = acceptTrip;
    _rejectTrip = rejectTrip;
    _driverArrived = driverArrived;
    _startTripOtp = startTripOtp;
    _startTripNoOtp = startTripNoOtp;
    _endTrip = endTrip;
    _setDriverOtp = setDriverOtp;

    _openGoogleMaps = openGoogleMaps ?? openGoogle ?? openMap;
    _openWazeMap = openWazeMap ?? openWaze;
  }

  // ================================================================
  // INIT: respeta que por defecto esté OFF al instalar
  // ================================================================
  Future<void> init(BuildContext context) async {
    await _mem.init();

    final ud = _getUserDetails?.call() ?? <String, dynamic>{};
    _driverId = _safeStr(ud['id']) ?? _driverId ?? '0';

    _enabled = await _mem.isAiEnabled();

    if (!_enabled) {
      uiHint.value = 'IA desactivada';
      // IMPORTANT: no arrancamos poll ni hablamos
      return;
    }

    await _activateCore(resumeFromCurrentState: true);
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;

    _autoRestartTimer?.cancel();
    _autoRestartTimer = null;

    _remindTimer?.cancel();
    _remindTimer = null;

    _autoMode = _AutoListenMode.none;
    try {
      _stt.stop();
    } catch (_) {}

    try {
      _tts.stop();
    } catch (_) {}
  }

  // ================================================================
  // PTT API (lo usa el botón)
  // ================================================================
  Future<void> pttStart() async {
    await _stopAutoListen();

    await _initStt();
    if (!_sttReady) return;

    // si estaba hablando, cortar
    if (_speaking) {
      try {
        await _tts.stop();
      } catch (_) {}
      _speaking = false;
    }

    _pttBuffer = '';
    _pttStartAt = DateTime.now();
    lastHeard.value = '';
    uiHint.value = _enabled ? 'BIP: escuchando (PTT)' : 'IA apagada: decí "activar IA"';
    isListening.value = true;

    try {
      await _stt.listen(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onResult: (r) {
          final w = r.recognizedWords.trim();
          if (w.isEmpty) return;
          lastHeard.value = w;
          _pttBuffer = w;
        },
      );
    } catch (_) {
      isListening.value = false;
      uiHint.value = _enabled ? 'BIP listo' : 'IA desactivada';
    }
  }

  Future<void> pttStopAndProcess() async {
    try {
      await _stt.stop();
    } catch (_) {}
    isListening.value = false;
    uiHint.value = _enabled ? 'BIP listo' : 'IA desactivada';

    await Future.delayed(const Duration(milliseconds: 280));

    final raw = _pttBuffer.trim();
    _pttBuffer = '';

    if (raw.isEmpty) return;
    if (DateTime.now().difference(_pttStartAt).inMilliseconds < 250) return;

    await _handleSpeech(raw, isFinal: true, allowNoBip: true);
  }

  // ================================================================
  // ENABLE/DISABLE por voz
  // ================================================================
  Future<void> _enableAiByVoice() async {
    if (_enabled) {
      await _say('Ya estoy activada.');
      return;
    }

    _enabled = true;
    await _mem.setAiEnabled(true);

    await _activateCore(resumeFromCurrentState: true, sayEnabled: true);
  }

  Future<void> _disableAiByVoice() async {
    if (!_enabled) return;

    // confirmación corta y apagamos TODO
    await _say('Listo. IA desactivada. Vuelven los sonidos normales.');
    _enabled = false;
    await _mem.setAiEnabled(false);

    _pollTimer?.cancel();
    _pollTimer = null;

    await _stopAutoListen();

    try {
      await _tts.stop();
    } catch (_) {}
    uiHint.value = 'IA desactivada';
  }

  Future<void> _activateCore({
    required bool resumeFromCurrentState,
    bool sayEnabled = false,
  }) async {
    await _initTts();
    await _initStt();

    if (sayEnabled) {
      await _say('Dale. Activé la IA.');
    }

    await _greetOnOpen(force: true);

    await _ensureDefaultNavAtStartup();

    if (resumeFromCurrentState) {
      await _primeFromCurrentReq();
    }

    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 900), (_) => _poll());
  }

  // ================================================================
  // TTS
  // ================================================================
  Future<void> _initTts() async {
    if (_ttsReady) return;
    try {
      try {
        await _tts.setLanguage('es-AR');
      } catch (_) {
        await _tts.setLanguage('es-ES');
      }
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.02);
      await _tts.setVolume(1.0);

      _tts.setStartHandler(() {
        _speaking = true;
        try {
          _stt.stop();
        } catch (_) {}
        isListening.value = false;
      });

      _tts.setCompletionHandler(() {
        _speaking = false;
        if (_autoMode != _AutoListenMode.none) {
          _ensureAutoListenSoon(120);
        }
      });

      _tts.setCancelHandler(() {
        _speaking = false;
        if (_autoMode != _AutoListenMode.none) {
          _ensureAutoListenSoon(180);
        }
      });

      _tts.setErrorHandler((_) {
        _speaking = false;
        if (_autoMode != _AutoListenMode.none) {
          _ensureAutoListenSoon(250);
        }
      });

      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
  }

  Future<void> _say(String text, {bool interrupt = true, bool force = false}) async {
    if (!_enabled && !force) return;

    text = text.trim();
    if (text.isEmpty) return;

    await _initTts();
    if (!_ttsReady) return;

    // anti-spam
    final now = DateTime.now();
    if (!force) {
      if (text == _lastSpokenText && now.difference(_lastSpokenAt).inMilliseconds < 1400) return;
    }
    _lastSpokenText = text;
    _lastSpokenAt = now;

    try {
      try {
        _stt.stop();
      } catch (_) {}
      isListening.value = false;

      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  // ================================================================
  // STT init + auto-restart (solo cuando estamos esperando respuesta)
  // ================================================================
  Future<void> _initStt() async {
    if (_sttReady) return;
    try {
      _sttReady = await _stt.initialize(
        onError: (_) {
          if (_autoMode != _AutoListenMode.none && !_speaking) {
            _ensureAutoListenSoon(_restartDelayMs());
          }
        },
        onStatus: (s) {
          final st = s.toLowerCase();
          if ((st == 'done' || st == 'notlistening') &&
              _autoMode != _AutoListenMode.none &&
              !_speaking) {
            _ensureAutoListenSoon(_restartDelayMs());
          }
          if (st == 'listening') {
            isListening.value = true;
          }
        },
      );
    } catch (_) {
      _sttReady = false;
    }
  }

  int _restartDelayMs() {
    final now = DateTime.now();
    if (_restartWindowStart.millisecondsSinceEpoch == 0 ||
        now.difference(_restartWindowStart).inSeconds >= 20) {
      _restartWindowStart = now;
      _restartCount = 0;
    }
    _restartCount++;
    if (_restartCount <= 3) return 140;
    if (_restartCount <= 8) return 280;
    if (_restartCount <= 14) return 520;
    return 950;
  }

  void _ensureAutoListenSoon(int ms) {
    if (!_enabled) return;
    if (_autoMode == _AutoListenMode.none) return;
    if (_speaking) return;

    _autoRestartTimer?.cancel();
    _autoRestartTimer = Timer(Duration(milliseconds: ms), () async {
      _autoRestartTimer = null;
      await _startAutoListenInternal();
    });
  }

  Future<void> _startAutoListen(_AutoListenMode mode) async {
    if (!_enabled) return;
    _autoMode = mode;
    _ensureAutoListenSoon(0);
  }

  Future<void> _stopAutoListen() async {
    _autoMode = _AutoListenMode.none;
    _autoRestartTimer?.cancel();
    _autoRestartTimer = null;
    try {
      await _stt.stop();
    } catch (_) {}
    isListening.value = false;
  }

  Future<void> _startAutoListenInternal() async {
    if (!_enabled) return;
    if (_autoMode == _AutoListenMode.none) return;
    if (_speaking) return;

    await _initStt();
    if (!_sttReady) return;

    if (_stt.isListening) {
      isListening.value = true;
      return;
    }

    uiHint.value = 'BIP: esperando respuesta...';
    isListening.value = true;

    try {
      await _stt.listen(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        onResult: (r) async {
          final w = r.recognizedWords.trim();
          if (w.isEmpty) return;
          lastHeard.value = w;
          await _handleSpeech(w, isFinal: r.finalResult, allowNoBip: true);
        },
      );
    } catch (_) {
      isListening.value = false;
      _ensureAutoListenSoon(_restartDelayMs());
    }
  }

  // ================================================================
  // PRIME: al abrir/activar IA, NO tratar un viaje ya aceptado como "nuevo"
  // ================================================================
  Future<void> _primeFromCurrentReq() async {
    final req = _getDriverReq?.call() ?? <String, dynamic>{};
    final tripId = _safeStr(req['id']);

    if (tripId == null || tripId.isEmpty) {
      _lastTripId = null;
      _lastTripStateHash = 0;
      _navAnsweredKeys.clear();
      return;
    }

    _lastTripId = tripId;
    _lastTripStateHash = _hashTripState(req);

    final acceptedAt = _safeStr(req['accepted_at']);
    final started = _asBool(req['is_trip_start']) == true;
    final arrived = _asBool(req['is_driver_arrived']) == true;

    // ✅ Si NO está aceptado todavía => es un viaje realmente nuevo
    if (acceptedAt == null || acceptedAt.isEmpty) {
      _navAnsweredKeys.clear();
      await _onNewTrip(req);
      return;
    }

    // ✅ Ya estaba aceptado: NO preguntar aceptar/rechazar
    _awaitingAcceptReject = false;
    _awaitingNavYesNo = false;
    _pendingNav = null;
    _cancelReminders();
    await _stopAutoListen();

    if (started) {
      await _say('Ya tenés un viaje en curso. Si querés, decime abrir navegador o finalizar viaje.');
    } else if (arrived) {
      await _say('Ya estás marcado como llegado. Cuando estés listo, decime iniciar viaje.');
    } else {
      await _say('Tenés un viaje aceptado. Vas a buscar al cliente. Si querés GPS, decime abrir navegador.');
    }
  }

  // ================================================================
  // Polling: detectar nuevo viaje + cambios
  // ================================================================
  Future<void> _poll() async {
    if (!_enabled) return;

    final req = _getDriverReq?.call() ?? <String, dynamic>{};
    final tripId = _safeStr(req['id']);

    // si no hay viaje
    if (tripId == null || tripId.isEmpty) {
      _lastTripId = null;
      _lastTripStateHash = 0;
      return;
    }

    // Nuevo ID
    if (tripId != _lastTripId) {
      _lastTripId = tripId;
      _lastTripStateHash = _hashTripState(req);

      final acceptedAt = _safeStr(req['accepted_at']);
      // ✅ solo es "nuevo viaje" si no está aceptado
      if (acceptedAt == null || acceptedAt.isEmpty) {
        _navAnsweredKeys.clear();
        await _onNewTrip(req);
      } else {
        await _onTripStateChange(req);
      }
      return;
    }

    // mismo ID, ver cambios
    final h = _hashTripState(req);
    if (h != _lastTripStateHash) {
      _lastTripStateHash = h;
      await _onTripStateChange(req);
    }
  }

  int _hashTripState(Map<String, dynamic> req) {
    final accepted = _safeStr(req['accepted_at']) ?? '';
    final started = '${req['is_trip_start']}';
    final arrived = '${req['is_driver_arrived']}';
    final done = '${req['is_completed']}';
    final cancel = '${req['is_cancelled']}';
    return Object.hash(accepted, started, arrived, done, cancel);
  }

  // ================================================================
  // Viaje: habla SIEMPRE
  // ================================================================
  Future<void> _onNewTrip(Map<String, dynamic> req) async {
    _awaitingAcceptReject = true;
    _awaitingNavYesNo = false;
    _pendingNav = null;

    _triesAcceptReject = 0;
    _scheduleReminderAcceptReject();

    await _say('Te llegó un viaje nuevo. ¿Querés aceptar o rechazar? Decime aceptar o rechazar.');
    await _startAutoListen(_AutoListenMode.acceptReject);
  }

  Future<void> _onTripStateChange(Map<String, dynamic> req) async {
    if (_asBool(req['is_cancelled']) == true || _asBool(req['is_cancelled_by_user']) == true) {
      _awaitingAcceptReject = false;
      _awaitingNavYesNo = false;
      _pendingNav = null;
      _cancelReminders();
      await _stopAutoListen();
      await _say('Atención. El viaje fue cancelado.');
      return;
    }

    if (_asBool(req['is_completed']) == true) {
      _awaitingAcceptReject = false;
      _awaitingNavYesNo = false;
      _pendingNav = null;
      _cancelReminders();
      await _stopAutoListen();
      await _say('Listo. Viaje finalizado.');
      return;
    }
  }

  // ================================================================
  // Startup: nav por defecto (1 vez)
  // ================================================================
  Future<void> _ensureDefaultNavAtStartup() async {
    if (_startupNavChecked) return;
    _startupNavChecked = true;

    final driverId = _driverId ?? '0';
    final pref = await _mem.getPreferredNavAppOrNull(driverId);
    if (pref != null) return;

    _awaitingStartupNavPick = true;
    _triesStartupNav = 0;
    _scheduleReminderStartupNav();

    await _say('Antes de arrancar, ¿qué navegador querés usar por defecto? Decime Waze o Google Maps.');
    await _startAutoListen(_AutoListenMode.startupNavPick);
  }

  // ================================================================
  // Reminders / retries (máx 3)
  // ================================================================
  void _cancelReminders() {
    _remindTimer?.cancel();
    _remindTimer = null;
  }

  void _scheduleReminderAcceptReject() {
    _remindTimer?.cancel();
    _remindTimer = Timer(const Duration(seconds: 8), () async {
      if (!_awaitingAcceptReject || _autoMode != _AutoListenMode.acceptReject) return;
      if (_triesAcceptReject >= 3) {
        _awaitingAcceptReject = false;
        await _stopAutoListen();
        await _say('No te entendí. Si querés, apretá el mic y decime aceptar o rechazar.');
        return;
      }
      _triesAcceptReject++;
      await _say('¿Aceptás o rechazás? Decime aceptar o rechazar.');
      _scheduleReminderAcceptReject();
    });
  }

  void _scheduleReminderNav() {
    _remindTimer?.cancel();
    _remindTimer = Timer(const Duration(seconds: 10), () async {
      if (!_awaitingNavYesNo || _autoMode != _AutoListenMode.navYesNo) return;

      final key = _pendingNavKey();
      if (key != null && _navAnsweredKeys.contains(key)) {
        _awaitingNavYesNo = false;
        _pendingNav = null;
        await _stopAutoListen();
        return;
      }

      if (_triesNav >= 3) {
        _awaitingNavYesNo = false;
        _pendingNav = null;
        await _stopAutoListen();
        await _say('Ok. Si querés abrir después, apretá el mic y decí: abrir navegador.');
        return;
      }
      _triesNav++;
      await _say('¿Querés que abra el navegador? Decime sí o no. También podés decir Waze o Google.');
      _scheduleReminderNav();
    });
  }

  void _scheduleReminderStartupNav() {
    _remindTimer?.cancel();
    _remindTimer = Timer(const Duration(seconds: 10), () async {
      if (!_awaitingStartupNavPick || _autoMode != _AutoListenMode.startupNavPick) return;
      if (_triesStartupNav >= 3) {
        _awaitingStartupNavPick = false;
        final driverId = _driverId ?? '0';
        await _mem.setPreferredNavApp(driverId, BipNavApp.waze);
        await _stopAutoListen();
        await _say('No te entendí. Dejo Waze por defecto.');
        return;
      }
      _triesStartupNav++;
      await _say('Decime cuál querés: Waze o Google Maps.');
      _scheduleReminderStartupNav();
    });
  }

  // ================================================================
  // Speech routing
  // ================================================================
  Future<void> _handleSpeech(String raw, {required bool isFinal, required bool allowNoBip}) async {
    final text = _norm(raw);
    if (text.isEmpty) return;

    // Si IA está apagada: solo permitimos activar IA (y ayuda mínima)
    if (!_enabled) {
      if (_containsAny(text, _enableSynonyms)) {
        await _enableAiByVoice();
      }
      return;
    }

    final driverId = _driverId ?? '0';
    final learnedIntent = await _mem.getIntentForPhrase(driverId, text);

    // Startup: elegir nav por defecto
    if (_awaitingStartupNavPick && _autoMode == _AutoListenMode.startupNavPick) {
      final app = _parseNavApp(text) ??
          (learnedIntent == 'waze' ? BipNavApp.waze : learnedIntent == 'google' ? BipNavApp.google : null);

      if (app != null) {
        _awaitingStartupNavPick = false;
        _cancelReminders();
        await _mem.setPreferredNavApp(driverId, app);
        await _stopAutoListen();
        await _say('Listo. Queda ${app == BipNavApp.waze ? 'Waze' : 'Google Maps'} por defecto.');
      } else if (isFinal) {
        _learnCandidatePhrase = text;
        await _say('No entendí. Decime Waze o Google.');
        _triesStartupNav++;
      }
      return;
    }

    // Nuevo viaje: aceptar/rechazar
    if (_awaitingAcceptReject && _autoMode == _AutoListenMode.acceptReject) {
      final intent = _parseAcceptRejectIntent(text, learnedIntent);

      if (intent == 'accept') {
        _awaitingAcceptReject = false;
        _cancelReminders();
        await _stopAutoListen();
        await _rememberCandidateIfAny('accept');
        await _doAccept(_getDriverReq?.call() ?? {});
        return;
      }

      if (intent == 'reject') {
        _awaitingAcceptReject = false;
        _cancelReminders();
        await _stopAutoListen();
        await _rememberCandidateIfAny('reject');
        await _doReject();
        return;
      }

      if (isFinal) {
        _triesAcceptReject++;
        _learnCandidatePhrase = text;

        if (_triesAcceptReject <= 3) {
          await _say('No te entendí. Decime aceptar o rechazar.');
        } else {
          _awaitingAcceptReject = false;
          await _stopAutoListen();
          await _say('No te entendí. Apretá el mic y decime aceptar o rechazar.');
        }
      }
      return;
    }

    // Navegador: sí/no + waze/google
    if (_awaitingNavYesNo && _autoMode == _AutoListenMode.navYesNo && _pendingNav != null) {
      final yesNo = _parseYesNo(text, learnedIntent);
      final override = _parseNavApp(text) ??
          (learnedIntent == 'waze' ? BipNavApp.waze : learnedIntent == 'google' ? BipNavApp.google : null);

      final wantsOpen = (yesNo == _YesNo.yes) || (override != null && yesNo != _YesNo.no);

      final key = _pendingNavKey();
      if (key != null && _navAnsweredKeys.contains(key)) {
        _awaitingNavYesNo = false;
        _cancelReminders();
        await _stopAutoListen();
        _pendingNav = null;
        return;
      }

      if (wantsOpen) {
        _awaitingNavYesNo = false;
        _cancelReminders();
        await _stopAutoListen();

        final pref = await _mem.getPreferredNavApp(driverId);
        final chosen = override ?? pref;

        await _mem.setPreferredNavApp(driverId, chosen);
        await _rememberCandidateIfAny(chosen == BipNavApp.waze ? 'waze' : 'google');

        if (key != null) _navAnsweredKeys.add(key);

        final p = _pendingNav!;
        _pendingNav = null;

        await _say('Dale. Abriendo ${chosen == BipNavApp.waze ? 'Waze' : 'Google Maps'}.');
        await _openNav(chosen, p.lat, p.lng);
        return;
      }

      if (yesNo == _YesNo.no) {
        _awaitingNavYesNo = false;
        _cancelReminders();
        await _stopAutoListen();
        await _rememberCandidateIfAny('no');

        if (key != null) _navAnsweredKeys.add(key);

        _pendingNav = null;
        await _say('Listo. No abro navegador.');
        return;
      }

      if (isFinal) {
        _triesNav++;
        _learnCandidatePhrase = text;
        if (_triesNav <= 3) {
          await _say('No entendí. Decime sí o no. También podés decir Waze o Google.');
        } else {
          _awaitingNavYesNo = false;
          await _stopAutoListen();
          await _say('Ok. Si querés, apretá el mic y decí: abrir navegador.');
        }
      }
      return;
    }

    // Comandos normales (PTT o auto). Permitimos sin "bip" si allowNoBip == true
    await _handleCommand(text, allowNoBip: allowNoBip);
  }

  String? _pendingNavKey() {
    final p = _pendingNav;
    final tripId = _lastTripId;
    if (p == null || tripId == null || tripId.isEmpty) return null;
    final t = p.target == _NavTarget.pickup ? 'pickup' : 'drop';
    return '$tripId:$t';
  }

  Future<void> _rememberCandidateIfAny(String resolvedIntent) async {
    final driverId = _driverId ?? '0';
    if (_learnCandidatePhrase == null) return;
    final phrase = _learnCandidatePhrase!.trim();
    if (phrase.length < 3) return;

    await _mem.rememberPhrase(driverId, phrase, resolvedIntent);
    _learnCandidatePhrase = null;
  }

  Future<void> _handleCommand(String text, {required bool allowNoBip}) async {
    final hasWake = _containsAny(text, ['bip', 'bia', 'vip', 'pip']);
    var cmd = text;

    if (hasWake) {
      cmd = cmd
          .replaceAll('bip', '')
          .replaceAll('bia', '')
          .replaceAll('vip', '')
          .replaceAll('pip', '')
          .trim();
    } else if (!allowNoBip) {
      return;
    }

    if (cmd.isEmpty) return;

    // ======= Toggle IA =======
    if (_containsAny(cmd, _disableSynonyms)) {
      await _disableAiByVoice();
      return;
    }
    if (_containsAny(cmd, _enableSynonyms)) {
      await _enableAiByVoice();
      return;
    }

    // ayuda
    if (_containsAny(cmd, ['ayuda', 'comandos', 'que puedo decir', 'que hago'])) {
      await _say(
        'Comandos: aceptar, rechazar, llegué, iniciar viaje, iniciar viaje OTP 1234, finalizar. '
        'Navegador: decí "usa Waze" o "usa Google" para dejarlo por defecto. '
        'También: "abrir navegador". '
        'IA: decí "desactivar IA" o "activar IA".',
      );
      return;
    }

    // cambiar navegador por defecto
    if (_containsAny(cmd, ['usa waze', 'poné waze', 'pone waze', 'waze por defecto'])) {
      await _mem.setPreferredNavApp(_driverId ?? '0', BipNavApp.waze);
      await _say('Listo. Waze queda por defecto.');
      return;
    }
    if (_containsAny(cmd, ['usa google', 'usa google maps', 'google por defecto', 'maps por defecto'])) {
      await _mem.setPreferredNavApp(_driverId ?? '0', BipNavApp.google);
      await _say('Listo. Google Maps queda por defecto.');
      return;
    }

    // abrir navegador (manual) - NO marca answered; es manual
    if (_containsAny(cmd, ['abrir navegador', 'abre navegador', 'abrir maps', 'abrir waze', 'navegador'])) {
      final req = _getDriverReq?.call() ?? <String, dynamic>{};
      final started = _asBool(req['is_trip_start']) == true;
      await _askNavIfWanted(req, started ? _NavTarget.drop : _NavTarget.pickup, forceAsk: true);
      return;
    }

    // acciones manuales
    final req = _getDriverReq?.call() ?? <String, dynamic>{};
    if (_containsAny(cmd, _acceptSynonyms)) {
      await _doAccept(req);
      return;
    }
    if (_containsAny(cmd, _rejectSynonyms)) {
      await _doReject();
      return;
    }
    if (_containsAny(cmd, _arrivedSynonyms)) {
      await _doArrived();
      return;
    }
    if (_containsAny(cmd, _startSynonyms)) {
      final otp = _extractOtp(cmd);
      await _doStartTrip(req, otp: otp);
      return;
    }
    if (_containsAny(cmd, _endSynonyms)) {
      await _doEndTrip();
      return;
    }

    await _say('No entendí. Decime: BIP ayuda.');
  }

  // ================================================================
  // Actions
  // ================================================================
  Future<void> _doAccept(Map<String, dynamic> req) async {
    final fn = _acceptTrip;
    if (fn == null) {
      await _say('No tengo la acción de aceptar configurada.');
      return;
    }

    final res = await fn.call();
    if (_isSuccess(res)) {
      await _say('Listo. Viaje aceptado. Ahora vamos a buscar al cliente.');
      await _askNavIfWanted(req, _NavTarget.pickup);
    } else {
      await _say('No pude aceptar.');
    }
  }

  Future<void> _doReject() async {
    final fn = _rejectTrip;
    if (fn == null) {
      await _say('No tengo la acción de rechazar configurada.');
      return;
    }

    final res = await fn.call();
    if (_isSuccess(res)) {
      await _say('Listo. Viaje rechazado.');
    } else {
      await _say('No pude rechazar.');
    }
  }

  Future<void> _doArrived() async {
    final fn = _driverArrived;
    if (fn == null) {
      await _say('No tengo la acción de llegada configurada.');
      return;
    }

    final res = await fn.call();
    if (_isSuccess(res)) {
      await _say('Perfecto. Marcado como llegado. Cuando estés listo, decime iniciar viaje.');
    } else {
      await _say('No pude marcar llegada.');
    }
  }

  Future<void> _doStartTrip(Map<String, dynamic> req, {String? otp}) async {
    final needsOtp = _asBool(req['show_otp_feature']) == true;

    if (needsOtp) {
      if (otp == null || otp.isEmpty) {
        await _say('Necesito el OTP. Decime: iniciar viaje OTP 1 2 3 4.');
        return;
      }
      _setDriverOtp?.call(otp);
      final res = await _startTripOtp?.call();
      if (_isSuccess(res)) {
        await _say('Viaje iniciado. Vamos al destino.');
        await _askNavIfWanted(req, _NavTarget.drop);
      } else {
        await _say('No pude iniciar. Revisá OTP.');
      }
      return;
    }

    final res = await _startTripNoOtp?.call();
    if (_isSuccess(res)) {
      await _say('Viaje iniciado. Vamos al destino.');
      await _askNavIfWanted(req, _NavTarget.drop);
    } else {
      await _say('No pude iniciar el viaje.');
    }
  }

  Future<void> _doEndTrip() async {
    final fn = _endTrip;
    if (fn == null) {
      await _say('No tengo la acción de finalizar configurada.');
      return;
    }

    final res = await fn.call();
    if (_isSuccess(res)) {
      await _say('Listo. Viaje finalizado.');
    } else {
      await _say('No pude finalizar.');
    }
  }

  // ================================================================
  // Navegación (sí/no) + anti-repetición
  // ================================================================
  Future<void> _askNavIfWanted(Map<String, dynamic> req, _NavTarget target, {bool forceAsk = false}) async {
    final lat = _toDouble(target == _NavTarget.pickup ? req['pick_lat'] : req['drop_lat']);
    final lng = _toDouble(target == _NavTarget.pickup ? req['pick_lng'] : req['drop_lng']);
    if (lat == null || lng == null) return;

    final tripId = _safeStr(req['id']) ?? _lastTripId;
    if (!forceAsk && tripId != null && tripId.isNotEmpty) {
      final key = '$tripId:${target == _NavTarget.pickup ? 'pickup' : 'drop'}';
      if (_navAnsweredKeys.contains(key)) return;
    }

    if (!forceAsk && _awaitingNavYesNo) return;

    _pendingNav = _PendingNav(target: target, lat: lat, lng: lng);
    _awaitingNavYesNo = true;
    _triesNav = 0;

    final where = target == _NavTarget.pickup ? 'para ir a buscar al cliente' : 'para ir al destino';
    _scheduleReminderNav();

    await _say('¿Querés que abra el navegador $where? Decime sí o no. También podés decir Waze o Google.');
    await _startAutoListen(_AutoListenMode.navYesNo);
  }

  Future<void> _openNav(BipNavApp app, double lat, double lng) async {
    if (app == BipNavApp.waze) {
      final fn = _openWazeMap;
      if (fn != null) return fn(lat, lng);
      await _say('No tengo Waze configurado.');
      return;
    }
    final fn = _openGoogleMaps;
    if (fn != null) return fn(lat, lng);
    await _say('No tengo Google Maps configurado.');
  }

  // ================================================================
  // Saludo
  // ================================================================
  Future<void> _greetOnOpen({bool force = false}) async {
    if (_greeted && !force) return;
    _greeted = true;

    final h = DateTime.now().hour;
    final greet = (h >= 5 && h < 12)
        ? 'Buen día'
        : (h >= 12 && h < 20)
            ? 'Buenas tardes'
            : 'Buenas noches';

    await _say('$greet. Soy BIP.', force: true);
  }

  // ================================================================
  // Intent parsing + synonyms
  // ================================================================
  static const List<String> _acceptSynonyms = [
    'aceptar', 'aceptalo', 'aceptalo ya', 'acepto', 'dale', 'de una', 'ok', 'listo',
    'tomalo', 'agarralo', 'agarra', 'vamos', 'mandale', 'metele'
  ];

  static const List<String> _rejectSynonyms = [
    'rechazar', 'rechazalo', 'rechazo', 'cancelar', 'cancela', 'paso', 'siguiente',
    'no quiero', 'dejalo', 'ni loco', 'ni en pedo'
  ];

  static const List<String> _arrivedSynonyms = [
    'llegue', 'llegué', 'estoy afuera', 'estoy aqui', 'estoy aca', 'toy aca', 'toy aqui', 'en la puerta'
  ];

  static const List<String> _startSynonyms = [
    'iniciar viaje', 'inicia viaje', 'arranca', 'arrancar', 'empeza', 'empezar', 'comenza', 'comenzar',
    'iniciar', 'inicia'
  ];

  static const List<String> _endSynonyms = [
    'finalizar', 'finaliza', 'terminar', 'termina', 'cortar', 'cortalo', 'fin', 'final'
  ];

  static const List<String> _disableSynonyms = [
    'no usar ia', 'desactivar ia', 'desactiva ia', 'apaga ia', 'silencio', 'no hable', 'no hables', 'no hables mas', 'no hable mas'
  ];

  static const List<String> _enableSynonyms = [
    'activar ia', 'activa ia', 'prende ia', 'habla bip', 'usa ia', 'comenza usa ia', 'comenza', 'comenzar ia'
  ];

  String _parseAcceptRejectIntent(String text, String? learnedIntent) {
    if (learnedIntent == 'accept') return 'accept';
    if (learnedIntent == 'reject') return 'reject';

    if (_containsAny(text, _acceptSynonyms)) return 'accept';
    if (_containsAny(text, _rejectSynonyms)) return 'reject';

    if (text.contains('acep')) return 'accept';
    if (text.contains('rech') || text.contains('canc')) return 'reject';

    return 'unknown';
  }

  _YesNo _parseYesNo(String text, String? learnedIntent) {
    if (learnedIntent == 'yes') return _YesNo.yes;
    if (learnedIntent == 'no') return _YesNo.no;

    if (_containsAny(text, [
      'si', 'sí', 'dale', 'ok', 'de una', 'mandale', 'metele', 'abrilo', 'abrir', 'abra', 'vamos',
      'claro', 'obvio', 'por supuesto',
    ])) return _YesNo.yes;

    if (_containsAny(text, [
      'no', 'nah', 'despues', 'después', 'no hace falta', 'no quiero', 'ni ahi', 'ni ahí',
    ])) return _YesNo.no;

    return _YesNo.unknown;
  }

  BipNavApp? _parseNavApp(String text) {
    if (_containsAny(text, ['waze', 'guaze', 'ways', 'weis', 'wase', 'uase', 'uaze', 'weys'])) return BipNavApp.waze;
    if (_containsAny(text, ['google', 'gogle', 'gugle', 'google maps', 'maps', 'mapas', 'mapa', 'g maps', 'gmap'])) {
      return BipNavApp.google;
    }
    return null;
  }

  // ================================================================
  // Parsing helpers
  // ================================================================
  bool _isSuccess(dynamic res) {
    final s = (res ?? '').toString().toLowerCase().trim();
    return s == 'true' || s.contains('success') || s.contains('ok');
  }

  bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  String? _safeStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _norm(String s) {
    s = s.toLowerCase().trim();
    const rep = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    rep.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  bool _containsAny(String text, List<String> tokens) {
    final t = _norm(text);
    for (final raw in tokens) {
      if (t.contains(_norm(raw))) return true;
    }
    return false;
  }

  String? _extractOtp(String text) {
    final t = _norm(text);
    final m = RegExp(r'otp\s+([0-9 ]{3,10})').firstMatch(t);
    if (m == null) return null;
    final raw = m.group(1) ?? '';
    final digits = raw.replaceAll(' ', '');
    if (digits.length < 3) return null;
    return digits;
  }
}

class _PendingNav {
  final _NavTarget target;
  final double lat;
  final double lng;
  _PendingNav({required this.target, required this.lat, required this.lng});
}

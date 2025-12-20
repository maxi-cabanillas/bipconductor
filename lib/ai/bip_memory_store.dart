// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum BipNavApp { waze, google }

class BipMemoryStore {
  BipMemoryStore._();
  static final BipMemoryStore instance = BipMemoryStore._();

  SharedPreferences? _pref;

  Future<void> init() async {
    _pref ??= await SharedPreferences.getInstance();
  }

  // =========================
  // IA enable/disable (DEFAULT: OFF)
  // =========================
  static const String _kAiEnabled = 'bip_ai_enabled';

  Future<bool> isAiEnabled() async {
    await init();
    // ✅ Si no existe, por defecto es FALSE (IA desactivada al instalar)
    return _pref?.getBool(_kAiEnabled) ?? false;
  }

  Future<void> setAiEnabled(bool enabled) async {
    await init();
    await _pref?.setBool(_kAiEnabled, enabled);
  }

  // =========================
  // Navegador por defecto
  // =========================
  String _kNavPref(String driverId) => 'bip_nav_pref_$driverId';

  Future<BipNavApp> getPreferredNavApp(String driverId) async {
    await init();
    final v = _pref?.getString(_kNavPref(driverId));
    if (v == 'google') return BipNavApp.google;
    return BipNavApp.waze;
  }

  Future<BipNavApp?> getPreferredNavAppOrNull(String driverId) async {
    await init();
    final v = _pref?.getString(_kNavPref(driverId));
    if (v == null) return null;
    if (v == 'google') return BipNavApp.google;
    if (v == 'waze') return BipNavApp.waze;
    return null;
  }

  Future<void> setPreferredNavApp(String driverId, BipNavApp app) async {
    await init();
    await _pref?.setString(_kNavPref(driverId), app == BipNavApp.google ? 'google' : 'waze');
  }

  // =========================
  // Aprendizaje: frase -> intent
  // =========================
  String _kIntentMap(String driverId) => 'bip_phrase_intents_$driverId';

  String _norm(String s) {
    s = s.toLowerCase().trim();
    const rep = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    rep.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  Future<String?> getIntentForPhrase(String driverId, String phrase) async {
    await init();
    final key = _kIntentMap(driverId);
    final raw = _pref?.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[_norm(phrase)]?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> rememberPhrase(String driverId, String phrase, String intent) async {
    await init();
    final key = _kIntentMap(driverId);
    Map<String, dynamic> map = {};
    final raw = _pref?.getString(key);

    if (raw != null && raw.isNotEmpty) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        map = {};
      }
    }

    map[_norm(phrase)] = intent;
    await _pref?.setString(key, jsonEncode(map));
  }
}

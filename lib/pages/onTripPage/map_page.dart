// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
// import 'package:dash_bubble/dash_bubble.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/pages/login/landingpage.dart';
import 'package:flutter_driver/pages/login/login.dart';
import 'package:flutter_driver/pages/onTripPage/droplocation.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:quick_nav/quick_nav.dart';
import 'package:vector_math/vector_math.dart' as vector;
import 'dart:io';
import '../../functions/functions.dart';
import '../../functions/geohash.dart';
import '../../functions/notifications.dart';
import '../../styles/styles.dart';
import '../../translation/translation.dart';
import '../../widgets/widgets.dart';
import '../NavigatorPages/notification.dart';
import '../NavigatorPages/withdraw.dart';
import '../NavigatorPages/driverearnings.dart';
import '../NavigatorPages/history.dart';
import '../chatPage/chat_page.dart';
import '../loadingPage/loading.dart';
import '../navDrawer/nav_drawer.dart';
import '../noInternet/nointernet.dart';
import '../vehicleInformations/docs_onprocess.dart';
import 'digitalsignature.dart';
import 'invoice.dart';
import 'rides.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
// ignore: depend_on_referenced_packages
import 'package:latlong2/latlong.dart' as fmlt;
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

class Maps extends StatefulWidget {
  const Maps({super.key});

  @override
  State<Maps> createState() => _MapsState();
}

dynamic _center = const LatLng(41.4219057, -102.0840772);
dynamic center;
bool locationAllowed = false;

List<Marker> myMarkers = [];
Set<Circle> circles = {};
bool polylineGot = false;

dynamic _timer;
String cancelReasonText = '';
bool notifyCompleted = false;
bool logout = false;
bool deleteAccount = false;
bool getStartOtp = false;
dynamic shipLoadImage;
dynamic shipUnloadImage;
bool unloadImage = false;
String driverOtp = '';
bool serviceEnabled = false;
bool show = true;

int filtericon = 0;
dynamic isAvailable;
List vechiletypeslist = [];
List<fmlt.LatLng> fmpoly = [];

class _MapsState extends State<Maps>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List driverData = [];
  double _isbottom = -1000;

  bool sosLoaded = false;
  bool cancelRequest = false;
  bool _pickAnimateDone = false;
  dynamic addressBottom;
  dynamic _addressBottom;
  bool fmPolyGot = false;
  late geolocator.LocationPermission permission;
  Location location = Location();
  String state = '';
  dynamic _controller;

  // --- Live tracking (follow car like Uber/DiDi) ---
  StreamSubscription<geolocator.Position>? _livePosSub;
  bool _followDriver = true;
  int _lastTripStartValueMemo = -999;


  // Uber/Didi style: rotate camera to driver heading and keep the car icon pointing "forward" (up) on screen.
  bool _followBearing = true; // false when user moves the map manually
  double _currentZoom = 18.0;
  double _cameraBearing = 0.0; // last applied camera bearing (deg)
  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _prevDriverLatLng;

  final fm.MapController _fmController = fm.MapController();
  Animation<double>? _animation;
  // UI: animación del texto "BUSCANDO VIAJE" (solo estética)
  late final AnimationController _bippSearchingCtrl;
  late final AnimationController _bippLaserCtrl;

  // BIP: cache/refresh de stats de hoy (viajes + ganancia) para el panel superior
  int _bippLastTodayStatsFetchMs = 0;
  bool _bippTodayStatsFetchInFlight = false;


  dynamic animationController;
  String _cancellingError = '';
  double mapPadding = 0.0;
  var iconDropKeys = {};
  String _cancelReason = '';
  bool _locationDenied = false;
  int gettingPerm = 0;
  bool _errorOtp = false;
  String beforeImageUploadError = '';
  String afterImageUploadError = '';
  dynamic loc;
  String _otp1 = '';
  String _otp2 = '';
  String _otp3 = '';
  String _otp4 = '';
  bool showSos = false;
  bool _showWaitingInfo = false;
  bool _isLoading = false;
  bool _reqCancelled = false;
  bool navigated = false;
  dynamic pinLocationIcon;
  dynamic pinLocationIcon2;
  dynamic pinLocationIcon3;
  dynamic userLocationIcon;
  bool makeOnline = false;
  bool contactus = false;
  GlobalKey iconKey = GlobalKey();
  GlobalKey iconDropKey = GlobalKey();
  List gesture = [];
  dynamic start;
  dynamic onrideicon;
  dynamic onridedeliveryicon;
  dynamic offlineicon;
  dynamic offlinedeliveryicon;
  dynamic onlineicon;
  dynamic onlinedeliveryicon;
  dynamic onridebikeicon;
  dynamic offlinebikeicon;
  dynamic onlinebikeicon;
  bool navigationtype = false;
  bool currentpage = true;
  bool _tripOpenMap = false;
  bool _isDarkTheme = false;

  // --- Vehicle marker heading ---
  // vehicle-marker.png in this project is drawn with the FRONT pointing UP.
  // So we use 0° offset.
  static const double _kVehicleRotationOffsetDeg = 0.0;

  double _vehicleRotationDeg(double rawDeg) {
    final v = (rawDeg + _kVehicleRotationOffsetDeg) % 360.0;
    return (v < 0) ? (v + 360.0) : v;
  }

  // --- Google-style blue navigation arrow for the driver's own marker (instead of vehicle-marker.png) ---
  BitmapDescriptor? _driverGoogleArrowIcon;

  // --- Waze-like FLAG icons for pickup/destination (Google Maps) ---
  BitmapDescriptor? _pickupFlagIcon;
  BitmapDescriptor? _dropFlagIcon;

  // Cache de íconos para paradas (1,2,3...)
  final Map<int, BitmapDescriptor> _stopIconCache = {};

  Future<BitmapDescriptor> _drawFlagIcon({
    required Color color,
    required String label,
  }) async {
    const int size = 140; // px
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size / 2;
    final cy = size * 0.42;
    final r = size * 0.22;
    final tailH = size * 0.26;
    final tailW = size * 0.16;

    final pinPath = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r))
      ..moveTo(cx - tailW / 2, cy + r - 2)
      ..lineTo(cx + tailW / 2, cy + r - 2)
      ..lineTo(cx, cy + r + tailH)
      ..close();

    // Shadow
    canvas.drawShadow(pinPath, Colors.black.withOpacity(0.50), 6, true);

    // Pin fill + border
    canvas.drawPath(pinPath, fillPaint);
    canvas.drawPath(pinPath, borderPaint);

    // Inner disc
    final innerPaint = Paint()..color = Colors.white.withOpacity(0.92);
    final innerR = r * 0.72;
    canvas.drawCircle(Offset(cx, cy), innerR, innerPaint);

    // Flag glyph (same color as pin)
    final glyphPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final poleX = cx - innerR * 0.25;
    final poleTop = cy - innerR * 0.55;
    final poleBottom = cy + innerR * 0.55;
    final poleW = size * 0.06;

    final pole = RRect.fromRectAndRadius(
      Rect.fromLTWH(poleX, poleTop, poleW, poleBottom - poleTop),
      Radius.circular(poleW / 2),
    );
    canvas.drawRRect(pole, glyphPaint);

    final flagY = cy - innerR * 0.45;
    final flagH = innerR * 0.55;
    final flagW = innerR * 0.65;

    final flag1 = Path()
      ..moveTo(poleX + poleW, flagY)
      ..lineTo(poleX + poleW + flagW, flagY + flagH * 0.22)
      ..lineTo(poleX + poleW, flagY + flagH * 0.44)
      ..close();
    canvas.drawPath(flag1, glyphPaint);

    final flag2 = Path()
      ..moveTo(poleX + poleW, flagY + flagH * 0.46)
      ..lineTo(poleX + poleW + flagW * 0.75, flagY + flagH * 0.66)
      ..lineTo(poleX + poleW, flagY + flagH * 0.86)
      ..close();
    canvas.drawPath(flag2, glyphPaint);

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xEBFFFFFF),
          fontSize: 48,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.toDouble());
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + innerR * 0.1));

    final picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return BitmapDescriptor.fromBytes(bytes);
  }



  Future<BitmapDescriptor> _drawStopIcon({required int stopNumber}) async {
    final cached = _stopIconCache[stopNumber];
    if (cached != null) return cached;

    try {
      const int size = 120; // px
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      final center = Offset(size / 2, size / 2);

      // Sombra suave
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      // Borde + relleno
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      // Morado del proyecto (igual al de la ruta)
      const fillColor = Color(0xFF6A1B9A);
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center.translate(0, 2), size * 0.42, shadowPaint);
      canvas.drawCircle(center, size * 0.44, borderPaint);
      canvas.drawCircle(center, size * 0.38, fillPaint);

      // Número
      final tp = TextPainter(
        text: TextSpan(
          text: stopNumber.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w800,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

      final picture = recorder.endRecording();
      final img = await picture.toImage(size, size);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      }
      final bytes = byteData.buffer.asUint8List();
      final icon = BitmapDescriptor.fromBytes(bytes);
      _stopIconCache[stopNumber] = icon;
      return icon;
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
  }

  Future<void> _ensureFlagIcons() async {
    // Evita trabajo repetido
    if (_pickupFlagIcon != null && _dropFlagIcon != null) return;

    // 1) Intentar cargar assets (rápido + consistente)
    try {
      const cfg = ImageConfiguration(size: Size(96, 96));
      _pickupFlagIcon ??= await BitmapDescriptor.fromAssetImage(
        cfg,
        'assets/images/flag_pickup.png',
      );
      _dropFlagIcon ??= await BitmapDescriptor.fromAssetImage(
        cfg,
        'assets/images/flag_dropoff.png',
      );
    } catch (_) {
      // Si falla el asset, seguimos a fallback dibujado
    }

    // 2) Fallback: íconos dibujados (por si el asset no está en pubspec o falla en runtime)
    _pickupFlagIcon ??= await _drawFlagIcon(
      color: const Color(0xFF00C853),
      label: 'Recogida',
    );
    _dropFlagIcon ??= await _drawFlagIcon(
      color: const Color(0xFFD50000),
      label: 'Destino',
    );

  }



  Future<void> _ensureDriverGoogleArrowIcon() async {
    if (_driverGoogleArrowIcon != null) return;

    const int size = 110; // px (sharp enough on most screens)
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double s = size.toDouble();

    // Shadow
    final Paint shadow = Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10);

    // Outer (white) shape
    final Paint outer = Paint()..color = Colors.white;

    // Inner (Google blue) shape
    final Paint inner = Paint()..color = const Color(0xFF1A73E8);

    // Arrow path (points UP by default)
    final Path arrow = Path()
      ..moveTo(s * 0.50, s * 0.06)
      ..lineTo(s * 0.88, s * 0.92)
      ..lineTo(s * 0.50, s * 0.76)
      ..lineTo(s * 0.12, s * 0.92)
      ..close();

    // Draw shadow (slight down-right)
    canvas.save();
    canvas.translate(2, 3);
    canvas.drawPath(arrow, shadow);
    canvas.restore();

    // Draw white border by drawing a slightly larger arrow behind
    canvas.save();
    canvas.translate(s * 0.50, s * 0.55);
    canvas.scale(1.06, 1.06);
    canvas.translate(-s * 0.50, -s * 0.55);
    canvas.drawPath(arrow, outer);
    canvas.restore();

    // Draw blue arrow on top
    canvas.drawPath(arrow, inner);

    // Tiny highlight (gives a "Google" feel)
    final Paint highlight = Paint()
      ..color = const Color(0x3329B6F6)
      ..style = PaintingStyle.fill;

    final Path hl = Path()
      ..moveTo(s * 0.50, s * 0.12)
      ..lineTo(s * 0.75, s * 0.86)
      ..lineTo(s * 0.50, s * 0.72)
      ..lineTo(s * 0.25, s * 0.86)
      ..close();

    canvas.drawPath(hl, highlight);

    final ui.Image img = await recorder.endRecording().toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    _driverGoogleArrowIcon =
        BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());

    if (mounted) setState(() {});
  }


  dynamic tempStopId;
  bool isLoading = false;

  // --- Route rebuild / recenter helpers (keep GoogleMap polyline stable) ---
  DateTime? _lastRouteRebuildAt;
  bool _routeRebuildInProgress = false;
  bool _pendingCenterAfterClear = false;

  String additionalChargesReason = '';
  double additionalChargesAmount = 0.0;
  String additionalChargesError = '';
  LatLng currentLocation = LatLng(0.0, 0.0);  // O la ubicación predeterminada si no tienes coordenadas iniciales

  final _mapMarkerSC = StreamController<List<Marker>>();
  StreamSink<List<Marker>> get _mapMarkerSink => _mapMarkerSC.sink;
  final ScrollController _cont = ScrollController();
  Stream<List<Marker>> get mapMarkerStream => _mapMarkerSC.stream;
  TextEditingController bidText = TextEditingController();

  // ============================
  // Keep screen awake (Driver mode)
  // ============================
  bool _wakelockEnabled = false;

  Future<void> _setKeepScreenOn(bool enable) async {
    try {
      if (enable && !_wakelockEnabled) {
        await WakelockPlus.enable();
        _wakelockEnabled = true;
      } else if (!enable && _wakelockEnabled) {
        await WakelockPlus.disable();
        _wakelockEnabled = false;
      }
    } catch (_) {
      // ignore wakelock errors (do not crash map screen)
    }
  }

  // final platforms = const MethodChannel('flutter.app/awake');
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _setKeepScreenOn(true);
    _ensureDriverGoogleArrowIcon();
    // DashBubble.instance.stopBubble();
    if (Platform.isAndroid) {
      QuickNav.I.stopService();
    }
    myMarkers = [];
    show = true;
    navigated = false;
    filtericon = 0;
    polylineGot = false;
    currentpage = true;
    _isDarkTheme = isDarkTheme;
    getadminCurrentMessages();
    getLocs();
    _startLiveDriverTracking();
    getonlineoffline();


    // Animación estética para el texto "BUSCANDO VIAJE"
    _bippSearchingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // BIP: borde LED animado del panel superior (laser)
    _bippLaserCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    super.initState();

    // BIP: trae stats de hoy para mostrar arriba del botón (Viajes / Ganancia)
    Future.microtask(() async {
      await _bippRefreshTodayStats(force: true);
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    setState(() {
      _controller = controller;
      _controller?.setMapStyle(mapStyle);
    });
    if ((choosenRide.isNotEmpty || driverReq.isNotEmpty) &&
        _pickAnimateDone == false) {
      _pickAnimateDone = true;
      Future.delayed(const Duration(milliseconds: 100), () {
        _pickAnimateDone = true;
        addMarkers();
      });
    }
  }


  Future<void> _bippRefreshTodayStats({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // evita spamear el endpoint
    if (!force && (now - _bippLastTodayStatsFetchMs) < 15000) return;
    if (_bippTodayStatsFetchInFlight) return;

    _bippTodayStatsFetchInFlight = true;
    _bippLastTodayStatsFetchMs = now;

    try {
      await driverTodayEarning(); // functions.dart -> GET /api/v1/driver/today-earnings
    } catch (_) {
      // ignore
    } finally {
      _bippTodayStatsFetchInFlight = false;
    }

    // fuerza rebuild del mapa/panel (usa ValueListenableBuilder)
    try {
      valueNotifierHome.incrementNotifier();
    } catch (_) {
      // ignore
    }
  }


  getonlineoffline() async {
    if (userDetails['role'] == 'driver' &&
        userDetails['owner_id'] != null &&
        (userDetails['vehicle_type_id'] == null &&
            userDetails['vehicle_types'] == []) &&
        userDetails['active'] == true) {
      var val = await driverStatus();
      if (val == 'logout') {
        navigateLogout();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (isDarkTheme == true) {
      await rootBundle.loadString('assets/dark.json').then((value) {
        mapStyle = value;
      });
    } else {
      await rootBundle.loadString('assets/map_default.json').then((value) {
        mapStyle = value;
      });
    }

    if (state == AppLifecycleState.resumed) {
      _setKeepScreenOn(true);
      if (_controller != null) {
        _controller!.setMapStyle(mapStyle);
        valueNotifierHome.incrementNotifier();
      }
      isBackground = false;
      _startLiveDriverTracking();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive && Platform.isAndroid) {
      _setKeepScreenOn(false);
      // DashBubble.instance.stopBubble();
      QuickNav.I.stopService();
      isBackground = true;
      _stopLiveDriverTracking();
    }
  }



  // ============================
  // Live driver tracking helpers
  // ============================

  Future<void> _startLiveDriverTracking() async {
    if (_livePosSub != null) return;

    try {
      final serviceEnabled =
      await geolocator.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permStatus = await geolocator.Geolocator.checkPermission();
      if (permStatus == geolocator.LocationPermission.denied) {
        permStatus = await geolocator.Geolocator.requestPermission();
      }
      if (permStatus == geolocator.LocationPermission.denied ||
          permStatus == geolocator.LocationPermission.deniedForever) {
        return;
      }

      const settings = geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      );

      _livePosSub =
          geolocator.Geolocator.getPositionStream(locationSettings: settings)
              .listen((pos) async {
            final latLng = LatLng(pos.latitude, pos.longitude);

            double newHeading;

            if (_prevDriverLatLng != null) {
              final moved = geolocator.Geolocator.distanceBetween(
                _prevDriverLatLng!.latitude,
                _prevDriverLatLng!.longitude,
                latLng.latitude,
                latLng.longitude,
              );

              // Prefer bearing computed from real GPS movement (more reliable than sensor heading).
              // This avoids the "crossed" rotation you see when Android reports a non-zero but wrong heading.
              if (moved >= 2.0) {
                newHeading = _bearingBetween(_prevDriverLatLng!, latLng);

                // Only advance the reference point when movement is real;
                // otherwise small GPS jitter can create random bearings.
                _prevDriverLatLng = latLng;
              } else {
                newHeading = heading; // keep last stable heading
              }
            } else {
              // First fix: use sensor heading if available (may be 0 / NaN at low speed).
              final sensorHeading = (pos.heading.isNaN) ? 0.0 : pos.heading;
              newHeading = (sensorHeading == 0.0) ? heading : sensorHeading;

              _prevDriverLatLng = latLng;
            }

            // Optional: small blend toward sensor heading when it's close (reduces lag at speed).
            final sensorHeading2 = (pos.heading.isNaN) ? 0.0 : pos.heading;
            if (sensorHeading2 != 0.0) {
              final delta = _shortestAngleDelta(newHeading, sensorHeading2).abs();
              if (delta <= 20.0) {
                newHeading = _wrap360(
                  newHeading + _shortestAngleDelta(newHeading, sensorHeading2) * 0.25,
                );
              }
            }

            newHeading = _wrap360(newHeading);

            center = latLng;
            currentLocation = latLng;
            heading = newHeading;

            // 🔁 Recalcular y redibujar la ruta en cada update de GPS
            // (OJO: esto puede consumir cuota/costo de la API de rutas si lo dejás muy seguido)
            if (driverReq.isNotEmpty && driverReq['accepted_at'] != null) {
              await handleRouteDeviationAndSnap(offRouteMeters: 50);
            }

            // _prevDriverLatLng is managed above (movement threshold) to avoid jitter bearings.

            _updateDriverMarker(latLng, newHeading);

            if (_followDriver) {
              _animateToDriver(latLng, newHeading);
            }

            valueNotifierHome.incrementNotifier();
          });
    } catch (_) {}
  }

  /// Clear ONLY route polylines (does not touch markers).
  void clearRoutePolylines() {
    try {
      polyline.clear();
      polyList.clear();
      fmpoly.clear();
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  // ============================
  // Waze-like route styling (Google Maps)
  // ============================
  void _applyWazePolylineStyle() {
    try {
      if (mapType != 'google') return;
      if (polyList.isEmpty) return;

      // Replace the route polyline with a thick "double stroke" (border + main line)
      polyline.clear();

      polyline.add(
        Polyline(
          polylineId: const PolylineId('route_border'),
          points: polyList,
          color: const Color(0xFF6A1B9A).withOpacity(0.25),
          width: 14,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          geodesic: true,
          zIndex: 0,
        ),
      );

      polyline.add(
        Polyline(
          polylineId: const PolylineId('route_main'),
          points: polyList,
          color: const Color(0xFF6A1B9A),
          width: 9,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          geodesic: true,
          zIndex: 1,
        ),
      );
    } catch (_) {}
  }

  int _tripStartValue() {
    if (driverReq.isEmpty) return 0;
    final v = driverReq['is_trip_start'];
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final s = v.toLowerCase().trim();
      if (s == 'true') return 1;
      if (s == 'false') return 0;
    }
    return 0;
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      // algunos backends mandan "1.0" o con coma
      final normalized = s.replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }


  bool _shouldShowPickupFlag() {
    if (driverReq.isNotEmpty) {
      // Before trip starts: show pickup target
      return _tripStartValue() != 1;
    }
    return choosenRide.isNotEmpty;
  }

  bool _shouldShowDropFlag() {
    if (driverReq.isEmpty) return false;

    // Only show while trip is in-progress.
    if (_tripStartValue() != 1) return false;

    final completed = driverReq['is_completed'];
    if (completed == null) return true;
    if (completed is bool) return completed == false;
    if (completed is num) return completed == 0;
    if (completed is String) {
      final parsed = int.tryParse(completed);
      if (parsed != null) return parsed == 0;
      final s = completed.toLowerCase().trim();
      if (s == 'true') return false;
      if (s == 'false') return true;
    }
    return true;
  }


  /// Re-center the map camera to the driver's current GPS position.
  Future<void> centerToCurrentLocation({double? zoom}) async {
    if (_controller == null) return;
    final lat = currentLocation.latitude;
    final lng = currentLocation.longitude;
    if (lat == 0.0 && lng == 0.0) return;

    final z = zoom ?? _currentZoom ?? 16;
    try {
      await _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: z,
          ),
        ),
      );
    } catch (_) {}
  }

  /// If the driver goes off-route by [offRouteMeters], rebuild the route polyline from the current position.
  /// This is throttled to avoid hammering the Directions API.
  Future<void> handleRouteDeviationAndSnap({double offRouteMeters = 50}) async {
    if (driverReq.isEmpty) return;
    if (polyList.isEmpty) return;
    if (_routeRebuildInProgress) return;

    final lat = currentLocation.latitude;
    final lng = currentLocation.longitude;
    if (lat == 0.0 && lng == 0.0) return;

    final len = polyList.length;
    if (len < 2) return;

    // Sample the polyline to keep this cheap.
    int step = (len / 80).ceil();
    if (step < 1) step = 1;

    double minD = double.infinity;
    for (int i = 0; i < len; i += step) {
      final p = polyList[i];
      final d = geolocator.Geolocator.distanceBetween(lat, lng, p.latitude, p.longitude);
      if (d < minD) minD = d;
      if (minD <= offRouteMeters) break;
    }

    if (minD <= offRouteMeters) return;

    final now = DateTime.now();
    if (_lastRouteRebuildAt != null) {
      final seconds = now.difference(_lastRouteRebuildAt!).inSeconds;
      // Cooldown: avoid rebuilding too often (cost + lag).
      if (seconds < 8 && minD < offRouteMeters * 3) {
        return;
      }
    }

    _routeRebuildInProgress = true;
    _lastRouteRebuildAt = now;
    try {
      await rebuildRoutePolylinesFromCurrent();
      syncGooglePolylineFromPolyList();
    } catch (_) {
      // If rebuild fails, keep the current polyline.
    } finally {
      _routeRebuildInProgress = false;
    }
  }


  void _stopLiveDriverTracking() {
    _livePosSub?.cancel();
    _livePosSub = null;
  }

  void _updateDriverMarker(LatLng latLng, double newHeading) {
    try {
      myMarkers.removeWhere((m) => m.markerId.value == '1');

      final icon = (userDetails['vehicle_type_icon_for'] == 'motor_bike')
          ? pinLocationIcon3
          : (userDetails['vehicle_type_icon_for'] == 'taxi')
          ? pinLocationIcon2
          : pinLocationIcon;

      myMarkers.add(
        Marker(
          markerId: const MarkerId('1'),
          position: latLng,
          icon: (mapType == 'google' && userDetails['role'] == 'driver' && _driverGoogleArrowIcon != null)
              ? _driverGoogleArrowIcon!
              : icon,
          rotation: _vehicleRotationDeg(newHeading),
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    } catch (_) {}
  }

  void _animateToDriver(LatLng latLng, double newHeading) {
    if (_controller == null) return;

    final now = DateTime.now();
    if (_lastCameraMove != null &&
        now.difference(_lastCameraMove!).inMilliseconds < 250) {
      return; // throttle camera work
    }
    _lastCameraMove = now;

    // Keep zoom stable unless you change it elsewhere.
    final desiredBearing = _followBearing ? _wrap360(newHeading) : 0.0;

    double bearingToApply = desiredBearing;
    bool useMoveCamera = false;

    if (_followBearing) {
      // Smooth + avoid crazy spins near 0/360 and on sharp turns.
      final delta = _shortestAngleDelta(_cameraBearing, desiredBearing);

      // Small noise -> ignore.
      if (delta.abs() < 2.0) {
        bearingToApply = _wrap360(_cameraBearing);
      } else if (delta.abs() <= 45.0) {
        // Smooth small rotations (Uber-like).
        bearingToApply = _wrap360(_cameraBearing + (delta * 0.35));
      } else {
        // Big turns: snap (prevents long wrong spins).
        bearingToApply = desiredBearing;
        useMoveCamera = true;
      }
    } else {
      _cameraBearing = 0.0;
    }

    final cam = CameraPosition(
      target: latLng,
      zoom: _currentZoom,
      bearing: bearingToApply,
    );

    if (useMoveCamera) {
      _controller!.moveCamera(CameraUpdate.newCameraPosition(cam));
    } else {
      _controller!.animateCamera(CameraUpdate.newCameraPosition(cam));
    }

    _cameraBearing = bearingToApply;
  }

  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = math.pi * a.latitude / 180.0;
    final lon1 = math.pi * a.longitude / 180.0;
    final lat2 = math.pi * b.latitude / 180.0;
    final lon2 = math.pi * b.longitude / 180.0;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final brng = math.atan2(y, x);
    final deg = ((brng * 180.0 / pi) + 360.0) % 360.0; // o 180.0
    return deg.isNaN ? 0.0 : deg;
  }

  double _wrap360(double deg) {
    final v = deg % 360.0;
    return (v < 0) ? (v + 360.0) : v;
  }

  /// Signed shortest delta from [from] to [to] in degrees (-180..180).
  double _shortestAngleDelta(double from, double to) {
    final a = _wrap360(from);
    final b = _wrap360(to);
    var d = b - a;
    if (d > 180.0) d -= 360.0;
    if (d < -180.0) d += 360.0;
    return d;
  }




  @override
  void dispose() {
    _setKeepScreenOn(false);
    _stopLiveDriverTracking();
    if (_timer != null) {
      _timer.cancel();
    }
    fmpoly.clear();
    myMarkers.clear();
    _controller?.dispose();
    _controller = null;
    animationController?.dispose();

    _bippSearchingCtrl.dispose();
    _bippLaserCtrl.dispose();

    super.dispose();
  }

  //navigate
  navigate() {
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const DigitalSignature()));
  }

  navigateLogout() {
    if (ownermodule == '1') {
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LandingPage()),
                (route) => false);
      });
    } else {
      ischeckownerordriver = 'driver';
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const Login()),
                (route) => false);
      });
    }
  }

  reqCancel() {
    _reqCancelled = true;

    Future.delayed(const Duration(seconds: 2), () {
      _reqCancelled = false;
      userReject = false;
    });
  }

  Future<Uint8List> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  capturePng(GlobalKey iconKeys) async {
    dynamic bitmap;

    try {
      RenderRepaintBoundary boundary =
      iconKeys.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      var pngBytes = byteData!.buffer.asUint8List();
      bitmap = BitmapDescriptor.fromBytes(pngBytes);
      // return pngBytes;
      return bitmap;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  getPoly(change) async {
    fmpoly.clear();
    if (driverReq.isEmpty ||
        driverReq['accepted_at'] == null ||
        driverReq['is_driver_arrived'] == 1) {
      for (var i = 1; i < addressList.length; i++) {
        var api = await http.get(Uri.parse(
            'https://routing.openstreetmap.de/routed-car/route/v1/driving/${addressList[i - 1].latlng.longitude},${addressList[i - 1].latlng.latitude};${addressList[i].latlng.longitude},${addressList[i].latlng.latitude}?overview=false&geometries=polyline&steps=true'));
        if (api.statusCode == 200) {
          // ignore: no_leading_underscores_for_local_identifiers
          List _poly = jsonDecode(api.body)['routes'][0]['legs'][0]['steps'];
          polyline.clear();
          if (addressList.length < 3) {
            fmpoly.clear();
          }
          for (var e in _poly) {
            decodeEncodedPolyline(e['geometry']);
          }
          double lat = (addressList[0].latlng.latitude +
              addressList[addressList.length - 1].latlng.latitude) /
              2;
          double lon = (addressList[0].latlng.longitude +
              addressList[addressList.length - 1].latlng.longitude) /
              2;
          var val = LatLng(lat, lon);
          _fmController.move(fmlt.LatLng(val.latitude, val.longitude), 13);
          setState(() {});
        }
      }
    } else {
      var api = await http.get(Uri.parse(
          'https://routing.openstreetmap.de/routed-car/route/v1/driving/${center.longitude},${center.latitude};${addressList[0].latlng.longitude},${addressList[0].latlng.latitude}?overview=false&geometries=polyline&steps=true'));
      if (api.statusCode == 200) {
        // ignore: no_leading_underscores_for_local_identifiers
        List _poly = jsonDecode(api.body)['routes'][0]['legs'][0]['steps'];
        polyline.clear();
        if (addressList.length < 3) {
          fmpoly.clear();
        }
        for (var e in _poly) {
          decodeEncodedPolyline(e['geometry']);
        }
        double lat = (center.latitude + addressList[0].latlng.latitude) / 2;
        double lon = (center.longitude + addressList[0].latlng.longitude) / 2;
        var val = LatLng(lat, lon);
        // if(change == true){
        _fmController.move(fmlt.LatLng(val.latitude, val.longitude), 15);
        // }
        setState(() {});
      }
    }
    fmPolyGot = false;
  }

  addMarkers() {
    if (mapType == 'google') {
      Future.delayed(const Duration(milliseconds: 200), () {
        addPickDropMarker();
      });
    } else {
      fmpoly.clear();
      Future.delayed(const Duration(milliseconds: 200), () {
        getPoly(true);
      });
    }
  }

  addDropMarker() async {
    // Destination target (red flag) — shown only when trip has started.
    // For multi-stops, we keep numbered markers, and show the final stop as a flag when navigating.
    try {
      if (mapType != 'google') return;

      // Clear old destination marker (single-target mode)
      myMarkers.removeWhere((m) => m.markerId.value == 'drop_flag');

      final showDrop = _shouldShowDropFlag();

      // MULTI-STOP markers
      if (tripStops.isNotEmpty) {
        // Remove old stop markers
        myMarkers.removeWhere((m) => m.markerId.value.startsWith('stop_'));

        await _ensureFlagIcons();
        final dropIcon = _dropFlagIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

        for (var i = 0; i < tripStops.length; i++) {
          final lat = _asDouble(tripStops[i]['latitude']);
          final lng = _asDouble(tripStops[i]['longitude']);
          if (lat == null || lng == null) continue;

          final icon = await _drawStopIcon(stopNumber: i + 1);
          myMarkers.add(
            Marker(
              markerId: MarkerId('stop_${i + 1}'),
              icon: icon,
              position: LatLng(lat, lng),
              anchor: const Offset(0.5, 1.0),
              infoWindow: InfoWindow(title: 'Parada ${i + 1}'),
            ),
          );
        }

        // Además de los stops numerados, marcamos el FINAL (último stop) con bandera
        // cuando corresponde (para que siempre se vea la bandera final del recorrido).
        if (showDrop) {
          try {
            final last = tripStops.last;
            final double? lat = (last['latitude'] is num)
                ? (last['latitude'] as num).toDouble()
                : double.tryParse(last['latitude'].toString());
            final double? lng = (last['longitude'] is num)
                ? (last['longitude'] as num).toDouble()
                : double.tryParse(last['longitude'].toString());
            if (lat != null && lng != null) {
              await _ensureFlagIcons();
              myMarkers.removeWhere((m) => m.markerId == const MarkerId('drop_flag'));
              myMarkers.add(
                Marker(
                  markerId: const MarkerId('drop_flag'),
                  position: LatLng(lat, lng),
                  icon: _dropFlagIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  anchor: const Offset(0.5, 1.0),
                ),
              );
            }
          } catch (_) {}
        }

        if (mounted) setState(() {});
        return;
      }

      if (!showDrop) {
        if (mounted) setState(() {});
        return;
      }

      await _ensureFlagIcons();
      final icon = _dropFlagIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

      LatLng pos;
      if (driverReq.isNotEmpty &&
          driverReq['drop_lat'] != null &&
          driverReq['drop_lng'] != null) {
        final lat = _asDouble(driverReq['drop_lat']);
        final lng = _asDouble(driverReq['drop_lng']);
        if (lat == null || lng == null) return;
        pos = LatLng(lat, lng);
      } else if (choosenRide.isNotEmpty) {
        final lat = _asDouble(choosenRide[choosenRide.length - 1]['drop_lat']);
        final lng = _asDouble(choosenRide[choosenRide.length - 1]['drop_lng']);
        if (lat == null || lng == null) return;
        pos = LatLng(lat, lng);
      } else {
        return;
      }

      myMarkers.add(
        Marker(
          markerId: const MarkerId('drop_flag'),
          icon: icon,
          position: pos,
          anchor: const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
      );

      if (mounted) setState(() {});
    } catch (_) {}
  }


  addMarker() async {
    // Pickup target (green flag) — shown while going to pickup / waiting at pickup.
    try {
      if (mapType != 'google') return;

      final showPickup = _shouldShowPickupFlag();
      myMarkers.removeWhere((m) => m.markerId.value == 'pickup_flag');
      if (!showPickup) {
        if (mounted) setState(() {});
        return;
      }

      if ((driverReq.isEmpty && choosenRide.isEmpty)) return;

      await _ensureFlagIcons();
      final icon = _pickupFlagIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

      final dynamic rawLat =
      (driverReq.isNotEmpty) ? driverReq['pick_lat'] : choosenRide[0]['pick_lat'];
      final dynamic rawLng =
      (driverReq.isNotEmpty) ? driverReq['pick_lng'] : choosenRide[0]['pick_lng'];

      final lat = _asDouble(rawLat);
      final lng = _asDouble(rawLng);
      if (lat == null || lng == null) return;

      final LatLng pos = LatLng(lat, lng);

      myMarkers.add(
        Marker(
          markerId: const MarkerId('pickup_flag'),
          position: pos,
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'Recogida'),
        ),
      );

      if (mounted) setState(() {});
    } catch (_) {}
  }

  addPickDropMarker() async {
    await addMarker();

    if (driverReq['drop_address'] != null || choosenRide.isNotEmpty) {
      // Rebuild route
      await Future.sync(() => getPolylines(false));
      syncGooglePolylineFromPolyList();

      await addDropMarker();
    }
  }

//getting permission and current location
  getLocs() async {
    if (signKey == '' || packageName == '') {
      PackageInfo buildKeys = await PackageInfo.fromPlatform();
      signKey = buildKeys.buildSignature;
      packageName = buildKeys.packageName;
    }
    unloadImage = false;
    afterImageUploadError = '';
    beforeImageUploadError = '';
    shipLoadImage = null;
    shipUnloadImage = null;
    permission = await geolocator.GeolocatorPlatform.instance.checkPermission();
    serviceEnabled =
    await geolocator.GeolocatorPlatform.instance.isLocationServiceEnabled();

    if (permission == geolocator.LocationPermission.denied ||
        permission == geolocator.LocationPermission.deniedForever ||
        serviceEnabled == false) {
      gettingPerm++;

      if (gettingPerm > 1) {
        locationAllowed = false;
        if (userDetails['active'] == true) {
          var val = await driverStatus();
          if (val == 'logout') {
            navigateLogout();
          }
        }
        state = '3';
      } else {
        state = '2';
      }
      setState(() {
        _isLoading = false;
      });
    } else if (permission == geolocator.LocationPermission.whileInUse ||
        permission == geolocator.LocationPermission.always) {
      if (serviceEnabled == true) {
        final Uint8List markerIcon;
        final Uint8List markerIcon2;
        final Uint8List markerIcon3;
        final Uint8List onrideicon1;
        final Uint8List onridedeliveryicon1;
        final Uint8List offlineicon1;
        final Uint8List offlinedeliveryicon1;
        final Uint8List onlineicon1;
        final Uint8List onlinedeliveryicon1;
        final Uint8List onlinebikeicon1;
        final Uint8List offlinebikeicon1;
        final Uint8List onridebikeicon1;
        // if(userDetails['transport_type'] == 'taxi'){
        markerIcon = await getBytesFromAsset('assets/images/top-taxi.png', 80);
        markerIcon2 = await getBytesFromAsset('assets/images/bike.png', 80);
        markerIcon3 =
        await getBytesFromAsset('assets/images/vehicle-marker.png', 80);
        if (userDetails['role'] == 'owner') {
          onlinebikeicon1 =
          await getBytesFromAsset('assets/images/bike_online.png', 80);
          onridebikeicon1 =
          await getBytesFromAsset('assets/images/bike_onride.png', 80);
          offlinebikeicon1 =
          await getBytesFromAsset('assets/images/bike.png', 80);
          onrideicon1 =
          await getBytesFromAsset('assets/images/onboardicon.png', 80);
          offlineicon1 =
          await getBytesFromAsset('assets/images/offlineicon.png', 80);
          onlineicon1 =
          await getBytesFromAsset('assets/images/onlineicon.png', 80);
          onridedeliveryicon1 = await getBytesFromAsset(
              'assets/images/onboardicon_delivery.png', 80);
          offlinedeliveryicon1 = await getBytesFromAsset(
              'assets/images/offlineicon_delivery.png', 80);
          onlinedeliveryicon1 = await getBytesFromAsset(
              'assets/images/onlineicon_delivery.png', 80);
          onrideicon = BitmapDescriptor.fromBytes(onrideicon1);
          offlineicon = BitmapDescriptor.fromBytes(offlineicon1);
          onlineicon = BitmapDescriptor.fromBytes(onlineicon1);
          onridedeliveryicon = BitmapDescriptor.fromBytes(onridedeliveryicon1);
          offlinedeliveryicon =
              BitmapDescriptor.fromBytes(offlinedeliveryicon1);
          onlinedeliveryicon = BitmapDescriptor.fromBytes(onlinedeliveryicon1);
          onridebikeicon = BitmapDescriptor.fromBytes(onridebikeicon1);
          offlinebikeicon = BitmapDescriptor.fromBytes(offlinebikeicon1);
          onlinebikeicon = BitmapDescriptor.fromBytes(onlinebikeicon1);
        }

        if (center == null) {
          var locs = await geolocator.Geolocator.getLastKnownPosition();
          if (locs != null) {
            center = LatLng(locs.latitude, locs.longitude);
            heading = locs.heading;
          } else {
            loc = await geolocator.Geolocator.getCurrentPosition(
                desiredAccuracy: geolocator.LocationAccuracy.low);
            center = LatLng(double.parse(loc.latitude.toString()),
                double.parse(loc.longitude.toString()));
            heading = loc.heading;
          }
          if (driverReq.isEmpty && choosenRide.isEmpty) {
            _controller
                ?.animateCamera(CameraUpdate.newLatLngZoom(center, 14.0));
          }
          if (userDetails['metaRequest'] != null) {
            aproximateDistance1 = calculateDistance(center.latitude,
                center.longitude, driverReq['pick_lat'], driverReq['pick_lng']);
            aproximateDistance =
                double.parse((aproximateDistance1 / 1000).toString());
          }
        }
        if (mounted) {
          setState(() {
            pinLocationIcon = BitmapDescriptor.fromBytes(markerIcon);
            pinLocationIcon2 = BitmapDescriptor.fromBytes(markerIcon2);
            pinLocationIcon3 = BitmapDescriptor.fromBytes(markerIcon3);

            if (myMarkers.isEmpty && userDetails['role'] != 'owner') {
              myMarkers = [
                Marker(
                    markerId: const MarkerId('1'),
                    rotation: _vehicleRotationDeg(heading),
                    position: center,
                    icon: (mapType == 'google' && userDetails['role'] == 'driver' && _driverGoogleArrowIcon != null)
                        ? _driverGoogleArrowIcon!
                        : (userDetails['vehicle_type_icon_for'] == 'motor_bike')
                        ? pinLocationIcon2
                        : (userDetails['vehicle_type_icon_for'] == 'taxi')
                        ? pinLocationIcon
                        : pinLocationIcon3,
                    anchor: const Offset(0.5, 0.5))
              ];
            }
          });
        }
      }

      if (makeOnline == true && userDetails['active'] == false) {
        var val = await driverStatus();
        if (val == 'logout') {
          navigateLogout();
        }
      }
      makeOnline = false;
      if (mounted) {
        setState(() {
          locationAllowed = true;
          state = '3';
          _isLoading = false;
        });
      }
      if (choosenRide.isNotEmpty || driverReq.isNotEmpty) {}
    }
  }

  getLocationService() async {
    // await location.requestService();
    await geolocator.Geolocator.getCurrentPosition(
        desiredAccuracy: geolocator.LocationAccuracy.low);
    getLocs();
  }

  animatePoly() {
    polyAnimated = false;
    LatLngBounds bound;
    if (driverReq.isNotEmpty && driverReq['arrived_at'] != null) {
      if (driverReq['pick_lat'] > driverReq['drop_lat'] &&
          driverReq['pick_lng'] > driverReq['drop_lng']) {
        bound = LatLngBounds(
            southwest: LatLng(driverReq['drop_lat'], driverReq['drop_lng']),
            northeast: LatLng(driverReq['pick_lat'], driverReq['pick_lng']));
      } else if (driverReq['pick_lng'] > driverReq['drop_lng']) {
        bound = LatLngBounds(
            southwest: LatLng(driverReq['pick_lat'], driverReq['drop_lng']),
            northeast: LatLng(driverReq['drop_lat'], driverReq['pick_lng']));
      } else if (driverReq['pick_lat'] > driverReq['drop_lat']) {
        bound = LatLngBounds(
            southwest: LatLng(driverReq['drop_lat'], driverReq['pick_lng']),
            northeast: LatLng(driverReq['pick_lat'], driverReq['drop_lng']));
      } else {
        bound = LatLngBounds(
            southwest: LatLng(driverReq['pick_lat'], driverReq['pick_lng']),
            northeast: LatLng(driverReq['drop_lat'], driverReq['drop_lng']));
      }
      CameraUpdate cameraUpdate = CameraUpdate.newLatLngBounds(bound, 100);
      _controller?.animateCamera(cameraUpdate);
    } else if (driverReq.isNotEmpty) {
      if (center.latitude > driverReq['pick_lat'] &&
          center.longitude > driverReq['pick_lng']) {
        bound = LatLngBounds(
            southwest: LatLng(driverReq['pick_lat'], driverReq['pick_lng']),
            northeast: LatLng(center.latitude, center.longitude));
      } else if (center.longitude > driverReq['pick_lng']) {
        bound = LatLngBounds(
            southwest: LatLng(center.latitude, driverReq['pick_lng']),
            northeast: LatLng(driverReq['pick_lat'], center.longitude));
      } else if (center.latitude > driverReq['pick_lat']) {
        bound = LatLngBounds(
            southwest: LatLng(driverReq['pick_lat'], center.longitude),
            northeast: LatLng(center.latitude, driverReq['pick_lng']));
      } else {
        bound = LatLngBounds(
            southwest: LatLng(center.latitude, center.longitude),
            northeast: LatLng(driverReq['pick_lat'], driverReq['pick_lng']));
      }
      CameraUpdate cameraUpdate = CameraUpdate.newLatLngBounds(bound, 100);
      _controller?.animateCamera(cameraUpdate);
    }
  }

  getLocationPermission() async {
    if (permission == geolocator.LocationPermission.denied ||
        permission == geolocator.LocationPermission.deniedForever) {
      if (permission != geolocator.LocationPermission.deniedForever) {
        if (platform == TargetPlatform.android) {
          await perm.Permission.location.request();
          QuickNav.I.initService(
              chatHeadIcon: '@drawable/logo',
              notificationIcon: "@drawable/logo",
              notificationCircleHexColor: 0xFFA432A7,
              screenHeight: MediaQuery.of(context).size.height);
          await perm.Permission.locationAlways.request();
        } else {
          await [perm.Permission.location].request();
        }
        if (serviceEnabled == false) {
          // await location.requestService();
          await geolocator.Geolocator.getCurrentPosition(
              desiredAccuracy: geolocator.LocationAccuracy.low);
        }
      }
    } else if (serviceEnabled == false) {
      // await location.requestService();
      await geolocator.Geolocator.getCurrentPosition(
          desiredAccuracy: geolocator.LocationAccuracy.low);
    }
    setState(() {
      _isLoading = true;
    });
    getLocs();
  }

  String _permission = '';

  GeoHasher geo = GeoHasher();

  @override
  Widget build(BuildContext context) {
    //get camera permission
    getCameraPermission() async {
      var status = await perm.Permission.camera.status;
      if (status != perm.PermissionStatus.granted) {
        status = await perm.Permission.camera.request();
      }
      return status;
    }

    ImagePicker picker = ImagePicker();
    //pick image from camera
    pickImageFromCamera(id) async {
      var permission = await getCameraPermission();
      if (permission == perm.PermissionStatus.granted) {
        final pickedFile = await picker.pickImage(
            source: ImageSource.camera, imageQuality: 50);
        if (pickedFile != null) {
          setState(() {
            if (id == 1) {
              shipLoadImage = pickedFile.path;
            } else {
              shipUnloadImage = pickedFile.path;
            }
            // _pickImage = false;
          });
        }
      } else {
        setState(() {
          _permission = 'noCamera';
        });
      }
    }

    var media = MediaQuery.of(context).size;

    // Bottom sheet (on-ride) sizing:
    // - _panelCollapsed: cuánto se esconde cuando está "abajo"
    // - _panelPeekHeight: cuánto queda visible cuando está "abajo" (bajalo para que se vea menos y el mapa se vea más)
    final double _panelHeight = media.height * 1.2;
    final double _panelPeekHeight = media.height * 0.10;
    final double _panelCollapsed = _panelHeight - _panelPeekHeight;

    // Límite de apertura para que el panel NO tape toda la pantalla:
    // - Con viaje iniciado abrimos más (como tu imagen 3A).
    // - Esperando al cliente abrimos menos (como tu imagen 4A).
    final bool _tripStarted = (driverReq.isNotEmpty &&
        (driverReq['is_trip_start'] == 1 || driverReq['is_trip_start'] == true));

    final double _panelMaxOpenVisible =
    _tripStarted ? (media.height * 0.72) : (media.height * 0.42);

    // "hidden" mínimo (más chico = más abierto) para que visible nunca supere _panelMaxOpenVisible.
    final double _panelOpenHidden =
    (_panelHeight - _panelMaxOpenVisible).clamp(0.0, _panelCollapsed);

    final double _panelHidden =
    (addressBottom ?? _panelCollapsed).clamp(_panelOpenHidden, _panelCollapsed);
    final double _panelVisible = _panelHeight - _panelHidden;

    return PopScope(
      canPop: true,
      child: Material(
        child: ValueListenableBuilder(
            valueListenable: valueNotifierHome.value,
            builder: (context, value, child) {
              // Si cambia el estado de inicio del viaje, refrescamos banderas (pickup/destino)
              // para que siempre se vea la bandera final cuando corresponde.
              final int _ts = _tripStartValue();
              if (_ts != _lastTripStartValueMemo) {
                _lastTripStartValueMemo = _ts;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  await addMarker();
                  await addDropMarker();
                });
              }

              // If a trip/request gets rejected/cancelled, ensure we clear the route and re-center on the driver.
              if (driverReq.isEmpty) {
                if (!_pendingCenterAfterClear) {
                  _pendingCenterAfterClear = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!mounted) return;
                    clearRoutePolylines();
                    await centerToCurrentLocation();
                  });
                }
              } else {
                _pendingCenterAfterClear = false;
              }

              if (_isDarkTheme != isDarkTheme && _controller != null) {
                _controller!.setMapStyle(mapStyle);
                _isDarkTheme = isDarkTheme;
              }
              if (polyAnimated == true) {
                animatePoly();
              }
              if (navigated == false) {
                if (driverReq.isEmpty &&
                    choosenRide.isEmpty &&
                    userDetails.isNotEmpty &&
                    userDetails['role'] != 'owner' &&
                    userDetails['enable_bidding'] == true) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const RidePage()),
                            (route) => false);
                  });
                }
                if (isGeneral == true) {
                  isGeneral = false;
                  if (lastNotification != latestNotification) {
                    lastNotification = latestNotification;
                    pref.setString('lastNotification', latestNotification);
                    latestNotification = '';
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const NotificationPage()));
                    });
                  }
                }

                if (driverReq.isNotEmpty && isDestinationChanged) {
                  isDestinationChanged = false;
                  addMarkers();
                }
                if (((choosenRide.isNotEmpty && _pickAnimateDone == false) ||
                    (driverReq.isNotEmpty && _pickAnimateDone == false)) &&
                    (_controller != null || mapType != 'google')) {
                  _pickAnimateDone = true;
                  fmPolyGot = true;
                  if (mounted) {
                    addMarkers();
                  }
                } else if (driverReq.isNotEmpty &&
                    mapType != 'google' &&
                    fmpoly.isEmpty &&
                    fmPolyGot == false &&
                    _pickAnimateDone == true) {
                  fmPolyGot = true;
                  getPoly(false);
                } else {}

                if (myMarkers
                    .where((element) => element.markerId == const MarkerId('1'))
                    .isNotEmpty) {
                  if (userDetails['vehicle_type_icon_for'] != 'motor_bike' &&
                      myMarkers
                          .firstWhere((element) =>
                      element.markerId == const MarkerId('1'))
                          .icon ==
                          pinLocationIcon2) {
                    myMarkers.removeWhere(
                            (element) => element.markerId == const MarkerId('1'));
                  } else if (userDetails['vehicle_type_icon_for'] != 'taxi' &&
                      myMarkers
                          .firstWhere((element) =>
                      element.markerId == const MarkerId('1'))
                          .icon ==
                          pinLocationIcon) {
                    myMarkers.removeWhere(
                            (element) => element.markerId == const MarkerId('1'));
                  } else if (userDetails['vehicle_type_icon_for'] != 'truck' &&
                      myMarkers
                          .firstWhere((element) =>
                      element.markerId == const MarkerId('1'))
                          .icon ==
                          pinLocationIcon3) {
                    myMarkers.removeWhere(
                            (element) => element.markerId == const MarkerId('1'));
                  }
                }
                if (myMarkers
                    .where((element) =>
                element.markerId == const MarkerId('1'))
                    .isNotEmpty &&
                    pinLocationIcon != null &&
                    (_controller != null || mapType != 'google') &&
                    center != null) {
                  var dist = calculateDistance(
                      myMarkers
                          .firstWhere((element) =>
                      element.markerId == const MarkerId('1'))
                          .position
                          .latitude,
                      myMarkers
                          .firstWhere((element) =>
                      element.markerId == const MarkerId('1'))
                          .position
                          .longitude,
                      center.latitude,
                      center.longitude);
                  if (dist > 0 &&
                      animationController == null &&
                      (_controller != null || mapType != 'google')) {
                    animationController = AnimationController(
                      duration: const Duration(
                          milliseconds: 1500), //Animation duration of marker

                      vsync: this, //From the widget
                    );
                    if (mapType == 'google') {
                      List polys = [];
                      dynamic nearestLat;
                      dynamic pol;
                      for (var e in polyList) {
                        var dist = calculateDistance(center.latitude,
                            center.longitude, e.latitude, e.longitude);
                        if (pol == null) {
                          polys.add(dist);
                          pol = dist;
                          nearestLat = e;
                        } else {
                          if (dist < pol) {
                            polys.add(dist);
                            pol = dist;
                            nearestLat = e;
                          }
                        }
                      }
                      int currentNumber = polyList
                          .indexWhere((element) => element == nearestLat);
                      for (var i = 0; i < currentNumber; i++) {
                        polyList.removeAt(0);
                      }
                      polyline.clear();
                      fmpoly.clear();
                      syncGooglePolylineFromPolyList();
                    } else {
                      List polys = [];
                      dynamic nearestLat;
                      dynamic pol;
                      for (var e in fmpoly) {
                        var dist = calculateDistance(center.latitude,
                            center.longitude, e.latitude, e.longitude);
                        if (pol == null) {
                          polys.add(dist);
                          pol = dist;
                          nearestLat = e;
                        } else {
                          if (dist < pol) {
                            polys.add(dist);
                            pol = dist;
                            nearestLat = e;
                          }
                        }
                      }
                      int currentNumber =
                      fmpoly.indexWhere((element) => element == nearestLat);
                      for (var i = 0; i < currentNumber; i++) {
                        fmpoly.removeAt(0);
                      }
                    }
                    animateCar(
                        myMarkers
                            .firstWhere((element) =>
                        element.markerId == const MarkerId('1'))
                            .position
                            .latitude,
                        myMarkers
                            .firstWhere((element) =>
                        element.markerId == const MarkerId('1'))
                            .position
                            .longitude,
                        center.latitude,
                        center.longitude,
                        _mapMarkerSink,
                        this,
                        // _controller,
                        '1',
                        (userDetails['vehicle_type_icon_for'] == 'motor_bike')
                            ? pinLocationIcon2
                            : (userDetails['vehicle_type_icon_for'] == 'taxi')
                            ? pinLocationIcon
                            : pinLocationIcon3,
                        '',
                        '');
                  }
                } else if (myMarkers
                    .where((element) =>
                element.markerId == const MarkerId('1'))
                    .isEmpty &&
                    pinLocationIcon != null &&
                    center != null &&
                    userDetails['role'] != 'owner') {
                  myMarkers.add(Marker(
                      markerId: const MarkerId('1'),
                      rotation: _vehicleRotationDeg(heading),
                      position: center,
                      icon:
                      (mapType == 'google' && userDetails['role'] == 'driver' && _driverGoogleArrowIcon != null)
                          ? _driverGoogleArrowIcon!
                          : (userDetails['vehicle_type_icon_for'] == 'motor_bike')
                          ? pinLocationIcon2
                          : (userDetails['vehicle_type_icon_for'] == 'taxi')
                          ? pinLocationIcon
                          : pinLocationIcon3,
                      anchor: const Offset(0.5, 0.5)));
                }
                if (driverReq.isNotEmpty) {
                  if (_controller != null) {
                    mapPadding = media.width * 1;
                  }
                  if (driverReq['is_completed'] == 1 &&
                      driverReq['requestBill'] != null &&
                      currentpage == true) {
                    _bippRefreshTodayStats(force: true);
                    navigated = true;
                    currentpage = false;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const Invoice()),
                              (route) => false);
                    });
                    _pickAnimateDone = false;
                    myMarkers.removeWhere(
                            (element) => element.markerId != const MarkerId('1'));
                    polyline.clear();
                    fmpoly.clear();
                    polylineGot = false;
                  }
                } else if (choosenRide.isEmpty && driverReq.isEmpty) {
                  mapPadding = 0;
                  if (myMarkers
                      .where((element) =>
                  element.markerId != const MarkerId('1'))
                      .isNotEmpty &&
                      userDetails['role'] != 'owner') {
                    myMarkers.removeWhere(
                            (element) => element.markerId != const MarkerId('1'));
                    polyline.clear();
                    fmpoly.clear();

                    if (userReject == true) {
                      reqCancel();
                    }
                    _pickAnimateDone = false;
                  }
                  if (_pickAnimateDone == true) {
                    _pickAnimateDone = false;
                  }
                }
              }

              if (userDetails['approve'] == false && driverReq.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const DocsProcess()),
                          (route) => false);
                });
              }
              return Directionality(
                textDirection: (languageDirection == 'rtl')
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: Scaffold(
                  drawer: (driverReq.isEmpty)
                      ? const NavDrawer()
                      : Container(
                      height: media.height * 1,
                      width: media.width * 1,
                      color: Colors.transparent),
                  body: StreamBuilder(
                      stream: userDetails['role'] == 'owner'
                          ? FirebaseDatabase.instance
                          .ref('drivers')
                          .orderByChild('ownerid')
                          .equalTo(userDetails['id'].toString())
                          .onValue
                          : null,
                      builder: (context, AsyncSnapshot<DatabaseEvent> event) {
                        if (event.hasData) {
                          driverData.clear();
                          for (var element in event.data!.snapshot.children) {
                            driverData.add(element.value);
                          }

                          for (var element in driverData) {
                            if (element['l'] != null &&
                                element['is_deleted'] != 1) {
                              if (userDetails['role'] == 'owner') {
                                if (userDetails['role'] == 'owner' &&
                                    offlineicon != null &&
                                    onlineicon != null &&
                                    onrideicon != null &&
                                    offlinebikeicon != null &&
                                    onlinebikeicon != null &&
                                    onridebikeicon != null &&
                                    filtericon == 0) {
                                  if (myMarkers
                                      .where((e) => e.markerId.toString().contains(
                                      'car#${element['id']}#${element['vehicle_type_icon']}'))
                                      .isEmpty) {
                                    myMarkers.add(Marker(
                                      markerId: (element['is_active'] == 0)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                          : MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                      rotation: double.parse(
                                          element['bearing'].toString()),
                                      position: LatLng(
                                          element['l'][0], element['l'][1]),
                                      infoWindow: InfoWindow(
                                          title: element['vehicle_number'],
                                          snippet: element['name']),
                                      anchor: const Offset(0.5, 0.5),
                                      icon: (element['is_active'] == 0)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? offlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? offlineicon
                                          : offlinedeliveryicon
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onlineicon
                                          : onlinedeliveryicon
                                          : (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onridebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onrideicon
                                          : onridedeliveryicon,
                                    ));
                                  } else if ((element['is_active'] != 0 && myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon == offlineicon) ||
                                      (element['is_active'] != 0 &&
                                          myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon ==
                                              offlinebikeicon) ||
                                      (element['is_active'] != 0 &&
                                          myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon ==
                                              offlinedeliveryicon)) {
                                    myMarkers.removeWhere((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'));
                                    myMarkers.add(Marker(
                                      markerId: (element['is_active'] == 0)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                          : MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                      rotation: double.parse(
                                          element['bearing'].toString()),
                                      position: LatLng(
                                          element['l'][0], element['l'][1]),
                                      infoWindow: InfoWindow(
                                          title: element['vehicle_number'],
                                          snippet: element['name']),
                                      anchor: const Offset(0.5, 0.5),
                                      icon: (element['is_active'] == 0)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? offlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? offlineicon
                                          : offlinedeliveryicon
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onlineicon
                                          : onlinedeliveryicon
                                          : (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onridebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onrideicon
                                          : onridedeliveryicon,
                                    ));
                                  } else if ((element['is_available'] != true && myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon == onlineicon) ||
                                      (element['is_available'] != true &&
                                          myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon ==
                                              onlinebikeicon) ||
                                      (element['is_available'] != true &&
                                          myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon ==
                                              onlinedeliveryicon)) {
                                    myMarkers.removeWhere((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'));
                                    myMarkers.add(Marker(
                                      markerId: (element['is_active'] == 0)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                          : MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                      rotation: double.parse(
                                          element['bearing'].toString()),
                                      position: LatLng(
                                          element['l'][0], element['l'][1]),
                                      infoWindow: InfoWindow(
                                          title: element['vehicle_number'],
                                          snippet: element['name']),
                                      anchor: const Offset(0.5, 0.5),
                                      icon: (element['is_active'] == 0)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? offlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? offlineicon
                                          : offlinedeliveryicon
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onlineicon
                                          : onlinedeliveryicon
                                          : (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onridebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onrideicon
                                          : onridedeliveryicon,
                                    ));
                                  } else if ((element['is_active'] != 1 && myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon == onlineicon) ||
                                      (element['is_active'] != 1 &&
                                          myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon ==
                                              onlinebikeicon) ||
                                      (element['is_active'] != 1 &&
                                          myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon ==
                                              onlinedeliveryicon)) {
                                    myMarkers.removeWhere((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'));
                                    myMarkers.add(Marker(
                                      markerId: (element['is_active'] == 0)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                          : MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                      rotation: double.parse(
                                          element['bearing'].toString()),
                                      position: LatLng(
                                          element['l'][0], element['l'][1]),
                                      infoWindow: InfoWindow(
                                          title: element['vehicle_number'],
                                          snippet: element['name']),
                                      anchor: const Offset(0.5, 0.5),
                                      icon: (element['is_active'] == 0)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? offlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? offlineicon
                                          : offlinedeliveryicon
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onlineicon
                                          : onlinedeliveryicon
                                          : (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onridebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onrideicon
                                          : onridedeliveryicon,
                                    ));
                                  } else if ((element['is_available'] == true && myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon == onrideicon) ||
                                      (element['is_available'] == true && myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon == onridebikeicon) ||
                                      (element['is_available'] == true && myMarkers.lastWhere((e) => e.markerId.toString().contains('car#${element['id']}#${element['vehicle_type_icon']}')).icon == onridedeliveryicon)) {
                                    myMarkers.removeWhere((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'));
                                    myMarkers.add(Marker(
                                      markerId: (element['is_active'] == 0)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                          : MarkerId(
                                          'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                      rotation: double.parse(
                                          element['bearing'].toString()),
                                      position: LatLng(
                                          element['l'][0], element['l'][1]),
                                      infoWindow: InfoWindow(
                                          title: element['vehicle_number'],
                                          snippet: element['name']),
                                      anchor: const Offset(0.5, 0.5),
                                      icon: (element['is_active'] == 0)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? offlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? offlineicon
                                          : offlinedeliveryicon
                                          : (element['is_available'] == true &&
                                          element['is_active'] == 1)
                                          ? (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onlinebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onlineicon
                                          : onlinedeliveryicon
                                          : (element['vehicle_type_icon'] ==
                                          'motor_bike')
                                          ? onridebikeicon
                                          : (element['vehicle_type_icon'] ==
                                          'taxi')
                                          ? onrideicon
                                          : onridedeliveryicon,
                                    ));
                                  } else if (_controller != null || mapType != 'google') {
                                    if (myMarkers
                                        .lastWhere((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'))
                                        .position
                                        .latitude !=
                                        element['l'][0] ||
                                        myMarkers
                                            .lastWhere((e) => e.markerId
                                            .toString()
                                            .contains(
                                            'car#${element['id']}#${element['vehicle_type_icon']}'))
                                            .position
                                            .longitude !=
                                            element['l'][1]) {
                                      var dist = calculateDistance(
                                          myMarkers
                                              .lastWhere((e) => e.markerId
                                              .toString()
                                              .contains(
                                              'car#${element['id']}#${element['vehicle_type_icon']}'))
                                              .position
                                              .latitude,
                                          myMarkers
                                              .lastWhere((e) => e.markerId
                                              .toString()
                                              .contains(
                                              'car#${element['id']}#${element['vehicle_type_icon']}'))
                                              .position
                                              .longitude,
                                          element['l'][0],
                                          element['l'][1]);
                                      if (dist > 0 && _controller != null) {
                                        animationController =
                                            AnimationController(
                                              duration: const Duration(
                                                  milliseconds:
                                                  1500), //Animation duration of marker

                                              vsync: this, //From the widget
                                            );

                                        animateCar(
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .latitude,
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .longitude,
                                            element['l'][0],
                                            element['l'][1],
                                            _mapMarkerSink,
                                            this,
                                            // _controller,
                                            'car#${element['id']}#${element['vehicle_type_icon']}',
                                            (element['is_active'] == 0)
                                                ? (element['vehicle_type_icon'] ==
                                                'motor_bike')
                                                ? offlinebikeicon
                                                : (element['vehicle_type_icon'] ==
                                                'taxi')
                                                ? offlineicon
                                                : offlinedeliveryicon
                                                : (element['is_available'] ==
                                                true &&
                                                element['is_active'] ==
                                                    1)
                                                ? (element['vehicle_type_icon'] ==
                                                'motor_bike')
                                                ? onlinebikeicon
                                                : (element['vehicle_type_icon'] ==
                                                'taxi')
                                                ? onlineicon
                                                : onlinedeliveryicon
                                                : (element['vehicle_type_icon'] ==
                                                'motor_bike')
                                                ? onridebikeicon
                                                : (element['vehicle_type_icon'] ==
                                                'taxi')
                                                ? onrideicon
                                                : onridedeliveryicon,
                                            element['vehicle_number'],
                                            element['name']);
                                      }
                                    }
                                  }
                                } else if (filtericon == 1 &&
                                    userDetails['role'] == 'owner' &&
                                    onlineicon != null) {
                                  if (element['l'] != null) {
                                    if (element['is_active'] == 0 &&
                                        offlineicon != null) {
                                      if (myMarkers
                                          .where((e) => e.markerId
                                          .toString()
                                          .contains(
                                          'car#${element['id']}#${element['vehicle_type_icon']}'))
                                          .isEmpty) {
                                        myMarkers.add(Marker(
                                          markerId: (element['is_active'] == 0)
                                              ? MarkerId(
                                              'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                              : (element['is_available'] ==
                                              true &&
                                              element['is_active'] == 1)
                                              ? MarkerId(
                                              'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                              : MarkerId(
                                              'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                          rotation: double.parse(
                                              element['bearing'].toString()),
                                          position: LatLng(
                                              element['l'][0], element['l'][1]),
                                          anchor: const Offset(0.5, 0.5),
                                          icon: (element['vehicle_type_icon'] ==
                                              'motor_bike')
                                              ? offlinebikeicon
                                              : (element['vehicle_type_icon'] ==
                                              'taxi')
                                              ? offlineicon
                                              : offlinedeliveryicon,
                                        ));
                                      } else if (_controller != null ||
                                          mapType != 'google') {
                                        if (myMarkers
                                            .lastWhere((e) => e.markerId
                                            .toString()
                                            .contains(
                                            'car#${element['id']}#${element['vehicle_type_icon']}'))
                                            .position
                                            .latitude !=
                                            element['l'][0] ||
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .longitude !=
                                                element['l'][1]) {
                                          var dist = calculateDistance(
                                              myMarkers
                                                  .lastWhere((e) => e.markerId
                                                  .toString()
                                                  .contains(
                                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                  .position
                                                  .latitude,
                                              myMarkers
                                                  .lastWhere((e) => e.markerId
                                                  .toString()
                                                  .contains(
                                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                  .position
                                                  .longitude,
                                              element['l'][0],
                                              element['l'][1]);
                                          if (dist > 0 &&
                                              (_controller != null ||
                                                  mapType != 'google')) {
                                            animationController =
                                                AnimationController(
                                                  duration: const Duration(
                                                      milliseconds:
                                                      1500), //Animation duration of marker

                                                  vsync: this, //From the widget
                                                );

                                            animateCar(
                                                myMarkers
                                                    .lastWhere((e) => e.markerId
                                                    .toString()
                                                    .contains(
                                                    'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                    .position
                                                    .latitude,
                                                myMarkers
                                                    .lastWhere((e) => e.markerId
                                                    .toString()
                                                    .contains(
                                                    'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                    .position
                                                    .longitude,
                                                element['l'][0],
                                                element['l'][1],
                                                _mapMarkerSink,
                                                this,
                                                // _controller,
                                                'car#${element['id']}#${element['vehicle_type_icon']}',
                                                (element['vehicle_type_icon'] ==
                                                    'motor_bike')
                                                    ? offlinebikeicon
                                                    : (element['vehicle_type_icon'] ==
                                                    'taxi')
                                                    ? offlineicon
                                                    : offlinedeliveryicon,
                                                element['vehicle_number'],
                                                element['name']);
                                          }
                                        }
                                      }
                                    } else {
                                      if (myMarkers
                                          .where((e) => e.markerId
                                          .toString()
                                          .contains(
                                          'car#${element['id']}#${element['vehicle_type_icon']}'))
                                          .isNotEmpty) {
                                        myMarkers.removeWhere((e) => e.markerId
                                            .toString()
                                            .contains(
                                            'car#${element['id']}#${element['vehicle_type_icon']}'));
                                      }
                                    }
                                  }
                                } else if (filtericon == 2 &&
                                    userDetails['role'] == 'owner' &&
                                    onlineicon != null) {
                                  if (element['is_available'] == false &&
                                      element['is_active'] == 1) {
                                    if (myMarkers
                                        .where((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'))
                                        .isEmpty) {
                                      myMarkers.add(Marker(
                                        markerId: (element['is_active'] == 0)
                                            ? MarkerId(
                                            'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                            : (element['is_available'] ==
                                            true &&
                                            element['is_active'] == 1)
                                            ? MarkerId(
                                            'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                            : MarkerId(
                                            'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                        rotation: double.parse(
                                            element['bearing'].toString()),
                                        position: LatLng(
                                            element['l'][0], element['l'][1]),
                                        anchor: const Offset(0.5, 0.5),
                                        icon: (element['vehicle_type_icon'] ==
                                            'motor_bike')
                                            ? onridebikeicon
                                            : (element['vehicle_type_icon'] ==
                                            'taxi')
                                            ? onrideicon
                                            : onridedeliveryicon,
                                      ));
                                    } else if (_controller != null ||
                                        mapType != 'google') {
                                      if (myMarkers
                                          .lastWhere((e) => e.markerId
                                          .toString()
                                          .contains(
                                          'car#${element['id']}#${element['vehicle_type_icon']}'))
                                          .position
                                          .latitude !=
                                          element['l'][0] ||
                                          myMarkers
                                              .lastWhere((e) => e.markerId
                                              .toString()
                                              .contains(
                                              'car#${element['id']}#${element['vehicle_type_icon']}'))
                                              .position
                                              .longitude !=
                                              element['l'][1]) {
                                        var dist = calculateDistance(
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .latitude,
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .longitude,
                                            element['l'][0],
                                            element['l'][1]);
                                        if (dist > 0 &&
                                            (_controller != null ||
                                                mapType != 'google')) {
                                          animationController =
                                              AnimationController(
                                                duration: const Duration(
                                                    milliseconds:
                                                    1500), //Animation duration of marker

                                                vsync: this, //From the widget
                                              );

                                          animateCar(
                                              myMarkers
                                                  .lastWhere((e) => e.markerId
                                                  .toString()
                                                  .contains(
                                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                  .position
                                                  .latitude,
                                              myMarkers
                                                  .lastWhere((e) => e.markerId
                                                  .toString()
                                                  .contains(
                                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                  .position
                                                  .longitude,
                                              element['l'][0],
                                              element['l'][1],
                                              _mapMarkerSink,
                                              this,
                                              // _controller,
                                              'car#${element['id']}#${element['vehicle_type_icon']}',
                                              (element['vehicle_type_icon'] ==
                                                  'motor_bike')
                                                  ? onridebikeicon
                                                  : (element['vehicle_type_icon'] ==
                                                  'taxi')
                                                  ? onrideicon
                                                  : onridedeliveryicon,
                                              element['vehicle_number'],
                                              element['name']);
                                        }
                                      }
                                    }
                                  } else {
                                    if (myMarkers
                                        .where((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'))
                                        .isNotEmpty) {
                                      myMarkers.removeWhere((e) => e.markerId
                                          .toString()
                                          .contains(
                                          'car#${element['id']}#${element['vehicle_type_icon']}'));
                                    }
                                  }
                                } else if (filtericon == 3 &&
                                    userDetails['role'] == 'owner' &&
                                    onlineicon != null) {
                                  if (element['is_available'] == true &&
                                      element['is_active'] == 1) {
                                    if (myMarkers
                                        .where((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'))
                                        .isEmpty) {
                                      myMarkers.add(Marker(
                                        markerId: (element['is_active'] == 0)
                                            ? MarkerId(
                                            'car#${element['id']}#${element['vehicle_type_icon']}#0')
                                            : (element['is_available'] ==
                                            true &&
                                            element['is_active'] == 1)
                                            ? MarkerId(
                                            'car#${element['id']}#${element['vehicle_type_icon']}#1')
                                            : MarkerId(
                                            'car#${element['id']}#${element['vehicle_type_icon']}#2'),
                                        rotation: double.parse(
                                            element['bearing'].toString()),
                                        position: LatLng(
                                            element['l'][0], element['l'][1]),
                                        anchor: const Offset(0.5, 0.5),
                                        icon: (element['vehicle_type_icon'] ==
                                            'motor_bike')
                                            ? onlinebikeicon
                                            : (element['vehicle_type_icon'] ==
                                            'taxi')
                                            ? onlineicon
                                            : onlinedeliveryicon,
                                      ));
                                    } else if (_controller != null ||
                                        mapType != 'google') {
                                      if (myMarkers
                                          .lastWhere((e) => e.markerId
                                          .toString()
                                          .contains(
                                          'car#${element['id']}#${element['vehicle_type_icon']}'))
                                          .position
                                          .latitude !=
                                          element['l'][0] ||
                                          myMarkers
                                              .lastWhere((e) => e.markerId
                                              .toString()
                                              .contains(
                                              'car#${element['id']}#${element['vehicle_type_icon']}'))
                                              .position
                                              .longitude !=
                                              element['l'][1]) {
                                        var dist = calculateDistance(
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .latitude,
                                            myMarkers
                                                .lastWhere((e) => e.markerId
                                                .toString()
                                                .contains(
                                                'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                .position
                                                .longitude,
                                            element['l'][0],
                                            element['l'][1]);
                                        if (dist > 0 &&
                                            (_controller != null ||
                                                mapType != 'google')) {
                                          animationController =
                                              AnimationController(
                                                duration: const Duration(
                                                    milliseconds:
                                                    1500), //Animation duration of marker

                                                vsync: this, //From the widget
                                              );

                                          animateCar(
                                              myMarkers
                                                  .lastWhere((e) => e.markerId
                                                  .toString()
                                                  .contains(
                                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                  .position
                                                  .latitude,
                                              myMarkers
                                                  .lastWhere((e) => e.markerId
                                                  .toString()
                                                  .contains(
                                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                                  .position
                                                  .longitude,
                                              element['l'][0],
                                              element['l'][1],
                                              _mapMarkerSink,
                                              this,
                                              // _controller,
                                              'car#${element['id']}#${element['vehicle_type_icon']}',
                                              (element['vehicle_type_icon'] ==
                                                  'motor_bike')
                                                  ? onlinebikeicon
                                                  : (element['vehicle_type_icon'] ==
                                                  'taxi')
                                                  ? onlineicon
                                                  : onlinedeliveryicon,
                                              element['vehicle_number'],
                                              element['name']);
                                        }
                                      }
                                    }
                                  }
                                } else {
                                  if (myMarkers
                                      .where((e) => e.markerId.toString().contains(
                                      'car#${element['id']}#${element['vehicle_type_icon']}'))
                                      .isNotEmpty) {
                                    myMarkers.removeWhere((e) => e.markerId
                                        .toString()
                                        .contains(
                                        'car#${element['id']}#${element['vehicle_type_icon']}'));
                                  }
                                }
                              }
                            } else {
                              if (myMarkers
                                  .where((e) => e.markerId.toString().contains(
                                  'car#${element['id']}#${element['vehicle_type_icon']}'))
                                  .isNotEmpty) {
                                myMarkers.removeWhere((e) => e.markerId
                                    .toString()
                                    .contains(
                                    'car#${element['id']}#${element['vehicle_type_icon']}'));
                              }
                            }
                          }
                        }
                        return Stack(
                          children: [
                            Container(
                              decoration: _bippGreenFadeDecoration(),
                              constraints: BoxConstraints(minHeight: media.height - MediaQuery.of(context).padding.vertical),
                              width: media.width,
                              child: Column(
                                  mainAxisAlignment:
                                  (state == '1' || state == '2')
                                      ? MainAxisAlignment.center
                                      : MainAxisAlignment.start,
                                  children: [
                                    (state == '1')
                                        ? Container(
                                      padding: EdgeInsets.all(
                                          media.width * 0.05),
                                      width: media.width * 0.6,
                                      height: media.width * 0.3,
                                      decoration: BoxDecoration(
                                          gradient: _bippGreenFadeGradient(),
                                          boxShadow: [
                                            BoxShadow(
                                                blurRadius: 5,
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                spreadRadius: 2)
                                          ],
                                          borderRadius:
                                          BorderRadius.circular(
                                              10)),
                                      child: Column(
                                        mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                        children: [
                                          Text(
                                            languages[choosenLanguage][
                                            'text_enable_location'],
                                            style: GoogleFonts.notoSans(
                                                fontSize: media.width *
                                                    sixteen,
                                                color: Colors.white,
                                                fontWeight:
                                                FontWeight.bold),
                                          ),
                                          Container(
                                            alignment:
                                            Alignment.centerRight,
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  state = '';
                                                });
                                                getLocs();
                                              },
                                              child: Text(
                                                languages[
                                                choosenLanguage]
                                                ['text_ok'],
                                                style: GoogleFonts
                                                    .notoSans(
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    fontSize: media
                                                        .width *
                                                        twenty,
                                                    color:
                                                    buttonColor),
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                    )
                                        : (state == '2')
                                        ? Container(
                                      height: media.height - 6,
                                      width: media.width * 1,
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisAlignment:
                                        MainAxisAlignment
                                            .center,
                                        children: [
                                          SizedBox(
                                            height:
                                            media.height * 0.31,
                                            width:
                                            media.width * 0.8,
                                            child: Image.asset(
                                              'assets/images/allow_location_permission.png',
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                          SizedBox(
                                            height:
                                            media.width * 0.05,
                                          ),
                                          Text(
                                            languages[
                                            choosenLanguage]
                                            [
                                            'text_trustedtaxi'],
                                            style: GoogleFonts
                                                .notoSans(
                                                fontSize: media
                                                    .width *
                                                    eighteen,
                                                fontWeight:
                                                FontWeight
                                                    .w600),
                                          ),
                                          SizedBox(
                                            height:
                                            media.width * 0.025,
                                          ),
                                          Text(
                                            languages[
                                            choosenLanguage]
                                            [
                                            'text_allowpermission1'],
                                            style: GoogleFonts
                                                .notoSans(
                                              fontSize:
                                              media.width *
                                                  fourteen,
                                            ),
                                          ),
                                          Text(
                                            languages[
                                            choosenLanguage]
                                            [
                                            'text_allowpermission2'],
                                            style: GoogleFonts
                                                .notoSans(
                                              fontSize:
                                              media.width *
                                                  fourteen,
                                            ),
                                          ),
                                          SizedBox(
                                            height:
                                            media.width * 0.05,
                                          ),
                                          Container(
                                            padding:
                                            EdgeInsets.fromLTRB(
                                                media.width *
                                                    0.05,
                                                0,
                                                media.width *
                                                    0.05,
                                                0),
                                            child: Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment
                                                  .start,
                                              children: [
                                                SizedBox(
                                                    width: media
                                                        .width *
                                                        0.075,
                                                    child: const Icon(
                                                        Icons
                                                            .location_on_outlined)),
                                                SizedBox(
                                                  width:
                                                  media.width *
                                                      0.025,
                                                ),
                                                SizedBox(
                                                  width:
                                                  media.width *
                                                      0.8,
                                                  child: Text(
                                                    languages[
                                                    choosenLanguage]
                                                    [
                                                    'text_loc_permission'],
                                                    style: GoogleFonts.notoSans(
                                                        fontSize: media
                                                            .width *
                                                            fourteen,
                                                        fontWeight:
                                                        FontWeight
                                                            .w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            height:
                                            media.width * 0.02,
                                          ),
                                          Container(
                                            padding:
                                            EdgeInsets.fromLTRB(
                                                media.width *
                                                    0.05,
                                                0,
                                                media.width *
                                                    0.05,
                                                0),
                                            child: Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment
                                                  .start,
                                              children: [
                                                SizedBox(
                                                    width: media
                                                        .width *
                                                        0.075,
                                                    child: const Icon(
                                                        Icons
                                                            .location_on_outlined)),
                                                SizedBox(
                                                  width:
                                                  media.width *
                                                      0.025,
                                                ),
                                                SizedBox(
                                                  width:
                                                  media.width *
                                                      0.8,
                                                  child: Text(
                                                    languages[
                                                    choosenLanguage]
                                                    [
                                                    'text_background_permission'],
                                                    style: GoogleFonts.notoSans(
                                                        fontSize: media
                                                            .width *
                                                            fourteen,
                                                        fontWeight:
                                                        FontWeight
                                                            .w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                              padding:
                                              EdgeInsets.all(
                                                  media.width *
                                                      0.05),
                                              child: Button(
                                                  onTap: () async {
                                                    getLocationPermission();
                                                  },
                                                  text: languages[
                                                  choosenLanguage]
                                                  [
                                                  'text_continue']))
                                        ],
                                      ),
                                    )
                                        : (state == '3')
                                        ? Stack(
                                      alignment:
                                      Alignment.center,
                                      children: [
                                        Container(
                                          alignment: Alignment
                                              .topCenter,
                                          height:
                                          media.height - MediaQuery.of(context).padding.vertical,
                                          width:
                                          media.width * 1,
                                          //google maps
                                          child: Listener(
                                            onPointerDown: (_) => _onUserInteractedWithMap(),
                                            onPointerMove: (_) => _onUserInteractedWithMap(),
                                            child: (mapType ==
                                                'google')
                                                ? StreamBuilder<
                                                List<Marker>>(
                                              stream:
                                              mapMarkerStream,
                                              builder: (context,
                                                  snapshot) {
                                                final bool _bippTopPanelShown =
                                                    userDetails.isNotEmpty &&
                                                        userDetails['role'] != 'owner' &&
                                                        driverReq.isEmpty &&
                                                        choosenRide.isEmpty &&
                                                        (userDetails['low_balance'] != true) &&
                                                        (userDetails['car_make_name'] != null);

                                                final double _bippTopPadding =
                                                    (_bippTopPanelShown
                                                        ? (media.height * 0.33)
                                                        : (media.height * 0.10)) +
                                                        MediaQuery.of(context).padding.top;

                                                return GoogleMap(
                                                  padding: EdgeInsets.only(
                                                    bottom: (driverReq['accepted_at'] != null)
                                                        ? (_panelVisible + MediaQuery.of(context).padding.bottom + 8)
                                                        : (media.width * 1),
                                                    top: _bippTopPadding,
                                                  ),
                                                  onMapCreated:
                                                  _onMapCreated,
                                                  initialCameraPosition:
                                                  CameraPosition(
                                                    target: (center ==
                                                        null)
                                                        ? _center
                                                        : center,
                                                    zoom:
                                                    18.0,
                                                  ),
                                                  markers: Set<
                                                      Marker>.from(
                                                      myMarkers),
                                                  polylines:
                                                  polyline,
                                                  minMaxZoomPreference:
                                                  const MinMaxZoomPreference(
                                                      0.0,
                                                      20.0),
                                                  myLocationButtonEnabled:
                                                  false,
                                                  compassEnabled:
                                                  false,
                                                  buildingsEnabled:
                                                  false,
                                                  zoomControlsEnabled:
                                                  false,
                                                );
                                              },
                                            )
                                                : StreamBuilder<
                                                List<
                                                    Marker>>(
                                                stream:
                                                mapMarkerStream,
                                                builder: (context,
                                                    snapshot) {
                                                  return SizedBox(
                                                    height: (driverReq.isEmpty)
                                                        ? media
                                                        .height
                                                        : ((media.height * 1.2) -
                                                        media.width),
                                                    child: fm
                                                        .FlutterMap(
                                                      mapController:
                                                      _fmController,
                                                      options: fm.MapOptions(
                                                          initialCenter:
                                                          fmlt.LatLng(center.latitude, center.longitude),
                                                          initialZoom: 16,
                                                          onTap: (P, L) {}),
                                                      children: [
                                                        fm.TileLayer(
                                                          // minZoom: 10,
                                                          urlTemplate: (isDarkTheme == false)
                                                              ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                                                              : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                                                          userAgentPackageName:
                                                          'com.example.app',
                                                        ),
                                                        if (userDetails['role'] == 'driver' &&
                                                            driverReq.isNotEmpty &&
                                                            fmpoly.isNotEmpty)
                                                          fm.PolylineLayer(
                                                            polylines: [
                                                              fm.Polyline(points: fmpoly, color: Colors.blue, strokeWidth: 4),
                                                            ],
                                                          ),
                                                        fm.MarkerLayer(
                                                            markers: [
                                                              if (userDetails['role'] == 'driver')
                                                                for (var k = 0; k < addressList.length; k++)
                                                                  fm.Marker(
                                                                      alignment: Alignment.topCenter,
                                                                      point: fmlt.LatLng(addressList[k].latlng.latitude, addressList[k].latlng.longitude),
                                                                      width: (k == 0 || k == addressList.length - 1) ? media.width * 0.7 : 10,
                                                                      height: (k == 0 || k == addressList.length - 1) ? media.width * 0.15 + 10 : 18,
                                                                      child: (k == 0 || k == addressList.length - 1)
                                                                          ? Column(
                                                                        children: [
                                                                          Container(
                                                                              decoration: BoxDecoration(
                                                                                  gradient: _bippGreenFadeGradient(),
                                                                                  borderRadius: BorderRadius.circular(5)),
                                                                              width: (platform == TargetPlatform.android) ? media.width * 0.5 : media.width * 0.7,
                                                                              padding: const EdgeInsets.all(5),
                                                                              child: (driverReq.isNotEmpty)
                                                                                  ? Text(
                                                                                addressList[k].address,
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.fade,
                                                                                softWrap: false,
                                                                                style: GoogleFonts.notoSans(color: Colors.white, fontSize: (platform == TargetPlatform.android) ? media.width * ten : media.width * twelve),
                                                                              )
                                                                                  : (addressList.where((element) => element.type == 'pickup').isNotEmpty)
                                                                                  ? Text(
                                                                                addressList[k].address,
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.fade,
                                                                                softWrap: false,
                                                                                style: GoogleFonts.notoSans(color: Colors.white, fontSize: (platform == TargetPlatform.android) ? media.width * ten : media.width * twelve),
                                                                              )
                                                                                  : Container()),
                                                                          const SizedBox(
                                                                            height: 10,
                                                                          ),
                                                                          Container(
                                                                            decoration: BoxDecoration(shape: BoxShape.circle, image: DecorationImage(image: AssetImage((addressList[k].type == 'pickup') ? 'assets/images/pick_icon.png' : 'assets/images/drop_icon.png'), fit: BoxFit.contain)),
                                                                            height: (platform == TargetPlatform.android) ? media.width * 0.07 : media.width * 0.12,
                                                                            width: (platform == TargetPlatform.android) ? media.width * 0.07 : media.width * 0.12,
                                                                          ),
                                                                        ],
                                                                      )
                                                                          : (addressList[k].completedat == null)
                                                                          ? MyText(
                                                                        text: k.toString(),
                                                                        size: 16,
                                                                        fontweight: FontWeight.bold,
                                                                        color: Colors.red,
                                                                      )
                                                                          : Container()),
                                                              for (var i = 0; i < myMarkers.length; i++)
                                                                fm.Marker(
                                                                    alignment: Alignment.topCenter,
                                                                    point: fmlt.LatLng(myMarkers[i].position.latitude, myMarkers[i].position.longitude),
                                                                    width: media.width * 0.7,
                                                                    height: 50,
                                                                    child: RotationTransition(
                                                                        turns: AlwaysStoppedAnimation(myMarkers[i].rotation / 360),
                                                                        child: (userDetails['role'] == 'driver')
                                                                            ? Image.asset(
                                                                          (userDetails['vehicle_type_icon_for'] == 'taxi')
                                                                              ? 'assets/images/top-taxi.png'
                                                                              : (userDetails['vehicle_type_icon_for'] == 'motor_bike')
                                                                              ? 'assets/images/bike.png'
                                                                              : 'assets/images/vehicle-marker.png',
                                                                        )
                                                                            : (userDetails['role'] == 'owner')
                                                                            ? Image.asset((myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[2].toString() == 'taxi')
                                                                            ? (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[3].toString() == '0')
                                                                            ? 'assets/images/offlineicon.png'
                                                                            : (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[3].toString() == '1')
                                                                            ? 'assets/images/onlineicon.png'
                                                                            : 'assets/images/onboardicon.png'
                                                                            : (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[2].toString() == 'truck')
                                                                            ? (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[3].toString() == '0')
                                                                            ? 'assets/images/offlineicon_delivery.png'
                                                                            : (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[3].toString() == '1')
                                                                            ? 'assets/images/onlineicon_delivery.png'
                                                                            : 'assets/images/onboardicon_delivery.png'
                                                                            : (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[3].toString() == '0')
                                                                            ? 'assets/images/bike.png'
                                                                            : (myMarkers[i].markerId.toString().replaceAll('MarkerId(', '').replaceAll(')', '').split('#')[3].toString() == '1')
                                                                            ? 'assets/images/bike_online.png'
                                                                            : 'assets/images/bike_onride.png')
                                                                            : Container())),
                                                            ]),
                                                        const fm
                                                            .RichAttributionWidget(
                                                          attributions: [],
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                          ),
                                        ),


                                        //driver status
                                        (userDetails['role'] ==
                                            'owner' ||
                                            driverReq
                                                .isNotEmpty ||
                                            userDetails[
                                            'low_balance'] ==
                                                true ||
                                            userDetails[
                                            'car_make_name'] ==
                                                null ||
                                            choosenRide
                                                .isNotEmpty)
                                            ? Container()
                                            : Positioned(
                                            top: MediaQuery.of(context).padding.top + (media.width * 0.14),
                                            child: InkWell(
                                                onTap:
                                                    () async {
                                                  if (((userDetails['vehicle_type_id'] != null) ||
                                                      (userDetails['vehicle_types'] !=
                                                          [])) &&
                                                      choosenRide
                                                          .isEmpty &&
                                                      driverReq
                                                          .isEmpty &&
                                                      userDetails['role'] ==
                                                          'driver') {
                                                    if (userDetails['active'] ==
                                                        false) {
                                                      if (pref.getBool('isOverlaypermission') != false &&
                                                          Theme.of(context).platform == TargetPlatform.android) {
                                                        // if (await DashBubble.instance.hasOverlayPermission() ==
                                                        //     false)
                                                        if (await QuickNav.I.checkPermission() ==
                                                            false) {
                                                          setState(() {
                                                            isOverLayPermission = true;
                                                          });
                                                        }
                                                      }
                                                    }
                                                    if (locationAllowed ==
                                                        true &&
                                                        serviceEnabled ==
                                                            true) {
                                                      if (platform ==
                                                          TargetPlatform.android) {
                                                        if (await QuickNav.I.checkPermission() ==
                                                            false) {
                                                          setState(() {
                                                            isOverLayPermission = true;
                                                          });
                                                        }
                                                      }
                                                      setState(
                                                              () {
                                                            _isLoading =
                                                            true;
                                                          });
                                                      var val =
                                                      await driverStatus();
                                                      if (val ==
                                                          'logout') {
                                                        navigateLogout();
                                                      }
                                                      setState(
                                                              () {
                                                            _isLoading =
                                                            false;
                                                          });
                                                    } else if (locationAllowed ==
                                                        true &&
                                                        serviceEnabled ==
                                                            false) {
                                                      await geolocator.Geolocator.getCurrentPosition(
                                                          desiredAccuracy: geolocator.LocationAccuracy.low);
                                                      if (await geolocator
                                                          .GeolocatorPlatform
                                                          .instance
                                                          .isLocationServiceEnabled()) {
                                                        serviceEnabled =
                                                        true;
                                                        setState(() {
                                                          _isLoading = true;
                                                        });
                                                        var val =
                                                        await driverStatus();
                                                        if (val ==
                                                            'logout') {
                                                          navigateLogout();
                                                        }
                                                        setState(() {
                                                          _isLoading = false;
                                                        });
                                                      }
                                                    } else {
                                                      if (serviceEnabled ==
                                                          true) {
                                                        setState(() {
                                                          makeOnline = true;
                                                          _locationDenied = true;
                                                        });
                                                      } else {
                                                        await geolocator.Geolocator.getCurrentPosition(desiredAccuracy: geolocator.LocationAccuracy.low);

                                                        setState(() {
                                                          _isLoading = true;
                                                        });
                                                        await getLocs();
                                                        if (serviceEnabled ==
                                                            true) {
                                                          setState(() {
                                                            makeOnline = true;
                                                            _locationDenied = true;
                                                          });
                                                        }
                                                      }
                                                    }
                                                  } else {}
                                                },
                                                child:
                                                _bippDriverTopPanel(media))),

                                        // Barra inferior futurista (solo home)
                                        driverReq.isEmpty ? _bippFuturisticBottomBar(media) : const SizedBox.shrink(),

                                        (userDetails.isNotEmpty &&
                                            userDetails[
                                            'low_balance'] ==
                                                true)
                                            ?
                                        //low balance
                                        Positioned(
                                          top: (choosenLanguage ==
                                              'zh')
                                              ? MediaQuery.of(context)
                                              .padding
                                              .top +
                                              15
                                              : MediaQuery.of(context)
                                              .padding
                                              .top +
                                              5,
                                          child:
                                          Container(
                                            decoration: BoxDecoration(
                                                color:
                                                buttonColor,
                                                borderRadius:
                                                BorderRadius.circular(
                                                    10)),
                                            width: media
                                                .width *
                                                0.8,
                                            padding: EdgeInsets
                                                .all(media
                                                .width *
                                                0.025),
                                            margin:
                                            EdgeInsets
                                                .only(
                                              left: (languageDirection ==
                                                  'ltr')
                                                  ? media.width *
                                                  0.15
                                                  : 0,
                                              right: (languageDirection ==
                                                  'ltr')
                                                  ? 0
                                                  : media.width *
                                                  0.15,
                                            ),
                                            child: Text(
                                              userDetails['owner_id'] !=
                                                  null
                                                  ? languages[choosenLanguage]
                                              [
                                              'text_fleet_diver_low_bal']
                                                  : languages[choosenLanguage]
                                              [
                                              'text_low_balance'],
                                              style: GoogleFonts
                                                  .notoSans(
                                                fontSize:
                                                media.width *
                                                    fourteen,
                                                color: (isDarkTheme)
                                                    ? Colors
                                                    .black
                                                    : textColor,
                                              ),
                                              textAlign:
                                              TextAlign
                                                  .center,
                                            ),
                                          ),
                                        )
                                            : (userDetails['car_make_name'] ==
                                            null &&
                                            userDetails[
                                            'owner_id'] !=
                                                null)
                                            ? Positioned(
                                          top: (choosenLanguage ==
                                              'zh')
                                              ? MediaQuery.of(context).padding.top +
                                              15
                                              : MediaQuery.of(context).padding.top +
                                              10,
                                          child: Container(
                                              decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(10)),
                                              width: media.width * 0.8,
                                              padding: EdgeInsets.all(media.width * 0.025),
                                              margin: EdgeInsets.only(
                                                left: (languageDirection == 'ltr')
                                                    ? media.width * 0.15
                                                    : 0,
                                                right: (languageDirection == 'ltr')
                                                    ? 0
                                                    : media.width * 0.15,
                                              ),
                                              child: MyText(
                                                text: languages[choosenLanguage]
                                                [
                                                'text_fleet_not_assigned'],
                                                size: media.width *
                                                    fourteen,
                                                color:
                                                verifyDeclined,
                                                textAlign:
                                                TextAlign.center,
                                                fontweight:
                                                FontWeight.w600,
                                              )),
                                        )
                                            : Container(),

                                        //menu bar
                                        (driverReq.isNotEmpty)
                                            ? Container()
                                            : Positioned(
                                            top: MediaQuery.of(
                                                context)
                                                .padding
                                                .top +
                                                12.5,
                                            child: SizedBox(
                                              width: media
                                                  .width *
                                                  0.9,
                                              child: Row(
                                                mainAxisAlignment:
                                                MainAxisAlignment
                                                    .start,
                                                children: [
                                                  _bippGlassCircleButton(
                                                    size: media.width * 0.11,
                                                    icon: (userDetails['enable_bidding'] == true) ? Icons.arrow_back : Icons.menu,
                                                    onTap: () async {
                                                      if ((userDetails['role'] != 'owner' && userDetails['enable_bidding'] == true)) {
                                                        addressList.clear();
                                                        tripStops.clear();
                                                        Navigator.pop(context);
                                                      } else {
                                                        Scaffold.of(context).openDrawer();
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            )),
                                        //notifications
                                        (driverReq.isNotEmpty)
                                            ? Container()
                                            : Positioned(
                                          top: MediaQuery.of(context).padding.top + 12.5,
                                          right: 16,
                                          child: _bippGlassCircleButton(
                                            size: media.width * 0.11,
                                            icon: Icons.notifications_none_rounded,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (context) => const NotificationPage()),
                                              );
                                            },
                                          ),
                                        ),

                                        //online or offline button
                                        (userDetails['role'] !=
                                            'owner')
                                            ? Container()
                                            : (languageDirection ==
                                            'rtl')
                                            ? Positioned(
                                          top: MediaQuery.of(context)
                                              .padding
                                              .top +
                                              12.5,
                                          left: 10,
                                          child:
                                          AnimatedContainer(
                                            curve: Curves
                                                .fastLinearToSlowEaseIn,
                                            duration: const Duration(
                                                milliseconds:
                                                0),
                                            height: media
                                                .width *
                                                0.13,
                                            width: (show == true)
                                                ? media.width *
                                                0.13
                                                : media.width *
                                                0.7,
                                            decoration:
                                            BoxDecoration(
                                              borderRadius: show ==
                                                  true
                                                  ? BorderRadius.circular(
                                                  100.0)
                                                  : const BorderRadius.only(
                                                  topLeft: Radius.circular(100),
                                                  bottomLeft: Radius.circular(100),
                                                  topRight: Radius.circular(20),
                                                  bottomRight: Radius.circular(20)),
                                              color: Colors
                                                  .white,
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: ui.Color.fromARGB(
                                                      255,
                                                      8,
                                                      38,
                                                      172),
                                                  offset:
                                                  Offset(0.0, 1.0), //(x,y)
                                                  blurRadius:
                                                  10.0,
                                                ),
                                              ],
                                            ),
                                            child:
                                            Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                              children: [
                                                show == false
                                                    ? SizedBox(
                                                  width: media.width * 0.57,
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      OwnerCarImagecontainer(
                                                        color: Colors.green,
                                                        imgurl: (transportType == 'taxi' || transportType == 'both') ? 'assets/images/available.png' : 'assets/images/available_delivery.png',
                                                        text: languages[choosenLanguage]['text_available'],
                                                        ontap: () {
                                                          setState(() {
                                                            filtericon = 3;
                                                            myMarkers.clear();
                                                          });
                                                        },
                                                      ),
                                                      OwnerCarImagecontainer(
                                                        color: Colors.red,
                                                        imgurl: (transportType == 'taxi' || transportType == 'both') ? 'assets/images/onboard.png' : 'assets/images/onboard_delivery.png',
                                                        text: languages[choosenLanguage]['text_onboard'],
                                                        ontap: () {
                                                          setState(() {
                                                            filtericon = 2;
                                                            myMarkers.clear();
                                                          });
                                                        },
                                                      ),
                                                      OwnerCarImagecontainer(
                                                        color: Colors.grey,
                                                        imgurl: (transportType == 'taxi' || transportType == 'both') ? 'assets/images/offlinecar.png' : 'assets/images/offlinecar_delivery.png',
                                                        text: languages[choosenLanguage]['text_offline'],
                                                        ontap: () {
                                                          setState(() {
                                                            filtericon = 1;
                                                            myMarkers.clear();
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                )
                                                    : Container(),
                                                InkWell(
                                                  onTap:
                                                      () {
                                                    setState(() {
                                                      filtericon = 0;
                                                      myMarkers.clear();
                                                      if (show == false) {
                                                        show = true;
                                                      } else {
                                                        show = false;
                                                      }
                                                    });
                                                  },
                                                  child:
                                                  Container(
                                                    width: media.width * 0.13,
                                                    decoration: BoxDecoration(image: DecorationImage(image: (transportType == 'taxi' || transportType == 'both') ? const AssetImage('assets/images/bluecar.png') : const AssetImage('assets/images/bluecar_delivery.png'), fit: BoxFit.contain), borderRadius: BorderRadius.circular(100.0)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                            : Positioned(
                                          top: MediaQuery.of(context)
                                              .padding
                                              .top +
                                              12.5,
                                          right: 10,
                                          child:
                                          AnimatedContainer(
                                            curve: Curves
                                                .fastLinearToSlowEaseIn,
                                            duration: const Duration(
                                                milliseconds:
                                                0),
                                            height: media
                                                .width *
                                                0.13,
                                            width: (show == true)
                                                ? media.width *
                                                0.13
                                                : media.width *
                                                0.7,
                                            decoration:
                                            BoxDecoration(
                                              borderRadius: show ==
                                                  true
                                                  ? BorderRadius.circular(
                                                  100.0)
                                                  : const BorderRadius.only(
                                                  topLeft: Radius.circular(20),
                                                  bottomLeft: Radius.circular(20),
                                                  topRight: Radius.circular(100),
                                                  bottomRight: Radius.circular(100)),
                                              color: Colors
                                                  .white,
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: ui.Color.fromARGB(
                                                      255,
                                                      8,
                                                      38,
                                                      172),
                                                  offset:
                                                  Offset(0.0, 1.0), //(x,y)
                                                  blurRadius:
                                                  10.0,
                                                ),
                                              ],
                                            ),
                                            child:
                                            Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                              children: [
                                                show == false
                                                    ? SizedBox(
                                                  width: media.width * 0.57,
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      OwnerCarImagecontainer(
                                                        color: Colors.green,
                                                        imgurl: (transportType == 'taxi' || transportType == 'both') ? 'assets/images/available.png' : 'assets/images/available_delivery.png',
                                                        text: languages[choosenLanguage]['text_available'],
                                                        ontap: () {
                                                          setState(() {
                                                            filtericon = 3;
                                                            myMarkers.clear();
                                                          });
                                                        },
                                                      ),
                                                      OwnerCarImagecontainer(
                                                        color: Colors.red,
                                                        imgurl: (transportType == 'taxi' || transportType == 'both') ? 'assets/images/onboard.png' : 'assets/images/onboard_delivery.png',
                                                        text: languages[choosenLanguage]['text_onboard'],
                                                        ontap: () {
                                                          setState(() {
                                                            filtericon = 2;
                                                            myMarkers.clear();
                                                          });
                                                        },
                                                      ),
                                                      OwnerCarImagecontainer(
                                                        color: Colors.grey,
                                                        imgurl: (transportType == 'taxi' || transportType == 'both') ? 'assets/images/offlinecar.png' : 'assets/images/offlinecar_delivery.png',
                                                        text: 'Offline',
                                                        ontap: () {
                                                          setState(() {
                                                            filtericon = 1;
                                                            myMarkers.clear();
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                )
                                                    : Container(),
                                                InkWell(
                                                  onTap:
                                                      () {
                                                    setState(() {
                                                      filtericon = 0;
                                                      myMarkers.clear();
                                                      if (show == false) {
                                                        show = true;
                                                      } else {
                                                        show = false;
                                                      }
                                                    });
                                                  },
                                                  child:
                                                  Container(
                                                    width: media.width * 0.13,
                                                    decoration: BoxDecoration(image: DecorationImage(image: (transportType == 'taxi' || transportType == 'both') ? const AssetImage('assets/images/bluecar.png') : const AssetImage('assets/images/bluecar_delivery.png'), fit: BoxFit.contain), borderRadius: BorderRadius.circular(100.0)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        (driverReq.isEmpty &&
                                            userDetails['role'] !=
                                                'owner' &&
                                            userDetails[
                                            'active'] ==
                                                true &&
                                            userDetails[
                                            'show_instant_ride_feature_on_mobile_app'] ==
                                                '1')
                                            ? Positioned(
                                            bottom:
                                            media.width *
                                                0.05,
                                            left: media.width *
                                                0.05,
                                            right: media
                                                .width *
                                                0.05,
                                            child: Row(
                                              children: [
                                                InkWell(
                                                  onTap:
                                                      () async {
                                                    if (userDetails['transport_type'].toString() ==
                                                        'taxi' ||
                                                        userDetails['enable_modules_for_applications'] ==
                                                            'taxi') {
                                                      var val = await geoCoding(
                                                          center.latitude,
                                                          center.longitude);
                                                      setState(
                                                              () {
                                                            if (addressList.where((element) => element.type == 'pickup').isNotEmpty) {
                                                              var add = addressList.firstWhere((element) => element.type == 'pickup');
                                                              add.address = val;
                                                              add.latlng = LatLng(center.latitude, center.longitude);
                                                            } else {
                                                              addressList.add(AddressList(id: '1', type: 'pickup', address: val, latlng: LatLng(center.latitude, center.longitude)));
                                                            }
                                                          });
                                                      if (addressList
                                                          .isNotEmpty) {
                                                        Navigator.push(context,
                                                            MaterialPageRoute(builder: (context) => const DropLocation()));
                                                      }
                                                    } else if (userDetails['transport_type'].toString() ==
                                                        'delivery' ||
                                                        userDetails['enable_modules_for_applications'] ==
                                                            'delivery') {
                                                      var val = await geoCoding(
                                                          center.latitude,
                                                          center.longitude);
                                                      setState(
                                                              () {
                                                            if (addressList.where((element) => element.type == 'pickup').isNotEmpty) {
                                                              var add = addressList.firstWhere((element) => element.type == 'pickup');
                                                              add.address = val;
                                                              add.latlng = LatLng(center.latitude, center.longitude);
                                                            } else {
                                                              addressList.add(AddressList(id: '1', type: 'pickup', address: val, latlng: LatLng(center.latitude, center.longitude)));
                                                            }
                                                          });
                                                      if (addressList
                                                          .isNotEmpty) {
                                                        Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (context) => const DropLocation(
                                                                  type: 1,
                                                                )));
                                                      }
                                                    } else {
                                                      setState(
                                                              () {
                                                            _isbottom =
                                                            0;
                                                          });
                                                    }
                                                  },
                                                  child:
                                                  SafeArea(
                                                    child:
                                                    Container(
                                                      height:
                                                      media.width * 0.12,
                                                      padding:
                                                      EdgeInsets.all(media.width * 0.03),
                                                      decoration: BoxDecoration(
                                                          color: (isDarkTheme) ? buttonColor : Colors.black,
                                                          borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                      child:
                                                      MyText(
                                                        text:
                                                        languages[choosenLanguage]['text_instant_ride'],
                                                        size:
                                                        media.width * sixteen,
                                                        fontweight:
                                                        FontWeight.w600,
                                                        color: (isDarkTheme)
                                                            ? Colors.black
                                                            : Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              ],
                                            ))
                                            : Container(),

                                        //request popup accept or reject
                                        Positioned(
                                            bottom: driverReq.isEmpty ? media.width * 0.20 : 0,
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .end,
                                              children: [
                                                (driverReq.isNotEmpty &&
                                                    driverReq['is_trip_start'] ==
                                                        1)
                                                    ? InkWell(
                                                    onTap:
                                                        () async {
                                                      setState(
                                                              () {
                                                            showSos =
                                                            true;
                                                          });
                                                    },
                                                    child:
                                                    Container(
                                                      height:
                                                      media.width * 0.1,
                                                      width:
                                                      media.width * 0.1,
                                                      decoration: BoxDecoration(
                                                          boxShadow: [
                                                            BoxShadow(blurRadius: 2, color: Colors.black.withOpacity(0.2), spreadRadius: 2)
                                                          ],
                                                          color: buttonColor,
                                                          borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                      alignment:
                                                      Alignment.center,
                                                      child:
                                                      Text(
                                                        'SOS',
                                                        style:
                                                        GoogleFonts.notoSans(fontSize: media.width * fourteen, color: page),
                                                      ),
                                                    ))
                                                    : Container(),
                                                const SizedBox(
                                                  height: 20,
                                                ),
                                                (driverReq.isNotEmpty &&
                                                    driverReq['accepted_at'] !=
                                                        null &&
                                                    driverReq['drop_address'] !=
                                                        null)
                                                    ? Row(
                                                  children: [
                                                    (navigationtype == true)
                                                        ? Container(
                                                      padding: EdgeInsets.all(media.width * 0.02),
                                                      decoration: BoxDecoration(boxShadow: [
                                                        BoxShadow(blurRadius: 2, color: Colors.black.withOpacity(0.2), spreadRadius: 2)
                                                      ], gradient: _bippGreenFadeGradient(), borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                      child: Row(
                                                        children: [
                                                          InkWell(
                                                            onTap: () {
                                                              if (driverReq['is_trip_start'] == 0) {
                                                                openMap(driverReq['pick_lat'], driverReq['pick_lng']);
                                                              }
                                                              if (tripStops.isEmpty && driverReq['is_trip_start'] != 0) {
                                                                openMap(driverReq['drop_lat'], driverReq['drop_lng']);
                                                              }
                                                            },
                                                            child: SizedBox(
                                                              width: media.width * 00.07,
                                                              child: Image.asset('assets/images/googlemaps.png', width: media.width * 0.05, fit: BoxFit.contain),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: media.width * 0.02,
                                                          ),
                                                          InkWell(
                                                            onTap: () {
                                                              if (driverReq['is_trip_start'] == 0) {
                                                                openWazeMap(driverReq['pick_lat'], driverReq['pick_lng']);
                                                              }
                                                              if (tripStops.isEmpty && driverReq['is_trip_start'] != 0) {
                                                                openWazeMap(driverReq['drop_lat'], driverReq['drop_lng']);
                                                              }
                                                            },
                                                            child: SizedBox(
                                                              width: media.width * 00.08,
                                                              child: Image.asset('assets/images/waze.png', width: media.width * 0.05, fit: BoxFit.contain),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                        : Container(),
                                                    SizedBox(
                                                      width:
                                                      media.width * 0.01,
                                                    ),
                                                    InkWell(
                                                      onTap:
                                                          () async {
                                                        if (userDetails['enable_vase_map'] == '1') {
                                                          if (navigationtype == false) {
                                                            if (driverReq['is_trip_start'] == 0) {
                                                              setState(() {
                                                                navigationtype = true;
                                                              });
                                                            } else if (tripStops.isNotEmpty) {
                                                              setState(() {
                                                                _tripOpenMap = true;
                                                              });
                                                            } else {
                                                              setState(() {
                                                                navigationtype = true;
                                                              });
                                                            }
                                                          } else {
                                                            setState(() {
                                                              navigationtype = false;
                                                            });
                                                          }
                                                        } else {
                                                          if (driverReq['is_trip_start'] == 0) {
                                                            openMap(driverReq['pick_lat'], driverReq['pick_lng']);
                                                          }
                                                          if (tripStops.isEmpty && driverReq['is_trip_start'] != 0) {
                                                            openMap(driverReq['drop_lat'], driverReq['drop_lng']);
                                                          }
                                                        }
                                                      },
                                                      child: Container(
                                                          height: media.width *
                                                              0.1,
                                                          width: media.width *
                                                              0.1,
                                                          decoration: BoxDecoration(boxShadow: [
                                                            BoxShadow(blurRadius: 2, color: Colors.black.withOpacity(0.2), spreadRadius: 2)
                                                          ], gradient: _bippGreenFadeGradient(), borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                          alignment: Alignment.center,
                                                          child: Image.asset('assets/images/locationFind.png', width: media.width * 0.06, color: Colors.white)),
                                                    ),
                                                  ],
                                                )
                                                    : Container(),
                                                const SizedBox(
                                                    height: 20),
                                                //animate to current location button
                                                SizedBox(
                                                  width: media
                                                      .width *
                                                      0.9,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .end,
                                                    children: [
                                                      _bippCyberMapButton(
                                                        size: media.width * 0.115,
                                                        icon: Icons.my_location_sharp,
                                                        iconSize: media.width * 0.060,
                                                        onTap: () async {
                                                          if (locationAllowed == true) {
                                                            if (mapType == 'google') {
                                                              _followDriver = true;
                                                              _controller?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: center, zoom: _currentZoom, bearing: heading)));
                                                            } else {
                                                              _fmController.move(fmlt.LatLng(center.latitude, center.longitude), 14);
                                                            }
                                                          } else {
                                                            if (serviceEnabled == true) {
                                                              setState(() {
                                                                _locationDenied = true;
                                                              });
                                                            } else {
                                                              await geolocator.Geolocator.getCurrentPosition(desiredAccuracy: geolocator.LocationAccuracy.low);

                                                              setState(() {
                                                                _isLoading = true;
                                                              });
                                                              await getLocs();
                                                              if (serviceEnabled == true) {
                                                                setState(() {
                                                                  _locationDenied = true;
                                                                });
                                                              }
                                                            }
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(
                                                    height: media
                                                        .width *
                                                        0.40),
                                                (choosenRide.isNotEmpty &&
                                                    driverReq
                                                        .isEmpty)
                                                    ? Column(
                                                  children: [
                                                    Container(
                                                        padding: const EdgeInsets.fromLTRB(0, 0, 0,
                                                            0),
                                                        width: media.width *
                                                            0.9,
                                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: _bippGreenFadeGradient(), boxShadow: [
                                                          BoxShadow(blurRadius: 2, color: Colors.black.withOpacity(0.2), spreadRadius: 2)
                                                        ]),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Container(
                                                              padding: EdgeInsets.fromLTRB(media.width * 0.05, media.width * 0.02, media.width * 0.05, media.width * 0.05),
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Row(
                                                                    children: [
                                                                      Container(
                                                                        height: media.width * 0.15,
                                                                        width: media.width * 0.15,
                                                                        decoration: BoxDecoration(shape: BoxShape.circle, image: DecorationImage(image: NetworkImage(choosenRide[0]['user_img']), fit: BoxFit.cover)),
                                                                      ),
                                                                      SizedBox(width: media.width * 0.05),
                                                                      Expanded(
                                                                        child: SizedBox(
                                                                          height: media.width * 0.2,
                                                                          child: Column(
                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                                                                            children: [
                                                                              Text(
                                                                                choosenRide[0]['user_name'],
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.ellipsis,
                                                                                style: GoogleFonts.notoSans(fontSize: media.width * eighteen, color: Colors.white),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      MyText(
                                                                        color: Colors.white,
                                                                        text: '${choosenRide[0]['km']} km',
                                                                        // maxLines: 1,
                                                                        size: media.width * sixteen,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  SizedBox(
                                                                    height: media.width * 0.02,
                                                                  ),
                                                                  Row(
                                                                    mainAxisAlignment: MainAxisAlignment.start,
                                                                    children: [
                                                                      Container(
                                                                        height: media.width * 0.05,
                                                                        width: media.width * 0.05,
                                                                        alignment: Alignment.center,
                                                                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                                                                        child: Container(
                                                                          height: media.width * 0.025,
                                                                          width: media.width * 0.025,
                                                                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: _bippGreenFadeGradient(opacity: 0.8)),
                                                                        ),
                                                                      ),
                                                                      SizedBox(
                                                                        width: media.width * 0.06,
                                                                      ),
                                                                      Expanded(
                                                                        child: MyText(
                                                                          color: Colors.white,
                                                                          text: choosenRide[0]['pick_address'],
                                                                          // maxLines: 1,
                                                                          size: media.width * twelve,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  SizedBox(
                                                                    height: media.width * 0.03,
                                                                  ),
                                                                  Row(
                                                                    mainAxisAlignment: MainAxisAlignment.start,
                                                                    children: [
                                                                      Container(
                                                                        height: media.width * 0.06,
                                                                        width: media.width * 0.06,
                                                                        alignment: Alignment.center,
                                                                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.1)),
                                                                        child: Icon(
                                                                          Icons.location_on_outlined,
                                                                          color: const Color(0xFFFF0000),
                                                                          size: media.width * eighteen,
                                                                        ),
                                                                      ),
                                                                      SizedBox(
                                                                        width: media.width * 0.05,
                                                                      ),
                                                                      Expanded(
                                                                        child: MyText(
                                                                          color: Colors.white,
                                                                          text: choosenRide[choosenRide.length - 1]['drop_address'],
                                                                          // maxLines: 1,
                                                                          size: media.width * twelve,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  SizedBox(
                                                                    height: media.width * 0.025,
                                                                  ),
                                                                  (choosenRide[0]['is_luggage_available'] == true || choosenRide[0]['is_pet_available'] == true)
                                                                      ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          MyText(
                                                                            color: Colors.white,
                                                                            text: languages[choosenLanguage]['text_ride_preference'] + ' :- ',
                                                                            size: media.width * twelve,
                                                                            fontweight: FontWeight.w600,
                                                                          ),
                                                                          SizedBox(
                                                                            width: media.width * 0.025,
                                                                          ),
                                                                          if (choosenRide[0]['is_pet_available'] == true)
                                                                            Row(
                                                                              children: [
                                                                                Icon(Icons.pets, size: media.width * 0.035, color: theme),
                                                                                SizedBox(
                                                                                  width: media.width * 0.01,
                                                                                ),
                                                                                MyText(
                                                                                  text: languages[choosenLanguage]['text_pets'],
                                                                                  size: media.width * twelve,
                                                                                  fontweight: FontWeight.w600,
                                                                                  color: theme,
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          if (choosenRide[0]['is_luggage_available'] == true && choosenRide[0]['is_pet_available'] == true)
                                                                            MyText(
                                                                              text: ', ',
                                                                              size: media.width * fourteen,
                                                                              fontweight: FontWeight.w600,
                                                                              color: theme,
                                                                            ),
                                                                          if (choosenRide[0]['is_luggage_available'] == true)
                                                                            Row(
                                                                              children: [
                                                                                // Icon(Icons.luggage, size: media.width * 0.05, color: theme),
                                                                                SizedBox(
                                                                                  height: media.width * 0.035,
                                                                                  width: media.width * 0.05,
                                                                                  child: Image.asset(
                                                                                    'assets/images/luggages.png',
                                                                                    color: theme,
                                                                                  ),
                                                                                ),
                                                                                SizedBox(
                                                                                  width: media.width * 0.01,
                                                                                ),
                                                                                MyText(
                                                                                  text: languages[choosenLanguage]['text_luggages'],
                                                                                  size: media.width * twelve,
                                                                                  fontweight: FontWeight.w600,
                                                                                  color: theme,
                                                                                ),
                                                                              ],
                                                                            ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                      : Container(),
                                                                  SizedBox(
                                                                    height: media.width * 0.02,
                                                                  ),
                                                                  SizedBox(
                                                                    child: Row(
                                                                      children: [
                                                                        InkWell(
                                                                          onTap: () {
                                                                            if (bidText.text.isNotEmpty && ((bidText.text.contains('.')) ? (double.parse(bidText.text) - double.parse(userDetails['bidding_amount_increase_or_decrease'].toString())) : (int.parse(bidText.text) - int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))) > 0) {
                                                                              setState(() {
                                                                                bidText.text = (bidText.text.isEmpty)
                                                                                    ? (choosenRide[0]['price'].toString().contains('.'))
                                                                                    ? (double.parse(choosenRide[0]['price'].toString()) - ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toStringAsFixed(2)
                                                                                    : (int.parse(choosenRide[0]['price'].toString()) - ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toString()
                                                                                    : (bidText.text.toString().contains('.'))
                                                                                    ? (double.parse(bidText.text.toString()) - ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toStringAsFixed(2)
                                                                                    : (int.parse(bidText.text.toString()) - ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toString();
                                                                              });
                                                                            }
                                                                          },
                                                                          child: Container(
                                                                            width: media.width * 0.2,
                                                                            alignment: Alignment.center,
                                                                            decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(media.width * 0.04)),
                                                                            padding: EdgeInsets.all(media.width * 0.025),
                                                                            child: Text(
                                                                              // '-10',
                                                                              (userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? '-${double.parse(userDetails['bidding_amount_increase_or_decrease'].toString())}' : '-${int.parse(userDetails['bidding_amount_increase_or_decrease'].toString())}',
                                                                              style: GoogleFonts.notoSans(fontSize: media.width * fourteen, fontWeight: FontWeight.w600, color: page),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        SizedBox(
                                                                          width: media.width * 0.4,
                                                                          child: TextField(
                                                                            textAlign: TextAlign.center,
                                                                            keyboardType: TextInputType.number,
                                                                            controller: bidText,
                                                                            decoration: InputDecoration(
                                                                              hintText: (choosenRide.isNotEmpty) ? choosenRide[0]['price'].toString() : '',
                                                                              hintStyle: GoogleFonts.notoSans(fontSize: media.width * sixteen, color: Colors.white),
                                                                              border: UnderlineInputBorder(borderSide: BorderSide(color: hintColor)),
                                                                            ),
                                                                            style: GoogleFonts.notoSans(fontSize: media.width * sixteen, color: Colors.white),
                                                                          ),
                                                                        ),
                                                                        InkWell(
                                                                          onTap: () {
                                                                            setState(() {
                                                                              bidText.text = (bidText.text.isEmpty)
                                                                                  ? (choosenRide[0]['price'].toString().contains('.'))
                                                                                  ? (double.parse(choosenRide[0]['price'].toString()) + ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toStringAsFixed(2)
                                                                                  : (int.parse(choosenRide[0]['price'].toString()) + ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toString()
                                                                                  : (bidText.text.toString().contains('.'))
                                                                                  ? (double.parse(bidText.text.toString()) + ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toStringAsFixed(2)
                                                                                  : (int.parse(bidText.text.toString()) + ((userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? double.parse(userDetails['bidding_amount_increase_or_decrease'].toString()) : int.parse(userDetails['bidding_amount_increase_or_decrease'].toString()))).toString();
                                                                            });
                                                                          },
                                                                          child: Container(
                                                                            width: media.width * 0.2,
                                                                            alignment: Alignment.center,
                                                                            decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(media.width * 0.04)),
                                                                            padding: EdgeInsets.all(media.width * 0.025),
                                                                            child: Text(
                                                                              // '+10',
                                                                              (userDetails['bidding_amount_increase_or_decrease'].toString().contains('.')) ? '+${double.parse(userDetails['bidding_amount_increase_or_decrease'].toString())}' : '+${int.parse(userDetails['bidding_amount_increase_or_decrease'].toString())}',
                                                                              style: GoogleFonts.notoSans(fontSize: media.width * fourteen, fontWeight: FontWeight.w600, color: page),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: media.width * 0.02,
                                                                  ),
                                                                  SizedBox(
                                                                      width: media.width * 0.9,
                                                                      child: Button(
                                                                          onTap: () async {
                                                                            if (bidText.text.isNotEmpty || choosenRide[0]['price'] != null) {
                                                                              setState(() {
                                                                                _isLoading = true;
                                                                              });
                                                                              try {
                                                                                await FirebaseDatabase.instance.ref().child('bid-meta/${choosenRide[0]["request_id"]}/drivers/driver_${userDetails["id"]}').update({
                                                                                  'driver_id': userDetails['id'],
                                                                                  'price': bidText.text.isNotEmpty ? bidText.text : choosenRide[0]['price'].toString(),
                                                                                  'driver_name': userDetails['name'],
                                                                                  'driver_img': userDetails['profile_picture'],
                                                                                  'bid_time': ServerValue.timestamp,
                                                                                  'is_rejected': 'none',
                                                                                  'vehicle_make': userDetails['car_make_name'],
                                                                                  'vehicle_model': userDetails['car_model_name'],
                                                                                  'lat': center.latitude,
                                                                                  'lng': center.longitude
                                                                                });
                                                                                setState(() {
                                                                                  isAvailable = false;
                                                                                });
                                                                                FirebaseDatabase.instance.ref().child('drivers/driver_${userDetails['id']}').update({'is_available': false});
                                                                                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const RidePage()), (route) => false);
                                                                                // Navigator.pop(context);
                                                                              } catch (e) {
                                                                                debugPrint(e.toString());
                                                                              }
                                                                              setState(() {
                                                                                _isLoading = false;
                                                                              });
                                                                            }
                                                                          },
                                                                          text: languages[choosenLanguage]['text_bid']))
                                                                ],
                                                              ),
                                                            )
                                                          ],
                                                        )),
                                                  ],
                                                )
                                                    : (driverReq
                                                    .isNotEmpty)
                                                    ? (driverReq['accepted_at'] ==
                                                    null)
                                                    ? Column(
                                                  children: [
                                                    (driverReq['is_later'] == 1 && driverReq['is_rental'] != true)
                                                        ? Container(
                                                      alignment: Alignment.center,
                                                      margin: EdgeInsets.only(bottom: media.width * 0.025),
                                                      padding: EdgeInsets.all(media.width * 0.025),
                                                      decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(6)),
                                                      width: media.width * 1,
                                                      child: MyText(
                                                        text: '${languages[choosenLanguage]['text_rideLaterTime']} ${driverReq['cv_trip_start_time']}',
                                                        size: media.width * sixteen,
                                                        color: topBar,
                                                      ),
                                                    )
                                                        : (driverReq['is_rental'] == true && driverReq['is_later'] != 1)
                                                        ? Container(
                                                      alignment: Alignment.center,
                                                      margin: EdgeInsets.only(bottom: media.width * 0.025),
                                                      padding: EdgeInsets.all(media.width * 0.025),
                                                      decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(6)),
                                                      width: media.width * 1,
                                                      child: MyText(
                                                        text: '${languages[choosenLanguage]['text_rental_ride']} - ${driverReq['rental_package_name']}',
                                                        size: media.width * sixteen,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                        : (driverReq['is_rental'] == true && driverReq['is_later'] == 1)
                                                        ? Container(
                                                      alignment: Alignment.center,
                                                      margin: EdgeInsets.only(bottom: media.width * 0.025),
                                                      padding: EdgeInsets.all(media.width * 0.025),
                                                      decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(6)),
                                                      width: media.width * 1,
                                                      child: Column(
                                                        children: [
                                                          MyText(
                                                            text: '${languages[choosenLanguage]['text_rideLaterTime']}  ${driverReq['cv_trip_start_time']}',
                                                            size: media.width * sixteen,
                                                            color: Colors.white,
                                                          ),
                                                          SizedBox(height: media.width * 0.02),
                                                          MyText(
                                                            text: '${languages[choosenLanguage]['text_rental_ride']} ${driverReq['rental_package_name']}',
                                                            size: media.width * sixteen,
                                                            color: Colors.white,
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                        : Container(),
                                                    Container(
                                                        padding: const EdgeInsets.fromLTRB(0, 0, 0,
                                                            0),
                                                        width: media.width *
                                                            1,
                                                        decoration: BoxDecoration(borderRadius: BorderRadius.only(topLeft: Radius.circular(media.width * 0.02), topRight: Radius.circular(media.width * 0.02)), gradient: _bippGreenFadeGradient(), boxShadow: [
                                                          BoxShadow(blurRadius: 2, color: Colors.black.withOpacity(0.2), spreadRadius: 2)
                                                        ]),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Container(
                                                              padding: EdgeInsets.fromLTRB(media.width * 0.05, media.width * 0.02, media.width * 0.05, media.width * 0.05),
                                                              child: Column(
                                                                children: [
                                                                  Container(
                                                                    width: media.width * 0.9,
                                                                    height: media.width * 0.3,
                                                                    padding: EdgeInsets.all(media.width * 0.02),
                                                                    // color: Colors.yellow,
                                                                    child: Row(
                                                                      children: [
                                                                        Container(
                                                                          height: media.width * 0.2,
                                                                          width: media.width * 0.2,
                                                                          decoration: BoxDecoration(image: DecorationImage(image: NetworkImage(driverReq['userDetail']['data']['profile_picture']), fit: BoxFit.cover), borderRadius: BorderRadius.circular(media.width * 0.02), boxShadow: [BoxShadow(blurRadius: 2, color: Colors.white.withOpacity(0.2), spreadRadius: 2)], gradient: _bippGreenFadeGradient(),),
                                                                        ),
                                                                        SizedBox(
                                                                          width: media.width * 0.05,
                                                                        ),
                                                                        Expanded(
                                                                            child: Column(
                                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                                              children: [
                                                                                MyText(
                                                                                  color: Colors.white,
                                                                                  text: driverReq['userDetail']['data']['name'],
                                                                                  size: media.width * sixteen,
                                                                                  fontweight: ui.FontWeight.bold,
                                                                                ),
                                                                                Row(
                                                                                  children: [
                                                                                    MyText(
                                                                                      color: Colors.white,
                                                                                      text: (aproximateDistance != null) ? '${aproximateDistance.toStringAsFixed(2).toString()} km' : '0.00 km',
                                                                                      size: media.width * fourteen,
                                                                                      // fontweight: ui.FontWeight.bold,
                                                                                    ),
                                                                                    SizedBox(
                                                                                      width: media.width * 0.04,
                                                                                    ),
                                                                                    Container(
                                                                                      height: 10,
                                                                                      width: 3,
                                                                                      color: buttonColor,
                                                                                    ),
                                                                                    SizedBox(
                                                                                      width: media.width * 0.04,
                                                                                    ),
                                                                                    MyText(
                                                                                      color: Colors.white,
                                                                                      text: aproximateMins,
                                                                                      size: media.width * fourteen,
                                                                                      // fontweight: ui.FontWeight.bold,
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                                (driverReq['drop_address'] == null && driverReq['is_rental'] == false)
                                                                                    ? Container()
                                                                                    : Container(
                                                                                  padding: EdgeInsets.all(media.width * 0.03),
                                                                                  decoration: BoxDecoration(
                                                                                    color: buttonColor.withOpacity(0.1),
                                                                                    borderRadius: BorderRadius.circular(media.width * 0.02),
                                                                                  ),
                                                                                  child: Row(
                                                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                                                    children: [
                                                                                      //payment image
                                                                                      Row(
                                                                                        children: [
                                                                                          SizedBox(
                                                                                            width: media.width * 0.06,
                                                                                            child: (driverReq['payment_opt'].toString() == '1')
                                                                                                ? Image.asset(
                                                                                              'assets/images/cash.png',
                                                                                              fit: BoxFit.contain,
                                                                                            )
                                                                                                : (driverReq['payment_opt'].toString() == '2')
                                                                                                ? Image.asset(
                                                                                              'assets/images/wallet.png',
                                                                                              fit: BoxFit.contain,
                                                                                            )
                                                                                                : (driverReq['payment_opt'].toString() == '0')
                                                                                                ? Image.asset(
                                                                                              'assets/images/card.png',
                                                                                              fit: BoxFit.contain,
                                                                                            )
                                                                                                : Container(),
                                                                                          ),
                                                                                          SizedBox(
                                                                                            width: media.width * 0.02,
                                                                                          ),
                                                                                          MyText(
                                                                                            color: Colors.white,
                                                                                            text: (driverReq['payment_opt'].toString() == '1')
                                                                                                ? languages[choosenLanguage]['text_cash']
                                                                                                : (driverReq['payment_opt'].toString() == '2')
                                                                                                ? languages[choosenLanguage]['text_wallet']
                                                                                                : (driverReq['payment_opt'].toString() == '0')
                                                                                                ? languages[choosenLanguage]['text_card']
                                                                                                : languages[choosenLanguage]['text_upi'],
                                                                                            // driverReq['payment_type_string'].toString(),
                                                                                            size: media.width * sixteen,
                                                                                          ),
                                                                                        ],
                                                                                      ),
                                                                                      SizedBox(width: media.width * 0.02),
                                                                                      (driverReq['show_request_eta_amount'] == true && driverReq['request_eta_amount'] != null)
                                                                                          ? Row(
                                                                                        children: [
                                                                                          MyText(
                                                                                            color: Colors.white,
                                                                                            text: userDetails['currency_symbol'],
                                                                                            size: media.width * fourteen,
                                                                                          ),
                                                                                          MyText(
                                                                                            color: Colors.white,
                                                                                            text: driverReq['request_eta_amount'].toStringAsFixed(2),
                                                                                            size: media.width * fourteen,
                                                                                            fontweight: FontWeight.w700,
                                                                                          ),
                                                                                        ],
                                                                                      )
                                                                                          : Container()
                                                                                    ],
                                                                                  ),
                                                                                )
                                                                              ],
                                                                            ))
                                                                      ],
                                                                    ),
                                                                  ),
                                                                  (duration != 0)
                                                                      ? Row(
                                                                    children: [
                                                                      Container(
                                                                        width: media.width * 0.9,
                                                                        height: 10,
                                                                        alignment: (languageDirection == 'ltr') ? Alignment.centerLeft : Alignment.centerRight,
                                                                        decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(100)),
                                                                        child: AnimatedContainer(
                                                                          duration: const Duration(milliseconds: 100),
                                                                          height: 10,
                                                                          width: (media.width * 0.9 / double.parse(userDetails['trip_accept_reject_duration_for_driver'].toString())) * (double.parse(userDetails['trip_accept_reject_duration_for_driver'].toString()) - duration),
                                                                          decoration: BoxDecoration(
                                                                              color: buttonColor,
                                                                              borderRadius: (languageDirection == 'ltr')
                                                                                  ? BorderRadius.only(
                                                                                topLeft: const Radius.circular(100),
                                                                                bottomLeft: const Radius.circular(100),
                                                                                bottomRight: const Radius.circular(100),
                                                                                topRight: (duration <= 2.0) ? const Radius.circular(100) : const Radius.circular(100),
                                                                              )
                                                                                  : BorderRadius.only(
                                                                                topRight: const Radius.circular(100),
                                                                                bottomLeft: const Radius.circular(100),
                                                                                bottomRight: const Radius.circular(100),
                                                                                topLeft: (duration <= 2.0) ? const Radius.circular(100) : const Radius.circular(100),
                                                                              )),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  )
                                                                      : Container(),
                                                                  SizedBox(
                                                                    height: media.width * 0.02,
                                                                  ),
                                                                  SizedBox(
                                                                    height: (tripStops.isEmpty) ? media.width * 0.3 : media.width * 0.4,
                                                                    child: SingleChildScrollView(
                                                                      child: Column(
                                                                        children: [
                                                                          Row(
                                                                            mainAxisAlignment: MainAxisAlignment.start,
                                                                            children: [
                                                                              Container(
                                                                                height: media.width * 0.05,
                                                                                width: media.width * 0.05,
                                                                                alignment: Alignment.center,
                                                                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                                                                                child: Container(
                                                                                  height: media.width * 0.025,
                                                                                  width: media.width * 0.025,
                                                                                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: _bippGreenFadeGradient(opacity: 0.8)),
                                                                                ),
                                                                              ),
                                                                              SizedBox(
                                                                                width: media.width * 0.06,
                                                                              ),
                                                                              Expanded(
                                                                                child: MyText(
                                                                                  color: Colors.white,
                                                                                  text: driverReq['pick_address'],
                                                                                  size: media.width * twelve,
                                                                                  // overflow: TextOverflow.ellipsis,
                                                                                  // maxLines: 1,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          SizedBox(
                                                                            height: media.width * 0.02,
                                                                          ),
                                                                          (tripStops.isNotEmpty)
                                                                              ? Column(
                                                                            children: tripStops
                                                                                .asMap()
                                                                                .map((i, value) {
                                                                              return MapEntry(
                                                                                  i,
                                                                                  (i < tripStops.length - 1)
                                                                                      ? Container(
                                                                                    padding: EdgeInsets.only(top: media.width * 0.02),
                                                                                    child: Column(
                                                                                      children: [
                                                                                        Row(
                                                                                          children: [
                                                                                            SizedBox(
                                                                                              width: media.width * 0.8,
                                                                                              child: Row(
                                                                                                mainAxisAlignment: MainAxisAlignment.start,
                                                                                                children: [
                                                                                                  Container(
                                                                                                    height: media.width * 0.06,
                                                                                                    width: media.width * 0.06,
                                                                                                    alignment: Alignment.center,
                                                                                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.1)),
                                                                                                    child: MyText(
                                                                                                      text: (i + 1).toString(),
                                                                                                      // maxLines: 1,
                                                                                                      color: const Color(0xFFFF0000),
                                                                                                      fontweight: FontWeight.w600,
                                                                                                      size: media.width * twelve,
                                                                                                    ),
                                                                                                  ),
                                                                                                  SizedBox(
                                                                                                    width: media.width * 0.05,
                                                                                                  ),
                                                                                                  Expanded(
                                                                                                    child: MyText(
                                                                                                      color: Colors.white,
                                                                                                      text: tripStops[i]['address'],
                                                                                                      // maxLines: 1,
                                                                                                      size: media.width * twelve,
                                                                                                    ),
                                                                                                  ),
                                                                                                ],
                                                                                              ),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ],
                                                                                    ),
                                                                                  )
                                                                                      : Container());
                                                                            })
                                                                                .values
                                                                                .toList(),
                                                                          )
                                                                              : Container(),
                                                                          SizedBox(
                                                                            height: media.width * 0.02,
                                                                          ),
                                                                          (driverReq['is_rental'] != true && driverReq['drop_address'] != null)
                                                                              ? Column(
                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                            children: [
                                                                              Row(
                                                                                mainAxisAlignment: MainAxisAlignment.start,
                                                                                children: [
                                                                                  Container(
                                                                                    height: media.width * 0.06,
                                                                                    width: media.width * 0.06,
                                                                                    alignment: Alignment.center,
                                                                                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.1)),
                                                                                    child: Icon(
                                                                                      Icons.location_on_outlined,
                                                                                      color: const Color(0xFFFF0000),
                                                                                      size: media.width * eighteen,
                                                                                    ),
                                                                                  ),
                                                                                  SizedBox(
                                                                                    width: media.width * 0.05,
                                                                                  ),
                                                                                  Expanded(
                                                                                    child: MyText(
                                                                                      color: Colors.white,
                                                                                      text: driverReq['drop_address'],
                                                                                      // maxLines: 1,
                                                                                      size: media.width * twelve,
                                                                                    ),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                            ],
                                                                          )
                                                                              : Container(),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: media.width * 0.02,
                                                                  ),
                                                                  (driverReq['goods_type'] != '-' && driverReq['goods_type'] != null)
                                                                      ? MyText(
                                                                    text: driverReq['goods_type'].toString(),
                                                                    size: media.width * fourteen,
                                                                    color: verifyDeclined,
                                                                  )
                                                                      : Container(),
                                                                  (driverReq['is_luggage_available'] == 1 || driverReq['is_pet_available'] == 1)
                                                                      ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          MyText(
                                                                            color: Colors.white,
                                                                            text: languages[choosenLanguage]['text_ride_preference'] + ' :- ',
                                                                            size: media.width * fourteen,
                                                                            fontweight: FontWeight.w600,
                                                                          ),
                                                                          SizedBox(
                                                                            width: media.width * 0.025,
                                                                          ),
                                                                          if (driverReq['is_pet_available'] == 1)
                                                                            Row(
                                                                              children: [
                                                                                Icon(Icons.pets, size: media.width * 0.05, color: theme),
                                                                                SizedBox(
                                                                                  width: media.width * 0.01,
                                                                                ),
                                                                                MyText(
                                                                                  text: languages[choosenLanguage]['text_pets'],
                                                                                  size: media.width * fourteen,
                                                                                  fontweight: FontWeight.w600,
                                                                                  color: theme,
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          if (driverReq['is_luggage_available'] == 1 && driverReq['is_pet_available'] == 1)
                                                                            MyText(
                                                                              text: ', ',
                                                                              size: media.width * fourteen,
                                                                              fontweight: FontWeight.w600,
                                                                              color: theme,
                                                                            ),
                                                                          if (driverReq['is_luggage_available'] == 1)
                                                                            Row(
                                                                              children: [
                                                                                // Icon(Icons.luggage, size: media.width * 0.05, color: theme),
                                                                                SizedBox(
                                                                                  height: media.width * 0.05,
                                                                                  width: media.width * 0.075,
                                                                                  child: Image.asset(
                                                                                    'assets/images/luggages.png',
                                                                                    color: theme,
                                                                                  ),
                                                                                ),
                                                                                SizedBox(
                                                                                  width: media.width * 0.01,
                                                                                ),
                                                                                MyText(
                                                                                  text: languages[choosenLanguage]['text_luggages'],
                                                                                  size: media.width * fourteen,
                                                                                  fontweight: FontWeight.w600,
                                                                                  color: theme,
                                                                                ),
                                                                              ],
                                                                            ),
                                                                        ],
                                                                      ),
                                                                      SizedBox(
                                                                        height: media.width * 0.025,
                                                                      ),
                                                                    ],
                                                                  )
                                                                      : Container(),
                                                                  SizedBox(
                                                                    height: media.width * 0.04,
                                                                  ),
                                                                  Row(
                                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                    children: [
                                                                      Button(
                                                                          color: const Color(0xFFFF0000).withOpacity(0.2),
                                                                          width: media.width * 0.4,
                                                                          textcolor: const Color(0XFFFF0000),
                                                                          onTap: () async {
                                                                            setState(() {
                                                                              _isLoading = true;
                                                                            });
                                                                            //reject request
                                                                            await requestReject();
                                                                            setState(() {
                                                                              _isLoading = false;
                                                                            });
                                                                          },
                                                                          text: languages[choosenLanguage]['text_decline']),
                                                                      Button(
                                                                        onTap: () async {
                                                                          setState(() {
                                                                            _isLoading = true;
                                                                          });
                                                                          if (duration != 0.0) {
                                                                            await requestAccept();
                                                                          }
                                                                          setState(() {
                                                                            _isLoading = false;
                                                                          });
                                                                        },
                                                                        text: languages[choosenLanguage]['text_accept'],
                                                                        width: media.width * 0.4,
                                                                      )
                                                                    ],
                                                                  )
                                                                ],
                                                              ),
                                                            )
                                                          ],
                                                        )),
                                                  ],
                                                )
                                                    : (driverReq['accepted_at'] != null)
                                                    ? SizedBox(
                                                  width: media.width * 0.9,
                                                  height: media.width * 0.7,
                                                )
                                                    : Container(width: media.width * 0.9)
                                                    : Container(
                                                  width:
                                                  media.width * 0.9,
                                                ),
                                              ],
                                            )),

                                        //on ride bottom sheet
                                        (driverReq['accepted_at'] !=
                                            null)
                                            ? AnimatedPositioned(
                                            duration:
                                            const Duration(
                                                milliseconds:
                                                250),
                                            bottom: -_panelHidden,
                                            child:
                                            GestureDetector(
                                              onVerticalDragStart:
                                                  (v) {
                                                _cont.jumpTo(0.0);
                                                start = v.globalPosition.dy;
                                                // Si está null, lo arrancamos colapsado (bien abajo)
                                                addressBottom ??= _panelCollapsed;
                                                _addressBottom = addressBottom;
                                                gesture.clear();
                                              },
                                              onVerticalDragUpdate:
                                                  (v) {
                                                final double dy = (v.globalPosition.dy - start);
                                                final double next =
                                                (_addressBottom + dy).clamp(_panelOpenHidden, _panelCollapsed).toDouble();
                                                setState(() {
                                                  addressBottom = next;
                                                });
                                              },
                                              onVerticalDragEnd:
                                                  (v) {
                                                final double current = (addressBottom ?? _panelCollapsed).toDouble();
                                                final double mid = (_panelCollapsed + _panelOpenHidden) * 0.5;
                                                setState(() {
                                                  addressBottom = (current > mid) ? _panelCollapsed : _panelOpenHidden;
                                                });
                                              },
                                              child: Column(
                                                children: [
                                                  (driverReq['is_trip_start'] ==
                                                      0)
                                                      ? Column(
                                                    children: [
                                                      (driverReq['is_later'] == 1 && driverReq['is_rental'] != true)
                                                          ? Container(
                                                        alignment: Alignment.center,
                                                        margin: EdgeInsets.only(bottom: media.width * 0.025),
                                                        padding: EdgeInsets.all(media.width * 0.025),
                                                        decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(6)),
                                                        width: media.width * 1,
                                                        child: MyText(
                                                          text: '${languages[choosenLanguage]['text_rideLaterTime']} ${driverReq['cv_trip_start_time']}',
                                                          size: media.width * sixteen,
                                                          color: topBar,
                                                        ),
                                                      )
                                                          : (driverReq['is_rental'] == true && driverReq['is_later'] != 1)
                                                          ? Container(
                                                        alignment: Alignment.center,
                                                        margin: EdgeInsets.only(bottom: media.width * 0.025),
                                                        padding: EdgeInsets.all(media.width * 0.025),
                                                        decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(6)),
                                                        width: media.width * 1,
                                                        child: MyText(
                                                          text: '${languages[choosenLanguage]['text_rental_ride']} - ${driverReq['rental_package_name']}',
                                                          size: media.width * sixteen,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                          : (driverReq['is_rental'] == true && driverReq['is_later'] == 1)
                                                          ? Container(
                                                        alignment: Alignment.center,
                                                        margin: EdgeInsets.only(bottom: media.width * 0.025),
                                                        padding: EdgeInsets.all(media.width * 0.025),
                                                        decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(6)),
                                                        width: media.width * 1,
                                                        child: Column(
                                                          children: [
                                                            MyText(
                                                              text: '${languages[choosenLanguage]['text_rideLaterTime']}  ${driverReq['cv_trip_start_time']}',
                                                              size: media.width * sixteen,
                                                              color: Colors.white,
                                                            ),
                                                            SizedBox(height: media.width * 0.02),
                                                            MyText(
                                                              text: '${languages[choosenLanguage]['text_rental_ride']} ${driverReq['rental_package_name']}',
                                                              size: media.width * sixteen,
                                                              color: Colors.white,
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                          : Container(),
                                                    ],
                                                  )
                                                      : Container(),
                                                  Container(
                                                    padding:
                                                    EdgeInsets.all(media.width *
                                                        0.05),
                                                    width:
                                                    media.width *
                                                        1,
                                                    height: media.height *
                                                        1.2,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                      const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
                                                      gradient: _bippGreenFadeGradient(),),
                                                    child:
                                                    Column(
                                                      children: [
                                                        Container(
                                                          width: media.width * 0.13,
                                                          height: media.width * 0.012,
                                                          decoration: BoxDecoration(
                                                              borderRadius: const BorderRadius.all(
                                                                Radius.circular(10),
                                                              ),
                                                              color: Colors.grey.withOpacity(0.5)),
                                                        ),
                                                        SizedBox(height: media.width * 0.02),
                                                        Row(
                                                          // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: Row(
                                                                children: [
                                                                  Image.asset(
                                                                      (driverReq['is_driver_arrived'] == 0)
                                                                          ? 'assets/images/ontheway.png'
                                                                          : (driverReq['is_trip_start'] == 1)
                                                                          ? 'assets/images/ontheway_icon.png'
                                                                          : 'assets/images/startonthe.png',
                                                                      width: media.width * 0.075,
                                                                      color: Colors.white),
                                                                  SizedBox(
                                                                    width: media.width * 0.02,
                                                                  ),
                                                                  Expanded(
                                                                    child: MyText(
                                                                      color: Colors.white,
                                                                      text: (driverReq['is_driver_arrived'] == 0)
                                                                          ? languages[choosenLanguage]['text_in_the_way']
                                                                          : (driverReq['is_trip_start'] == 1)
                                                                          ? (driverReq['drop_address'] == null || distTime == null)
                                                                          ? languages[choosenLanguage]['text_wat_to_drop']
                                                                          : '${languages[choosenLanguage]['text_onride']} ${double.parse(((distTime * 2)).toString()).round()} ${languages[choosenLanguage]['text_mins']}'
                                                                          : languages[choosenLanguage]['text_waiting_rider'],
                                                                      size: media.width * fourteen,
                                                                      fontweight: FontWeight.w700,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            (driverReq['is_driver_arrived'] == 1 && waitingTime != null)
                                                                ? (waitingTime / 60 >= 1)
                                                                ? Container(
                                                              padding: EdgeInsets.all(media.width * 0.03),
                                                              decoration: BoxDecoration(color: topBar, borderRadius: BorderRadius.circular(media.width * 0.02), border: Border.all(color: Colors.grey.withOpacity(0.5))),
                                                              child: (driverReq['accepted_at'] == null && driverReq['show_request_eta_amount'] == true && driverReq['request_eta_amount'] != null)
                                                                  ? MyText(
                                                                text: userDetails['currency_symbol'] + driverReq['request_eta_amount'].toString(),
                                                                size: media.width * fourteen,
                                                                color: isDarkTheme == true ? Colors.black : textColor,
                                                              )
                                                                  : (driverReq['is_driver_arrived'] == 1 && waitingTime != null)
                                                                  ? (waitingTime / 60 >= 1)
                                                                  ? Column(
                                                                children: [
                                                                  MyText(color: Colors.white, text: 'Waiting Time', size: media.width * twelve),
                                                                  SizedBox(
                                                                    height: media.width * 0.015,
                                                                  ),
                                                                  Row(
                                                                    children: [
                                                                      Icon(
                                                                        Icons.alarm_outlined,
                                                                        size: media.width * fourteen,
                                                                      ),
                                                                      MyText(
                                                                        text: '${(waitingTime / 60).toInt()} ${languages[choosenLanguage]['text_mins']}',
                                                                        size: media.width * twelve,
                                                                        color: isDarkTheme == true ? Colors.black : textColor,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              )
                                                                  : Container()
                                                                  : Container(),
                                                            )
                                                                : Container()
                                                                : Container(),
                                                          ],
                                                        ),
                                                        SizedBox(
                                                          height: media.width * 0.05,
                                                        ),
                                                        Column(children: [
                                                          Container(
                                                            padding: EdgeInsets.all(media.width * 0.025),
                                                            width: media.width * 0.9,
                                                            color: borderLines.withOpacity(0.1),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                                  children: [
                                                                    SizedBox(
                                                                      height: media.width * 0.02,
                                                                    ),
                                                                    Row(
                                                                      children: [
                                                                        if (driverReq['userDetail']['data']['profile_picture'] != null)
                                                                          Container(
                                                                            height: media.width * 0.15,
                                                                            width: media.width * 0.15,
                                                                            decoration: BoxDecoration(
                                                                              shape: BoxShape.circle,
                                                                              image: DecorationImage(
                                                                                  image: NetworkImage(
                                                                                    driverReq['userDetail']['data']['profile_picture'].toString(),
                                                                                  ),
                                                                                  fit: BoxFit.cover),
                                                                            ),
                                                                          ),
                                                                        SizedBox(
                                                                          width: media.width * 0.03,
                                                                        ),
                                                                        SizedBox(
                                                                          height: media.width * 0.01,
                                                                        ),
                                                                        Expanded(
                                                                          child: Column(
                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                            children: [
                                                                              MyText(color: Colors.white, text: driverReq['userDetail']['data']['name'], size: media.width * sixteen, fontweight: FontWeight.w500),
                                                                              SizedBox(
                                                                                height: media.width * 0.01,
                                                                              ),
                                                                              Row(
                                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                                mainAxisAlignment: MainAxisAlignment.start,
                                                                                children: [
                                                                                  Icon(
                                                                                    Icons.star,
                                                                                    color: theme,
                                                                                    size: media.width * 0.05,
                                                                                  ),
                                                                                  SizedBox(
                                                                                    width: media.width * 0.005,
                                                                                  ),
                                                                                  Expanded(
                                                                                    child: MyText(
                                                                                      color: Colors.grey,
                                                                                      text: (driverReq['userDetail']['data']['rating'] == 0) ? '0.0' : driverReq['userDetail']['data']['rating'].toString(),
                                                                                      size: media.width * fourteen,
                                                                                      fontweight: FontWeight.w600,
                                                                                      maxLines: 1,
                                                                                    ),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ],
                                                                ),
                                                                SizedBox(
                                                                  height: media.width * 0.03,
                                                                ),
                                                                if (driverReq['is_trip_start'] != 1)
                                                                  Row(
                                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                                    children: [
                                                                      InkWell(
                                                                        onTap: () async {
                                                                          Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatPage()));
                                                                        },
                                                                        child: Container(
                                                                          width: media.width * 0.725,
                                                                          height: media.width * 0.125,
                                                                          decoration: BoxDecoration(color: boxColors, borderRadius: BorderRadius.circular(44)),
                                                                          child: StreamBuilder(
                                                                              stream: null,
                                                                              builder: (context, snapshot) {
                                                                                return Row(
                                                                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                                                  children: [
                                                                                    SizedBox(
                                                                                      width: media.width * 0.05,
                                                                                    ),
                                                                                    const Icon(
                                                                                      Icons.message,
                                                                                      color: Colors.grey,
                                                                                    ),
                                                                                    SizedBox(
                                                                                      width: media.width * 0.025,
                                                                                    ),
                                                                                    Expanded(
                                                                                      child: MyText(
                                                                                        color: (chatList.where((element) => element['from_type'] == 1 && element['seen'] == 0).isNotEmpty) ? theme : Colors.grey,
                                                                                        text: '${languages[choosenLanguage]['text_chatwithuser']} ${driverReq['userDetail']['data']['name'].toString()}',
                                                                                        size: media.width * fourteen,
                                                                                        fontweight: FontWeight.w400,
                                                                                        maxLines: 1,
                                                                                        overflow: TextOverflow.ellipsis,
                                                                                      ),
                                                                                    ),
                                                                                    if (chatList.where((element) => element['from_type'] == 1 && element['seen'] == 0).isNotEmpty)
                                                                                      Row(
                                                                                        children: [
                                                                                          SizedBox(
                                                                                            width: media.width * 0.025,
                                                                                          ),
                                                                                          MyText(
                                                                                            text: chatList.where((element) => element['from_type'] == 1 && element['seen'] == 0).length.toString(),
                                                                                            size: media.width * sixteen,
                                                                                            fontweight: FontWeight.w500,
                                                                                            color: theme,
                                                                                          )
                                                                                        ],
                                                                                      ),
                                                                                    SizedBox(
                                                                                      width: media.width * 0.05,
                                                                                    ),
                                                                                  ],
                                                                                );
                                                                              }),
                                                                        ),
                                                                      ),
                                                                      InkWell(
                                                                        onTap: () {
                                                                          makingPhoneCall(driverReq['userDetail']['data']['mobile']);
                                                                        },
                                                                        child: Container(
                                                                          height: media.width * 0.096,
                                                                          width: media.width * 0.096,
                                                                          decoration: BoxDecoration(border: Border.all(color: const Color(0xff5BDD0A), width: 1), shape: BoxShape.circle),
                                                                          alignment: Alignment.center,
                                                                          child: Image.asset(
                                                                            'assets/images/Call.png',
                                                                            color: const Color(0xff5BDD0A),
                                                                            height: media.width * 0.05,
                                                                            width: media.width * 0.05,
                                                                            fit: BoxFit.contain,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                SizedBox(
                                                                  height: media.width * 0.02,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            height: media.width * 0.03,
                                                          ),
                                                          (driverReq['is_trip_start'] == 1)
                                                              ? Container()
                                                              : Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              InkWell(
                                                                onTap: () async {
                                                                  setState(() {
                                                                    _isLoading = true;
                                                                  });
                                                                  var val = await cancelReason((driverReq['is_driver_arrived'] == 0) ? 'before' : 'after');
                                                                  if (val == true) {
                                                                    setState(() {
                                                                      cancelRequest = true;
                                                                      _cancelReason = '';
                                                                      _cancellingError = '';
                                                                    });
                                                                  }
                                                                  setState(() {
                                                                    _isLoading = false;
                                                                  });
                                                                },
                                                                child: Row(
                                                                  children: [
                                                                    Image.asset(
                                                                      'assets/images/cancelride.png',
                                                                      height: media.width * 0.064,
                                                                      width: media.width * 0.064,
                                                                      fit: BoxFit.contain,
                                                                      color: verifyDeclined,
                                                                    ),
                                                                    MyText(
                                                                      text: languages[choosenLanguage]['text_cancel_booking'],
                                                                      size: media.width * twelve,
                                                                      color: verifyDeclined,
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ]),
                                                        SizedBox(
                                                          height: media.width * 0.03,
                                                        ),
                                                        if (driverReq['show_additional_charge_feature'] == '1' &&
                                                            driverReq['is_trip_start'] == 1)
                                                          InkWell(
                                                              onTap: () {
                                                                additionalChargesAmount = 0.0;
                                                                additionalChargesReason = '';
                                                                additionalChargesError = '';
                                                                if (driverReq['additional_charges_amount'] == 0) {
                                                                  showModalBottomSheet(
                                                                      context: context,
                                                                      isScrollControlled: true,
                                                                      builder: (context) {
                                                                        return Container(
                                                                          padding: MediaQuery.of(context).viewInsets,
                                                                          decoration: BoxDecoration(gradient: _bippGreenFadeGradient(), borderRadius: BorderRadius.only(topLeft: Radius.circular(media.width * 0.05), topRight: Radius.circular(media.width * 0.05))),
                                                                          child: Container(
                                                                            padding: EdgeInsets.all(media.width * 0.05),
                                                                            child: Column(
                                                                              mainAxisSize: MainAxisSize.min,
                                                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                                                              mainAxisAlignment: MainAxisAlignment.start,
                                                                              children: [
                                                                                Padding(
                                                                                  padding: const EdgeInsets.all(8.0),
                                                                                  child: MyText(
                                                                                    textAlign: TextAlign.center,
                                                                                    text: languages[choosenLanguage]['text_additional_charges'],
                                                                                    size: media.width * sixteen,
                                                                                    fontweight: FontWeight.w600,
                                                                                    color: Colors.white,
                                                                                  ),
                                                                                ),
                                                                                SizedBox(
                                                                                  height: media.width * 0.05,
                                                                                ),
                                                                                MyText(
                                                                                  text: languages[choosenLanguage]['text_additional_fees'],
                                                                                  size: media.width * sixteen,
                                                                                  fontweight: FontWeight.w600,
                                                                                  color: Colors.white,
                                                                                ),
                                                                                SizedBox(
                                                                                  height: media.width * 0.025,
                                                                                ),
                                                                                Container(
                                                                                  // margin: EdgeInsets
                                                                                  //     .fromLTRB(
                                                                                  //         0,
                                                                                  //         media.width *
                                                                                  //             0.025,
                                                                                  //         0,
                                                                                  //         media.width *
                                                                                  //             0.025),
                                                                                  padding: EdgeInsets.fromLTRB(media.width * 0.05, 0, media.width * 0.05, 0),
                                                                                  width: media.width * 0.9,
                                                                                  decoration: BoxDecoration(border: Border.all(color: (isDarkTheme == true) ? textColor : textColor, width: 1.2), borderRadius: BorderRadius.circular(7)),
                                                                                  child: TextField(
                                                                                    keyboardType: TextInputType.text,
                                                                                    inputFormatters: [
                                                                                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')), // Only allows alphabetic characters and spaces
                                                                                    ],
                                                                                    decoration: InputDecoration(border: InputBorder.none, hintText: languages[choosenLanguage]['text_charge_details'], hintStyle: GoogleFonts.notoSans(color: Colors.white.withOpacity(0.4), fontSize: media.width * fourteen)),
                                                                                    style: GoogleFonts.notoSans(color: Colors.white),
                                                                                    minLines: 1,
                                                                                    onChanged: (val) {
                                                                                      setState(() {
                                                                                        additionalChargesReason = val;
                                                                                      });
                                                                                    },
                                                                                  ),
                                                                                ),
                                                                                SizedBox(
                                                                                  height: media.width * 0.025,
                                                                                ),
                                                                                Container(
                                                                                  padding: EdgeInsets.fromLTRB(media.width * 0.05, 0, media.width * 0.05, 0),
                                                                                  width: media.width * 0.9,
                                                                                  decoration: BoxDecoration(border: Border.all(color: (isDarkTheme == true) ? textColor : textColor, width: 1.2), borderRadius: BorderRadius.circular(7)),
                                                                                  child: TextField(
                                                                                    keyboardType: TextInputType.numberWithOptions(decimal: true), // This allows numeric input with a decimal point
                                                                                    inputFormatters: [
                                                                                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), // Allow only numbers and the dot (.)
                                                                                    ],
                                                                                    decoration: InputDecoration(border: InputBorder.none, hintText: languages[choosenLanguage]['text_amount'], hintStyle: GoogleFonts.notoSans(color: Colors.white.withOpacity(0.4), fontSize: media.width * fourteen)),
                                                                                    style: GoogleFonts.notoSans(color: Colors.white),
                                                                                    minLines: 1,
                                                                                    onChanged: (val) {
                                                                                      setState(() {
                                                                                        additionalChargesAmount = double.parse(val);
                                                                                      });
                                                                                    },
                                                                                  ),
                                                                                ),
                                                                                (additionalChargesError != '') ? Container(padding: EdgeInsets.only(top: media.width * 0.02, bottom: media.width * 0.02), width: media.width * 0.9, child: Text(additionalChargesError, style: GoogleFonts.notoSans(fontSize: media.width * twelve, color: Colors.red))) : Container(),
                                                                                SizedBox(
                                                                                  height: media.width * 0.05,
                                                                                ),
                                                                                Button(
                                                                                    width: media.width * 0.5,
                                                                                    onTap: () async {
                                                                                      if (additionalChargesAmount != 0.0 && additionalChargesReason != '') {
                                                                                        setState(() {
                                                                                          _isLoading = true;
                                                                                        });
                                                                                        var val = await additionalCharge(additionalChargesReason, additionalChargesAmount);
                                                                                        if (val == true) {
                                                                                          setState(() {
                                                                                            _isLoading = true;
                                                                                          });
                                                                                          Navigator.pop(context);
                                                                                          setState(() {
                                                                                            _isLoading = false;
                                                                                          });
                                                                                        }
                                                                                        setState(() {
                                                                                          _isLoading = false;
                                                                                        });
                                                                                      } else {
                                                                                        setState(() {
                                                                                          additionalChargesError = languages[choosenLanguage]['text_please_fill_all_fields'];
                                                                                        });
                                                                                      }
                                                                                    },
                                                                                    text: languages[choosenLanguage]['text_confirm'])
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        );
                                                                      });
                                                                }
                                                              },
                                                              child: MyText(
                                                                color: Colors.white,
                                                                text: (driverReq['additional_charges_amount'] == 0) ? '${languages[choosenLanguage]['text_additional_charges']} ?' : '${languages[choosenLanguage]['text_additional_charges']} : ${driverReq['additional_charges_amount'].toString()}',
                                                                size: media.width * fourteen,
                                                                fontweight: FontWeight.w600,
                                                              )),
                                                        SizedBox(
                                                          height: media.width * 0.03,
                                                        ),
                                                        (driverReq['transport_type'] == 'taxi')
                                                            ? Button(
                                                            onTap: () async {
                                                              navigationtype = false;
                                                              setState(() {
                                                                _isLoading = true;
                                                              });
                                                              if ((driverReq['is_driver_arrived'] == 0)) {
                                                                var val = await driverArrived();
                                                                if (val == 'logout') {
                                                                  navigateLogout();
                                                                }
                                                              } else if (driverReq['is_driver_arrived'] == 1 && driverReq['is_trip_start'] == 0) {
                                                                if (driverReq['show_otp_feature'] == true) {
                                                                  setState(() {
                                                                    _errorOtp = false;
                                                                    getStartOtp = true;
                                                                  });
                                                                } else {
                                                                  var val = await tripStartDispatcher();
                                                                  if (val == 'logout') {
                                                                    navigateLogout();
                                                                  }
                                                                }
                                                              } else {
                                                                if (tripStops.isNotEmpty) {
                                                                  tempStopId = null;
                                                                  List sublist = tripStops.sublist(0, tripStops.length - 1);
                                                                  if (sublist.any((task) => task['completed_at'] == null)) {
                                                                    showModalBottomSheet(
                                                                        context: context,
                                                                        isScrollControlled: true,
                                                                        builder: (context) {
                                                                          return const TripStopsBottomSheet();
                                                                        });
                                                                  } else {
                                                                    driverOtp = '';
                                                                    var val = await endTrip();
                                                                    if (val == 'logout') {
                                                                      navigateLogout();
                                                                    }
                                                                  }
                                                                } else {
                                                                  driverOtp = '';
                                                                  var val = await endTrip();
                                                                  if (val == 'logout') {
                                                                    navigateLogout();
                                                                  }
                                                                }
                                                              }

                                                              _isLoading = false;
                                                            },
                                                            text: (driverReq['is_driver_arrived'] == 0)
                                                                ? languages[choosenLanguage]['text_arrived']
                                                                : (driverReq['is_driver_arrived'] == 1 && driverReq['is_trip_start'] == 0)
                                                                ? languages[choosenLanguage]['text_startride']
                                                                : languages[choosenLanguage]['text_endtrip'])
                                                            : Button(
                                                            onTap: () async {
                                                              navigationtype = false;
                                                              setState(() {
                                                                _isLoading = true;
                                                              });
                                                              if ((driverReq['is_driver_arrived'] == 0)) {
                                                                var val = await driverArrived();
                                                                if (val == 'logout') {
                                                                  navigateLogout();
                                                                }
                                                              } else if (driverReq['is_driver_arrived'] == 1 && driverReq['is_trip_start'] == 0) {
                                                                if (driverReq['show_otp_feature'] == false && driverReq['enable_shipment_load_feature'].toString() == '0') {
                                                                  var val = await tripStartDispatcher();
                                                                  if (val == 'logout') {
                                                                    navigateLogout();
                                                                  }
                                                                } else {
                                                                  setState(() {
                                                                    shipLoadImage = null;
                                                                    _errorOtp = false;
                                                                    getStartOtp = true;
                                                                  });
                                                                }
                                                              } else if (tripStops.isNotEmpty) {
                                                                tempStopId = null;
                                                                List sublist = tripStops.sublist(0, tripStops.length - 1);
                                                                if (sublist.any((task) => task['completed_at'] == null)) {
                                                                  showModalBottomSheet(
                                                                      context: context,
                                                                      isScrollControlled: true,
                                                                      builder: (context) {
                                                                        return const TripStopsBottomSheet();
                                                                      });
                                                                } else {
                                                                  if (driverReq['enable_shipment_unload_feature'].toString() == '1') {
                                                                    setState(() {
                                                                      unloadImage = true;
                                                                    });
                                                                  } else if (driverReq['enable_shipment_unload_feature'].toString() == '0' && driverReq['enable_digital_signature'].toString() == '1') {
                                                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DigitalSignature()));
                                                                  } else {
                                                                    var val = await endTrip();
                                                                    if (val == 'logout') {
                                                                      navigateLogout();
                                                                    }
                                                                  }
                                                                }
                                                              } else {
                                                                if (driverReq['enable_shipment_unload_feature'].toString() == '1') {
                                                                  setState(() {
                                                                    unloadImage = true;
                                                                  });
                                                                } else if (driverReq['enable_shipment_unload_feature'].toString() == '0' && driverReq['enable_digital_signature'].toString() == '1') {
                                                                  Navigator.push(context, MaterialPageRoute(builder: (context) => const DigitalSignature()));
                                                                } else {
                                                                  var val = await endTrip();
                                                                  if (val == 'logout') {
                                                                    navigateLogout();
                                                                  }
                                                                }
                                                              }

                                                              _isLoading = false;
                                                            },
                                                            text: (driverReq['is_driver_arrived'] == 0)
                                                                ? languages[choosenLanguage]['text_arrived']
                                                                : (driverReq['is_driver_arrived'] == 1 && driverReq['is_trip_start'] == 0)
                                                                ? languages[choosenLanguage]['text_shipment_load']
                                                                : languages[choosenLanguage]['text_shipment_unload']),
                                                        SizedBox(
                                                          height: media.width * 0.05,
                                                        ),
                                                        Expanded(
                                                          child: SingleChildScrollView(
                                                            controller: _cont,
                                                            physics: (addressBottom != null && addressBottom <= (media.height * 0.25)) ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                                                            child: Column(
                                                              children: [
                                                                if (driverReq['transport_type'] == 'delivery')
                                                                  Column(
                                                                    children: [
                                                                      SizedBox(
                                                                        height: media.width * 0.02,
                                                                      ),
                                                                      SizedBox(
                                                                        width: media.width * 0.9,
                                                                        child: Text(
                                                                          '${driverReq['goods_type']} - ${driverReq['goods_type_quantity']}',
                                                                          style: GoogleFonts.notoSans(fontSize: media.width * fourteen, fontWeight: FontWeight.w600, color: buttonColor),
                                                                          textAlign: TextAlign.center,
                                                                          maxLines: 2,
                                                                          overflow: TextOverflow.ellipsis,
                                                                        ),
                                                                      ),
                                                                      SizedBox(
                                                                        height: media.width * 0.02,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                Column(
                                                                  children: addressList
                                                                      .asMap()
                                                                      .map((k, value) => MapEntry(
                                                                      k,
                                                                      (addressList[k].type == 'pickup')
                                                                          ? Column(
                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                        children: [
                                                                          Container(
                                                                            width: media.width * 0.9,
                                                                            padding: EdgeInsets.all(media.width * 0.03),
                                                                            margin: EdgeInsets.only(bottom: media.width * 0.02),
                                                                            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                                            child: Column(
                                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                                              mainAxisAlignment: MainAxisAlignment.start,
                                                                              children: [
                                                                                Row(
                                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                                  children: [
                                                                                    Padding(
                                                                                      padding: const EdgeInsets.all(4.0),
                                                                                      child: Container(
                                                                                        width: media.width * 0.05,
                                                                                        height: media.width * 0.05,
                                                                                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withOpacity(0.4)),
                                                                                        alignment: Alignment.center,
                                                                                        child: Container(
                                                                                          width: media.width * 0.025,
                                                                                          height: media.width * 0.025,
                                                                                          decoration: const BoxDecoration(
                                                                                            shape: BoxShape.circle,
                                                                                            color: Colors.green,
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    SizedBox(
                                                                                      width: media.width * 0.02,
                                                                                    ),
                                                                                    Expanded(
                                                                                      child: Column(
                                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                                        children: [
                                                                                          Row(
                                                                                            mainAxisAlignment: MainAxisAlignment.start,
                                                                                            children: [
                                                                                              MyText(
                                                                                                text: languages[choosenLanguage]['text_pick_up_location'],
                                                                                                size: media.width * fourteen,
                                                                                                fontweight: FontWeight.w600,
                                                                                                color: Colors.white,
                                                                                              ),
                                                                                            ],
                                                                                          ),
                                                                                          MyText(
                                                                                            color: greyText,
                                                                                            text: (addressList[k].type == 'pickup') ? addressList[k].address : 'nil',
                                                                                            size: media.width * twelve,
                                                                                            fontweight: FontWeight.normal,
                                                                                            maxLines: 5,
                                                                                          ),
                                                                                        ],
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      )
                                                                          : Container()))
                                                                      .values
                                                                      .toList(),
                                                                ),
                                                                Column(
                                                                    children: addressList
                                                                        .asMap()
                                                                        .map((k, value) => MapEntry(
                                                                        k,
                                                                        (addressList[k].type == 'drop')
                                                                            ? Column(
                                                                          children: [
                                                                            (k == addressList.length - 1)
                                                                                ? Container(
                                                                              width: media.width * 0.9,
                                                                              padding: EdgeInsets.all(media.width * 0.03),
                                                                              margin: EdgeInsets.only(bottom: media.width * 0.02),
                                                                              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                                              child: Column(
                                                                                children: [
                                                                                  Row(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                      Padding(
                                                                                        padding: const EdgeInsets.all(4.0),
                                                                                        child: Icon(
                                                                                          Icons.location_on,
                                                                                          size: media.width * 0.05,
                                                                                          color: const Color(0xffF52D56),
                                                                                        ),
                                                                                      ),
                                                                                      SizedBox(
                                                                                        width: media.width * 0.02,
                                                                                      ),
                                                                                      Expanded(
                                                                                        child: Column(
                                                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                                                          children: [
                                                                                            Row(
                                                                                              mainAxisAlignment: MainAxisAlignment.start,
                                                                                              children: [
                                                                                                MyText(
                                                                                                  text: languages[choosenLanguage]['text_droppoint'],
                                                                                                  size: media.width * fourteen,
                                                                                                  fontweight: FontWeight.w600,
                                                                                                  color: Colors.white,
                                                                                                ),
                                                                                              ],
                                                                                            ),
                                                                                            MyText(
                                                                                              color: greyText,
                                                                                              text: (addressList[k].type == 'drop') ? addressList[k].address : 'nil',
                                                                                              size: media.width * twelve,
                                                                                              fontweight: FontWeight.normal,
                                                                                              maxLines: 5,
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                      if (driverReq['transport_type'] == 'delivery' && driverReq['is_trip_start'] == 1)
                                                                                        IconButton(
                                                                                            onPressed: () {
                                                                                              makingPhoneCall(addressList[k].number);
                                                                                            },
                                                                                            icon: const Icon(Icons.call))
                                                                                    ],
                                                                                  ),
                                                                                  if (driverReq['transport_type'] == 'delivery' && driverReq['is_trip_start'] == 0)
                                                                                    SizedBox(
                                                                                      height: media.width * 0.025,
                                                                                    ),
                                                                                  if (addressList[k].instructions != null)
                                                                                    Column(
                                                                                      children: [
                                                                                        Row(
                                                                                          children: [
                                                                                            for (var i = 0; i < 50; i++)
                                                                                              Container(
                                                                                                margin: EdgeInsets.only(right: (i < 49) ? 2 : 0),
                                                                                                width: (media.width * 0.8 - 98) / 50,
                                                                                                height: 1,
                                                                                                color: borderColor,
                                                                                              )
                                                                                          ],
                                                                                        ),
                                                                                        SizedBox(
                                                                                          height: media.width * 0.015,
                                                                                        ),
                                                                                        Row(
                                                                                          children: [
                                                                                            MyText(
                                                                                              color: Colors.red,
                                                                                              text: languages[choosenLanguage]['text_instructions'] + ' :- ',
                                                                                              size: media.width * twelve,
                                                                                              fontweight: FontWeight.w600,
                                                                                              maxLines: 1,
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                        SizedBox(
                                                                                          height: media.width * 0.015,
                                                                                        ),
                                                                                        Row(
                                                                                          children: [
                                                                                            SizedBox(
                                                                                              width: media.width * 0.1,
                                                                                            ),
                                                                                            Expanded(
                                                                                              child: MyText(
                                                                                                color: greyText,
                                                                                                text: (addressList[k].type == 'drop') ? addressList[k].instructions : 'nil',
                                                                                                size: media.width * twelve,
                                                                                                fontweight: FontWeight.normal,
                                                                                                maxLines: 5,
                                                                                              ),
                                                                                            ),
                                                                                          ],
                                                                                        )
                                                                                      ],
                                                                                    ),
                                                                                ],
                                                                              ),
                                                                            )
                                                                                : Container(
                                                                              width: media.width * 0.9,
                                                                              padding: EdgeInsets.all(media.width * 0.03),
                                                                              margin: EdgeInsets.only(bottom: media.width * 0.02),
                                                                              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                                              child: Column(
                                                                                children: [
                                                                                  Row(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                      Container(
                                                                                        height: media.width * 0.05,
                                                                                        width: media.width * 0.05,
                                                                                        alignment: Alignment.center,
                                                                                        child: MyText(
                                                                                          text: (k).toString(),
                                                                                          size: media.width * fourteen,
                                                                                          color: verifyDeclined,
                                                                                          fontweight: FontWeight.w600,
                                                                                        ),
                                                                                      ),
                                                                                      SizedBox(
                                                                                        width: media.width * 0.02,
                                                                                      ),
                                                                                      Expanded(
                                                                                        child: Column(
                                                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                                                          children: [
                                                                                            MyText(
                                                                                              color: greyText,
                                                                                              text: (addressList[k].type == 'drop') ? addressList[k].address : 'nil',
                                                                                              size: media.width * twelve,
                                                                                              fontweight: FontWeight.normal,
                                                                                              maxLines: 5,
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                      if (driverReq['transport_type'] == 'delivery' && driverReq['is_trip_start'] == 1)
                                                                                        IconButton(
                                                                                            onPressed: () {
                                                                                              makingPhoneCall(addressList[k].number);
                                                                                            },
                                                                                            icon: const Icon(Icons.call))
                                                                                    ],
                                                                                  ),
                                                                                  if (addressList[k].instructions != null)
                                                                                    Column(
                                                                                      children: [
                                                                                        Row(
                                                                                          children: [
                                                                                            for (var i = 0; i < 50; i++)
                                                                                              Container(
                                                                                                margin: EdgeInsets.only(right: (i < 49) ? 2 : 0),
                                                                                                width: (media.width * 0.8 - 98) / 50,
                                                                                                height: 1,
                                                                                                color: borderColor,
                                                                                              )
                                                                                          ],
                                                                                        ),
                                                                                        SizedBox(
                                                                                          height: media.width * 0.015,
                                                                                        ),
                                                                                        Row(
                                                                                          children: [
                                                                                            MyText(
                                                                                              color: Colors.red,
                                                                                              text: languages[choosenLanguage]['text_instructions'] + ' :- ',
                                                                                              size: media.width * twelve,
                                                                                              fontweight: FontWeight.w600,
                                                                                              maxLines: 1,
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                        SizedBox(
                                                                                          height: media.width * 0.015,
                                                                                        ),
                                                                                        Row(
                                                                                          children: [
                                                                                            SizedBox(
                                                                                              width: media.width * 0.1,
                                                                                            ),
                                                                                            Expanded(
                                                                                              child: MyText(
                                                                                                color: greyText,
                                                                                                text: (addressList[k].type == 'drop') ? addressList[k].instructions : 'nil',
                                                                                                size: media.width * twelve,
                                                                                                fontweight: FontWeight.normal,
                                                                                                maxLines: 5,
                                                                                              ),
                                                                                            ),
                                                                                          ],
                                                                                        )
                                                                                      ],
                                                                                    ),
                                                                                ],
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        )
                                                                            : Container()))
                                                                        .values
                                                                        .toList()),
                                                                SizedBox(
                                                                  height: media.width * 0.025,
                                                                ),
                                                                (driverReq['is_luggage_available'] == 1 || driverReq['is_pet_available'] == 1)
                                                                    ? Column(
                                                                  children: [
                                                                    Row(
                                                                      children: [
                                                                        MyText(
                                                                          color: Colors.white,
                                                                          text: languages[choosenLanguage]['text_ride_preference'] + ' :- ',
                                                                          size: media.width * fourteen,
                                                                          fontweight: FontWeight.w600,
                                                                        ),
                                                                        SizedBox(
                                                                          width: media.width * 0.025,
                                                                        ),
                                                                        if (driverReq['is_pet_available'] == 1)
                                                                          Row(
                                                                            children: [
                                                                              Icon(Icons.pets, size: media.width * 0.05, color: theme),
                                                                              SizedBox(
                                                                                width: media.width * 0.01,
                                                                              ),
                                                                              MyText(
                                                                                text: languages[choosenLanguage]['text_pets'],
                                                                                size: media.width * fourteen,
                                                                                fontweight: FontWeight.w600,
                                                                                color: theme,
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        if (driverReq['is_luggage_available'] == 1 && driverReq['is_pet_available'] == 1)
                                                                          MyText(
                                                                            text: ', ',
                                                                            size: media.width * fourteen,
                                                                            fontweight: FontWeight.w600,
                                                                            color: theme,
                                                                          ),
                                                                        if (driverReq['is_luggage_available'] == 1)
                                                                          Row(
                                                                            children: [
                                                                              // Icon(Icons.luggage, size: media.width * 0.05, color: theme),
                                                                              SizedBox(
                                                                                height: media.width * 0.05,
                                                                                width: media.width * 0.075,
                                                                                child: Image.asset(
                                                                                  'assets/images/luggages.png',
                                                                                  color: theme,
                                                                                ),
                                                                              ),
                                                                              SizedBox(
                                                                                width: media.width * 0.01,
                                                                              ),
                                                                              MyText(
                                                                                text: languages[choosenLanguage]['text_luggages'],
                                                                                size: media.width * fourteen,
                                                                                fontweight: FontWeight.w600,
                                                                                color: theme,
                                                                              ),
                                                                            ],
                                                                          ),
                                                                      ],
                                                                    ),
                                                                    SizedBox(
                                                                      height: media.width * 0.025,
                                                                    ),
                                                                  ],
                                                                )
                                                                    : Container(),
                                                                (driverReq['is_rental'] == false && driverReq['drop_address'] == null)
                                                                    ? Container()
                                                                    : Container(
                                                                  width: media.width * 0.9,
                                                                  padding: EdgeInsets.all(media.width * 0.03),
                                                                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(media.width * 0.02)),
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      MyText(
                                                                        text: languages[choosenLanguage]['text_payingvia'],
                                                                        size: media.width * fourteen,
                                                                        fontweight: FontWeight.w600,
                                                                        color: Colors.white,
                                                                      ),
                                                                      SizedBox(
                                                                        height: media.width * 0.025,
                                                                      ),
                                                                      Row(
                                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                        children: [
                                                                          Expanded(
                                                                            child: Row(
                                                                              children: [
                                                                                Image.asset(
                                                                                  (driverReq['payment_opt'].toString() == '1')
                                                                                      ? 'assets/images/cash.png'
                                                                                      : (driverReq['payment_opt'].toString() == '2')
                                                                                      ? 'assets/images/wallet.png'
                                                                                      : 'assets/images/card.png',
                                                                                  width: media.width * 0.07,
                                                                                  height: media.width * 0.07,
                                                                                  fit: BoxFit.contain,
                                                                                ),
                                                                                SizedBox(
                                                                                  width: media.width * 0.02,
                                                                                ),
                                                                                MyText(
                                                                                    color: Colors.white,
                                                                                    text: (driverReq['payment_opt'].toString() == '1')
                                                                                        ? languages[choosenLanguage]['text_cash']
                                                                                        : (driverReq['payment_opt'].toString() == '2')
                                                                                        ? languages[choosenLanguage]['text_wallet']
                                                                                        : languages[choosenLanguage]['text_card'],
                                                                                    size: media.width * sixteen,
                                                                                    fontweight: FontWeight.w600)
                                                                              ],
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width: media.width * 0.02,
                                                                          ),
                                                                          Row(
                                                                            mainAxisAlignment: MainAxisAlignment.end,
                                                                            children: [
                                                                              SizedBox(
                                                                                width: media.width * 0.02,
                                                                              ),
                                                                              MyText(
                                                                                text: ((driverReq['is_bid_ride'] == 1)) ? '${driverReq['requested_currency_symbol']}${driverReq['accepted_ride_fare'].toString()}' : '${driverReq['requested_currency_symbol']}${driverReq['request_eta_amount'].toString()}',
                                                                                size: media.width * sixteen,
                                                                                fontweight: FontWeight.w600,
                                                                                color: Colors.white,
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  height: media.height * 0.25,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        )
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                            : Container(),

                                        //user cancelled request popup
                                        (_reqCancelled == true)
                                            ? Positioned(
                                            bottom: media
                                                .height *
                                                0.5,
                                            child:
                                            Container(
                                                padding:
                                                EdgeInsets.all(media.width *
                                                    0.05),
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                    BorderRadius.circular(10),
                                                    gradient: _bippGreenFadeGradient(),
                                                    boxShadow: [
                                                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2, spreadRadius: 2)
                                                    ]),
                                                child:
                                                MyText(
                                                  text: languages[choosenLanguage]
                                                  [
                                                  'text_user_cancelled_request'],
                                                  size: media.width *
                                                      fourteen,
                                                  color: (isDarkTheme == true)
                                                      ? Colors.white
                                                      : Colors.black,
                                                )))
                                            : Container(),
                                      ],
                                    )
                                        : Container(),
                                  ]),
                            ),
                            (_locationDenied == true)
                                ? Positioned(
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: media.width * 0.9,
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _locationDenied = false;
                                                });
                                              },
                                              child: Container(
                                                height: media.height * 0.05,
                                                width: media.height * 0.05,
                                                decoration: BoxDecoration(
                                                  gradient: _bippGreenFadeGradient(),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(Icons.cancel,
                                                    color: buttonColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: media.width * 0.025),
                                      Container(
                                        padding: EdgeInsets.all(
                                            media.width * 0.05),
                                        width: media.width * 0.9,
                                        decoration: BoxDecoration(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            gradient: _bippGreenFadeGradient(),
                                            boxShadow: [
                                              BoxShadow(
                                                  blurRadius: 2.0,
                                                  spreadRadius: 2.0,
                                                  color: Colors.black
                                                      .withOpacity(0.2))
                                            ]),
                                        child: Column(
                                          children: [
                                            SizedBox(
                                                width: media.width * 0.8,
                                                child: Text(
                                                  languages[choosenLanguage]
                                                  [
                                                  'text_open_loc_settings'],
                                                  style:
                                                  GoogleFonts.notoSans(
                                                      fontSize:
                                                      media.width *
                                                          sixteen,
                                                      color: Colors.white,
                                                      fontWeight:
                                                      FontWeight
                                                          .w600),
                                                )),
                                            SizedBox(
                                                height: media.width * 0.05),
                                            Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                              children: [
                                                InkWell(
                                                    onTap: () async {
                                                      await perm
                                                          .openAppSettings();
                                                    },
                                                    child: Text(
                                                      languages[
                                                      choosenLanguage]
                                                      [
                                                      'text_open_settings'],
                                                      style: GoogleFonts.notoSans(
                                                          fontSize:
                                                          media.width *
                                                              sixteen,
                                                          color:
                                                          buttonColor,
                                                          fontWeight:
                                                          FontWeight
                                                              .w600),
                                                    )),
                                                InkWell(
                                                    onTap: () async {
                                                      setState(() {
                                                        _locationDenied =
                                                        false;
                                                        _isLoading = true;
                                                      });

                                                      getLocs();
                                                    },
                                                    child: Text(
                                                      languages[
                                                      choosenLanguage]
                                                      ['text_done'],
                                                      style: GoogleFonts.notoSans(
                                                          fontSize:
                                                          media.width *
                                                              sixteen,
                                                          color:
                                                          buttonColor,
                                                          fontWeight:
                                                          FontWeight
                                                              .w600),
                                                    ))
                                              ],
                                            )
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ))
                                : Container(),
                            //enter otp
                            (getStartOtp == true &&
                                driverReq.isNotEmpty &&
                                driverReq['enable_shipment_load_feature']
                                    .toString() !=
                                    '1')
                                ? Positioned(
                              top: 0,
                              child: Container(
                                height: media.height * 1,
                                width: media.width * 1,
                                color:
                                Colors.transparent.withOpacity(0.5),
                                child: Column(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: media.width * 0.8,
                                      child: Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.end,
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                getStartOtp = false;
                                              });
                                            },
                                            child: Container(
                                              height:
                                              media.height * 0.05,
                                              width:
                                              media.height * 0.05,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: borderLines
                                                        .withOpacity(
                                                        0.5)),
                                                gradient: _bippGreenFadeGradient(),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(Icons.cancel,
                                                  color: buttonColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                        height: media.width * 0.025),
                                    Container(
                                      padding: EdgeInsets.all(
                                          media.width * 0.05),
                                      width: media.width * 0.8,
                                      // height: media.width * 0.7,
                                      decoration: BoxDecoration(
                                          borderRadius:
                                          BorderRadius.circular(10),
                                          border: Border.all(
                                              color: borderLines
                                                  .withOpacity(0.5)),
                                          gradient: _bippGreenFadeGradient(),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                spreadRadius: 2,
                                                blurRadius: 2)
                                          ]),
                                      child: Column(
                                        children: [
                                          Text(
                                            languages[choosenLanguage]
                                            ['text_driver_otp'],
                                            style: GoogleFonts.notoSans(
                                                fontSize: media.width *
                                                    eighteen,
                                                fontWeight:
                                                FontWeight.bold,
                                                color: Colors.white),
                                          ),
                                          SizedBox(
                                              height:
                                              media.width * 0.05),
                                          Text(
                                            languages[choosenLanguage]
                                            ['text_enterdriverotp'],
                                            style: GoogleFonts.notoSans(
                                              fontSize:
                                              media.width * twelve,
                                              color: Colors.white
                                                  .withOpacity(0.7),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          SizedBox(
                                            height: media.width * 0.05,
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment
                                                .spaceAround,
                                            children: [
                                              Container(
                                                alignment:
                                                Alignment.center,
                                                width:
                                                media.width * 0.12,
                                                decoration: _bippGreenFadeDecoration(),
                                                child: TextFormField(
                                                  onChanged: (val) {
                                                    if (val.length ==
                                                        1) {
                                                      setState(() {
                                                        _otp1 = val;
                                                        driverOtp =
                                                            _otp1 +
                                                                _otp2 +
                                                                _otp3 +
                                                                _otp4;
                                                        FocusScope.of(
                                                            context)
                                                            .nextFocus();
                                                      });
                                                    }
                                                  },
                                                  keyboardType:
                                                  TextInputType
                                                      .number,
                                                  maxLength: 1,
                                                  textAlign:
                                                  TextAlign.center,
                                                  style: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          sixteen,
                                                      fontWeight:
                                                      FontWeight
                                                          .bold,
                                                      color: Colors.white),
                                                  decoration: const InputDecoration(
                                                      counterText: '',
                                                      border: UnderlineInputBorder(
                                                          borderSide: BorderSide(
                                                              color: Colors
                                                                  .black,
                                                              width:
                                                              1.5,
                                                              style: BorderStyle
                                                                  .solid))),
                                                ),
                                              ),
                                              Container(
                                                alignment:
                                                Alignment.center,
                                                width:
                                                media.width * 0.12,
                                                decoration: _bippGreenFadeDecoration(),
                                                child: TextFormField(
                                                  onChanged: (val) {
                                                    if (val.length ==
                                                        1) {
                                                      setState(() {
                                                        _otp2 = val;
                                                        driverOtp =
                                                            _otp1 +
                                                                _otp2 +
                                                                _otp3 +
                                                                _otp4;
                                                        FocusScope.of(
                                                            context)
                                                            .nextFocus();
                                                      });
                                                    } else {
                                                      setState(() {
                                                        FocusScope.of(
                                                            context)
                                                            .previousFocus();
                                                      });
                                                    }
                                                  },
                                                  style: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          sixteen,
                                                      fontWeight:
                                                      FontWeight
                                                          .bold,
                                                      color: Colors.white),
                                                  keyboardType:
                                                  TextInputType
                                                      .number,
                                                  maxLength: 1,
                                                  textAlign:
                                                  TextAlign.center,
                                                  decoration: const InputDecoration(
                                                      counterText: '',
                                                      border: UnderlineInputBorder(
                                                          borderSide: BorderSide(
                                                              color: Colors
                                                                  .black,
                                                              width:
                                                              1.5,
                                                              style: BorderStyle
                                                                  .solid))),
                                                ),
                                              ),
                                              Container(
                                                alignment:
                                                Alignment.center,
                                                width:
                                                media.width * 0.12,
                                                decoration: _bippGreenFadeDecoration(),
                                                child: TextFormField(
                                                  onChanged: (val) {
                                                    if (val.length ==
                                                        1) {
                                                      setState(() {
                                                        _otp3 = val;
                                                        driverOtp =
                                                            _otp1 +
                                                                _otp2 +
                                                                _otp3 +
                                                                _otp4;
                                                        FocusScope.of(
                                                            context)
                                                            .nextFocus();
                                                      });
                                                    } else {
                                                      setState(() {
                                                        FocusScope.of(
                                                            context)
                                                            .previousFocus();
                                                      });
                                                    }
                                                  },
                                                  style: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          sixteen,
                                                      fontWeight:
                                                      FontWeight
                                                          .bold,
                                                      color: Colors.white),
                                                  keyboardType:
                                                  TextInputType
                                                      .number,
                                                  maxLength: 1,
                                                  textAlign:
                                                  TextAlign.center,
                                                  decoration: const InputDecoration(
                                                      counterText: '',
                                                      border: UnderlineInputBorder(
                                                          borderSide: BorderSide(
                                                              color: Colors
                                                                  .black,
                                                              width:
                                                              1.5,
                                                              style: BorderStyle
                                                                  .solid))),
                                                ),
                                              ),
                                              Container(
                                                alignment:
                                                Alignment.center,
                                                width:
                                                media.width * 0.12,
                                                decoration: _bippGreenFadeDecoration(),
                                                child: TextFormField(
                                                  onChanged: (val) {
                                                    if (val.length ==
                                                        1) {
                                                      setState(() {
                                                        _otp4 = val;
                                                        driverOtp =
                                                            _otp1 +
                                                                _otp2 +
                                                                _otp3 +
                                                                _otp4;
                                                        FocusScope.of(
                                                            context)
                                                            .nextFocus();
                                                      });
                                                    } else {
                                                      setState(() {
                                                        FocusScope.of(
                                                            context)
                                                            .previousFocus();
                                                      });
                                                    }
                                                  },
                                                  style: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          sixteen,
                                                      fontWeight:
                                                      FontWeight
                                                          .bold,
                                                      color: Colors.white),
                                                  keyboardType:
                                                  TextInputType
                                                      .number,
                                                  maxLength: 1,
                                                  textAlign:
                                                  TextAlign.center,
                                                  decoration: const InputDecoration(
                                                      counterText: '',
                                                      border: UnderlineInputBorder(
                                                          borderSide: BorderSide(
                                                              color: Colors
                                                                  .black,
                                                              width:
                                                              1.5,
                                                              style: BorderStyle
                                                                  .solid))),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(
                                            height: media.width * 0.04,
                                          ),
                                          (_errorOtp == true)
                                              ? Text(
                                            languages[
                                            choosenLanguage]
                                            [
                                            'text_error_trip_otp'],
                                            style: GoogleFonts
                                                .notoSans(
                                                color: Colors
                                                    .red,
                                                fontSize: media
                                                    .width *
                                                    twelve),
                                          )
                                              : Container(),
                                          SizedBox(
                                              height:
                                              media.width * 0.02),
                                          Button(
                                            onTap: () async {
                                              if (driverOtp.length !=
                                                  4) {
                                                setState(() {});
                                              } else {
                                                setState(() {
                                                  _errorOtp = false;
                                                  _isLoading = true;
                                                });
                                                var val =
                                                await tripStart();
                                                if (val == 'logout') {
                                                  navigateLogout();
                                                } else if (val !=
                                                    'success') {
                                                  setState(() {
                                                    _errorOtp = true;
                                                    _isLoading = false;
                                                  });
                                                } else {
                                                  setState(() {
                                                    _isLoading = false;
                                                    getStartOtp = false;
                                                  });
                                                }
                                              }
                                            },
                                            text: languages[
                                            choosenLanguage]
                                            ['text_confirm'],
                                          )
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                                : (getStartOtp == true &&
                                driverReq.isNotEmpty)
                                ? Positioned(
                              top: 0,
                              child: Container(
                                height: media.height * 1,
                                width: media.width * 1,
                                padding: EdgeInsets.fromLTRB(
                                    media.width * 0.1,
                                    MediaQuery.of(context)
                                        .padding
                                        .top +
                                        media.width * 0.05,
                                    media.width * 0.1,
                                    media.width * 0.05),
                                decoration: _bippGreenFadeDecoration(),
                                child: Column(
                                  mainAxisAlignment:
                                  MainAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: media.width * 0.8,
                                      child: Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.end,
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                getStartOtp = false;
                                              });
                                            },
                                            child: Container(
                                              height: media.height *
                                                  0.05,
                                              width: media.height *
                                                  0.05,
                                              decoration:
                                              BoxDecoration(
                                                gradient: _bippGreenFadeGradient(),
                                                shape:
                                                BoxShape.circle,
                                              ),
                                              child: Icon(
                                                  Icons.cancel,
                                                  color:
                                                  buttonColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                        height:
                                        media.width * 0.025),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            (driverReq['show_otp_feature'] ==
                                                true)
                                                ? Column(children: [
                                              Text(
                                                languages[
                                                choosenLanguage]
                                                [
                                                'text_driver_otp'],
                                                style: GoogleFonts.notoSans(
                                                    fontSize:
                                                    media.width *
                                                        eighteen,
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    color: Colors.white),
                                              ),
                                              SizedBox(
                                                  height: media
                                                      .width *
                                                      0.05),
                                              Text(
                                                languages[
                                                choosenLanguage]
                                                [
                                                'text_enterdriverotp'],
                                                style: GoogleFonts
                                                    .notoSans(
                                                  fontSize: media
                                                      .width *
                                                      twelve,
                                                  color: Colors.white
                                                      .withOpacity(
                                                      0.7),
                                                ),
                                                textAlign:
                                                TextAlign
                                                    .center,
                                              ),
                                              SizedBox(
                                                height: media
                                                    .width *
                                                    0.05,
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                MainAxisAlignment
                                                    .spaceAround,
                                                children: [
                                                  Container(
                                                    alignment:
                                                    Alignment
                                                        .center,
                                                    width: media
                                                        .width *
                                                        0.12,
                                                    decoration: _bippGreenFadeDecoration(),
                                                    child:
                                                    TextFormField(
                                                      onChanged:
                                                          (val) {
                                                        if (val.length ==
                                                            1) {
                                                          setState(() {
                                                            _otp1 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).nextFocus();
                                                          });
                                                        }
                                                      },
                                                      style: GoogleFonts.notoSans(
                                                          color: Colors.white,
                                                          fontSize:
                                                          media.width * sixteen),
                                                      keyboardType:
                                                      TextInputType.number,
                                                      maxLength:
                                                      1,
                                                      textAlign:
                                                      TextAlign.center,
                                                      decoration: InputDecoration(
                                                          counterText:
                                                          '',
                                                          border:
                                                          UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 1.5, style: BorderStyle.solid))),
                                                    ),
                                                  ),
                                                  Container(
                                                    alignment:
                                                    Alignment
                                                        .center,
                                                    width: media
                                                        .width *
                                                        0.12,
                                                    decoration: _bippGreenFadeDecoration(),
                                                    child:
                                                    TextFormField(
                                                      onChanged:
                                                          (val) {
                                                        if (val.length ==
                                                            1) {
                                                          setState(() {
                                                            _otp2 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).nextFocus();
                                                          });
                                                        } else {
                                                          setState(() {
                                                            _otp2 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).previousFocus();
                                                          });
                                                        }
                                                      },
                                                      style: GoogleFonts.notoSans(
                                                          color: Colors.white,
                                                          fontSize:
                                                          media.width * sixteen),
                                                      keyboardType:
                                                      TextInputType.number,
                                                      maxLength:
                                                      1,
                                                      textAlign:
                                                      TextAlign.center,
                                                      decoration: InputDecoration(
                                                          counterText:
                                                          '',
                                                          border:
                                                          UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 1.5, style: BorderStyle.solid))),
                                                    ),
                                                  ),
                                                  Container(
                                                    alignment:
                                                    Alignment
                                                        .center,
                                                    width: media
                                                        .width *
                                                        0.12,
                                                    decoration: _bippGreenFadeDecoration(),
                                                    child:
                                                    TextFormField(
                                                      onChanged:
                                                          (val) {
                                                        if (val.length ==
                                                            1) {
                                                          setState(() {
                                                            _otp3 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).nextFocus();
                                                          });
                                                        } else {
                                                          setState(() {
                                                            _otp3 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).previousFocus();
                                                          });
                                                        }
                                                      },
                                                      style: GoogleFonts.notoSans(
                                                          color: Colors.white,
                                                          fontSize:
                                                          media.width * sixteen),
                                                      keyboardType:
                                                      TextInputType.number,
                                                      maxLength:
                                                      1,
                                                      textAlign:
                                                      TextAlign.center,
                                                      decoration: InputDecoration(
                                                          counterText:
                                                          '',
                                                          border:
                                                          UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 1.5, style: BorderStyle.solid))),
                                                    ),
                                                  ),
                                                  Container(
                                                    alignment:
                                                    Alignment
                                                        .center,
                                                    width: media
                                                        .width *
                                                        0.12,
                                                    decoration: _bippGreenFadeDecoration(),
                                                    child:
                                                    TextFormField(
                                                      onChanged:
                                                          (val) {
                                                        if (val.length ==
                                                            1) {
                                                          setState(() {
                                                            _otp4 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).nextFocus();
                                                          });
                                                        } else {
                                                          setState(() {
                                                            _otp4 = val;
                                                            driverOtp = _otp1 + _otp2 + _otp3 + _otp4;
                                                            FocusScope.of(context).previousFocus();
                                                          });
                                                        }
                                                      },
                                                      style: GoogleFonts.notoSans(
                                                          color: Colors.white,
                                                          fontSize:
                                                          media.width * sixteen),
                                                      keyboardType:
                                                      TextInputType.number,
                                                      maxLength:
                                                      1,
                                                      textAlign:
                                                      TextAlign.center,
                                                      decoration: InputDecoration(
                                                          counterText:
                                                          '',
                                                          border:
                                                          UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 1.5, style: BorderStyle.solid))),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(
                                                height: media
                                                    .width *
                                                    0.04,
                                              ),
                                              (_errorOtp ==
                                                  true)
                                                  ? Text(
                                                languages[choosenLanguage]
                                                [
                                                'text_error_trip_otp'],
                                                style: GoogleFonts.notoSans(
                                                    color:
                                                    Colors.red,
                                                    fontSize: media.width * twelve),
                                              )
                                                  : Container(),
                                              SizedBox(
                                                  height: media
                                                      .width *
                                                      0.02),
                                            ])
                                                : Container(),
                                            SizedBox(
                                              width:
                                              media.width * 0.8,
                                              child: Text(
                                                languages[
                                                choosenLanguage]
                                                [
                                                'text_shipment_title'],
                                                style: GoogleFonts
                                                    .notoSans(
                                                  fontSize:
                                                  media.width *
                                                      eighteen,
                                                  fontWeight:
                                                  FontWeight
                                                      .bold,
                                                  color: Colors.white,
                                                ),
                                                textAlign: TextAlign
                                                    .center,
                                              ),
                                            ),
                                            SizedBox(
                                                height:
                                                media.width *
                                                    0.02),
                                            Container(
                                                height:
                                                media.width *
                                                    0.5,
                                                width: media.width *
                                                    0.5,
                                                decoration:
                                                BoxDecoration(
                                                  border: Border.all(
                                                      color:
                                                      borderLines,
                                                      width: 1.1),
                                                ),
                                                child:
                                                (shipLoadImage ==
                                                    null)
                                                    ? InkWell(
                                                  onTap:
                                                      () {
                                                    pickImageFromCamera(
                                                        1);
                                                  },
                                                  child:
                                                  Center(
                                                    child: Text(
                                                        languages[choosenLanguage]['text_add_shipmentimage'],
                                                        style: GoogleFonts.notoSans(fontSize: media.width * twelve, color: hintColor),
                                                        textAlign: TextAlign.center),
                                                  ),
                                                )
                                                    : InkWell(
                                                  onTap:
                                                      () {
                                                    pickImageFromCamera(
                                                        1);
                                                  },
                                                  child:
                                                  Container(
                                                    height:
                                                    media.width * 0.5,
                                                    width:
                                                    media.width * 0.5,
                                                    decoration:
                                                    BoxDecoration(image: DecorationImage(image: FileImage(File(shipLoadImage)), fit: BoxFit.contain, colorFilter: ColorFilter.mode(Colors.white.withOpacity(0.5), BlendMode.dstATop))),
                                                    child:
                                                    Center(child: Text(languages[choosenLanguage]['text_edit_shipmentimage'], style: GoogleFonts.notoSans(fontSize: media.width * twelve, color: Colors.white), textAlign: TextAlign.center)),
                                                  ),
                                                )),
                                            SizedBox(
                                              height: media.width *
                                                  0.05,
                                            ),
                                            (beforeImageUploadError !=
                                                '')
                                                ? SizedBox(
                                              width: media
                                                  .width *
                                                  0.9,
                                              child: Text(
                                                  beforeImageUploadError,
                                                  style: GoogleFonts.notoSans(
                                                      fontSize:
                                                      media.width *
                                                          sixteen,
                                                      color: Colors
                                                          .red),
                                                  textAlign:
                                                  TextAlign
                                                      .center),
                                            )
                                                : Container()
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                        height: media.width * 0.02),
                                    Button(
                                      onTap: () async {
                                        if (driverReq[
                                        'show_otp_feature'] ==
                                            true) {
                                          if (driverOtp.length !=
                                              4 ||
                                              shipLoadImage ==
                                                  null) {
                                            setState(() {});
                                          } else {
                                            setState(() {
                                              _errorOtp = false;
                                              beforeImageUploadError =
                                              '';
                                              _isLoading = true;
                                            });
                                            var upload =
                                            await uploadLoadingImage(
                                                shipLoadImage);
                                            if (upload ==
                                                'success') {
                                              var val =
                                              await tripStart();
                                              if (val == 'logout') {
                                                navigateLogout();
                                              } else if (val !=
                                                  'success') {
                                                setState(() {
                                                  _errorOtp = true;
                                                  _isLoading =
                                                  false;
                                                });
                                              } else {
                                                setState(() {
                                                  _isLoading =
                                                  false;
                                                  getStartOtp =
                                                  false;
                                                });
                                              }
                                            } else if (upload ==
                                                'logout') {
                                              navigateLogout();
                                            } else {
                                              setState(() {
                                                beforeImageUploadError =
                                                languages[
                                                choosenLanguage]
                                                [
                                                'text_somethingwentwrong'];
                                                _isLoading = false;
                                              });
                                            }
                                          }
                                        } else {
                                          if (shipLoadImage ==
                                              null) {
                                            setState(() {});
                                          } else {
                                            setState(() {
                                              _errorOtp = false;
                                              beforeImageUploadError =
                                              '';
                                              _isLoading = true;
                                            });
                                            var upload =
                                            await uploadLoadingImage(
                                                shipLoadImage);
                                            if (upload ==
                                                'success') {
                                              var val =
                                              await tripStartDispatcher();
                                              if (val == 'logout') {
                                                navigateLogout();
                                              } else if (val !=
                                                  'success') {
                                                setState(() {
                                                  _errorOtp = true;
                                                  _isLoading =
                                                  false;
                                                });
                                              } else {
                                                setState(() {
                                                  _isLoading =
                                                  false;
                                                  getStartOtp =
                                                  false;
                                                });
                                              }
                                            } else if (upload ==
                                                'logout') {
                                              navigateLogout();
                                            } else {
                                              setState(() {
                                                beforeImageUploadError =
                                                languages[
                                                choosenLanguage]
                                                [
                                                'text_somethingwentwrong'];
                                                _isLoading = false;
                                              });
                                            }
                                          }
                                        }
                                      },
                                      text:
                                      languages[choosenLanguage]
                                      ['text_confirm'],
                                    )
                                  ],
                                ),
                              ),
                            )
                                : Container(),

                            //shipment unload image
                            (unloadImage == true)
                                ? Positioned(
                                child: Container(
                                  height: media.height,
                                  width: media.width * 1,
                                  decoration: _bippGreenFadeDecoration(),
                                  padding: EdgeInsets.fromLTRB(
                                      media.width * 0.05,
                                      MediaQuery.of(context).padding.top +
                                          media.width * 0.05,
                                      media.width * 0.05,
                                      media.width * 0.05),
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        width: media.width * 0.8,
                                        child: Stack(
                                          children: [
                                            Container(
                                                padding: EdgeInsets.only(
                                                    left:
                                                    media.width * 0.05,
                                                    right:
                                                    media.width * 0.05),
                                                alignment: Alignment.center,
                                                // color:Colors.red,
                                                height: media.width * 0.15,
                                                width: media.width * 0.9,
                                                child: Text(
                                                  languages[choosenLanguage]
                                                  ['text_unload_title'],
                                                  style:
                                                  GoogleFonts.notoSans(
                                                      color: Colors.white,
                                                      fontSize:
                                                      media.width *
                                                          eighteen),
                                                  maxLines: 1,
                                                  textAlign:
                                                  TextAlign.center,
                                                )),
                                            Positioned(
                                              right: 0,
                                              top: media.width * 0.025,
                                              child: InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    unloadImage = false;
                                                  });
                                                },
                                                child: Container(
                                                  height: media.width * 0.1,
                                                  width: media.width * 0.1,
                                                  decoration: BoxDecoration(
                                                    gradient: _bippGreenFadeGradient(),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(Icons.cancel,
                                                      color: buttonColor),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: media.width * 0.05,
                                      ),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: Column(
                                            children: [
                                              Container(
                                                height: media.width * 0.5,
                                                width: media.width * 0.5,
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                      color: borderLines,
                                                      width: 1.1),
                                                ),
                                                child:
                                                (shipUnloadImage ==
                                                    null)
                                                    ? InkWell(
                                                  onTap: () {
                                                    pickImageFromCamera(
                                                        2);
                                                  },
                                                  child: Center(
                                                    child: Text(
                                                        languages[
                                                        choosenLanguage]
                                                        [
                                                        'text_add_unloadImage'],
                                                        style: GoogleFonts.notoSans(
                                                            fontSize: media.width *
                                                                twelve,
                                                            color:
                                                            hintColor),
                                                        textAlign:
                                                        TextAlign
                                                            .center),
                                                  ),
                                                )
                                                    : InkWell(
                                                  onTap: () {
                                                    pickImageFromCamera(
                                                        2);
                                                  },
                                                  child:
                                                  Container(
                                                    height: media
                                                        .width *
                                                        0.5,
                                                    width: media
                                                        .width *
                                                        0.5,
                                                    decoration: BoxDecoration(
                                                        image: DecorationImage(
                                                            image: FileImage(File(
                                                                shipUnloadImage)),
                                                            fit: BoxFit
                                                                .contain,
                                                            colorFilter: ColorFilter.mode(
                                                                Colors.white.withOpacity(0.5),
                                                                BlendMode.dstATop))),
                                                    child: Center(
                                                        child: Text(
                                                            languages[choosenLanguage]
                                                            [
                                                            'text_edit_unloadimage'],
                                                            style: GoogleFonts.notoSans(
                                                                fontSize: media.width *
                                                                    twelve,
                                                                color: Colors.white),
                                                            textAlign:
                                                            TextAlign.center)),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                  height:
                                                  media.width * 0.05),
                                              (afterImageUploadError != '')
                                                  ? SizedBox(
                                                width:
                                                media.width * 0.9,
                                                child: Text(
                                                    afterImageUploadError,
                                                    style: GoogleFonts.notoSans(
                                                        fontSize: media
                                                            .width *
                                                            sixteen,
                                                        color: Colors
                                                            .red),
                                                    textAlign:
                                                    TextAlign
                                                        .center),
                                              )
                                                  : Container()
                                            ],
                                          ),
                                        ),
                                      ),
                                      (shipUnloadImage != null)
                                          ? Button(
                                          onTap: () async {
                                            setState(() {
                                              _isLoading = true;
                                              afterImageUploadError =
                                              '';
                                            });
                                            var val =
                                            await uploadUnloadingImage(
                                                shipUnloadImage);
                                            if (val == 'success') {
                                              if (driverReq[
                                              'enable_digital_signature']
                                                  .toString() ==
                                                  '1') {
                                                navigate();
                                              } else {
                                                var val =
                                                await endTrip();
                                                if (val == 'logout') {
                                                  navigateLogout();
                                                }
                                              }
                                            } else if (val ==
                                                'logout') {
                                              navigateLogout();
                                            } else {
                                              setState(() {
                                                afterImageUploadError =
                                                languages[
                                                choosenLanguage]
                                                [
                                                'text_somethingwentwrong'];
                                              });
                                            }
                                            setState(() {
                                              _isLoading = false;
                                            });
                                          },
                                          text: 'Upload')
                                          : Container()
                                    ],
                                  ),
                                ))
                                : Container(),

                            //permission denied popup
                            (_permission != '')
                                ? Positioned(
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: media.width * 0.9,
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _permission = '';
                                                });
                                              },
                                              child: Container(
                                                height: media.width * 0.1,
                                                width: media.width * 0.1,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: _bippGreenFadeGradient(),),
                                                child: Icon(
                                                    Icons.cancel_outlined,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: media.width * 0.05,
                                      ),
                                      Container(
                                        padding: EdgeInsets.all(
                                            media.width * 0.05),
                                        width: media.width * 0.9,
                                        decoration: BoxDecoration(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            gradient: _bippGreenFadeGradient(),
                                            boxShadow: [
                                              BoxShadow(
                                                  blurRadius: 2.0,
                                                  spreadRadius: 2.0,
                                                  color: Colors.black
                                                      .withOpacity(0.2))
                                            ]),
                                        child: Column(
                                          children: [
                                            SizedBox(
                                                width: media.width * 0.8,
                                                child: Text(
                                                  languages[choosenLanguage]
                                                  [
                                                  'text_open_camera_setting'],
                                                  style:
                                                  GoogleFonts.notoSans(
                                                      fontSize:
                                                      media.width *
                                                          sixteen,
                                                      color: Colors.white,
                                                      fontWeight:
                                                      FontWeight
                                                          .w600),
                                                )),
                                            SizedBox(
                                                height: media.width * 0.05),
                                            Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                              children: [
                                                InkWell(
                                                    onTap: () async {
                                                      await perm
                                                          .openAppSettings();
                                                    },
                                                    child: Text(
                                                      languages[
                                                      choosenLanguage]
                                                      [
                                                      'text_open_settings'],
                                                      style: GoogleFonts.notoSans(
                                                          fontSize:
                                                          media.width *
                                                              sixteen,
                                                          color:
                                                          buttonColor,
                                                          fontWeight:
                                                          FontWeight
                                                              .w600),
                                                    )),
                                                InkWell(
                                                    onTap: () async {
                                                      // pickImageFromCamera();
                                                      setState(() {
                                                        _permission = '';
                                                      });
                                                    },
                                                    child: Text(
                                                      languages[
                                                      choosenLanguage]
                                                      ['text_done'],
                                                      style: GoogleFonts.notoSans(
                                                          fontSize:
                                                          media.width *
                                                              sixteen,
                                                          color:
                                                          buttonColor,
                                                          fontWeight:
                                                          FontWeight
                                                              .w600),
                                                    ))
                                              ],
                                            )
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ))
                                : Container(),

                            //popup for cancel request
                            (cancelRequest == true && driverReq.isNotEmpty)
                                ? Positioned(
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(
                                            media.width * 0.05),
                                        width: media.width * 0.9,
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                                color: borderLines
                                                    .withOpacity(0.5)),
                                            gradient: _bippGreenFadeGradient(),
                                            borderRadius:
                                            BorderRadius.circular(12)),
                                        child: Column(children: [
                                          Container(
                                            height: media.width * 0.18,
                                            width: media.width * 0.18,
                                            decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Color(0xffFEF2F2)),
                                            alignment: Alignment.center,
                                            child: Container(
                                              height: media.width * 0.14,
                                              width: media.width * 0.14,
                                              decoration:
                                              const BoxDecoration(
                                                  shape:
                                                  BoxShape.circle,
                                                  color: Color(
                                                      0xffFF0000)),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.cancel_outlined,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Column(
                                            children: cancelReasonsList
                                                .asMap()
                                                .map((i, value) {
                                              return MapEntry(
                                                  i,
                                                  InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        _cancelReason =
                                                        cancelReasonsList[
                                                        i][
                                                        'reason'];
                                                      });
                                                    },
                                                    child: Container(
                                                      padding: EdgeInsets
                                                          .all(media
                                                          .width *
                                                          0.01),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            height: media
                                                                .height *
                                                                0.05,
                                                            width: media
                                                                .width *
                                                                0.05,
                                                            decoration: BoxDecoration(
                                                                shape: BoxShape
                                                                    .circle,
                                                                border: Border.all(
                                                                    color: Colors.white,
                                                                    width:
                                                                    1.2)),
                                                            alignment:
                                                            Alignment
                                                                .center,
                                                            child: (_cancelReason ==
                                                                cancelReasonsList[i]['reason'])
                                                                ? Container(
                                                              height:
                                                              media.width * 0.03,
                                                              width:
                                                              media.width * 0.03,
                                                              decoration:
                                                              BoxDecoration(
                                                                shape: BoxShape.circle,
                                                                color: Colors.white,
                                                              ),
                                                            )
                                                                : Container(),
                                                          ),
                                                          SizedBox(
                                                            width: media
                                                                .width *
                                                                0.05,
                                                          ),
                                                          SizedBox(
                                                            width: media
                                                                .width *
                                                                0.65,
                                                            child:
                                                            MyText(
                                                              color: Colors.white,
                                                              text: cancelReasonsList[
                                                              i]
                                                              [
                                                              'reason'],
                                                              size: media
                                                                  .width *
                                                                  twelve,
                                                            ),
                                                          )
                                                        ],
                                                      ),
                                                    ),
                                                  ));
                                            })
                                                .values
                                                .toList(),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                _cancelReason = 'others';
                                              });
                                            },
                                            child: Container(
                                              padding: EdgeInsets.all(
                                                  media.width * 0.01),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    height:
                                                    media.height * 0.05,
                                                    width:
                                                    media.width * 0.05,
                                                    decoration: BoxDecoration(
                                                        shape:
                                                        BoxShape.circle,
                                                        border: Border.all(
                                                            color: Colors.white,
                                                            width: 1.2)),
                                                    alignment:
                                                    Alignment.center,
                                                    child: (_cancelReason ==
                                                        'others')
                                                        ? Container(
                                                      height: media
                                                          .width *
                                                          0.03,
                                                      width: media
                                                          .width *
                                                          0.03,
                                                      decoration:
                                                      BoxDecoration(
                                                        shape: BoxShape
                                                            .circle,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                        : Container(),
                                                  ),
                                                  SizedBox(
                                                    width:
                                                    media.width * 0.05,
                                                  ),
                                                  MyText(
                                                    color: Colors.white,
                                                    text: languages[
                                                    choosenLanguage]
                                                    ['text_others'],
                                                    size: media.width *
                                                        twelve,
                                                  )
                                                ],
                                              ),
                                            ),
                                          ),
                                          (_cancelReason == 'others')
                                              ? Container(
                                            margin:
                                            EdgeInsets.fromLTRB(
                                                0,
                                                media.width *
                                                    0.025,
                                                0,
                                                media.width *
                                                    0.025),
                                            padding: EdgeInsets.all(
                                                media.width * 0.05),
                                            width: media.width * 0.9,
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                    color:
                                                    borderLines,
                                                    width: 1.2),
                                                borderRadius:
                                                BorderRadius
                                                    .circular(
                                                    12)),
                                            child: TextField(
                                              decoration: InputDecoration(
                                                  border: InputBorder
                                                      .none,
                                                  hintText: languages[
                                                  choosenLanguage]
                                                  [
                                                  'text_cancelRideReason'],
                                                  hintStyle: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          twelve)),
                                              maxLines: 4,
                                              minLines: 2,
                                              onChanged: (val) {
                                                setState(() {
                                                  cancelReasonText =
                                                      val;
                                                });
                                              },
                                            ),
                                          )
                                              : Container(),
                                          (_cancellingError != '')
                                              ? Container(
                                              padding: EdgeInsets.only(
                                                  top: media.width *
                                                      0.02,
                                                  bottom: media.width *
                                                      0.02),
                                              width: media.width * 0.9,
                                              child: Text(
                                                  _cancellingError,
                                                  style: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          twelve,
                                                      color: Colors
                                                          .red)))
                                              : Container(),
                                          Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment
                                                .spaceBetween,
                                            children: [
                                              Button(
                                                  color: page,
                                                  textcolor: buttonColor,
                                                  borcolor: buttonColor,
                                                  width: media.width * 0.39,
                                                  onTap: () async {
                                                    setState(() {
                                                      _isLoading = true;
                                                    });
                                                    if (_cancelReason !=
                                                        '') {
                                                      if (_cancelReason ==
                                                          'others') {
                                                        if (cancelReasonText !=
                                                            '' &&
                                                            cancelReasonText
                                                                .isNotEmpty) {
                                                          _cancellingError =
                                                          '';
                                                          var val =
                                                          await cancelRequestDriver(
                                                              cancelReasonText);
                                                          if (val ==
                                                              'logout') {
                                                            navigateLogout();
                                                          }
                                                          setState(() {
                                                            cancelRequest =
                                                            false;
                                                          });
                                                        } else {
                                                          setState(() {
                                                            _cancellingError =
                                                            languages[
                                                            choosenLanguage]
                                                            [
                                                            'text_add_cancel_reason'];
                                                          });
                                                        }
                                                      } else {
                                                        var val =
                                                        await cancelRequestDriver(
                                                            _cancelReason);
                                                        if (val ==
                                                            'logout') {
                                                          navigateLogout();
                                                        }
                                                        setState(() {
                                                          cancelRequest =
                                                          false;
                                                        });
                                                      }
                                                    }
                                                    setState(() {
                                                      _isLoading = false;
                                                    });
                                                  },
                                                  text: languages[
                                                  choosenLanguage]
                                                  ['text_cancel']),
                                              Button(
                                                  width: media.width * 0.39,
                                                  onTap: () {
                                                    setState(() {
                                                      cancelRequest = false;
                                                    });
                                                  },
                                                  text: languages[
                                                  choosenLanguage]
                                                  ['tex_dontcancel'])
                                            ],
                                          )
                                        ]),
                                      ),
                                    ],
                                  ),
                                ))
                                : Container(),

                            //loader
                            (state == '')
                                ? const Positioned(top: 0, child: Loading())
                                : Container(),

                            //logout popup
                            (logout == true)
                                ? Positioned(
                                top: 0,
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: media.width * 0.9,
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          children: [
                                            Container(
                                                height:
                                                media.height * 0.1,
                                                width: media.width * 0.1,
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                      color: borderLines
                                                          .withOpacity(
                                                          0.5)),
                                                  shape:
                                                  BoxShape.circle,
                                                  gradient: _bippGreenFadeGradient(),),
                                                child: InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        logout = false;
                                                      });
                                                    },
                                                    child: Icon(
                                                      Icons
                                                          .cancel_outlined,
                                                      color: Colors.white,
                                                    ))),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.all(
                                            media.width * 0.05),
                                        width: media.width * 0.9,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: borderLines
                                                  .withOpacity(0.5)),
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          gradient: _bippGreenFadeGradient(),),
                                        child: Column(
                                          children: [
                                            Text(
                                              languages[choosenLanguage]
                                              ['text_confirmlogout'],
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.notoSans(
                                                  fontSize: media.width *
                                                      sixteen,
                                                  color: Colors.white,
                                                  fontWeight:
                                                  FontWeight.w600),
                                            ),
                                            SizedBox(
                                              height: media.width * 0.05,
                                            ),
                                            Button(
                                                color: (isDarkTheme ==
                                                    true)
                                                    ? buttonColorDarkMood
                                                    : buttonColorLightMood,
                                                onTap: () async {
                                                  setState(() {
                                                    _isLoading = true;
                                                    logout = false;
                                                  });
                                                  var result =
                                                  await userLogout();
                                                  if (result ==
                                                      'success') {
                                                    setState(() {
                                                      navigateLogout();
                                                      userDetails.clear();
                                                    });
                                                  } else if (result ==
                                                      'logout') {
                                                    navigateLogout();
                                                  } else {
                                                    setState(() {
                                                      logout = true;
                                                    });
                                                  }
                                                },
                                                text: languages[
                                                choosenLanguage]
                                                ['text_confirm'])
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ))
                                : Container(),

                            //waiting time popup
                            (_showWaitingInfo == true)
                                ? Positioned(
                                top: 0,
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: media.width * 0.9,
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          children: [
                                            Container(
                                                height:
                                                media.height * 0.1,
                                                width: media.width * 0.1,
                                                decoration: BoxDecoration(
                                                  shape:
                                                  BoxShape.circle,
                                                  gradient: _bippGreenFadeGradient(),),
                                                child: InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        _showWaitingInfo =
                                                        false;
                                                      });
                                                    },
                                                    child: const Icon(Icons
                                                        .cancel_outlined))),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.all(
                                            media.width * 0.05),
                                        width: media.width * 0.9,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                          BorderRadius.circular(12),
                                          gradient: _bippGreenFadeGradient(),),
                                        child: Column(
                                          children: [
                                            Text(
                                              languages[choosenLanguage]
                                              ['text_waiting_time_1'],
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.notoSans(
                                                  fontSize: media.width *
                                                      sixteen,
                                                  color: Colors.white,
                                                  fontWeight:
                                                  FontWeight.w600),
                                            ),
                                            SizedBox(
                                              height: media.width * 0.05,
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                              children: [
                                                Text(
                                                    languages[
                                                    choosenLanguage]
                                                    [
                                                    'text_waiting_time_2'],
                                                    style: GoogleFonts
                                                        .notoSans(
                                                        fontSize: media
                                                            .width *
                                                            fourteen,
                                                        color: Colors.white)),
                                                Text(
                                                    '${driverReq['free_waiting_time_in_mins_before_trip_start']} ${languages[choosenLanguage]['text_mins']}',
                                                    style: GoogleFonts
                                                        .notoSans(
                                                        fontSize: media
                                                            .width *
                                                            fourteen,
                                                        color: Colors.white,
                                                        fontWeight:
                                                        FontWeight
                                                            .w600)),
                                              ],
                                            ),
                                            SizedBox(
                                              height: media.width * 0.05,
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                              children: [
                                                Text(
                                                    languages[
                                                    choosenLanguage]
                                                    [
                                                    'text_waiting_time_3'],
                                                    style: GoogleFonts
                                                        .notoSans(
                                                        fontSize: media
                                                            .width *
                                                            fourteen,
                                                        color: Colors.white)),
                                                Text(
                                                    '${driverReq['free_waiting_time_in_mins_after_trip_start']} ${languages[choosenLanguage]['text_mins']}',
                                                    style: GoogleFonts
                                                        .notoSans(
                                                        fontSize: media
                                                            .width *
                                                            fourteen,
                                                        color: Colors.white,
                                                        fontWeight:
                                                        FontWeight
                                                            .w600)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ))
                                : Container(),

                            //no internet
                            (internet == false)
                                ? Positioned(
                                top: 0,
                                child: NoInternet(
                                  onTap: () {
                                    setState(() {
                                      internetTrue();
                                      getUserDetails();
                                    });
                                  },
                                ))
                                : Container(),

                            //sos popup
                            (showSos == true)
                                ? Positioned(
                                top: 0,
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  child: Column(
                                      mainAxisAlignment:
                                      MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: media.width * 0.7,
                                          child: Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment.end,
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    notifyCompleted =
                                                    false;
                                                    showSos = false;
                                                  });
                                                },
                                                child: Container(
                                                  height:
                                                  media.width * 0.1,
                                                  width:
                                                  media.width * 0.1,
                                                  decoration:
                                                  BoxDecoration(
                                                    shape: BoxShape
                                                        .circle,
                                                    gradient: _bippGreenFadeGradient(),),
                                                  child: const Icon(Icons
                                                      .cancel_outlined),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          height: media.width * 0.05,
                                        ),
                                        Container(
                                          padding: EdgeInsets.all(
                                              media.width * 0.05),
                                          height: media.height * 0.5,
                                          width: media.width * 0.7,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                            BorderRadius.circular(
                                                12),
                                            gradient: _bippGreenFadeGradient(),),
                                          child: SingleChildScrollView(
                                              physics:
                                              const BouncingScrollPhysics(),
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                                children: [
                                                  InkWell(
                                                    onTap: () async {
                                                      setState(() {
                                                        notifyCompleted =
                                                        false;
                                                      });
                                                      var val =
                                                      await notifyAdmin();
                                                      if (val == true) {
                                                        setState(() {
                                                          notifyCompleted =
                                                          true;
                                                        });
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: EdgeInsets
                                                          .all(media
                                                          .width *
                                                          0.05),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                              children: [
                                                                Text(
                                                                  languages[choosenLanguage]['text_notifyadmin'],
                                                                  maxLines: 2,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: GoogleFonts.notoSans(
                                                                      fontSize: media.width *
                                                                          sixteen,
                                                                      color: Colors.white,
                                                                      fontWeight:
                                                                      FontWeight.w600),
                                                                ),
                                                                (notifyCompleted ==
                                                                    true)
                                                                    ? Container(
                                                                  padding:
                                                                  EdgeInsets.only(top: media.width * 0.01),
                                                                  child:
                                                                  Text(
                                                                    languages[choosenLanguage]['text_notifysuccess'],
                                                                    style: GoogleFonts.notoSans(
                                                                      fontSize: media.width * twelve,
                                                                      color: const Color(0xff319900),
                                                                    ),
                                                                  ),
                                                                )
                                                                    : Container()
                                                              ],
                                                            ),
                                                          ),
                                                          SizedBox(width: media.width * 0.02),
                                                          const Icon(Icons.notification_add)
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  (sosData.isNotEmpty)
                                                      ? Column(
                                                    children: sosData
                                                        .asMap()
                                                        .map((i, value) {
                                                      return MapEntry(
                                                          i,
                                                          InkWell(
                                                            onTap:
                                                                () {
                                                              makingPhoneCall(sosData[i]['number'].toString().replaceAll(' ', ''));
                                                            },
                                                            child:
                                                            Container(
                                                              padding: EdgeInsets.all(media.width * 0.05),
                                                              child: Row(
                                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                                children: [
                                                                  Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      SizedBox(
                                                                        width: media.width * 0.4,
                                                                        child: Text(
                                                                          sosData[i]['name'],
                                                                          style: GoogleFonts.notoSans(fontSize: media.width * fourteen, color: Colors.white, fontWeight: FontWeight.w600),
                                                                        ),
                                                                      ),
                                                                      SizedBox(
                                                                        height: media.width * 0.01,
                                                                      ),
                                                                      Text(
                                                                        sosData[i]['number'],
                                                                        style: GoogleFonts.notoSans(
                                                                          fontSize: media.width * twelve,
                                                                          color: Colors.white,
                                                                        ),
                                                                      )
                                                                    ],
                                                                  ),
                                                                  const Icon(Icons.call)
                                                                ],
                                                              ),
                                                            ),
                                                          ));
                                                    })
                                                        .values
                                                        .toList(),
                                                  )
                                                      : Container(
                                                    width: media
                                                        .width *
                                                        0.7,
                                                    alignment:
                                                    Alignment
                                                        .center,
                                                    child: Text(
                                                      languages[
                                                      choosenLanguage]
                                                      [
                                                      'text_noDataFound'],
                                                      style: GoogleFonts.notoSans(
                                                          fontSize:
                                                          media.width *
                                                              eighteen,
                                                          fontWeight:
                                                          FontWeight
                                                              .w600,
                                                          color: Colors.white),
                                                    ),
                                                  )
                                                ],
                                              )),
                                        )
                                      ]),
                                ))
                                : Container(),

                            //choose option for seeing location on map while having multiple stops
                            (_tripOpenMap == true)
                                ? Positioned(
                                top: 0,
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color:
                                  Colors.transparent.withOpacity(0.6),
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: media.width * 0.9,
                                        child: Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.end,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _tripOpenMap = false;
                                                });
                                              },
                                              child: Container(
                                                height: media.width * 0.1,
                                                width: media.width * 0.1,
                                                decoration: BoxDecoration(
                                                  shape:
                                                  BoxShape.circle,
                                                  gradient: _bippGreenFadeGradient(),),
                                                child: Icon(
                                                  Icons.cancel_outlined,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: media.width * 0.05,
                                      ),
                                      Container(
                                          width: media.width * 0.9,
                                          padding: EdgeInsets.fromLTRB(
                                              media.width * 0.02,
                                              media.width * 0.05,
                                              media.width * 0.02,
                                              media.width * 0.05),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                            BorderRadius.circular(
                                                12),
                                            gradient: _bippGreenFadeGradient(),),
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                width: media.width * 0.8,
                                                child: Text(
                                                  languages[
                                                  choosenLanguage]
                                                  [
                                                  'text_choose_address_nav'],
                                                  style: GoogleFonts
                                                      .notoSans(
                                                      fontSize: media
                                                          .width *
                                                          sixteen,
                                                      color: Colors.white,
                                                      fontWeight:
                                                      FontWeight
                                                          .w600),
                                                  maxLines: 1,
                                                  overflow: TextOverflow
                                                      .ellipsis,
                                                ),
                                              ),
                                              SizedBox(
                                                height:
                                                media.width * 0.03,
                                              ),
                                              SizedBox(
                                                height:
                                                media.height * 0.2,
                                                child:
                                                SingleChildScrollView(
                                                  physics:
                                                  const BouncingScrollPhysics(),
                                                  child: Column(
                                                    children: tripStops
                                                        .asMap()
                                                        .map((i, value) {
                                                      return MapEntry(
                                                          i,
                                                          Container(
                                                            // width: media.width*0.5,
                                                            padding: EdgeInsets.all(
                                                                media.width *
                                                                    0.025),
                                                            child:
                                                            Row(
                                                              mainAxisAlignment:
                                                              MainAxisAlignment.spaceBetween,
                                                              children: [
                                                                Expanded(
                                                                  child:
                                                                  Text(
                                                                    tripStops[i]['address'],
                                                                    style: GoogleFonts.notoSans(fontSize: media.width * fourteen, color: Colors.white, fontWeight: FontWeight.w600),
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  width:
                                                                  media.width * 0.01,
                                                                ),
                                                                InkWell(
                                                                  onTap:
                                                                      () {
                                                                    openMap(tripStops[i]['latitude'], tripStops[i]['longitude']);
                                                                  },
                                                                  child:
                                                                  SizedBox(
                                                                    width: media.width * 00.08,
                                                                    child: Image.asset('assets/images/googlemaps.png', width: media.width * 0.05, fit: BoxFit.contain),
                                                                  ),
                                                                ),
                                                                (userDetails['enable_vase_map'] == '1')
                                                                    ? SizedBox(
                                                                  width: media.width * 0.02,
                                                                )
                                                                    : Container(),
                                                                (userDetails['enable_vase_map'] == '1')
                                                                    ? InkWell(
                                                                  onTap: () {
                                                                    openWazeMap(tripStops[i]['latitude'], tripStops[i]['longitude']);
                                                                  },
                                                                  child: SizedBox(
                                                                    width: media.width * 00.1,
                                                                    child: Image.asset('assets/images/waze.png', width: media.width * 0.05, fit: BoxFit.contain),
                                                                  ),
                                                                )
                                                                    : Container(),
                                                              ],
                                                            ),
                                                          ));
                                                    })
                                                        .values
                                                        .toList(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ))
                                    ],
                                  ),
                                ))
                                : Container(),

                            //loader
                            (_isLoading == true)
                                ? const Positioned(top: 0, child: Loading())
                                : Container(),
                            //pickup marker
                            Positioned(
                              top: media.height * 1.5,
                              left: 100,
                              child: RepaintBoundary(
                                  key: iconKey,
                                  child: Column(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                            gradient: _bippGreenFadeGradient(),
                                            borderRadius:
                                            BorderRadius.circular(5)),
                                        width: media.width * 0.5,
                                        padding: const EdgeInsets.all(5),
                                        child: (driverReq.isNotEmpty &&
                                            driverReq['pick_address'] !=
                                                null)
                                            ? MyText(
                                          color: Colors.white,
                                          text:
                                          driverReq['pick_address'],
                                          size: media.width * twelve,
                                          overflow: TextOverflow.fade,
                                          maxLines: 1,
                                        )
                                            : (choosenRide.isNotEmpty)
                                            ? MyText(
                                          color: Colors.white,
                                          text: choosenRide[0]
                                          ['pick_address'],
                                          size:
                                          media.width * twelve,
                                          overflow:
                                          TextOverflow.fade,
                                          maxLines: 1,
                                        )
                                            : Container(),
                                      ),
                                      const SizedBox(
                                        height: 10,
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF00C853),
                                          border: Border.all(color: const Color(0xFF00FFB0).withOpacity(0.12), width: 3),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x55000000),
                                              blurRadius: 8,
                                              offset: Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Icon(Icons.flag, color: Colors.white, size: media.width * 0.045),
                                        ),
                                        height: media.width * 0.07,
                                        width: media.width * 0.08,
                                      )
                                    ],
                                  )),
                            ),

                            //drop marker
                            Positioned(
                                top: media.height * 2.5,
                                left: 100,
                                child: Column(
                                  children: [
                                    (tripStops.isNotEmpty)
                                        ? Column(
                                      children: tripStops
                                          .asMap()
                                          .map((i, value) {
                                        iconDropKeys[i] =
                                            GlobalKey();
                                        return MapEntry(
                                          i,
                                          RepaintBoundary(
                                              key: iconDropKeys[i],
                                              child: Column(
                                                children: [
                                                  (i <=
                                                      tripStops
                                                          .length -
                                                          2)
                                                      ? Column(
                                                    children: [
                                                      if (tripStops[i]['completed_at'] ==
                                                          null)
                                                        Container(
                                                          padding:
                                                          const EdgeInsets.only(bottom: 5),
                                                          child:
                                                          Text(
                                                            (i + 1).toString(),
                                                            style: GoogleFonts.notoSans(fontSize: media.width * sixteen, fontWeight: FontWeight.w600, color: Colors.red),
                                                          ),
                                                        ),
                                                      const SizedBox(
                                                        height:
                                                        10,
                                                      ),
                                                    ],
                                                  )
                                                      : (i ==
                                                      tripStops.length -
                                                          1)
                                                      ? Column(
                                                    children: [
                                                      Container(
                                                        decoration: BoxDecoration(
                                                            gradient: _bippGreenFadeGradient(),
                                                            borderRadius: BorderRadius.circular(5)),
                                                        width: media.width * 0.5,
                                                        padding: const EdgeInsets.all(5),
                                                        child: (driverReq.isNotEmpty && driverReq['drop_address'] != null)
                                                            ? Text(driverReq['drop_address'],
                                                            maxLines: 1,
                                                            style: GoogleFonts.notoSans(
                                                              fontSize: media.width * ten,
                                                            ))
                                                            : (choosenRide.isNotEmpty && choosenRide[0]['drop_address'] != null)
                                                            ? Text(
                                                          choosenRide[choosenRide.length - 1]['drop_address'],
                                                          maxLines: 1,
                                                          style: GoogleFonts.notoSans(
                                                            fontSize: media.width * ten,
                                                          ),
                                                          overflow: TextOverflow.fade,
                                                        )
                                                            : Container(),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Container(
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: const Color(0xFFD50000),
                                                          border: Border.all(color: const Color(0xFF00FFB0).withOpacity(0.12), width: 3),
                                                          boxShadow: const [
                                                            BoxShadow(
                                                              color: Color(0x55000000),
                                                              blurRadius: 8,
                                                              offset: Offset(0, 3),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Center(
                                                          child: Icon(Icons.flag, color: Colors.white, size: media.width * 0.045),
                                                        ),
                                                        height: media.width * 0.07,
                                                        width: media.width * 0.08,
                                                      )
                                                    ],
                                                  )
                                                      : Container(),
                                                ],
                                              )),
                                        );
                                      })
                                          .values
                                          .toList(),
                                    )
                                        : Container(),
                                  ],
                                )),

                            //drop marker
                            Positioned(
                              top: media.height * 2.5,
                              left: 100,
                              child: Column(
                                children: [
                                  RepaintBoundary(
                                      key: iconDropKey,
                                      child: Column(
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                                gradient: _bippGreenFadeGradient(),
                                                borderRadius:
                                                BorderRadius.circular(5)),
                                            width: media.width * 0.5,
                                            padding: const EdgeInsets.all(5),
                                            child: (driverReq.isNotEmpty &&
                                                driverReq[
                                                'drop_address'] !=
                                                    null)
                                                ? MyText(
                                              color: Colors.white,
                                              text: driverReq[
                                              'drop_address'],
                                              size: media.width * ten,
                                              overflow:
                                              TextOverflow.fade,
                                              maxLines: 1,
                                            )
                                                : (choosenRide.isNotEmpty &&
                                                choosenRide[0][
                                                'drop_address'] !=
                                                    null)
                                                ? MyText(
                                              color: Colors.white,
                                              text: choosenRide[0]
                                              ['drop_address'],
                                              size:
                                              media.width * ten,
                                              overflow:
                                              TextOverflow.fade,
                                              maxLines: 1,
                                            )
                                                : Container(),
                                          ),
                                          const SizedBox(
                                            height: 10,
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFFD50000),
                                              border: Border.all(color: const Color(0xFF00FFB0).withOpacity(0.12), width: 3),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x55000000),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Icon(Icons.flag, color: Colors.white, size: media.width * 0.045),
                                            ),
                                            height: media.width * 0.07,
                                            width: media.width * 0.08,
                                          )
                                        ],
                                      )),
                                ],
                              ),
                            ),

                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 1),
                              bottom: _isbottom,
                              child: InkWell(
                                onTap: () {
                                  Future.delayed(
                                      const Duration(milliseconds: 200), () {
                                    setState(() {
                                      _isbottom = -1000;
                                    });
                                  });
                                  setState(() {});
                                },
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color: Colors.black.withOpacity(0.3),
                                  alignment: Alignment.bottomCenter,
                                  child: AnimatedContainer(
                                    padding:
                                    EdgeInsets.all(media.width * 0.05),
                                    duration:
                                    const Duration(milliseconds: 200),
                                    width: media.width * 1,
                                    decoration: _bippGreenFadeDecoration(),
                                    curve: Curves.easeOut,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          MyText(
                                            text: languages[choosenLanguage]
                                            ['text_chooe_transport_type'],
                                            size: media.width * sixteen,
                                            fontweight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                          SizedBox(
                                            height: media.width * 0.02,
                                          ),
                                          InkWell(
                                            onTap: () async {
                                              _isbottom = -1000;
                                              var val = await geoCoding(
                                                  center.latitude,
                                                  center.longitude);
                                              setState(() {
                                                if (addressList
                                                    .where((element) =>
                                                element.type ==
                                                    'pickup')
                                                    .isNotEmpty) {
                                                  var add = addressList
                                                      .firstWhere((element) =>
                                                  element.type ==
                                                      'pickup');
                                                  add.address = val;
                                                  add.latlng = LatLng(
                                                      center.latitude,
                                                      center.longitude);
                                                } else {
                                                  addressList.add(AddressList(
                                                      id: '1',
                                                      type: 'pickup',
                                                      address: val,
                                                      latlng: LatLng(
                                                          center.latitude,
                                                          center.longitude)));
                                                }
                                              });
                                              if (addressList.isNotEmpty) {
                                                Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                        builder: (context) =>
                                                        const DropLocation()));
                                              }
                                            },
                                            child: Container(
                                              height: media.width * 0.15,
                                              width: media.width * 0.9,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                  BorderRadius.circular(
                                                      media.width * 0.02),
                                                  gradient: _bippGreenFadeGradient(),
                                                  border: Border.all(
                                                      color: hintColor)),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    height:
                                                    media.width * 0.12,
                                                    width: media.width * 0.15,
                                                    alignment:
                                                    Alignment.centerLeft,
                                                    margin: EdgeInsets.only(
                                                        left: media.width *
                                                            0.02,
                                                        right: media.width *
                                                            0.02),
                                                    decoration:
                                                    const BoxDecoration(
                                                      image: DecorationImage(
                                                          image: AssetImage(
                                                              'assets/images/taxi_main1.png')),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: media.width * 0.02,
                                                  ),
                                                  Expanded(
                                                    child: MyText(
                                                        color: Colors.white,
                                                        text: languages[
                                                        choosenLanguage]
                                                        ['text_taxi_'],
                                                        size: media.width *
                                                            sixteen),
                                                  ),
                                                  RotatedBox(
                                                      quarterTurns: 4,
                                                      child: Icon(
                                                        Icons
                                                            .arrow_forward_ios,
                                                        size: media.width *
                                                            0.05,
                                                      ))
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            height: media.width * 0.02,
                                          ),
                                          InkWell(
                                            onTap: () async {
                                              _isbottom = -1000;
                                              var val = await geoCoding(
                                                  center.latitude,
                                                  center.longitude);
                                              setState(() {
                                                if (addressList
                                                    .where((element) =>
                                                element.type ==
                                                    'pickup')
                                                    .isNotEmpty) {
                                                  var add = addressList
                                                      .firstWhere((element) =>
                                                  element.type ==
                                                      'pickup');
                                                  add.address = val;
                                                  add.latlng = LatLng(
                                                      center.latitude,
                                                      center.longitude);
                                                } else {
                                                  addressList.add(AddressList(
                                                      id: '1',
                                                      type: 'pickup',
                                                      address: val,
                                                      latlng: LatLng(
                                                          center.latitude,
                                                          center.longitude)));
                                                }
                                              });
                                              if (addressList.isNotEmpty) {
                                                Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                        builder: (context) =>
                                                        const DropLocation(
                                                          type: 1,
                                                        )));
                                              }
                                            },
                                            child: Container(
                                              height: media.width * 0.15,
                                              width: media.width * 0.9,
                                              decoration: BoxDecoration(
                                                  borderRadius:
                                                  BorderRadius.circular(
                                                      media.width * 0.02),
                                                  gradient: _bippGreenFadeGradient(),
                                                  border: Border.all(
                                                      color: hintColor)),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    height:
                                                    media.width * 0.12,
                                                    width: media.width * 0.15,
                                                    alignment:
                                                    Alignment.centerLeft,
                                                    margin: EdgeInsets.only(
                                                        left: media.width *
                                                            0.02,
                                                        right: media.width *
                                                            0.02),
                                                    decoration:
                                                    const BoxDecoration(
                                                      image: DecorationImage(
                                                          image: AssetImage(
                                                              'assets/images/delivery_main.png')),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: media.width * 0.02,
                                                  ),
                                                  Expanded(
                                                    child: MyText(
                                                        color: Colors.white,
                                                        text: languages[
                                                        choosenLanguage]
                                                        ['text_delivery'],
                                                        size: media.width *
                                                            sixteen),
                                                  ),
                                                  RotatedBox(
                                                      quarterTurns: 4,
                                                      child: Icon(
                                                        Icons
                                                            .arrow_forward_ios,
                                                        size: media.width *
                                                            0.05,
                                                      ))
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            (isOverLayPermission &&
                                Theme.of(context).platform ==
                                    TargetPlatform.android)
                                ? Positioned(
                                child: Container(
                                  height: media.height * 1,
                                  width: media.width * 1,
                                  color: Colors.black.withOpacity(0.2),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment:
                                    MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        // height: media.width * 0.5,
                                        width: media.width * 0.9,
                                        padding: EdgeInsets.all(
                                            media.width * 0.05),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: borderLines
                                                  .withOpacity(0.5)),
                                          borderRadius:
                                          BorderRadius.circular(
                                              media.width * 0.05),
                                          gradient: _bippGreenFadeGradient(),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                          MainAxisAlignment
                                              .spaceBetween,
                                          children: [
                                            MyText(
                                              color: Colors.white,
                                              text:
                                              "Please Allow Overlay Permisson for Appear on the Other Apps",
                                              size: media.width * sixteen,
                                              textAlign: TextAlign.center,
                                              fontweight: FontWeight.bold,
                                            ),
                                            SizedBox(
                                              height: media.width * 0.05,
                                            ),
                                            Row(
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      isOverLayPermission =
                                                      false;
                                                    });
                                                    pref.setBool(
                                                        'isOverlaypermission',
                                                        isOverLayPermission);
                                                  },
                                                  child: SizedBox(
                                                    width:
                                                    media.width * 0.3,
                                                    child: MyText(
                                                      text: languages[
                                                      choosenLanguage]
                                                      ['text_decline'],
                                                      size: media.width *
                                                          sixteen,
                                                      color: verifyDeclined,
                                                      fontweight:
                                                      FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        isOverLayPermission =
                                                        false;
                                                      });
                                                      // DashBubble.instance
                                                      //     .requestOverlayPermission();
                                                      if (platform ==
                                                          TargetPlatform
                                                              .android) {
                                                        QuickNav.I
                                                            .askPermission();
                                                      }
                                                    },
                                                    child: MyText(
                                                      text: languages[
                                                      choosenLanguage]
                                                      [
                                                      'text_open_settings'],
                                                      textAlign:
                                                      TextAlign.end,
                                                      size: media.width *
                                                          sixteen,
                                                      color: online,
                                                      fontweight:
                                                      FontWeight.bold,
                                                    ),
                                                  ),
                                                )
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                                : Container(),
                          ],
                        );
                      }),
                ),
              );
            }),
      ),
    );
  }

  double getBearing(LatLng begin, LatLng end) {
    // Returns bearing in degrees (0° = North, 90° = East), normalized to [0, 360).
    final double lat1 = begin.latitude * (pi / 180.0);
    final double lon1 = begin.longitude * (pi / 180.0);
    final double lat2 = end.latitude * (pi / 180.0);
    final double lon2 = end.longitude * (pi / 180.0);

    final double dLon = lon2 - lon1;

    final double y = sin(dLon) * cos(lat2);
    final double x =
        (cos(lat1) * sin(lat2)) - (sin(lat1) * cos(lat2) * cos(dLon));

    final double brng = atan2(y, x);
    final double brngDeg = ((brng * 180.0 / pi) + 360.0) % 360.0; // o 180.0

    return brngDeg;
  }

  animateCar(
      double fromLat, //Starting latitude

      double fromLong, //Starting longitude

      double toLat, //Ending latitude

      double toLong, //Ending longitude

      StreamSink<List<Marker>>
      mapMarkerSink, //Stream build of map to update the UI

      TickerProvider
      provider, //Ticker provider of the widget. This is used for animation

      // GoogleMapController controller, //Google map controller of our widget

      markerid,
      icon,
      name,
      number) async {
    final double bearing =
    getBearing(LatLng(fromLat, fromLong), LatLng(toLat, toLong));


    // Force Google-style blue arrow for the driver's own marker (id '1')
    if (mapType == 'google' && markerid.toString() == '1' && userDetails['role'] == 'driver') {
      await _ensureDriverGoogleArrowIcon();
      if (_driverGoogleArrowIcon != null) {
        icon = _driverGoogleArrowIcon!;
      }
    }


    dynamic carMarker;
    if (name == '' && number == '') {
      carMarker = Marker(
          markerId: MarkerId(markerid),
          position: LatLng(fromLat, fromLong),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: _followBearing ? ((bearing % 360) + 360) % 360 : _vehicleRotationDeg(bearing),
          draggable: false);
    } else {
      carMarker = Marker(
          markerId: MarkerId(markerid),
          position: LatLng(fromLat, fromLong),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: number, snippet: name),
          flat: true,
          rotation: _followBearing ? ((bearing % 360) + 360) % 360 : _vehicleRotationDeg(bearing),
          draggable: false);
    }

    myMarkers.add(carMarker);

    mapMarkerSink.add(Set<Marker>.from(myMarkers).toList());

    Tween<double> tween = Tween(begin: 0, end: 1);

    _animation = tween.animate(animationController)
      ..addListener(() async {
        myMarkers
            .removeWhere((element) => element.markerId == MarkerId(markerid));

        final v = _animation!.value;

        double lng = v * toLong + (1 - v) * fromLong;

        double lat = v * toLat + (1 - v) * fromLat;

        LatLng newPos = LatLng(lat, lng);

        // Seguir automáticamente al vehículo en Google Maps
        if (mapType == 'google' && _controller != null) {
          try {
            _controller!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: newPos,
                  zoom: 18.0,
                ),
              ),
            );
          } catch (_) {}
        }

        //New marker location

        if (name == '' && number == '') {
          carMarker = Marker(
              markerId: MarkerId(markerid),
              position: newPos,
              icon: icon,
              anchor: const Offset(0.5, 0.5),
              flat: true,
              rotation: _followBearing ? ((bearing % 360) + 360) % 360 : _vehicleRotationDeg(bearing),
              draggable: false);
        } else {
          carMarker = Marker(
              markerId: MarkerId(markerid),
              position: newPos,
              icon: icon,
              infoWindow: InfoWindow(title: number, snippet: name),
              anchor: const Offset(0.5, 0.5),
              flat: true,
              rotation: _followBearing ? ((bearing % 360) + 360) % 360 : _vehicleRotationDeg(bearing),
              draggable: false);
        }

        //Adding new marker to our list and updating the google map UI.

        myMarkers.add(carMarker);

        mapMarkerSink.add(Set<Marker>.from(myMarkers).toList());
      });

    //Starting the animation

    animationController.forward();

    if (driverReq.isEmpty || driverReq['accepted_at'] != null) {
      if (mapType == 'google') {
        _controller.getVisibleRegion().then((value) {
          if (value.contains(myMarkers
              .firstWhere((element) => element.markerId == MarkerId(markerid))
              .position)) {
          } else {
            _controller.animateCamera(CameraUpdate.newLatLng(center));
          }
        });
      } else {
        if (_fmController.camera.visibleBounds.contains(fmlt.LatLng(
            myMarkers
                .firstWhere(
                    (element) => element.markerId == MarkerId(markerid))
                .position
                .latitude,
            myMarkers
                .firstWhere(
                    (element) => element.markerId == MarkerId(markerid))
                .position
                .longitude)) ==
            false) {
          _fmController.move(
              fmlt.LatLng(
                  myMarkers
                      .firstWhere(
                          (element) => element.markerId == MarkerId(markerid))
                      .position
                      .latitude,
                  myMarkers
                      .firstWhere(
                          (element) => element.markerId == MarkerId(markerid))
                      .position
                      .longitude),
              14);
        }
      }
    }
    animationController = null;
  }

  // ---------------------------------------------------------------------------
  // UI refresh (Home) - BIPP Conductor: Driver status panel (estético, sin lógica)
  // ---------------------------------------------------------------------------

  String _bippPickFirstValue(List<String> keys, {String fallback = '—'}) {
    // 0) stats de hoy (endpoint /driver/today-earnings) si ya están cargadas
    try {
      if (driverTodayEarnings.isNotEmpty) {
        for (final k in keys) {
          if (driverTodayEarnings.containsKey(k) && driverTodayEarnings[k] != null) {
            final s = driverTodayEarnings[k].toString().trim();
            if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
          }
        }
      }
    } catch (_) {
      // ignore
    }

    // 1) userDetails
    for (final k in keys) {
      if (userDetails.containsKey(k) && userDetails[k] != null) {
        final s = userDetails[k].toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
    }
    return fallback;
  }

  double? _bippToDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9\.-]'), '');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  String _bippFormatMoney(dynamic value, String currency) {
    final d = _bippToDouble(value);
    if (d == null) return '${currency}0';
    // Sin intl para no agregar dependencias: redondeo simple
    final rounded = d.round();
    return '$currency$rounded';
  }



  Widget _bippSearchingAnimatedText(TextStyle style) {
    // Latido tipo corazón (sin puntos "...").
    // Importante: solo anima el TEXTO (la lupa queda fija).
    return AnimatedBuilder(
      animation: _bippSearchingCtrl,
      builder: (context, _) {
        final t = _bippSearchingCtrl.value; // 0..1

        double gauss(double mu, double sigma) {
          final x = (t - mu) / sigma;
          return math.exp(-(x * x));
        }

        // Doble pulso estilo latido
        final beat = (gauss(0.18, 0.07) + 0.65 * gauss(0.34, 0.10)).clamp(0.0, 1.0);
        final pulse = 1.0 + 0.032 * beat;
        final opacity = 0.86 + 0.14 * beat;

        return Transform.scale(
          scale: pulse,
          child: Opacity(
            opacity: opacity,
            child: Text(
              'BUSCANDO VIAJE',
              style: style,
            ),
          ),
        );
      },
    );
  }



  Widget _bippGlassCircle({
    required double size,
    required IconData icon,
    double? iconSize,
    Color? iconColor,
    Color? glowColor,
  }) {
    final double s = size;
    final Color g = glowColor ?? Colors.greenAccent.withOpacity(0.35);
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: g,
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.50),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.black.withOpacity(0.25),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                size: iconSize ?? (s * 0.52),
                color: iconColor ?? Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }


  /// Botón redondo "cyber" para controles del mapa (centrar/mi ubicación).
  /// - Glass + blur
  /// - Borde LED verde
  /// - Glow suave (no pesado)
  Widget _bippCyberMapButton({
    required double size,
    required IconData icon,
    double? iconSize,
    VoidCallback? onTap,
  }) {
    final s = size;
    final inner = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // halo externo
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withOpacity(0.35),
            blurRadius: 22,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.50),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
        // anillo LED
        border: Border.all(
          color: Colors.greenAccent.withOpacity(0.35),
          width: 1.2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.greenAccent.withOpacity(0.18),
            Colors.black.withOpacity(0.50),
          ],
        ),
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.35),
                radius: 1.0,
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.black.withOpacity(0.32),
                  Colors.black.withOpacity(0.60),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
                width: 0.8,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                size: iconSize ?? (s * 0.52),
                color: Colors.white.withOpacity(0.92),
                shadows: [
                  Shadow(
                    color: Colors.greenAccent.withOpacity(0.55),
                    blurRadius: 14,
                  ),
                  Shadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (onTap == null) return inner;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(s / 2),
        onTap: onTap,
        child: inner,
      ),
    );
  }

  Widget _bippGlassCircleButton({
    required double size,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onTap,
        child: _bippGlassCircle(
          size: size,
          icon: icon,
        ),
      ),
    );
  }

  Widget _bippStatsBar({
    required Size media,
    required String trips,
    required String earnings,
    required String timeOnline,
  }) {
    final double h = media.width * 0.175;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            border: Border.all(color: const Color(0xFF00FFB0).withOpacity(0.12), width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: _bippStatItem(
                  icon: Icons.local_taxi_outlined,
                  value: trips,
                  labelTop: 'Viajes',
                  labelBottom: 'hoy',
                ),
              ),
              _bippVDivider(),
              Expanded(
                child: _bippStatItem(
                  icon: Icons.payments_outlined,
                  value: earnings,
                  labelTop: 'Ganancia',
                  labelBottom: 'hoy',
                  valueColor: const Color(0xff00FFB0),
                ),
              ),
              _bippVDivider(),
              Expanded(
                child: _bippStatItem(
                  icon: Icons.schedule,
                  value: timeOnline,
                  labelTop: 'Tiempo',
                  labelBottom: 'en línea',
                  valueColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  // =============================================================
  // Barra inferior futurista (estilo mockup) - solo en pantalla home
  // =============================================================
  Widget _bippFuturisticBottomBar(Size media) {
    return Positioned(
      left: 14,
      right: 14,
      bottom: 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: media.width * 0.18,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.26),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFF00FFB0).withOpacity(0.10), width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff00FFB0).withOpacity(0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _bippNavItem(
                  icon: Icons.home_rounded,
                  label: 'Inicio',
                  active: true,
                  onTap: () {},
                ),
                _bippNavItem(
                  icon: Icons.history_rounded,
                  label: 'Historia',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const History()),
                    );
                  },
                ),
                _bippNavItem(
                  icon: Icons.savings_outlined,
                  label: 'Ganancias',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DriverEarnings()),
                    );
                  },
                ),
                _bippNavItem(
                  icon: Icons.directions_car_rounded,
                  label: 'Viajes',
                  onTap: () {
                    // Por ahora no hace nada (pedido por Maxi)
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bippNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final c = active ? const Color(0xff00FFB0) : Colors.white.withOpacity(0.85);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bippVDivider() {
    return Container(
      width: 1,
      height: 34,
      decoration: _bippGreenFadeDecoration(opacity: 0.10, withBorder: false, withShadow: false, borderRadius: BorderRadius.circular(2)),
      margin: const EdgeInsets.symmetric(horizontal: 10),
    );
  }

  Widget _bippStatItem({
    required IconData icon,
    required String value,
    required String labelTop,
    required String labelBottom,
    Color? valueColor,
  }) {
    final String label = (labelBottom.trim().isEmpty)
        ? labelTop
        : '$labelTop ${labelBottom.trim()}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.90), size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Valor (más grande) pero nunca se desborda
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 18,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bippStatChip({
    required String value,
    required String label,
    required Size media,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: media.width * 0.02,
          horizontal: media.width * 0.02,
        ),
        margin: EdgeInsets.symmetric(horizontal: media.width * 0.008),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF00FFB0).withOpacity(0.08), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bippDriverTopPanel(Size media) {
    final bool online = userDetails['active'] == true;

    final String name = _bippPickFirstValue(
      ['name', 'first_name', 'firstname', 'user_name', 'username'],
      fallback: 'Conductor',
    );

    final String currency = _bippPickFirstValue(
      ['requested_currency_symbol', 'currency_symbol', 'currency', 'symbol'],
      fallback: '\$',
    );

    final dynamic tripsRaw = _bippPickFirstDynamic(
      [
        'total_rides',
        'total_trips',
        'rides',
        'trips',
        'rides_count',
        'trips_count',
        'completed_rides',
        'completed_trips',
        'ride_count',
        'trip_count',
        'today_trips',
        'trips_today',
        'rides_today',
        'completed_trips_today',
        'trip_today',
        'today_trip',
        'todayTrip',
        'today_trip_count',
        'trip_count_today',
        'today_completed_trips',
        'today_rides',
      ],
      fallback: 0,
    );
    final String trips = (_bippToDouble(tripsRaw)?.round() ?? 0).toString();

    final dynamic earningsRaw = _bippPickFirstDynamic(
      [
        'total_earnings',
        'totalEarnings',
        'earnings',
        'total',
        'total_amount',
        'amount',
        'grand_total',
        'total_income',
        'income',
        'total_profit',
        'profit',
        'today_earnings',
        'earnings_today',
        'profit_today',
        'driver_earnings_today',
        'earning_today',
        'todayEarnings',
        'today_earning',
        'today_profit',
        'today_income',
        'today_amount',
        'income_today',
        'earningsDay',
      ],
      fallback: 0,
    );

    final String timeOnline = _bippPickFirstValue(
      ['time_online', 'online_time', 'time_in_line', 'online_duration', 'minutes_online'],
      fallback: online ? 'En línea' : '—',
    );

    final String earnings = _bippFormatMoney(earningsRaw, currency);

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        // Más ancho (casi de borde a borde), con margen externo mínimo
        width: media.width * 0.985,
        padding: EdgeInsets.symmetric(
          horizontal: media.width * 0.018,
          vertical: media.width * 0.014,
        ),
        child: _bippGlassCard(
          greenFade: true,
          // Padding interno para que el texto no quede pegado al borde
          padding: EdgeInsets.symmetric(
            horizontal: media.width * 0.04,
            vertical: media.width * 0.03,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola $name',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                online ? 'Todo listo para conducir' : 'Conectate para empezar',
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.15),
              ),
              SizedBox(height: media.width * 0.03),
              _bippStatsBar(
                media: media,
                trips: trips,
                earnings: earnings,
                timeOnline: timeOnline,
              ),
              SizedBox(height: media.width * 0.03),

              // Botón principal (online = BUSCANDO VIAJE, offline = CONECTARSE)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (online ? Colors.redAccent : Colors.greenAccent).withOpacity(0.25),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                    if (online)
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      height: media.width * 0.175,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.55, 1.0],
                          colors: online
                              ? [
                            const Color(0xffFF4D6D).withOpacity(0.95),
                            const Color(0xffFF165D).withOpacity(0.95),
                            const Color(0xffB5172E).withOpacity(0.95),
                          ]
                              : [
                            const Color(0xff00FFB0).withOpacity(0.95),
                            const Color(0xff00E688).withOpacity(0.95),
                            const Color(0xff00B86B).withOpacity(0.95),
                          ],
                        ),
                        border: Border.all(
                          color: online
                              ? Colors.white.withOpacity(0.18)
                              : Colors.greenAccent.withOpacity(0.22),
                          width: 1.2,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Neon glow interno (futurista)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _bippSearchingCtrl,
                                builder: (context, _) {
                                  final t = _bippSearchingCtrl.value;
                                  final pulse = 0.55 + 0.45 * math.sin(2 * math.pi * t).abs();
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: const Alignment(0, -0.2),
                                        radius: 1.25,
                                        colors: [
                                          Colors.white.withOpacity(0.06 * pulse),
                                          (userDetails['active'] == true
                                              ? const Color(0xff7CF7FF)
                                              : const Color(0xff00FFB0))
                                              .withOpacity(0.10 * pulse),
                                          Colors.transparent,
                                        ],
                                        stops: const [0.0, 0.55, 1.0],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // Top highlight interno (da el efecto premium del mockup)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Container(
                                height: media.width * 0.06,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withOpacity(0.18),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Borde láser/LED (cyber) alrededor del botón
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _bippSearchingCtrl,
                                    builder: (context, _) {
                                      return CustomPaint(
                                        painter: _BippLaserBorderPainter(
                                          t: _bippSearchingCtrl.value,
                                          online: online,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Shine barrido (más elegante) - mantiene la lupa fija
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: AnimatedBuilder(
                                  animation: _bippSearchingCtrl,
                                  builder: (context, _) {
                                    final t = _bippSearchingCtrl.value; // 0..1
                                    final dx = (t * 2 - 1) * (media.width * 0.22);
                                    return Transform.translate(
                                      offset: Offset(dx, 0),
                                      child: Opacity(
                                        opacity: online ? 0.22 : 0.16,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            widthFactor: 0.55,
                                            heightFactor: 1.0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.white24,
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                online ? Icons.search_rounded : Icons.power,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: media.width * 0.55,
                                child: Center(
                                  child: online
                                      ? _bippSearchingAnimatedText(
                                    const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.85,
                                      shadows: [
                                        Shadow(
                                          color: Color(0x66000000),
                                          blurRadius: 14,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  )
                                      : const Text(
                                    'CONECTARSE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // Helpers faltantes (v5) - NO afectan lógica, solo UI (compila y es seguro)
  // ---------------------------------------------------------------------------

  dynamic _bippPickFirstDynamic(List<String> keys, {dynamic fallback}) {
    // 0) Stats de hoy (endpoint /driver/today-earnings) si ya están cargadas
    try {
      if (driverTodayEarnings.isNotEmpty) {
        // 0.a) nivel raíz (driverTodayEarnings['...'])
        for (final k in keys) {
          if (driverTodayEarnings.containsKey(k) && driverTodayEarnings[k] != null) {
            return driverTodayEarnings[k];
          }
        }

        // 0.b) nivel anidado común dentro del payload
        const nestedBuckets = [
          'today',
          'stats',
          'summary',
          'dashboard',
          'home',
          'data',
        ];

        for (final b in nestedBuckets) {
          final v = driverTodayEarnings[b];
          if (v is Map) {
            for (final k in keys) {
              if (v.containsKey(k) && v[k] != null) return v[k];
            }
          }
        }
      }
    } catch (_) {
      // ignore
    }

    // 1) Nivel raíz (userDetails['...'])
    for (final k in keys) {
      if (userDetails.containsKey(k) && userDetails[k] != null) {
        return userDetails[k];
      }
    }

    // 2) Nivel anidado típico (userDetails['today'] / ['stats'] / etc)
    const nestedBuckets = [
      'today',
      'stats',
      'summary',
      'dashboard',
      'home',
      'data',
      'driver',
    ];

    for (final bucket in nestedBuckets) {
      final v = userDetails[bucket];
      if (v is Map) {
        for (final k in keys) {
          if (v.containsKey(k) && v[k] != null) return v[k];
        }
      }
    }

    return fallback;
  }

  Widget _bippGlassCard({required Widget child, EdgeInsetsGeometry? padding, bool greenFade = false}) {
    final EdgeInsetsGeometry pad = padding ?? EdgeInsets.zero;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC0B1620),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF00FFB0).withOpacity(0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.50),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.10),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Suave brillo diagonal (premium)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0.0, 0.5, 1.0],
                        colors: [
                          Colors.white.withOpacity(0.05),
                          Colors.transparent,
                          Colors.black.withOpacity(0.06),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Degradé verde (cyber) que se desvanece a transparente
              if (greenFade)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.32, 0.72, 1.0],
                          colors: [
                            const Color(0xFF00FFB0).withOpacity(0.26),
                            const Color(0xFF00FFB0).withOpacity(0.14),
                            const Color(0xFF00FFB0).withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Top glow suave (premium)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 64,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.greenAccent.withOpacity(0.18),
                          Colors.greenAccent.withOpacity(0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: pad,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _onUserInteractedWithMap() {
    // Si el usuario toca o mueve el mapa con la mano, dejamos de seguir automáticamente
    // para que el mapa se pueda panear libremente.
    if (!_followDriver && !_followBearing) return;
    setState(() {
      _followDriver = false;
      _followBearing = false;
    });
  }
}


LinearGradient _bippGreenFadeGradient({bool strong = false, double opacity = 1.0}) {
  // Degradé VERDE pero 100% OPACO (sin transparencias) para que se lean las letras
  // sobre el mapa. Mantiene el look del panel principal pero sólido.
  return const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.35, 0.75, 1.0],
    colors: [
      Color(0xFF0E5B54),
      Color(0xFF0B3F46),
      Color(0xFF082B3A),
      Color(0xFF061722),
    ],
  );
}



BoxDecoration _bippGreenFadeDecoration({
  BorderRadius? borderRadius,
  bool withBorder = true,
  bool strong = false,
  bool withShadow = true,
  double opacity = 1.0,
}) {
  // Fondo sólido (opaco). `opacity` se mantiene por compatibilidad pero NO se usa.
  final BorderRadius br = borderRadius ?? BorderRadius.circular(16);

  return BoxDecoration(
    gradient: _bippGreenFadeGradient(strong: strong, opacity: 1.0),
    borderRadius: br,
    border: withBorder
        ? Border.all(
      color: const Color(0xFF136E64), // borde verde oscuro, opaco
      width: 1.2,
    )
        : null,
    boxShadow: withShadow
        ? const [
      BoxShadow(
        color: Color(0x66000000), // sombra suave
        blurRadius: 18,
        offset: Offset(0, 10),
      ),
    ]
        : null,
  );
}


dynamic distTime;

class OwnerCarImagecontainer extends StatelessWidget {
  final String imgurl;
  final String text;
  final Color color;
  final void Function()? ontap;
  const OwnerCarImagecontainer(
      {super.key,
        required this.imgurl,
        required this.text,
        required this.ontap,
        required this.color});

  @override
  Widget build(BuildContext context) {
    var media = MediaQuery.of(context).size;

    return InkWell(
      onTap: ontap,
      child: Container(
        padding: EdgeInsets.all(
          media.width * 0.01,
        ),
        width: media.width * 0.15,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                      image: AssetImage(imgurl), fit: BoxFit.contain)),
              height: media.width * 0.07,
              width: media.width * 0.15,
            ),
            Container(
              height: media.width * 0.03,
              width: media.width * 0.13,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: color,
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            )
          ],
        ),
      ),
    );
  }
}

List decodeEncodedPolyline(String encoded) {
  // List poly = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;
    LatLng p = LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble());
    fmpoly.add(
      fmlt.LatLng(p.latitude, p.longitude),
    );
  }
  return fmpoly;
}

class TripStopsBottomSheet extends StatefulWidget {
  const TripStopsBottomSheet({super.key});

  @override
  State<TripStopsBottomSheet> createState() => _TripStopsBottomSheetState();
}

class _TripStopsBottomSheetState extends State<TripStopsBottomSheet> {
  dynamic tempStopId;
  dynamic tempAddress;
  @override
  Widget build(BuildContext context) {
    var media = MediaQuery.of(context).size;

    return Container(
      padding: EdgeInsets.all(media.width * 0.05),
      width: media.width * 1,
      height: media.width * 0.7,
      decoration: BoxDecoration(
          gradient: _bippGreenFadeGradient(),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(media.width * 0.05),
              topRight: Radius.circular(media.width * 0.05))),
      child: Column(
        children: [
          SizedBox(
            width: media.width * 0.9,
            child: MyText(
              color: Colors.white,
              text: languages[choosenLanguage]['text_drop_stops'],
              size: media.width * sixteen,
              fontweight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: ListView.builder(
                itemCount: tripStops.length - 1,
                itemBuilder: (BuildContext context, int i) {
                  return (tripStops[i]['completed_at'] == null)
                      ? InkWell(
                      onTap: () {
                        setState(() {
                          tempStopId = tripStops[i]['id'];
                          tempAddress = tripStops[i]['address'].toString();
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.all(media.width * 0.02),
                        child: Row(
                          children: [
                            Container(
                              width: media.width * 0.05,
                              height: media.width * 0.05,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border:
                                  Border.all(width: 1, color: theme)),
                              alignment: Alignment.center,
                              child: (tempStopId == tripStops[i]['id'])
                                  ? Container(
                                width: media.width * 0.025,
                                height: media.width * 0.025,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme),
                              )
                                  : Container(),
                            ),
                            SizedBox(
                              width: media.width * 0.025,
                            ),
                            Expanded(
                                child: MyText(
                                    color: Colors.white,
                                    text:
                                    tripStops[i]['address'].toString(),
                                    size: media.width * fourteen)),
                          ],
                        ),
                      ))
                      : Container();
                }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Button(
                  onTap: () async {
                    if (tempStopId != null) {
                      Navigator.pop(context);
                      Future.delayed(const Duration(milliseconds: 50), () {
                        showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) {
                              return TRipBottomSheetConfrimation(
                                tempStopId: tempStopId,
                                tempAddress: tempAddress,
                              );
                            });
                      });
                    }
                  },
                  color: (tempStopId == null)
                      ? Colors.grey
                      : (isDarkTheme)
                      ? buttonColor
                      : Colors.black,
                  text: languages[choosenLanguage]['text_confirm']),
            ],
          )
        ],
      ),
    );
  }
}

class TRipBottomSheetConfrimation extends StatefulWidget {
  final dynamic tempStopId;
  final dynamic tempAddress;
  const TRipBottomSheetConfrimation(
      {super.key, this.tempStopId, this.tempAddress});

  @override
  State<TRipBottomSheetConfrimation> createState() =>
      _TRipBottomSheetConfrimationState();
}

class _TRipBottomSheetConfrimationState
    extends State<TRipBottomSheetConfrimation> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    var media = MediaQuery.of(context).size;

    return Container(
      padding: EdgeInsets.all(media.width * 0.05),
      width: media.width * 1,
      height: media.width * 0.5,
      decoration: BoxDecoration(
          gradient: _bippGreenFadeGradient(),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(media.width * 0.05),
              topRight: Radius.circular(media.width * 0.05))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          MyText(
            color: Colors.white,
            text: languages[choosenLanguage]['text_end_trip_desc']
                .toString()
                .replaceAll('3', '${tripStops.length - 1}'),
            size: media.width * sixteen,
            fontweight: FontWeight.bold,
          ),
          (isLoading == true)
              ? Container(
            height: media.width * 0.12,
            width: media.width * 0.9,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(media.width * 0.02)),
            child: SizedBox(
              height: media.width * 0.06,
              width: media.width * 0.07,
              child: const CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Button(
                  width: media.width * 0.4,
                  color: page,
                  onTap: () async {
                    setState(() {
                      isLoading = true;
                    });
                    if (driverReq['enable_shipment_unload_feature']
                        .toString() ==
                        '1') {
                      unloadImage = true;
                      valueNotifierHome.incrementNotifier();

                      Navigator.pop(context);
                    } else if (driverReq['enable_shipment_unload_feature']
                        .toString() ==
                        '0' &&
                        driverReq['enable_digital_signature']
                            .toString() ==
                            '1') {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                              const DigitalSignature()));
                    } else {
                      await endTrip();
                    }
                  },
                  text: languages[choosenLanguage]['text_end_all']),
              Button(
                  width: media.width * 0.4,
                  onTap: () async {
                    setState(() {
                      isLoading = true;
                    });
                    var val = await stopComplete(widget.tempStopId);
                    if (val == 'success') {
                      if (mapType == 'google') {
                        var res = await getUserDetails();
                        if (res == true) {
                          // addMarkers();

                          Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const Maps()),
                                  (route) => false);
                        }
                      } else {
                        // fmpoly.clear();
                        getUserDetails();
                        if (addressList
                            .firstWhere((e) => e.type == 'drop')
                            .address ==
                            widget.tempAddress) {
                          addressList
                              .firstWhere((e) => e.type == 'drop')
                              .completedat = '1234';
                        }
                        Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const Maps()),
                                (route) => false);
                      }
                      setState(() {
                        isLoading = false;
                      });
                    }
                  },
                  text: languages[choosenLanguage]['text_end_stop'])
            ],
          )
        ],
      ),
    );
  }
}





// =============================================================
// Borde láser / LED (cyber) para el botón principal
// =============================================================
class _BippLaserBorderPainter extends CustomPainter {
  final double t; // 0..1
  final bool online;

  const _BippLaserBorderPainter({required this.t, required this.online});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final radius = Radius.circular(math.min(28, size.height / 2));
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final rect = Offset.zero & size;

    // Paleta cyber: cian/verde para "neón"; si está online (buscando) suma un toque magenta.
    final neonA = online ? const Color(0xFF7CF7FF) : const Color(0xFF00FFB0);
    final neonB = online ? const Color(0xFF00FFB0) : const Color(0xFF7CF7FF);
    final neonC = online ? const Color(0xFFFF5C8A) : const Color(0xFF7CF7FF);

    // Giro del brillo alrededor del borde (efecto láser)
    final rotation = GradientRotation(2 * math.pi * t);

    final sweep = SweepGradient(
      transform: rotation,
      colors: [
        Colors.transparent,
        neonA.withOpacity(0.10),
        neonB.withOpacity(0.90),
        Colors.white.withOpacity(0.80),
        neonC.withOpacity(0.45),
        neonA.withOpacity(0.10),
        Colors.transparent,
      ],
      stops: const [0.00, 0.40, 0.47, 0.50, 0.54, 0.60, 1.00],
    );

    // Glow externo (más grande)
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..shader = sweep.createShader(rect)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10);

    // Línea principal (más nítida)
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = sweep.createShader(rect);

    // Borde base suave (para que no "tiemble" el contorno)
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(0.12);

    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, strokePaint);
    canvas.drawRRect(rrect, basePaint);
  }

  @override
  bool shouldRepaint(covariant _BippLaserBorderPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.online != online;
  }
}

// =============================================================
// Pequeña línea ECG para el botón "BUSCANDO VIAJE"
// =============================================================
class _BippEcgLine extends StatefulWidget {
  const _BippEcgLine({super.key});

  @override
  State<_BippEcgLine> createState() => _BippEcgLineState();
}

class _BippEcgLineState extends State<_BippEcgLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final raw = _controller.value; // 0..1
          final t = Curves.easeInOut.transform(raw);
          return CustomPaint(
            painter: _EcgPulsePainter(
              progress: t,
              intensity: 0.92 + 0.08 * sin(2 * pi * t),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}


class _EcgPulsePainter extends CustomPainter {
  _EcgPulsePainter({
    required this.progress,
    required this.intensity,
  });

  final double progress; // 0..1
  final double intensity; // ~0.7..1.0

  // Patrón tipo ECG (x: 0..1, y: -1..1)
  static const List<Offset> _pattern = [
    Offset(0.00, 0.00),
    Offset(0.08, 0.00),
    Offset(0.12, 0.18),
    Offset(0.16, -0.10),
    Offset(0.20, 0.00),
    Offset(0.30, 0.00),
    Offset(0.34, 0.78),
    Offset(0.36, -0.70),
    Offset(0.40, 0.12),
    Offset(0.44, 0.00),
    Offset(0.56, 0.00),
    Offset(0.60, 0.26),
    Offset(0.64, 0.00),
    Offset(1.00, 0.00),
  ];

  double _samplePattern(double x) {
    // x in [0,1)
    for (int i = 0; i < _pattern.length - 1; i++) {
      final a = _pattern[i];
      final b = _pattern[i + 1];
      if (x >= a.dx && x <= b.dx) {
        final span = (b.dx - a.dx);
        final t = span == 0 ? 0 : (x - a.dx) / span;
        return a.dy + (b.dy - a.dy) * t;
      }
    }
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final amp = size.height * 0.40 * intensity;

    // Baseline (muy sutil)
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.08);

    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), basePaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x5500FFB0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF00FFB0);

    // Construimos la línea repitiendo el patrón y desplazándolo con progress
    final pts = <Offset>[];
    const repeats = 2.0;
    final shift = progress; // 0..1

    // sample points
    const samples = 160;
    for (int i = 0; i <= samples; i++) {
      final xNorm = i / samples; // 0..1
      final xShift = (xNorm + shift) % 1.0;
      final pX = (xShift * repeats) % 1.0;
      final yNorm = _samplePattern(pX);
      final x = xNorm * size.width;
      final y = midY - (yNorm * amp);
      pts.add(Offset(x, y));
    }

    // Dibujo glow + línea
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // Punto "vivo" que recorre la línea
    final dotX = size.width * (0.10 + 0.80 * progress);
    final dotIndex = ((dotX / size.width) * samples).clamp(0, samples).toInt();
    final dot = pts[dotIndex];

    final dotGlow = Paint()
      ..color = const Color(0x6600FFB0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final dotPaint = Paint()..color = const Color(0xFF00FFB0);

    canvas.drawCircle(dot, 9, dotGlow);
    canvas.drawCircle(dot, 3.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _EcgPulsePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.intensity != intensity;
  }
}
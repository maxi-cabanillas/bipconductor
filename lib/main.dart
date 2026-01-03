import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:quick_nav/quick_nav.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';

import 'functions/functions.dart';
import 'functions/notifications.dart';
import 'pages/loadingPage/loadingpage.dart';

// -------------------------------------------------------------
// BACKGROUND PUSH HANDLER
// -------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.data['push_type']?.toString() == 'meta-request') {
    AndroidIntent intent = AndroidIntent(
      action: 'action_view',
      package: 'com.macmovil.driver',
      componentName: 'com.macmovil.driver.MainActivity',
    );
    await intent.launch();
  }
}

// -------------------------------------------------------------
// BACKGROUND LOCATION UPDATE
// -------------------------------------------------------------
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp();

      final position = await Geolocator.getCurrentPosition();

      if (inputData?['id'] != null) {
        FirebaseDatabase.instance.ref().child('drivers/driver_${inputData!['id']}').update({
          'lat-lng': position.latitude.toString(),
          'l': {'0': position.latitude, '1': position.longitude},
          'updated_at': ServerValue.timestamp,
        });
      }
    } catch (e) {
      debugPrint("BackgroundLocationError: $e");
    }

    return Future.value(true);
  });
}

// -------------------------------------------------------------
// MAIN
// -------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp();
  initMessaging();
  checkInternetConnection();
  currentPositionUpdate();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

// -------------------------------------------------------------
// ROOT APP
// -------------------------------------------------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Workmanager().cancelAll();

    if (Platform.isAndroid) {
      initQuickNav();
    }
  }

  // -----------------------------------------------------------
  // QUICKNAV (BURBUJA)
  // -----------------------------------------------------------
  Future<void> initQuickNav() async {
    try {
      QuickNav.I.initService(
        chatHeadIcon: '@drawable/logo',
        notificationIcon: "@drawable/logo",
        notificationCircleHexColor: 0xFFA432A7,
        screenHeight: 100,
      );
    } catch (e) {
      debugPrint("QuickNavInitError: $e");
    }
  }

  Future<void> startBubbleHead() async {
    try {
      bool? hasPermission = await QuickNav.I.checkPermission();
      if (hasPermission == false) {
        hasPermission = await QuickNav.I.askPermission();
      }

      if (hasPermission == true) {
        await QuickNav.I.startService();
      }
    } catch (e) {
      debugPrint("BubbleStartError: $e");
    }
  }

  Future<void> stopBubbleHead() async {
    try {
      await QuickNav.I.stopService();
    } catch (e) {
      debugPrint("BubbleStopError: $e");
    }
  }

  // -----------------------------------------------------------
  // LIFECYCLE MANAGEMENT
  // -----------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (Platform.isAndroid) {
      if (state == AppLifecycleState.paused) {
        // App se fue al background
        if (userDetails.isNotEmpty &&
            userDetails['role'] == 'driver' &&
            userDetails['active'] == true) {
          updateLocation(10);
          initQuickNav();
          final hasPermission = await QuickNav.I.checkPermission() ?? false;
          if (hasPermission) {
            startBubbleHead();
          }
        }
      }

      if (state == AppLifecycleState.resumed) {
        // App volvió al foreground
        stopBubbleHead();
        Workmanager().cancelAll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    platform = Theme.of(context).platform;

    return GestureDetector(
      onTap: () {
        final currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus) {
          currentFocus.unfocus();
        }
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Bip Conductor',
        theme: ThemeData(),
        home: const LoadingPage(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.0),
            ),
            child: child!,
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------
// PERIODIC LOCATION UPDATES
// -------------------------------------------------------------
void updateLocation(int initialDelayMinutes) {
  // NOTE: WorkManager periodic tasks have a minimum interval of 15 minutes on Android.
  // If you need sub-minute / 5s updates in background, you'll need a Foreground Service.
  if (userDetails.isEmpty || userDetails['id'] == null) return;

  final id = userDetails['id'].toString();
  final safeDelay = initialDelayMinutes < 0 ? 0 : initialDelayMinutes;

  // Register ONE periodic task (avoid scheduling 15 tasks).
  Workmanager().registerPeriodicTask(
    'bg_location',
    'bg_location',
    initialDelay: Duration(minutes: safeDelay),
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
    inputData: {'id': id},
  );
}

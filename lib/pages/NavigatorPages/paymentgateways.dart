// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_driver/functions/functions.dart';
import 'package:flutter_driver/pages/NavigatorPages/walletpage.dart';
import 'package:flutter_driver/pages/noInternet/nointernet.dart';
import 'package:flutter_driver/styles/styles.dart';
import 'package:flutter_driver/translation/translation.dart';
import 'package:flutter_driver/widgets/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ignore: must_be_immutable
class PaymentGateWaysPage extends StatefulWidget {
  // dynamic from;
  dynamic url;
  PaymentGateWaysPage({super.key, this.url});

  @override
  State<PaymentGateWaysPage> createState() => _PaymentGateWaysPageState();
}

class _PaymentGateWaysPageState extends State<PaymentGateWaysPage> {
  bool pop = true;
  bool _success = false;
  late final WebViewController _controller;

  @override
  void initState() {
    // Construimos una URL válida (con scheme) para cargar en WebView.
    // En algunos backends, widget.url llega como "mercadopago" (sin https),
    // entonces hay que prefijar con el dominio base global `url` (functions.dart).
    final String raw = (widget.url ?? '').toString().trim();

    // Base absoluta: si ya viene con http(s), la usamos; si no, la completamos con `url`.
    final String absoluteBase = (raw.startsWith('http://') || raw.startsWith('https://'))
        ? raw
        : '${url}${raw.startsWith('/') ? raw.substring(1) : raw}';

    final Uri baseUri = Uri.parse(absoluteBase);

    // Armamos params del checkout (wallet).
    final Map<String, String> qp = <String, String>{}
      ..addAll(baseUri.queryParameters)
      ..addAll(<String, String>{
        'amount': addMoney.toString(),
        'payment_for': 'wallet',
        'currency': (walletBalance['currency_symbol'] ?? '').toString(),
        'user_id': (userDetails['user_id'] ?? '').toString(),
      });

    final Uri paymentUri = baseUri.replace(queryParameters: qp);

    late final PlatformWebViewControllerCreationParams params;
    params = const PlatformWebViewControllerCreationParams();

    final WebViewController controller =
    WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            final String u = request.url;
            // Debug: para ver por dónde navega Mercado Pago
            // ignore: avoid_print
            print('PAY NAV => $u');

            // Interceptar esquemas especiales (intent://, mercadopago://, market://, etc.)
            // WebView no puede manejarlos bien; se abren afuera.
            if (!(u.startsWith('http://') || u.startsWith('https://'))) {
              final Uri? ext = Uri.tryParse(u);
              if (ext != null && await canLaunchUrl(ext)) {
                await launchUrl(ext, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            // Success / Failure (back_urls del backend suelen volver a tu dominio base `url`)
            if (u.startsWith('${url}success')) {
              setState(() {
                pop = false;
                _success = true;
              });
              return NavigationDecision.prevent;
            }

            if (u.startsWith('${url}failure')) {
              // No mostramos overlay de éxito; habilitamos el back.
              setState(() {
                pop = true;
              });
              return NavigationDecision.navigate;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (e) {
            // ignore: avoid_print
            print('PAY WEB ERROR => $e');
          },
        ),
      )
      ..loadRequest(paymentUri);

    _controller = controller;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var media = MediaQuery.of(context).size;
    return PopScope(
      canPop: false,
      child: Material(
        child: Stack(
          children: [
            Container(
              height: media.height,
              width: media.width,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              child: Column(
                children: [
                  if (pop == true)
                    Container(
                      width: media.width,
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.all(media.width * 0.05),
                      child: InkWell(
                          onTap: () {
                            Navigator.pop(context, true);
                          },
                          child: const Icon(Icons.arrow_back)),
                    ),
                  Expanded(
                    child: WebViewWidget(
                      controller: _controller,
                    ),
                  ),
                ],
              ),
            ),
            //payment success
            (_success == true)
                ? Positioned(
                top: 0,
                child: Container(
                  alignment: Alignment.center,
                  height: media.height * 1,
                  width: media.width * 1,
                  color: Colors.transparent.withOpacity(0.6),
                  child: Container(
                    padding: EdgeInsets.all(media.width * 0.05),
                    width: media.width * 0.9,
                    height: media.width * 0.8,
                    decoration: BoxDecoration(
                        color: page,
                        borderRadius:
                        BorderRadius.circular(media.width * 0.03)),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/images/paymentsuccess.png',
                          fit: BoxFit.contain,
                          width: media.width * 0.5,
                        ),
                        MyText(
                          text: languages[choosenLanguage]
                          ['text_paymentsuccess'],
                          textAlign: TextAlign.center,
                          size: media.width * sixteen,
                          fontweight: FontWeight.w600,
                        ),
                        SizedBox(
                          height: media.width * 0.07,
                        ),
                        Button(
                            onTap: () {
                              setState(() {
                                _success = false;
                                Navigator.pop(context, true);
                              });
                            },
                            text: languages[choosenLanguage]['text_ok'])
                      ],
                    ),
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
                    });
                  },
                ))
                : Container(),
          ],
        ),
      ),
    );
  }
}

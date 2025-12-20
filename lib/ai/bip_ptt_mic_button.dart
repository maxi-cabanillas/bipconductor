import 'package:flutter/material.dart';
import 'package:flutter_driver/ai/bip_ia.dart';

/// Botón PTT: mantené apretado para hablar.
/// - Presionar: empieza a escuchar
/// - Soltar: procesa comando
class BipPttMicButton extends StatelessWidget {
  const BipPttMicButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BipIA.instance.isListening,
      builder: (context, listening, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTapDown: (_) => BipIA.instance.pttStart(),
            onTapCancel: () => BipIA.instance.pttStopAndProcess(),
            onTapUp: (_) => BipIA.instance.pttStopAndProcess(),
            borderRadius: BorderRadius.circular(32),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: listening ? const Color(0xFFE53935) : const Color(0xFF1E88E5),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: Offset(0, 4),
                    color: Colors.black26,
                  )
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 30),
            ),
          ),
        );
      },
    );
  }
}

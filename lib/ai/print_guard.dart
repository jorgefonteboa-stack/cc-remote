import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../printer/sdcp_client.dart';
import 'failure_detector.dart';
import 'notifier.dart';

enum GuardSensitivity { low, medium, high }

extension on GuardSensitivity {
  /// Confiança mínima numa verificação para contar como "suspeita".
  double get threshold => switch (this) {
        GuardSensitivity.low => 0.70,
        GuardSensitivity.medium => 0.55,
        GuardSensitivity.high => 0.40,
      };

  /// Verificações suspeitas seguidas antes de pausar (evita falsos alarmes).
  int get strikesNeeded => switch (this) {
        GuardSensitivity.low => 4,
        GuardSensitivity.medium => 3,
        GuardSensitivity.high => 2,
      };
}

/// Vigilância IA: analisa frames da câmara durante a impressão e pausa a
/// impressora quando a falha se confirma em várias verificações seguidas.
class PrintGuard extends ChangeNotifier {
  final SdcpClient client;
  PrintGuard(this.client);

  final detector = YoloFailureDetector();
  Duration interval = const Duration(seconds: 10);

  bool enabled = false;
  bool modelReady = false;
  GuardSensitivity sensitivity = GuardSensitivity.medium;

  double risk = 0; // média móvel 0..1, para a barra na UI
  int strikes = 0;
  DateTime? lastCheck;
  String? lastLabel;

  bool triggered = false;
  Uint8List? alertFrame;
  String? alertMessage;

  bool _busy = false;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('guard_enabled') ?? false;
    sensitivity = GuardSensitivity.values[p.getInt('guard_sens') ?? 1];
    modelReady = await detector.load();
    _applyWakelock();
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    if (!v) _resetCounters();
    (await SharedPreferences.getInstance()).setBool('guard_enabled', v);
    if (v) await Notifier.init();
    _applyWakelock();
    notifyListeners();
  }

  Future<void> setSensitivity(GuardSensitivity s) async {
    sensitivity = s;
    (await SharedPreferences.getInstance()).setInt('guard_sens', s.index);
    notifyListeners();
  }

  /// Mantém o ecrã ligado enquanto vigia (a app tem de estar aberta).
  void _applyWakelock() => WakelockPlus.toggle(enable: enabled && modelReady);

  bool get _shouldCheck {
    final s = client.status;
    // Só durante a impressão propriamente dita (não a aquecer/nivelar/em pausa).
    return s.print.status == 13 && !s.isPaused && s.print.currentLayer >= 1;
  }

  /// Ligado ao MjpegView.onFrame. Amostra 1 frame a cada [interval].
  Future<void> onFrame(Uint8List jpeg) async {
    if (!enabled || !modelReady || triggered || _busy) return;
    if (!_shouldCheck) {
      if (strikes > 0 || risk > 0) _resetCounters();
      return;
    }
    final now = DateTime.now();
    if (now.isBefore(_next)) return;
    _next = now.add(interval);
    _busy = true;
    try {
      final r = await detector.analyze(jpeg);
      if (r == null) return;
      lastCheck = now;
      lastLabel = r.failureLabel;
      risk = 0.6 * risk + 0.4 * r.failureScore;
      if (r.failureScore >= sensitivity.threshold) {
        strikes++;
      } else {
        strikes = max(0, strikes - 1);
      }
      if (strikes >= sensitivity.strikesNeeded) {
        await _trigger(jpeg, r);
      }
    } catch (e) {
      debugPrint('PrintGuard: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _trigger(Uint8List frame, DetectorResult r) async {
    triggered = true;
    alertFrame = frame;
    final what = r.failureLabel ?? 'falha';
    final pct = (r.failureScore * 100).round();
    try {
      await client.pause();
      alertMessage = 'Impressão pausada: possível "$what" ($pct%).';
    } catch (e) {
      alertMessage = 'Detetei "$what" ($pct%) mas não consegui pausar: $e';
    }
    await Notifier.alert('Possível falha na impressão', alertMessage!);
    notifyListeners();
  }

  /// O utilizador viu o alerta (retomou ou parou): volta a vigiar do zero.
  void acknowledge() {
    triggered = false;
    alertFrame = null;
    alertMessage = null;
    _resetCounters();
    notifyListeners();
  }

  void _resetCounters() {
    strikes = 0;
    risk = 0;
    _next = DateTime.now().add(interval);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    detector.dispose();
    super.dispose();
  }
}

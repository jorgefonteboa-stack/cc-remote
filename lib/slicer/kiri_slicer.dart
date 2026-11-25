import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'slicer.dart';

/// Corre o motor Kiri:Moto dentro de um WebView invisível, no próprio
/// telemóvel. O HTML é carregado com baseUrl em grid.space para que o motor
/// e os seus web workers carreguem com a mesma origem.
/// (Para funcionar 100% offline, ver "Slicing offline" no README.)
class KiriSlicer implements Slicer {
  HeadlessInAppWebView? _web;
  InAppWebViewController? _ctrl;
  final _ready = Completer<void>();
  void Function(double, String)? _onProgress;

  @override
  Future<void> init() async {
    if (_web != null) return _ready.future;
    final html = await rootBundle.loadString('assets/slicer/slicer.html');
    _web = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: html,
        baseUrl: WebUri('https://grid.space/kiri/'),
      ),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
      onWebViewCreated: (c) {
        _ctrl = c;
        c.addJavaScriptHandler(
            handlerName: 'ready',
            callback: (_) {
              if (!_ready.isCompleted) _ready.complete();
            });
        c.addJavaScriptHandler(
            handlerName: 'progress',
            callback: (args) {
              final p = (args.isNotEmpty && args[0] is num) ? (args[0] as num).toDouble() : 0.0;
              final s = args.length > 1 ? '${args[1]}' : '';
              _onProgress?.call(p, s);
            });
      },
      onReceivedError: (c, req, err) {
        if (!_ready.isCompleted) {
          _ready.completeError('Não foi possível carregar o motor de slicing: ${err.description}');
        }
      },
    );
    await _web!.run();
    return _ready.future.timeout(const Duration(seconds: 30));
  }

  @override
  Future<SliceResult> slice(Uint8List stl, SliceSettings settings,
      {void Function(double progress, String stage)? onProgress}) async {
    await init();
    _onProgress = onProgress;
    final res = await _ctrl!.callAsyncJavaScript(
      functionBody: 'return await window.sliceModel(stl, settings);',
      arguments: {'stl': base64Encode(stl), 'settings': settings.toJson()},
    );
    _onProgress = null;
    if (res == null || res.error != null) {
      throw Exception('Erro no slicing: ${res?.error ?? 'sem resposta'}');
    }
    final v = Map<String, dynamic>.from(res.value as Map);
    final gcode = '${v['gcode'] ?? ''}';
    if (gcode.isEmpty) throw Exception('O slicer não gerou G-code');
    return SliceResult(
      gcode,
      estimatedTime: v['time'] is num ? Duration(seconds: (v['time'] as num).round()) : null,
      filamentMm: v['filament'] is num ? (v['filament'] as num).toDouble() : null,
    );
  }

  @override
  void dispose() {
    _web?.dispose();
    _web = null;
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Visualizador MJPEG sem dependências: lê o stream HTTP e extrai cada JPEG
/// pelos marcadores SOI (FFD8) e EOI (FFD9).
class MjpegView extends StatefulWidget {
  final String url;

  /// Chamado com cada frame JPEG (usado pela vigilância IA).
  final void Function(Uint8List jpeg)? onFrame;
  const MjpegView({super.key, required this.url, this.onFrame});

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Uint8List? _frame;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant MjpegView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _stop();
      _start();
    }
  }

  Future<void> _start() async {
    _client = http.Client();
    final buf = BytesBuilder(copy: false);
    try {
      final res = await _client!.send(http.Request('GET', Uri.parse(widget.url)));
      _sub = res.stream.listen((chunk) {
        buf.add(chunk);
        var data = buf.toBytes();
        while (true) {
          final s = _find(data, 0xD8, 0);
          if (s < 0) break;
          final e = _find(data, 0xD9, s + 2);
          if (e < 0) break;
          final frame = Uint8List.sublistView(data, s, e + 2);
          final copy = Uint8List.fromList(frame);
          if (mounted) setState(() => _frame = copy);
          widget.onFrame?.call(copy);
          data = Uint8List.sublistView(data, e + 2);
        }
        buf.clear();
        // Evita crescer sem limite se o stream vier corrompido.
        if (data.length < 4 * 1024 * 1024) buf.add(data);
      }, onError: (e) {
        if (mounted) setState(() => _error = '$e');
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static int _find(Uint8List d, int marker, int from) {
    for (var i = from; i < d.length - 1; i++) {
      if (d[i] == 0xFF && d[i + 1] == marker) return i;
    }
    return -1;
  }

  void _stop() {
    _sub?.cancel();
    _client?.close();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame != null) {
      return Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.contain);
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Câmara indisponível\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)))
          : const CircularProgressIndicator(),
    );
  }
}

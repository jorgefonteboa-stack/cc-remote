import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/print_guard.dart';
import '../printer/canvas.dart';
import '../printer/object_exclusion.dart';
import '../printer/printer_status.dart';
import 'canvas_panel.dart';
import 'guard_card.dart';
import 'objects_card.dart';
import '../printer/sdcp_client.dart';
import 'mjpeg_view.dart';
import 'slice_screen.dart';

/// Painel da impressora: câmara, estado, temperaturas e controlos.
class PrinterScreen extends StatefulWidget {
  final DiscoveredPrinter printer;
  const PrinterScreen({super.key, required this.printer});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  late final SdcpClient _client =
      SdcpClient(widget.printer.ip, widget.printer.mainboardId);
  final _subs = <StreamSubscription>[];
  PrinterStatus _s = const PrinterStatus();
  bool _connected = false;
  String? _cameraUrl;
  String? _error;
  CanvasState? _canvas;
  bool _canvasLoading = false;
  late final PrintGuard _guard = PrintGuard(_client);
  ExclusionSupport? _exclusion;

  @override
  void initState() {
    super.initState();
    _guard.init();
    _subs.add(_client.statusStream.listen((s) => setState(() => _s = s)));
    _subs.add(_client.canvasStream.listen((c) => setState(() => _canvas = c)));
    _subs.add(_client.connectionStream.listen((c) {
      setState(() => _connected = c);
      if (!c) _reconnectLater();
    }));
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _client.connect();
      setState(() => _error = null);
      unawaited(_loadCanvas());
      unawaited(_detectExclusion());
      final url = await _client.enableCamera();
      if (mounted) setState(() => _cameraUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      _reconnectLater();
    }
  }

  Future<void> _loadCanvas() async {
    setState(() => _canvasLoading = true);
    try {
      final c = await _client.readCanvas();
      if (mounted) setState(() => _canvas = c ?? const CanvasState());
    } catch (e) {
      _toast('Não foi possível ler o CANVAS: $e');
    } finally {
      if (mounted) setState(() => _canvasLoading = false);
    }
  }

  /// Verifica se esta impressora permite cancelar objetos individuais.
  Future<void> _detectExclusion() async {
    if (_exclusion != null) return;
    // Dá tempo a que os atributos (versão de firmware) cheguem.
    await Future.delayed(const Duration(seconds: 1));
    final fw = '${_client.attributes['FirmwareVersion'] ?? widget.printer.firmware}';
    final r = await ObjectExclusion.detect(widget.printer.ip, firmware: fw);
    if (mounted) setState(() => _exclusion = r);
  }

  void _reconnectLater() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_client.connected) _connect();
    });
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      _toast(ok);
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  Future<void> _confirmStop() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Parar impressão?'),
        content: const Text('A impressão atual vai ser cancelada e não pode ser retomada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Parar')),
        ],
      ),
    );
    if (yes == true) _run(_client.stop, 'Impressão parada');
  }

  Future<void> _openFiles() async {
    try {
      final files = await _client.listFiles();
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (c) => ListView(children: [
          const ListTile(title: Text('Ficheiros na impressora')),
          if (files.isEmpty) const ListTile(title: Text('Sem ficheiros .gcode')),
          for (final f in files)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(f),
              trailing: const Icon(Icons.play_arrow),
              onTap: () {
                Navigator.pop(c);
                _run(() => _client.startPrint(f), 'A iniciar $f');
              },
            ),
        ]),
      );
    } catch (e) {
      _toast('Erro: $e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _guard.dispose();
    _client.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}min' : '${d.inMinutes}min';

  @override
  Widget build(BuildContext context) {
    final p = _s.print;
    final busy = _s.isPrinting || _s.isPaused;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.printer.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.circle, size: 12, color: _connected ? Colors.green : Colors.red),
          ),
        ],
      ),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _cameraUrl == null
                ? Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Text(_error ?? 'A ligar…',
                        style: const TextStyle(color: Colors.white70)))
                : MjpegView(url: _cameraUrl!, onFrame: _guard.onFrame),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.label, style: Theme.of(context).textTheme.titleLarge),
              if (p.filename.isNotEmpty) Text(p.filename, overflow: TextOverflow.ellipsis),
              if (busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: (p.progress / 100).clamp(0, 1)),
                const SizedBox(height: 6),
                Text('${p.progress.toStringAsFixed(0)}% · camada ${p.currentLayer}/${p.totalLayer}'
                    ' · faltam ${_fmt(p.remaining)}'),
              ],
              const SizedBox(height: 16),
              Row(children: [
                _Temp('Bico', _s.nozzle, _s.nozzleTarget, Icons.local_fire_department_outlined),
                _Temp('Mesa', _s.bed, _s.bedTarget, Icons.grid_on),
                _Temp('Câmara', _s.chamber, null, Icons.thermostat),
              ]),
              const SizedBox(height: 8),
              GuardCard(
                guard: _guard,
                onResume: () => _run(_client.resume, 'A retomar'),
                onStop: () => _run(_client.stop, 'Impressão parada'),
              ),
              ObjectsCard(support: _exclusion, printing: busy),
              CanvasPanel(
                canvas: _canvas,
                loading: _canvasLoading,
                onRefresh: _loadCanvas,
              ),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_s.isPrinting && !_s.isPaused)
                  FilledButton.tonalIcon(
                      onPressed: () => _run(_client.pause, 'Em pausa'),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pausa')),
                if (_s.isPaused)
                  FilledButton.tonalIcon(
                      onPressed: () {
                        _guard.acknowledge();
                        _run(_client.resume, 'A retomar');
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Retomar')),
                if (busy)
                  FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: _confirmStop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop')),
                FilledButton.tonalIcon(
                  onPressed: () => _run(() => _client.setLight(!(_s.light ?? false)),
                      (_s.light ?? false) ? 'Luz desligada' : 'Luz ligada'),
                  icon: Icon((_s.light ?? false) ? Icons.lightbulb : Icons.lightbulb_outline),
                  label: const Text('Luz'),
                ),
                OutlinedButton.icon(
                    onPressed: _openFiles,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Ficheiros')),
              ]),
            ]),
          ),
        ],
      ),
      floatingActionButton: busy
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SliceScreen(client: _client))),
              icon: const Icon(Icons.layers_outlined),
              label: const Text('Imprimir modelo'),
            ),
    );
  }
}

class _Temp extends StatelessWidget {
  final String label;
  final double value;
  final double? target;
  final IconData icon;
  const _Temp(this.label, this.value, this.target, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text('${value.toStringAsFixed(0)}°C',
                style: Theme.of(context).textTheme.titleMedium),
            Text(target != null && target! > 0 ? '$label → ${target!.toStringAsFixed(0)}°' : label,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

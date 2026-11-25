import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../printer/canvas.dart';
import '../printer/sdcp_client.dart';
import 'canvas_panel.dart';
import '../slicer/kiri_slicer.dart';
import '../slicer/slicer.dart';

/// Fluxo: escolher STL → definir parâmetros → slicing no telemóvel →
/// enviar para a impressora → iniciar.
class SliceScreen extends StatefulWidget {
  final SdcpClient client;
  const SliceScreen({super.key, required this.client});

  @override
  State<SliceScreen> createState() => _SliceScreenState();
}

enum _Stage { idle, slicing, sliced, uploading, done }

class _SliceScreenState extends State<SliceScreen> {
  final Slicer _slicer = KiriSlicer();
  SliceSettings _settings = SliceSettings();
  String? _fileName;
  Uint8List? _stl;
  SliceResult? _result;
  _Stage _stage = _Stage.idle;
  double _progress = 0;
  String _stageLabel = '';
  CanvasState? _canvas;
  bool _canvasLoading = false;

  @override
  void initState() {
    super.initState();
    _slicer.init().catchError((e) => _toast('$e'));
    _canvas = widget.client.canvas;
    if (_canvas != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoSelect();
      });
    }
  }

  /// Botão "Configurar pela máquina": lê os slots e aplica o filamento.
  Future<void> _syncFromMachine() async {
    setState(() => _canvasLoading = true);
    try {
      final c = await widget.client.readCanvas();
      if (!mounted) return;
      setState(() => _canvas = c ?? const CanvasState());
      if (c == null || !c.hasCanvas) {
        _toast('A impressora não reportou filamentos no CANVAS');
      } else {
        _autoSelect();
        _toast('Filamentos sincronizados com a máquina');
      }
    } catch (e) {
      _toast('Erro a ler o CANVAS: $e');
    } finally {
      if (mounted) setState(() => _canvasLoading = false);
    }
  }

  /// Mantém o slot escolhido se ainda tiver filamento; senão usa o ativo
  /// na impressora ou o primeiro slot carregado.
  void _autoSelect() {
    final c = _canvas;
    if (c == null || !c.hasCanvas) return;
    final loaded = c.trays.where((t) => !t.isEmpty).toList();
    if (loaded.isEmpty) return;
    final keep = loaded.where((t) => t.slot == _settings.canvasSlot);
    final active = c.activeTray;
    _selectTray(keep.isNotEmpty
        ? keep.first
        : (active != null && !active.isEmpty ? active : loaded.first));
  }

  void _selectTray(CanvasTray t) {
    setState(() {
      _settings = _settings.withFilament(
        type: t.type,
        slot: t.slot,
        colorHex: t.colorHex,
        minTemp: t.minTemp,
        maxTemp: t.maxTemp,
      );
      _result = _stl != null ? null : _result; // parâmetros mudaram: refazer slicing
      if (_stl != null) _stage = _Stage.idle;
    });
  }

  @override
  void dispose() {
    _slicer.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final name = f.name;
    if (name.toLowerCase().endsWith('.gcode')) {
      // G-code já fatiado: envia diretamente.
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      setState(() {
        _fileName = name;
        _stl = null;
        _result = SliceResult(utf8.decode(bytes, allowMalformed: true));
        _stage = _Stage.sliced;
      });
      return;
    }
    if (!name.toLowerCase().endsWith('.stl')) {
      _toast('Por agora só são suportados ficheiros .stl e .gcode');
      return;
    }
    setState(() {
      _fileName = name;
      _stl = f.bytes ?? File(f.path!).readAsBytesSync();
      _result = null;
      _stage = _Stage.idle;
    });
  }

  Future<void> _slice() async {
    if (_stl == null) return;
    setState(() {
      _stage = _Stage.slicing;
      _progress = 0;
    });
    try {
      final r = await _slicer.slice(_stl!, _settings, onProgress: (p, s) {
        if (mounted) setState(() {
          _progress = p;
          _stageLabel = s;
        });
      });
      setState(() {
        _result = r;
        _stage = _Stage.sliced;
      });
    } catch (e) {
      setState(() => _stage = _Stage.idle);
      _toast('$e');
    }
  }

  String get _gcodeName {
    final base = (_fileName ?? 'modelo').replaceAll(RegExp(r'\.(stl|gcode)$', caseSensitive: false), '');
    return '${base.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}.gcode';
  }

  Future<void> _sendAndPrint() async {
    if (_result == null) return;
    setState(() {
      _stage = _Stage.uploading;
      _progress = 0;
    });
    try {
      final bytes = Uint8List.fromList(utf8.encode(_result!.gcode));
      await widget.client.upload(_gcodeName, bytes,
          onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await widget.client.startPrint(_gcodeName);
      setState(() => _stage = _Stage.done);
      _toast('Impressão iniciada');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _stage = _Stage.sliced);
      _toast('$e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.slicing || _stage == _Stage.uploading;
    return Scaffold(
      appBar: AppBar(title: const Text('Imprimir modelo')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.view_in_ar_outlined, size: 36),
            title: Text(_fileName ?? 'Escolher ficheiro'),
            subtitle: Text(_fileName == null ? '.stl ou .gcode' : 'Toca para trocar'),
            onTap: busy ? null : _pick,
          ),
        ),
        if (_stl != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: Text('Filamento', style: Theme.of(context).textTheme.titleMedium)),
            FilledButton.tonalIcon(
              onPressed: busy || _canvasLoading ? null : _syncFromMachine,
              icon: const Icon(Icons.sync),
              label: const Text('Configurar pela máquina'),
            ),
          ]),
          const SizedBox(height: 8),
          if (_canvas != null || _canvasLoading)
            CanvasPanel(
              canvas: _canvas,
              loading: _canvasLoading,
              selectedSlot: _settings.canvasSlot,
              onSelect: busy ? null : _selectTray,
              onRefresh: _syncFromMachine,
            ),
          if (_settings.canvasSlot != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  'A imprimir com o slot A${_settings.canvasSlot! + 1} · '
                  '${_settings.material} · bico ${_settings.nozzleTemp}° / mesa ${_settings.bedTemp}°'),
            ),
          const SizedBox(height: 8),
          Text('Ou escolher manualmente', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: [
              for (final m in SliceSettings.presets.keys) ButtonSegment(value: m, label: Text(m))
            ],
            selected: _settings.canvasSlot == null &&
                    SliceSettings.presets.containsKey(_settings.material)
                ? {_settings.material}
                : <String>{},
            onSelectionChanged: busy
                ? null
                : (s) {
                    if (s.isEmpty) return;
                    setState(() => _settings = SliceSettings.presets[s.first]!());
                  },
          ),
          const SizedBox(height: 16),
          _slider('Altura de camada', _settings.layerHeight, 0.08, 0.32, 12,
              (v) => _settings.layerHeight = v, (v) => '${v.toStringAsFixed(2)} mm'),
          _slider('Paredes', _settings.walls.toDouble(), 1, 6, 5,
              (v) => _settings.walls = v.round(), (v) => '${v.round()}'),
          _slider('Enchimento', _settings.infill, 0, 1, 20, (v) => _settings.infill = v,
              (v) => '${(v * 100).round()}%'),
          _slider('Bico', _settings.nozzleTemp.toDouble(), 180, 300, 24,
              (v) => _settings.nozzleTemp = v.round(), (v) => '${v.round()}°C'),
          _slider('Mesa', _settings.bedTemp.toDouble(), 0, 110, 22,
              (v) => _settings.bedTemp = v.round(), (v) => '${v.round()}°C'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Suportes'),
            value: _settings.supports,
            onChanged: busy ? null : (v) => setState(() => _settings.supports = v),
          ),
        ],
        const SizedBox(height: 16),
        if (busy) ...[
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          const SizedBox(height: 6),
          Text(_stage == _Stage.slicing
              ? 'A fazer slicing no telemóvel… $_stageLabel'
              : 'A enviar para a impressora… ${(_progress * 100).round()}%'),
        ],
        if (_result != null && !busy)
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(_gcodeName),
              subtitle: Text([
                '${(_result!.gcode.length / 1024 / 1024).toStringAsFixed(1)} MB',
                if (_result!.estimatedTime != null)
                  '~${_result!.estimatedTime!.inMinutes} min',
              ].join(' · ')),
            ),
          ),
        const SizedBox(height: 16),
        if (_stl != null && _stage != _Stage.sliced)
          FilledButton.icon(
              onPressed: busy ? null : _slice,
              icon: const Icon(Icons.layers),
              label: const Text('Fazer slicing')),
        if (_stage == _Stage.sliced)
          FilledButton.icon(
              onPressed: _sendAndPrint,
              icon: const Icon(Icons.send),
              label: const Text('Enviar e imprimir')),
      ]),
    );
  }

  Widget _slider(String label, double value, double min, double max, int div,
      void Function(double) set, String Function(double) fmt) {
    final busy = _stage == _Stage.slicing || _stage == _Stage.uploading;
    return Row(children: [
      SizedBox(width: 120, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: div,
          onChanged: busy ? null : (v) => setState(() => set(v)),
        ),
      ),
      SizedBox(width: 72, child: Text(fmt(value), textAlign: TextAlign.end)),
    ]);
  }
}

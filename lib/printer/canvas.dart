import 'package:flutter/painting.dart';

/// Um slot (tabuleiro) do CANVAS, tal como a CC1 o reporta no Cmd 324.
class CanvasTray {
  final int canvasId, trayId;
  final String brand, type, name, colorHex;
  final int minTemp, maxTemp, status;

  const CanvasTray({
    required this.canvasId,
    required this.trayId,
    this.brand = '',
    this.type = '',
    this.name = '',
    this.colorHex = '',
    this.minTemp = 0,
    this.maxTemp = 0,
    this.status = 0,
  });

  static int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory CanvasTray.fromJson(int canvasId, Map j) => CanvasTray(
        canvasId: canvasId,
        trayId: _i(j['tray_id']),
        brand: '${j['brand'] ?? ''}',
        type: '${j['filament_type'] ?? ''}'.trim(),
        name: '${j['filament_name'] ?? ''}'.trim(),
        colorHex: '${j['filament_color'] ?? ''}',
        minTemp: _i(j['min_nozzle_temp']),
        maxTemp: _i(j['max_nozzle_temp']),
        status: _i(j['status']),
      );

  /// Índice global do slot (0–3 com um Canvas), usado como ferramenta T<n>.
  int get slot => canvasId * 4 + trayId;

  /// Rótulo como no ecrã da impressora: A1…A4.
  String get label => '${String.fromCharCode(65 + canvasId)}${trayId + 1}';

  bool get isEmpty => type.isEmpty;

  Color get color {
    final h = colorHex.replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? const Color(0xFF9E9E9E) : Color(v);
  }

  /// Temperatura sugerida para o bico: o meio do intervalo indicado no slot.
  int get suggestedNozzle =>
      (minTemp > 0 && maxTemp > 0) ? ((minTemp + maxTemp) / 2).round() : 0;
}

class CanvasState {
  final int activeCanvasId, activeTrayId;
  final bool autoRefill;
  final List<CanvasTray> trays;

  const CanvasState({
    this.activeCanvasId = 0,
    this.activeTrayId = -1,
    this.autoRefill = false,
    this.trays = const [],
  });

  bool get hasCanvas => trays.isNotEmpty;

  CanvasTray? get activeTray {
    for (final t in trays) {
      if (t.canvasId == activeCanvasId && t.trayId == activeTrayId) return t;
    }
    return null;
  }

  factory CanvasState.fromJson(Map j) {
    final trays = <CanvasTray>[];
    final list = j['canvas_list'];
    if (list is List) {
      for (final c in list.whereType<Map>()) {
        if (c['connected'] == 0) continue;
        final cid = c['canvas_id'] is num ? (c['canvas_id'] as num).toInt() : 0;
        final tl = c['tray_list'];
        if (tl is List) {
          trays.addAll(tl.whereType<Map>().map((t) => CanvasTray.fromJson(cid, t)));
        }
      }
    }
    trays.sort((a, b) => a.slot.compareTo(b.slot));
    return CanvasState(
      activeCanvasId: j['active_canvas_id'] is num ? (j['active_canvas_id'] as num).toInt() : 0,
      activeTrayId: j['active_tray_id'] is num ? (j['active_tray_id'] as num).toInt() : -1,
      autoRefill: j['auto_refill'] == 1 || j['auto_refill'] == true,
      trays: trays,
    );
  }

  /// A resposta do Cmd 324 pode vir dentro de Data.Data ou noutro nível;
  /// procura o objeto que contém `canvas_list`, esteja onde estiver.
  static CanvasState? find(dynamic json, [int depth = 0]) {
    if (depth > 5) return null;
    if (json is Map) {
      if (json.containsKey('canvas_list')) return CanvasState.fromJson(json);
      for (final v in json.values) {
        final r = find(v, depth + 1);
        if (r != null) return r;
      }
    } else if (json is List) {
      for (final v in json) {
        final r = find(v, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }
}

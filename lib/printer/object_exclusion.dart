import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:http/http.dart' as http;

/// Um objeto da impressão (definido no G-code com EXCLUDE_OBJECT_DEFINE).
class PrintObject {
  final String name;
  final Offset? center;
  final List<Offset> polygon;
  const PrintObject(this.name, {this.center, this.polygon = const []});

  /// Nome mais legível: o OrcaSlicer/ElegooSlicer gera "Cubo.stl_id_0_copy_0".
  String get displayName {
    final m = RegExp(r'^(.*?)(?:\.stl|\.3mf|\.obj)?_id_(\d+)_copy_(\d+)$', caseSensitive: false)
        .firstMatch(name);
    if (m == null) return name.replaceAll('_', ' ');
    final base = m.group(1)!.replaceAll('_', ' ');
    final copy = int.parse(m.group(3)!);
    return copy > 0 ? '$base (${copy + 1})' : base;
  }
}

class ExclusionState {
  final List<PrintObject> objects;
  final Set<String> excluded;
  final String? current;
  final double bedWidth, bedDepth;
  const ExclusionState({
    this.objects = const [],
    this.excluded = const {},
    this.current,
    this.bedWidth = 256,
    this.bedDepth = 256,
  });

  bool isExcluded(PrintObject o) => excluded.contains(o.name);
  int get remaining => objects.where((o) => !isExcluded(o)).length;
}

/// O que a impressora ligada permite fazer com objetos individuais.
class ExclusionSupport {
  final ObjectExclusion? backend;
  final String reason;
  const ExclusionSupport.supported(ObjectExclusion b, this.reason) : backend = b;
  const ExclusionSupport.unsupported(this.reason) : backend = null;
  bool get supported => backend != null;
}

/// Interface comum: cada tipo de firmware implementa à sua maneira.
abstract class ObjectExclusion {
  Future<ExclusionState> fetch();
  Future<void> exclude(String name);

  /// Deteta o suporte para uma impressora. Ordem:
  /// 1. Klipper/Moonraker na porta 7125 (Creality, Sovol, Voron, CC1 com COSMOS…)
  /// 2. Firmware Elegoo (SDCP): não suporta; o módulo existe no código-fonte
  ///    publicado mas não está ativo nem tem comando de rede.
  static Future<ExclusionSupport> detect(String ip, {String? firmware}) async {
    final m = MoonrakerExclusion(ip);
    if (await m.available()) {
      return ExclusionSupport.supported(m, 'Klipper (Moonraker)');
    }
    final fw = (firmware == null || firmware.isEmpty) ? '' : ' $firmware';
    return ExclusionSupport.unsupported(
        'Não compatível: o firmware Elegoo$fw não permite cancelar objetos individualmente.');
  }
}

/// Cancelamento de objetos via API Moonraker (Klipper).
class MoonrakerExclusion implements ObjectExclusion {
  final String ip;
  final int port;
  MoonrakerExclusion(this.ip, {this.port = 7125});

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri(scheme: 'http', host: ip, port: port, path: path, queryParameters: q);

  /// Moonraker a responder e com o módulo [exclude_object] carregado.
  Future<bool> available() async {
    try {
      final r = await http
          .get(_u('/printer/objects/list'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return false;
      final objs = (jsonDecode(r.body)['result']?['objects'] as List?) ?? const [];
      return objs.contains('exclude_object');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ExclusionState> fetch() async {
    final r = await http
        .get(Uri.parse('http://$ip:$port/printer/objects/query?exclude_object&toolhead'))
        .timeout(const Duration(seconds: 4));
    if (r.statusCode != 200) throw Exception('Moonraker respondeu ${r.statusCode}');
    final st = (jsonDecode(r.body)['result']?['status'] as Map?) ?? const {};
    final ex = (st['exclude_object'] as Map?) ?? const {};
    final th = (st['toolhead'] as Map?) ?? const {};
    final max = th['axis_maximum'];

    Offset? pt(dynamic p) =>
        (p is List && p.length >= 2 && p[0] is num && p[1] is num)
            ? Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())
            : null;

    final objects = <PrintObject>[];
    for (final o in (ex['objects'] as List?) ?? const []) {
      if (o is! Map) continue;
      final poly = <Offset>[];
      for (final p in (o['polygon'] as List?) ?? const []) {
        final v = pt(p);
        if (v != null) poly.add(v);
      }
      objects.add(PrintObject('${o['name']}', center: pt(o['center']), polygon: poly));
    }
    return ExclusionState(
      objects: objects,
      excluded: {for (final e in (ex['excluded_objects'] as List?) ?? const []) '$e'},
      current: ex['current_object'] == null ? null : '${ex['current_object']}',
      bedWidth: (max is List && max.isNotEmpty && max[0] is num) ? (max[0] as num).toDouble() : 256,
      bedDepth: (max is List && max.length > 1 && max[1] is num) ? (max[1] as num).toDouble() : 256,
    );
  }

  @override
  Future<void> exclude(String name) async {
    final r = await http
        .post(_u('/printer/gcode/script', {'script': 'EXCLUDE_OBJECT NAME=$name'}))
        .timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) {
      throw Exception('A impressora recusou cancelar "$name" (${r.statusCode}): ${r.body}');
    }
  }
}

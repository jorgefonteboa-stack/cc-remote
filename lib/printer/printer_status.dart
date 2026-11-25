/// Modelo do estado reportado pela CC1 no tópico `sdcp/status/{MainboardID}`.
/// O parsing é defensivo: os nomes de campos do SDCP têm gralhas e variam
/// entre versões de firmware.
class PrinterStatus {
  final List<int> currentStatus;
  final double nozzle, nozzleTarget, bed, bedTarget, chamber;
  final bool? light;
  final PrintInfo print;
  final Map<String, dynamic> raw;

  const PrinterStatus({
    this.currentStatus = const [],
    this.nozzle = 0,
    this.nozzleTarget = 0,
    this.bed = 0,
    this.bedTarget = 0,
    this.chamber = 0,
    this.light,
    this.print = const PrintInfo(),
    this.raw = const {},
  });

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  factory PrinterStatus.fromJson(Map<String, dynamic> j) {
    final ls = j['LightStatus'];
    bool? light;
    if (ls is Map) {
      final s = ls['SecondLight'];
      light = s is bool ? s : (s is num ? s != 0 : null);
    }
    final cs = j['CurrentStatus'];
    return PrinterStatus(
      currentStatus: cs is List ? cs.whereType<num>().map((e) => e.toInt()).toList() : const [],
      nozzle: _d(j['TempOfNozzle']),
      nozzleTarget: _d(j['TempTargetNozzle']),
      bed: _d(j['TempOfHotbed']),
      bedTarget: _d(j['TempTargetHotbed']),
      chamber: _d(j['TempOfBox']),
      light: light,
      print: j['PrintInfo'] is Map
          ? PrintInfo.fromJson(Map<String, dynamic>.from(j['PrintInfo']))
          : const PrintInfo(),
      raw: j,
    );
  }

  bool get isPrinting => print.status == 13 || currentStatus.contains(1);
  bool get isPaused => print.status == 6 || print.status == 5;
}

class PrintInfo {
  final int status, currentLayer, totalLayer;
  final int currentTicks, totalTicks;
  final double progress;
  final String filename;

  const PrintInfo({
    this.status = 0,
    this.currentLayer = 0,
    this.totalLayer = 0,
    this.currentTicks = 0,
    this.totalTicks = 0,
    this.progress = 0,
    this.filename = '',
  });

  static int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory PrintInfo.fromJson(Map<String, dynamic> j) => PrintInfo(
        status: _i(j['Status']),
        currentLayer: _i(j['CurrentLayer']),
        totalLayer: _i(j['TotalLayer']),
        currentTicks: _i(j['CurrentTicks']),
        totalTicks: _i(j['TotalTicks']),
        progress: (j['Progress'] is num) ? (j['Progress'] as num).toDouble() : 0,
        filename: '${j['Filename'] ?? ''}',
      );

  /// Códigos observados pela comunidade; confirma no teu firmware.
  String get label => switch (status) {
        0 => 'Inativa',
        1 => 'A fazer homing',
        5 => 'A pausar',
        6 => 'Em pausa',
        7 => 'A parar',
        8 => 'Parada',
        9 => 'Concluída',
        10 => 'A verificar ficheiro',
        13 => 'A imprimir',
        16 => 'A aquecer',
        20 => 'A nivelar',
        _ => 'Estado $status',
      };

  /// Tempo restante (assume que os "ticks" estão em segundos — confirmar).
  Duration get remaining {
    final s = totalTicks - currentTicks;
    return Duration(seconds: s > 0 ? s : 0);
  }
}

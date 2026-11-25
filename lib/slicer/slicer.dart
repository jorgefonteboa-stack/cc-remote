import 'dart:typed_data';

/// Parâmetros principais de slicing expostos na UI.
class SliceSettings {
  double layerHeight;
  int walls;
  double infill; // 0..1
  bool supports;
  int nozzleTemp;
  int bedTemp;
  String material;

  /// Slot do CANVAS a usar (0–3) ou null para usar o que estiver ativo.
  int? canvasSlot;
  String? colorHex;

  SliceSettings({
    this.layerHeight = 0.2,
    this.walls = 2,
    this.infill = 0.15,
    this.supports = false,
    this.nozzleTemp = 220,
    this.bedTemp = 60,
    this.material = 'PLA',
    this.canvasSlot,
    this.colorHex,
  });

  static final presets = <String, SliceSettings Function()>{
    'PLA': () => SliceSettings(),
    'PETG': () => SliceSettings(material: 'PETG', nozzleTemp: 245, bedTemp: 75),
    'ABS': () => SliceSettings(material: 'ABS', nozzleTemp: 255, bedTemp: 100),
    'ASA': () => SliceSettings(material: 'ASA', nozzleTemp: 260, bedTemp: 100),
    'TPU': () => SliceSettings(material: 'TPU', nozzleTemp: 225, bedTemp: 45),
  };

  /// Cria parâmetros a partir do filamento que está num slot do CANVAS:
  /// material pelo tipo reportado, temperatura do bico pelo intervalo do slot,
  /// mantendo camada/paredes/enchimento/suportes atuais.
  SliceSettings withFilament({
    required String type,
    required int slot,
    String? colorHex,
    int minTemp = 0,
    int maxTemp = 0,
  }) {
    final t = type.toUpperCase();
    final key = presets.keys.firstWhere((k) => t.startsWith(k),
        orElse: () => t.contains('PET') ? 'PETG' : 'PLA');
    final base = presets[key]!();
    var nozzle = base.nozzleTemp;
    if (minTemp > 0 && maxTemp >= minTemp) {
      nozzle = nozzle.clamp(minTemp, maxTemp);
    }
    return SliceSettings(
      layerHeight: layerHeight,
      walls: walls,
      infill: infill,
      supports: supports,
      nozzleTemp: nozzle,
      bedTemp: base.bedTemp,
      material: type.isEmpty ? key : type,
      canvasSlot: slot,
      colorHex: colorHex,
    );
  }

  Map<String, dynamic> toJson() => {
        'layerHeight': layerHeight,
        'walls': walls,
        'infill': infill,
        'supports': supports,
        'nozzleTemp': nozzleTemp,
        'bedTemp': bedTemp,
        'canvasSlot': canvasSlot,
      };
}

class SliceResult {
  final String gcode;
  final Duration? estimatedTime;
  final double? filamentMm;
  SliceResult(this.gcode, {this.estimatedTime, this.filamentMm});
}

/// Interface do motor de slicing. A implementação atual usa o Kiri:Moto
/// (JS) num WebView invisível; mais tarde pode trocar-se por um motor
/// nativo (ex.: libslic3r/CuraEngine via FFI) sem mexer na UI.
abstract class Slicer {
  Future<void> init();
  Future<SliceResult> slice(Uint8List stl, SliceSettings settings,
      {void Function(double progress, String stage)? onProgress});
  void dispose();
}

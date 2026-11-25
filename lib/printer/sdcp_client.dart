import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'canvas.dart';
import 'printer_status.dart';

/// Impressora encontrada via UDP (porta 3000, mensagem "M99999").
class DiscoveredPrinter {
  final String ip, mainboardId, name, firmware;
  const DiscoveredPrinter(this.ip, this.mainboardId, this.name, this.firmware);

  factory DiscoveredPrinter.fromJson(Map<String, dynamic> j, String fallbackIp) {
    final d = Map<String, dynamic>.from(j['Data'] ?? j);
    return DiscoveredPrinter(
      '${d['MainboardIP'] ?? fallbackIp}',
      '${d['MainboardID'] ?? ''}',
      '${d['Name'] ?? d['MachineName'] ?? 'Centauri Carbon'}',
      '${d['FirmwareVersion'] ?? ''}',
    );
  }
}

class SdcpDiscovery {
  static const _port = 3000;

  /// Broadcast na rede local. No iOS exige o entitlement de multicast
  /// (ver README); se falhar, usa [probe] com o IP introduzido à mão.
  static Future<List<DiscoveredPrinter>> scan(
      {Duration timeout = const Duration(seconds: 3)}) {
    return _query(InternetAddress('255.255.255.255'), timeout, broadcast: true);
  }

  /// Pergunta diretamente a um IP (unicast) — funciona sem entitlement.
  static Future<DiscoveredPrinter?> probe(String ip,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final r = await _query(InternetAddress(ip), timeout, broadcast: false);
    return r.isEmpty ? null : r.first;
  }

  static Future<List<DiscoveredPrinter>> _query(
      InternetAddress target, Duration timeout,
      {required bool broadcast}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = broadcast;
    final found = <String, DiscoveredPrinter>{};
    final sub = socket.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      try {
        final j = jsonDecode(utf8.decode(dg.data));
        final p = DiscoveredPrinter.fromJson(Map<String, dynamic>.from(j), dg.address.address);
        found[p.ip] = p;
      } catch (_) {/* resposta que não é de uma CC1 */}
    });
    final msg = utf8.encode('M99999');
    for (var i = 0; i < 3; i++) {
      socket.send(msg, target, _port);
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await Future.delayed(timeout);
    await sub.cancel();
    socket.close();
    return found.values.toList();
  }
}

class SdcpException implements Exception {
  final String message;
  SdcpException(this.message);
  @override
  String toString() => message;
}

/// Cliente SDCP v3 sobre WebSocket (ws://IP:3030/websocket).
class SdcpClient {
  final String ip;
  final String mainboardId;
  SdcpClient(this.ip, this.mainboardId);

  WebSocketChannel? _ch;
  Timer? _ping;
  final _uuid = const Uuid();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _statusCtrl = StreamController<PrinterStatus>.broadcast();
  final _attrCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final _canvasCtrl = StreamController<CanvasState>.broadcast();

  PrinterStatus status = const PrinterStatus();
  CanvasState? canvas;
  Stream<CanvasState> get canvasStream => _canvasCtrl.stream;
  Map<String, dynamic> attributes = {};

  Stream<PrinterStatus> get statusStream => _statusCtrl.stream;
  Stream<Map<String, dynamic>> get attributesStream => _attrCtrl.stream;
  Stream<bool> get connectionStream => _connCtrl.stream;
  bool get connected => _ch != null;

  Future<void> connect() async {
    final ch = WebSocketChannel.connect(Uri.parse('ws://$ip:3030/websocket'));
    await ch.ready.timeout(const Duration(seconds: 5));
    _ch = ch;
    _connCtrl.add(true);
    ch.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
    // A CC1 fecha ligações inativas; um "ping" em texto mantém-na aberta.
    _ping = Timer.periodic(const Duration(seconds: 10), (_) => ch.sink.add('ping'));
    unawaited(send(1).catchError((_) => <String, dynamic>{})); // atributos
    unawaited(send(0).catchError((_) => <String, dynamic>{})); // estado
  }

  void _onClosed() {
    _ping?.cancel();
    _ch = null;
    _connCtrl.add(false);
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(SdcpException('Ligação fechada'));
    }
    _pending.clear();
  }

  Future<void> disconnect() async {
    _ping?.cancel();
    await _ch?.sink.close();
    _ch = null;
  }

  void _onMessage(dynamic data) {
    if (data is! String || data == 'pong') return;
    Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(data));
    } catch (_) {
      return;
    }
    final topic = '${j['Topic'] ?? ''}';
    // Dados do CANVAS (Cmd 324): a impressora envia primeiro um ack e depois
    // os dados; aceitamos canvas_list venha em que mensagem vier.
    if (data.contains('canvas_list')) {
      final c = CanvasState.find(j);
      if (c != null) {
        canvas = c;
        _canvasCtrl.add(c);
      }
    }
    if (topic.startsWith('sdcp/status') && j['Status'] is Map) {
      status = PrinterStatus.fromJson(Map<String, dynamic>.from(j['Status']));
      _statusCtrl.add(status);
    } else if (topic.startsWith('sdcp/attributes') && j['Attributes'] is Map) {
      attributes = Map<String, dynamic>.from(j['Attributes']);
      _attrCtrl.add(attributes);
    } else if (topic.startsWith('sdcp/response') && j['Data'] is Map) {
      final d = Map<String, dynamic>.from(j['Data']);
      final c = _pending.remove('${d['RequestID']}');
      final payload = d['Data'] is Map ? Map<String, dynamic>.from(d['Data']) : <String, dynamic>{};
      c?.complete(payload);
    }
  }

  /// Envia um comando SDCP e espera pela resposta com o mesmo RequestID.
  Future<Map<String, dynamic>> send(int cmd, [Map<String, dynamic> data = const {}]) {
    final ch = _ch;
    if (ch == null) return Future.error(SdcpException('Sem ligação à impressora'));
    final reqId = _uuid.v4().replaceAll('-', '');
    final msg = {
      'Id': _uuid.v4().replaceAll('-', ''),
      'Data': {
        'Cmd': cmd,
        'Data': data,
        'RequestID': reqId,
        'MainboardID': mainboardId,
        'TimeStamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'From': 1,
      },
      'Topic': 'sdcp/request/$mainboardId',
    };
    final c = Completer<Map<String, dynamic>>();
    _pending[reqId] = c;
    ch.sink.add(jsonEncode(msg));
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _pending.remove(reqId);
      throw SdcpException('A impressora não respondeu ao comando $cmd');
    });
  }

  // ---- Comandos de alto nível -------------------------------------------

  Future<void> startPrint(String filename) =>
      // Formato do exemplo da documentação OpenCentauri. Se o firmware
      // exigir o caminho completo, experimentar '/local/$filename'.
      send(128, {'Filename': filename, 'StartLayer': 0});
  Future<void> pause() => send(129);
  Future<void> stop() => send(130);
  Future<void> resume() => send(131);

  /// Luz da câmara — Cmd 403 confirmado numa CC1 com firmware V1.4.49.
  Future<void> setLight(bool on) => send(403, {
        'LightStatus': {'SecondLight': on, 'RgbLight': [0, 0, 0]}
      });

  /// Liga o stream MJPEG e devolve o URL (normalmente http://IP:3031/video).
  Future<String> enableCamera([bool enable = true]) async {
    final r = await send(386, {'Enable': enable ? 1 : 0});
    final url = '${r['VideoUrl'] ?? ''}';
    if (url.isEmpty) return 'http://$ip:3031/video';
    return url.startsWith('http') ? url : 'http://$url';
  }

  /// Lê o que está carregado em cada slot do CANVAS (tipo, cor, temperaturas).
  /// Confirmado em V1.4.49: os dados vêm logo na resposta ao Cmd 324.
  Future<CanvasState?> readCanvas() async {
    final next = canvasStream.first
        .then<CanvasState?>((c) => c)
        .timeout(const Duration(seconds: 6), onTimeout: () => null)
        .catchError((_) => null);
    final ack = await send(324);
    final inAck = CanvasState.find(ack);
    if (inAck != null) {
      canvas = inAck;
      return inAck;
    }
    return next;
  }

  Future<List<String>> listFiles([String path = '/local']) async {
    final r = await send(258, {'Url': path});
    final list = r['FileList'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .where((f) => f['type'] == 1 || '${f['name']}'.endsWith('.gcode'))
        .map((f) => '${f['name']}'.split('/').last)
        .toList();
  }

  /// Upload por HTTP multipart em blocos de 1 MB com verificação MD5.
  Future<void> upload(String filename, Uint8List bytes,
      {void Function(double progress)? onProgress}) async {
    final md5hex = md5.convert(bytes).toString();
    final uuid = _uuid.v4().replaceAll('-', '');
    const chunk = 1024 * 1024;
    final uri = Uri.parse('http://$ip:3030/uploadFile/upload');
    for (var off = 0; off < bytes.length; off += chunk) {
      final end = min(off + chunk, bytes.length);
      final req = http.MultipartRequest('POST', uri)
        ..fields.addAll({
          'S-File-MD5': md5hex,
          'Check': '1',
          'Offset': '$off',
          'Uuid': uuid,
          'TotalSize': '${bytes.length}',
        })
        ..files.add(http.MultipartFile.fromBytes('File', bytes.sublist(off, end),
            filename: filename));
      final res = await http.Response.fromStream(await req.send());
      Map<String, dynamic> j = {};
      try {
        j = Map<String, dynamic>.from(jsonDecode(res.body));
      } catch (_) {}
      if (res.statusCode != 200 || j['success'] != true) {
        throw SdcpException('Falha no upload (${res.statusCode}): ${res.body}');
      }
      onProgress?.call(end / bytes.length);
    }
  }

  void dispose() {
    disconnect();
    _statusCtrl.close();
    _attrCtrl.close();
    _connCtrl.close();
    _canvasCtrl.close();
  }
}

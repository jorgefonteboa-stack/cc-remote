import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../printer/sdcp_client.dart';
import 'printer_screen.dart';

/// Ecrã inicial: procura impressoras na rede ou aceita um IP manual.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DiscoveredPrinter> _found = [];
  bool _scanning = false;
  String? _lastIp;
  final _ipCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastIp = p.getString('last_ip');
      if (_lastIp != null) _ipCtrl.text = _lastIp!;
    });
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final r = await SdcpDiscovery.scan();
      if (mounted) setState(() => _found = r);
    } catch (e) {
      _toast('Pesquisa falhou: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _manual() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() => _scanning = true);
    final p = await SdcpDiscovery.probe(ip);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (p == null) {
      _toast('Nenhuma Centauri Carbon respondeu em $ip');
      return;
    }
    _open(p);
  }

  Future<void> _open(DiscoveredPrinter p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', p.ip);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrinterScreen(printer: p)));
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('As minhas impressoras')),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_scanning) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            if (_found.isEmpty && !_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nenhuma impressora encontrada automaticamente.\n'
                  'Confirma que o telemóvel está na mesma rede Wi-Fi, ou introduz o IP.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final p in _found)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.print_outlined, size: 36),
                  title: Text(p.name),
                  subtitle: Text('${p.ip} · firmware ${p.firmware}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(p),
                ),
              ),
            const SizedBox(height: 24),
            Text('Ligar por IP', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ipCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: '192.168.1.50', border: OutlineInputBorder()),
                  onSubmitted: (_) => _manual(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _scanning ? null : _manual, child: const Text('Ligar')),
            ]),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _scan,
        icon: const Icon(Icons.wifi_find),
        label: const Text('Procurar'),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../printer/object_exclusion.dart';

/// Cartão "Objetos na mesa": mapa da mesa com cada objeto e botão para
/// cancelar só esse. Se a impressora não suportar, mostra "não compatível".
class ObjectsCard extends StatefulWidget {
  final ExclusionSupport? support; // null = ainda a verificar
  final bool printing;
  const ObjectsCard({super.key, required this.support, required this.printing});

  @override
  State<ObjectsCard> createState() => _ObjectsCardState();
}

class _ObjectsCardState extends State<ObjectsCard> {
  ExclusionState? _state;
  String? _error;
  Timer? _poll;
  String? _selected;
  final _busy = <String>{};

  ObjectExclusion? get _backend => widget.support?.backend;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ObjectsCard old) {
    super.didUpdateWidget(old);
    if (old.printing != widget.printing || old.support != widget.support) _sync();
  }

  void _sync() {
    _poll?.cancel();
    if (_backend != null && widget.printing) {
      _refresh();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      final s = await _backend!.fetch();
      if (mounted) {
        setState(() {
          _state = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _cancel(PrintObject o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancelar "${o.displayName}"?'),
        content: const Text(
            'A impressora deixa de imprimir só este objeto. Os outros continuam. Não dá para desfazer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Cancelar objeto')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(o.name));
    try {
      await _backend!.exclude(o.name);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('"${o.displayName}" cancelado')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(o.name));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sup = widget.support;

    Widget header(String sub, {IconData icon = Icons.grid_view, Color? color}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: const Text('Cancelar objetos'),
          subtitle: Text(sub),
        );

    if (sup == null) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: header('A verificar se a impressora suporta…')));
    }
    if (!sup.supported) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: header(sup.reason, icon: Icons.block, color: theme.colorScheme.outline),
        ),
      );
    }
    if (!widget.printing) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: header('Compatível (${sup.reason}). Disponível durante a impressão.',
                  icon: Icons.check_circle_outline, color: Colors.green)));
    }

    final s = _state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          header(s == null
              ? 'A carregar objetos…'
              : s.objects.isEmpty
                  ? 'Esta impressão não tem objetos identificados. No slicer, ativa '
                      '"Exclude objects" (Outros) e volta a fatiar.'
                  : '${s.remaining} de ${s.objects.length} objetos a imprimir'),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (s != null && s.objects.isNotEmpty) ...[
            AspectRatio(
              aspectRatio: s.bedWidth / s.bedDepth,
              child: LayoutBuilder(builder: (ctx, box) {
                return GestureDetector(
                  onTapUp: (d) {
                    final hit = _hitTest(s, d.localPosition, box.biggest);
                    if (hit != null) setState(() => _selected = hit.name);
                  },
                  child: CustomPaint(
                    painter: _BedPainter(s, _selected, theme.colorScheme),
                    size: box.biggest,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            for (final o in s.objects)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: _selected == o.name,
                onTap: () => setState(() => _selected = o.name),
                leading: Icon(
                  s.isExcluded(o)
                      ? Icons.cancel
                      : s.current == o.name
                          ? Icons.play_circle_fill
                          : Icons.circle_outlined,
                  color: s.isExcluded(o)
                      ? theme.colorScheme.outline
                      : s.current == o.name
                          ? Colors.green
                          : null,
                ),
                title: Text(o.displayName,
                    style: s.isExcluded(o)
                        ? const TextStyle(decoration: TextDecoration.lineThrough)
                        : null),
                subtitle: s.isExcluded(o)
                    ? const Text('Cancelado')
                    : s.current == o.name
                        ? const Text('A imprimir agora')
                        : null,
                trailing: s.isExcluded(o)
                    ? null
                    : _busy.contains(o.name)
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: s.remaining <= 1 ? null : () => _cancel(o),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancelar'),
                          ),
              ),
            if (s.remaining <= 1)
              Text('Para cancelar o último objeto, usa o Stop.', style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  PrintObject? _hitTest(ExclusionState s, Offset p, Size size) {
    PrintObject? best;
    var bestD = double.infinity;
    for (final o in s.objects) {
      final c = o.center ?? (o.polygon.isNotEmpty ? o.polygon.first : null);
      if (c == null) continue;
      final sp = _BedPainter.toScreen(c, s, size);
      final d = (sp - p).distance;
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    return bestD < 60 ? best : null;
  }
}

class _BedPainter extends CustomPainter {
  final ExclusionState s;
  final String? selected;
  final ColorScheme cs;
  _BedPainter(this.s, this.selected, this.cs);

  /// Coordenadas da mesa (mm, origem em baixo à esquerda) → ecrã.
  static Offset toScreen(Offset mm, ExclusionState s, Size size) =>
      Offset(mm.dx / s.bedWidth * size.width, size.height - mm.dy / s.bedDepth * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final bed = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(bed, Paint()..color = cs.surfaceContainerHighest);
    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8, y = size.height * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    for (final o in s.objects) {
      final excluded = s.isExcluded(o);
      final current = s.current == o.name;
      final sel = selected == o.name;
      final color = excluded
          ? cs.outline.withValues(alpha: 0.35)
          : current
              ? Colors.green
              : cs.primary;
      final fill = Paint()..color = color.withValues(alpha: excluded ? 0.25 : 0.45);
      final stroke = Paint()
        ..color = sel ? Colors.orange : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = sel ? 3 : 1.5;

      if (o.polygon.length >= 3) {
        final path = Path()..moveTo(toScreen(o.polygon.first, s, size).dx, toScreen(o.polygon.first, s, size).dy);
        for (final p in o.polygon.skip(1)) {
          final q = toScreen(p, s, size);
          path.lineTo(q.dx, q.dy);
        }
        path.close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      } else if (o.center != null) {
        final c = toScreen(o.center!, s, size);
        canvas.drawCircle(c, 12, fill);
        canvas.drawCircle(c, 12, stroke);
      }
      if (excluded && o.center != null) {
        final c = toScreen(o.center!, s, size);
        final x = Paint()
          ..color = cs.error
          ..strokeWidth = 2.5;
        canvas.drawLine(c + const Offset(-8, -8), c + const Offset(8, 8), x);
        canvas.drawLine(c + const Offset(-8, 8), c + const Offset(8, -8), x);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BedPainter old) => old.s != s || old.selected != selected;
}

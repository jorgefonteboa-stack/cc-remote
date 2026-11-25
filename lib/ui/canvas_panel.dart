import 'package:flutter/material.dart';

import '../printer/canvas.dart';

/// Mostra os 4 slots do CANVAS (cor, material, temperaturas).
/// Com [onSelect], os slots ficam selecionáveis (ecrã de slicing).
class CanvasPanel extends StatelessWidget {
  final CanvasState? canvas;
  final bool loading;
  final int? selectedSlot;
  final ValueChanged<CanvasTray>? onSelect;
  final VoidCallback? onRefresh;

  const CanvasPanel({
    super.key,
    required this.canvas,
    this.loading = false,
    this.selectedSlot,
    this.onSelect,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = canvas;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.palette_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Filamentos no CANVAS', style: theme.textTheme.titleSmall)),
            if (c != null && c.autoRefill)
              const Tooltip(
                  message: 'Recarga automática ativa',
                  child: Icon(Icons.autorenew, size: 18)),
            IconButton(
              tooltip: 'Ler da impressora',
              onPressed: loading ? null : onRefresh,
              icon: loading
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
            ),
          ]),
          if (c == null && !loading)
            const Padding(
              padding: EdgeInsets.only(top: 4, right: 8),
              child: Text('Toca em ⟳ para ler os filamentos carregados na máquina.'),
            )
          else if (c != null && !c.hasCanvas)
            const Padding(
              padding: EdgeInsets.only(top: 4, right: 8),
              child: Text('A impressora não reportou nenhum CANVAS ligado. '
                  'Confirma que o firmware é 1.4.44 ou mais recente.'),
            )
          else if (c != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Row(children: [
                for (final t in c.trays)
                  Expanded(
                    child: _Slot(
                      tray: t,
                      active: c.activeTray == t,
                      selected: selectedSlot == t.slot,
                      onTap: (onSelect == null || t.isEmpty) ? null : () => onSelect!(t),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final CanvasTray tray;
  final bool active, selected;
  final VoidCallback? onTap;
  const _Slot({required this.tray, required this.active, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = tray.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(children: [
            Text(tray.label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            Stack(alignment: Alignment.center, children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: empty ? scheme.surfaceContainerHighest : tray.color,
                child: empty ? Icon(Icons.remove, color: scheme.outline, size: 18) : null,
              ),
              if (active)
                const Positioned(
                    right: 0, bottom: 0,
                    child: Icon(Icons.play_circle_fill, size: 14, color: Colors.green)),
            ]),
            const SizedBox(height: 6),
            Text(empty ? 'Vazio' : tray.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (!empty && tray.name.isNotEmpty && tray.name != tray.type)
              Text(tray.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            if (!empty && tray.minTemp > 0)
              Text('${tray.minTemp}–${tray.maxTemp}°',
                  style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

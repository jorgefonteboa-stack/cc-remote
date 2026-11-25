import 'package:flutter/material.dart';

import '../ai/print_guard.dart';

/// Cartão "Vigilância IA": ligar/desligar, sensibilidade, risco atual e,
/// quando dispara, a imagem que levou à pausa com as ações possíveis.
class GuardCard extends StatelessWidget {
  final PrintGuard guard;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;

  const GuardCard({super.key, required this.guard, required this.onResume, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: guard,
      builder: (context, _) {
        final theme = Theme.of(context);
        final g = guard;
        if (g.triggered) return _alert(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_awesome),
                title: const Text('Vigilância IA'),
                subtitle: Text(_subtitle()),
                value: g.enabled,
                onChanged: g.modelReady ? g.setEnabled : null,
              ),
              if (!g.modelReady)
                Text('Modelo não instalado. Vê assets/ai/LEIA-ME.md para o treinar e adicionar.',
                    style: theme.textTheme.bodySmall),
              if (g.modelReady && g.enabled) ...[
                SegmentedButton<GuardSensitivity>(
                  segments: const [
                    ButtonSegment(value: GuardSensitivity.low, label: Text('Baixa')),
                    ButtonSegment(value: GuardSensitivity.medium, label: Text('Média')),
                    ButtonSegment(value: GuardSensitivity.high, label: Text('Alta')),
                  ],
                  selected: {g.sensitivity},
                  onSelectionChanged: (s) => g.setSensitivity(s.first),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Risco'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: g.risk.clamp(0, 1),
                        color: g.risk > 0.5
                            ? Colors.red
                            : g.risk > 0.25
                                ? Colors.orange
                                : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${(g.risk * 100).round()}%'),
                ]),
                const SizedBox(height: 6),
                Text('Mantém a app aberta: o ecrã fica ligado enquanto vigia.',
                    style: theme.textTheme.bodySmall),
              ],
            ]),
          ),
        );
      },
    );
  }

  String _subtitle() {
    final g = guard;
    if (!g.modelReady) return 'Indisponível';
    if (!g.enabled) return 'Desligada';
    final last = g.lastCheck;
    if (last == null) return 'À espera que a impressão comece';
    final s = DateTime.now().difference(last).inSeconds;
    return 'A vigiar · última verificação há ${s}s'
        '${g.strikes > 0 ? ' · suspeitas: ${g.strikes}' : ''}';
  }

  Widget _alert(BuildContext context) {
    final g = guard;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded),
            const SizedBox(width: 8),
            Expanded(
                child: Text(g.alertMessage ?? 'Possível falha detetada',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (g.alertFrame != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(g.alertFrame!, fit: BoxFit.cover),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                await onResume();
                g.acknowledge();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Falso alarme, retomar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await onStop();
                g.acknowledge();
              },
              icon: const Icon(Icons.stop),
              label: const Text('Parar impressão'),
            ),
            TextButton(onPressed: g.acknowledge, child: const Text('Fechar')),
          ]),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_live_service.dart';

enum StateSlotAction {
  save('Salvar estado'),
  load('Carregar estado');

  const StateSlotAction(this.label);
  final String label;
}

class StateSlotsDialog extends StatefulWidget {
  const StateSlotsDialog({
    super.key,
    required this.service,
    required this.gameTitle,
    required this.action,
  });
  final StateSlotAction action;
  final String gameTitle;
  final SameBoyLiveService service;
  @override
  State<StateSlotsDialog> createState() => _StateSlotsDialogState();
}

class _StateSlotsDialogState extends State<StateSlotsDialog> {
  List<String?> slots = [];
  String? message;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await widget.service.stateCommand(listStateSlots);
      if (result.length != 5) throw StateError('Lista de slots inválida.');
      if (mounted) setState(() => slots = result);
    } catch (error) {
      if (mounted) {
        setState(() => message = 'Falha ao consultar os slots. $error');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(int slot) async {
    if (busy) return;
    final load = widget.action == StateSlotAction.load;
    final occupied = slots[slot - 1] != null;
    setState(() {
      busy = true;
      message = null;
    });
    if (load || occupied) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(load ? 'Carregar slot $slot?' : 'Substituir slot $slot?'),
          content: Text(
            load
                ? 'O progresso atual do cartucho será preservado. Até reabrir o jogo, use os slots para guardar o progresso desta sessão.'
                : 'O estado anterior deste slot será substituído.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(load ? 'Carregar' : 'Substituir'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => busy = false);
        return;
      }
    }
    try {
      await widget.service.stateCommand(
        (load
                ? loadStateBase
                : occupied
                ? replaceStateBase
                : createStateBase) +
            slot,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        load
            ? 'Estado carregado do slot $slot.'
            : 'Estado salvo no slot $slot.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => message =
            'Falha ao ${load ? "carregar" : "salvar"} o slot $slot. $error',
      );
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.action.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.gameTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Semantics(liveRegion: true, child: Text(message!)),
            for (var i = 0; i < slots.length; i++)
              Builder(
                builder: (context) {
                  final entry = slots[i];
                  final date = entry == null
                      ? null
                      : DateTime.tryParse(entry)?.toLocal();
                  final labels = MaterialLocalizations.of(context);
                  final available =
                      date != null ||
                      (entry == null && widget.action == StateSlotAction.save);
                  return ListTile(
                    enabled: !busy && available,
                    onTap: !busy && available ? () => act(i + 1) : null,
                    title: Text('Slot ${i + 1}'),
                    subtitle: Text(
                      date == null
                          ? entry ?? 'Vazio'
                          : 'Ocupado · ${labels.formatCompactDate(date)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}',
                    ),
                    trailing: Icon(
                      widget.action == StateSlotAction.save
                          ? Icons.save_outlined
                          : Icons.restore,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Voltar ao jogo'),
        ),
      ],
    ),
  );
}

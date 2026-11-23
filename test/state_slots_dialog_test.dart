import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:beastemu/widgets/state_slots_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Slots extends SameBoyLiveService {
  bool failWrite = false;
  final requests = <int>[];
  @override
  Future<List<String?>> stateCommand(int byte) async {
    requests.add(byte);
    if (failWrite && byte != listStateSlots) {
      throw StateError('Disco indisponível');
    }
    return byte == listStateSlots
        ? ['2026-01-01T10:00:00Z', null, null, 'Incompatível ou ilegível', null]
        : [];
  }
}

Future<void> _open(
  WidgetTester tester,
  _Slots slots,
  StateSlotAction action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => StateSlotsDialog(
                service: slots,
                action: action,
                gameTitle: 'Teste',
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'salvar mostra cinco slots, data e hora e confirma a substituição',
    (tester) async {
      final slots = _Slots();
      await _open(tester, slots, StateSlotAction.save);
      expect(find.byType(ListTile), findsNWidgets(5));
      expect(find.text('Vazio'), findsNWidgets(3));
      expect(find.textContaining(RegExp(r' · \d{2}:\d{2}')), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Slot 4'))
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Slot 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(slots.requests, [listStateSlots]);
      await tester.tap(find.text('Slot 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Substituir'));
      await tester.pumpAndSettle();
      expect(slots.requests, [listStateSlots, replaceStateBase + 1]);
    },
  );

  testWidgets(
    'carregar bloqueia slots vazios e ilegíveis e informa erro do auxiliar',
    (tester) async {
      final slots = _Slots()..failWrite = true;
      await _open(tester, slots, StateSlotAction.load);
      for (final number in [2, 3, 4, 5]) {
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, 'Slot $number'))
              .onTap,
          isNull,
        );
      }
      await tester.tap(find.text('Slot 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.textContaining('progresso atual do cartucho'),
        findsOneWidget,
      );
      await tester.tap(find.text('Carregar'));
      await tester.pumpAndSettle();
      expect(slots.requests, [
        listStateSlots,
        loadStateBase + 1,
        listStateSlots,
      ]);
      expect(find.textContaining('Falha ao carregar o slot 1'), findsOneWidget);
      expect(find.textContaining('Disco indisponível'), findsOneWidget);
    },
  );
}

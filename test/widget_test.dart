import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/widgets/transaction_form.dart';

void main() {
  Future<TransactionDraft?> openForm(WidgetTester tester, {double? amount}) async {
    TransactionDraft? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showTransactionForm(context, title: 'Add', amount: amount),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('form blocks empty amount and blank merchant', (tester) async {
    await openForm(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Merchant / description'), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount above 0'), findsOneWidget);
    expect(find.text('Enter a description'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget); // dialog still open
  });

  testWidgets('form accepts decimals and returns a trimmed draft', (tester) async {
    TransactionDraft? draft;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => draft = await showTransactionForm(context, title: 'Add'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '100.55');
    await tester.enterText(find.widgetWithText(TextFormField, 'Merchant / description'), '  Chai  ');
    await tester.tap(find.text('Income'));
    await tester.tap(find.text('Transfer between my accounts'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(draft, isNotNull);
    expect(draft!.amount, 100.55);
    expect(draft!.merchant, 'Chai');
    expect(draft!.type, 'CREDIT');
    expect(draft!.transfer, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/data/finance_store.dart';
import 'package:frontend/main.dart';
import 'fake_finance_api.dart';

void main() {
  testWidgets('phone OTP sign-in opens the account overview', (tester) async {
    final api = FakeFinanceApi();
    final store = FinanceStore.forTesting(api: api, vault: MemorySecureVault());
    await tester.pumpWidget(MyApp(store: store));

    await tester.enterText(find.byKey(const ValueKey('phone-field')), '+14155550123');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('otp-field')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('otp-field')), '123456');
    await tester.tap(find.text('Verify and sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Overview').first, findsOneWidget);
    expect(store.isSignedIn, isTrue);
  });

  testWidgets('user can create a transaction and see the updated balance', (tester) async {
    final api = FakeFinanceApi(transactions: _sampleTransactions());
    final store = await _signedInStore(api);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add expense'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('transaction-description')), 'Coffee');
    await tester.enterText(find.byKey(const ValueKey('transaction-amount')), '4.50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Coffee'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Coffee'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('current-balance')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(r'$1,230.06 USD'), findsOneWidget);
  });

  testWidgets('search filters transactions through the API', (tester) async {
    final api = FakeFinanceApi(transactions: _sampleTransactions());
    final store = await _signedInStore(api);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-search')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('transaction-search')), 'Groceries');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(store.transactions, hasLength(1));
    expect(store.transactions.single.description, 'Groceries');
    expect(find.text('Monthly salary'), findsNothing);
  });

  testWidgets('insights, recurring rules, and profile are navigable', (tester) async {
    final api = FakeFinanceApi(transactions: _sampleTransactions());
    final store = await _signedInStore(api);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Spending by category'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Spending by category'), findsOneWidget);

    await tester.tap(find.text('Recurring').last);
    await tester.pumpAndSettle();
    expect(find.text('No recurring entries yet. Add a rule to get started.'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified phone'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });
}

Future<FinanceStore> _signedInStore(FakeFinanceApi api) async {
  final store = FinanceStore.forTesting(api: api, vault: MemorySecureVault());
  await store.requestPhoneCode('+14155550123');
  await store.verifyPhoneCode('+14155550123', '123456');
  return store;
}

List<FinanceTransaction> _sampleTransactions() => [
      _transaction(1, 'Monthly salary', 150000, 'income', 'Salary', 0),
      _transaction(2, 'Online purchase refund', 25000, 'income', 'Other', 1),
      _transaction(3, 'Groceries', 5000, 'expense', 'Food', 2),
      _transaction(4, 'Rent', 46544, 'expense', 'Housing', 3),
    ];

FinanceTransaction _transaction(
  int id,
  String description,
  int amountMinor,
  String type,
  String category,
  int daysAgo,
) =>
    FinanceTransaction(
      id: id,
      description: description,
      category: category,
      amountMinor: amountMinor,
      currency: 'USD',
      occurredAt: DateTime.now().subtract(Duration(days: daysAgo)),
      transactionType: type,
    );

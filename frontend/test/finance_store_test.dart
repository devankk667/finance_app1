import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/data/finance_store.dart';
import 'fake_finance_api.dart';

void main() {
  test('money input is parsed and formatted in integer minor units', () {
    expect(parseAmountMinorUnits('12.99'), 1299);
    expect(parseAmountMinorUnits('12'), 1200);
    expect(parseAmountMinorUnits('0'), isNull);
    expect(parseAmountMinorUnits('1.999'), isNull);
    expect(parseAmountMinorUnits('1e3'), isNull);
    expect(parseAmountMinorUnits('90071992547409.91'), 9007199254740991);
    expect(parseAmountMinorUnits('90071992547409.92'), isNull);
    expect(formatMinorUnits(-123456, 'USD'), r'−$1,234.56 USD');
  });

  test('OTP sign-in stores the token in secure storage', () async {
    final api = FakeFinanceApi();
    final vault = MemorySecureVault();
    final store = FinanceStore.forTesting(api: api, vault: vault);

    await store.requestPhoneCode('+14155550123');
    await store.verifyPhoneCode('+14155550123', '123456');

    expect(api.otpSent, isTrue);
    expect(store.isSignedIn, isTrue);
    expect(api.accessToken, 'test-access-token');
    expect(vault.values.values, contains('test-access-token'));
  });

  test('transaction CRUD updates server-backed summary totals', () async {
    final api = FakeFinanceApi();
    final store = FinanceStore.forTesting(
      api: api,
      vault: MemorySecureVault(),
      accessToken: 'test-access-token',
    );

    await store.addTransaction(_draft('Salary', 250000, 'income'));
    await store.addTransaction(_draft('Rent', 125000, 'expense'));
    expect(store.balanceMinor, 125000);
    expect(store.incomeMinor, 250000);
    expect(store.expenseMinor, 125000);

    final rent = store.transactions.singleWhere(
      (item) => item.description == 'Rent',
    );
    await store.updateTransaction(rent.id, _draft('Rent', 130000, 'expense'));
    expect(store.balanceMinor, 120000);

    await store.deleteTransaction(rent.id);
    expect(store.balanceMinor, 250000);
    expect(store.transactions, hasLength(1));
  });

  test(
    'currency selection separates totals without applying exchange rates',
    () async {
      final api = FakeFinanceApi(
        transactions: [
          _transaction(1, 10000, 'USD', 'income'),
          _transaction(2, 9000, 'EUR', 'income'),
        ],
      );
      final store = FinanceStore.forTesting(
        api: api,
        vault: MemorySecureVault(),
        accessToken: 'test-access-token',
      );

      await store.refreshAll();
      expect(store.balanceMinor, 10000);
      await store.changeCurrency('EUR');
      expect(store.balanceMinor, 9000);
      expect(
        store.transactions.map((item) => item.currency),
        everyElement('EUR'),
      );
    },
  );

  test('recurring entries and CSV export use the selected filters', () async {
    final api = FakeFinanceApi();
    final store = FinanceStore.forTesting(
      api: api,
      vault: MemorySecureVault(),
      accessToken: 'test-access-token',
    );
    await store.addRecurringTemplate(
      RecurringTemplateDraft(
        description: 'Rent',
        category: 'Housing',
        amountMinor: 125000,
        currency: 'USD',
        transactionType: 'expense',
        frequency: 'monthly',
        startDate: DateTime.now(),
      ),
    );
    expect(store.recurringTemplates, hasLength(1));

    await store.addTransaction(_draft('Groceries', 2500, 'expense'));
    final csv = await store.exportTransactions();
    expect(csv, contains('amount_minor'));
    expect(csv, contains('2500'));
  });

  test(
    'network failures preserve cached data and mark the app offline',
    () async {
      final api = FakeFinanceApi()..throwOffline = true;
      final cached = _transaction(9, 5000, 'USD', 'expense');
      final store = FinanceStore.forTesting(
        api: api,
        vault: MemorySecureVault(),
        accessToken: 'test-access-token',
        transactions: [cached],
      );

      await store.refreshAll();

      expect(store.isOffline, isTrue);
      expect(store.transactions.single.id, 9);
      expect(store.errorMessage, 'offline');
    },
  );

  test('encrypted cached session and data can be restored', () async {
    final api = FakeFinanceApi();
    final vault = MemorySecureVault();
    final store = FinanceStore.forTesting(api: api, vault: vault);
    await store.requestPhoneCode('+14155550123');
    await store.verifyPhoneCode('+14155550123', '123456');
    await store.updateDisplayName('Test User');
    await store.addTransaction(_draft('Notebook', 1299, 'expense'));

    final restored = await FinanceStore.load(
      api: FakeFinanceApi(),
      vault: vault,
    );
    expect(restored.isSignedIn, isTrue);
    expect(restored.displayName, 'Test User');
    expect(restored.transactions.single.description, 'Notebook');
    expect(restored.balanceMinor, -1299);
  });
}

FinanceTransactionDraft _draft(String description, int amount, String type) =>
    FinanceTransactionDraft(
      description: description,
      category: 'Other',
      amountMinor: amount,
      currency: 'USD',
      transactionType: type,
      occurredAt: DateTime.now(),
    );

FinanceTransaction _transaction(
  int id,
  int amount,
  String currency,
  String type,
) => FinanceTransaction(
  id: id,
  description: 'Transaction $id',
  category: 'Other',
  amountMinor: amount,
  currency: currency,
  occurredAt: DateTime.now(),
  transactionType: type,
);

import 'package:frontend/data/finance_api.dart';
import 'package:frontend/data/finance_models.dart';
import 'package:frontend/data/secure_vault.dart';

class FakeFinanceApi implements FinanceApi {
  final List<FinanceTransaction> transactions;
  final List<RecurringTemplate> recurringTemplates = [];
  bool otpSent = false;
  bool throwOffline = false;
  String? accessToken;
  int _nextTransactionId = 100;
  int _nextRecurringId = 1;

  FakeFinanceApi({List<FinanceTransaction>? transactions})
      : transactions = transactions ?? [];

  @override
  void setAccessToken(String? token) => accessToken = token;

  void _checkOnline() {
    if (throwOffline) {
      throw const FinanceApiException(
        'offline',
        isNetworkError: true,
      );
    }
  }

  @override
  Future<void> startPhoneVerification(String phoneNumber) async {
    _checkOnline();
    otpSent = true;
  }

  @override
  Future<String> verifyPhone(String phoneNumber, String code) async {
    _checkOnline();
    if (!otpSent || code != '123456') {
      throw const FinanceApiException('Invalid verification code', statusCode: 400);
    }
    return 'test-access-token';
  }

  @override
  Future<List<FinanceTransaction>> getTransactions(
    TransactionFilters filters,
  ) async {
    _checkOnline();
    return transactions.where((transaction) {
      if (filters.currency != null && transaction.currency != filters.currency) {
        return false;
      }
      if (filters.category != null && transaction.category != filters.category) {
        return false;
      }
      if (filters.transactionType != null &&
          transaction.transactionType != filters.transactionType) {
        return false;
      }
      if (filters.search != null &&
          !('${transaction.description} ${transaction.category ?? ''}')
              .toLowerCase()
              .contains(filters.search!.toLowerCase())) {
        return false;
      }
      if (filters.dateFrom != null &&
          transaction.occurredAt.isBefore(filters.dateFrom!)) {
        return false;
      }
      if (filters.dateTo != null &&
          transaction.occurredAt.isAfter(
            filters.dateTo!.add(const Duration(days: 1)),
          )) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<FinanceSummary> getSummary(String currency) async {
    _checkOnline();
    final selected = transactions.where((transaction) => transaction.currency == currency);
    var income = 0;
    var expense = 0;
    for (final transaction in selected) {
      if (transaction.isIncome) {
        income += transaction.amountMinor;
      } else {
        expense += transaction.amountMinor;
      }
    }
    return FinanceSummary(
      balanceMinor: income - expense,
      incomeMinor: income,
      expenseMinor: expense,
      currency: currency,
    );
  }

  @override
  Future<FinanceTransaction> createTransaction(
    FinanceTransactionDraft draft,
  ) async {
    _checkOnline();
    final transaction = FinanceTransaction(
      id: _nextTransactionId++,
      description: draft.description,
      category: draft.category,
      amountMinor: draft.amountMinor,
      currency: draft.currency,
      occurredAt: draft.occurredAt,
      transactionType: draft.transactionType,
    );
    transactions.add(transaction);
    return transaction;
  }

  @override
  Future<FinanceTransaction> updateTransaction(
    int id,
    FinanceTransactionDraft draft,
  ) async {
    _checkOnline();
    final index = transactions.indexWhere((transaction) => transaction.id == id);
    if (index == -1) throw const FinanceApiException('Not found', statusCode: 404);
    final transaction = FinanceTransaction(
      id: id,
      description: draft.description,
      category: draft.category,
      amountMinor: draft.amountMinor,
      currency: draft.currency,
      occurredAt: draft.occurredAt,
      transactionType: draft.transactionType,
    );
    transactions[index] = transaction;
    return transaction;
  }

  @override
  Future<void> deleteTransaction(int id) async {
    _checkOnline();
    transactions.removeWhere((transaction) => transaction.id == id);
  }

  @override
  Future<List<RecurringTemplate>> getRecurringTemplates() async {
    _checkOnline();
    return List.of(recurringTemplates);
  }

  @override
  Future<RecurringTemplate> createRecurringTemplate(
    RecurringTemplateDraft draft,
  ) async {
    _checkOnline();
    final template = RecurringTemplate(
      id: _nextRecurringId++,
      description: draft.description,
      category: draft.category,
      amountMinor: draft.amountMinor,
      currency: draft.currency,
      transactionType: draft.transactionType,
      frequency: draft.frequency,
      startDate: draft.startDate,
      nextOccurrence: draft.startDate,
      endDate: draft.endDate,
    );
    recurringTemplates.add(template);
    return template;
  }

  @override
  Future<void> deleteRecurringTemplate(int id) async {
    _checkOnline();
    recurringTemplates.removeWhere((template) => template.id == id);
  }

  @override
  Future<void> materializeDueRecurringTransactions() async {}

  @override
  Future<String> exportTransactions(TransactionFilters filters) async {
    final rows = await getTransactions(filters);
    return [
      'occurred_at,description,category,transaction_type,amount_minor,currency',
      ...rows.map((transaction) =>
          '${transaction.occurredAt.toIso8601String()},${transaction.description},${transaction.category ?? ''},${transaction.transactionType},${transaction.amountMinor},${transaction.currency}'),
    ].join('\n');
  }
}

class MemorySecureVault implements SecureVault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

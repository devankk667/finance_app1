import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:frontend/data/finance_api.dart';
import 'package:frontend/data/finance_models.dart';
import 'package:frontend/data/secure_vault.dart';

export 'package:frontend/data/finance_models.dart';

class FinanceStore extends ChangeNotifier {
  FinanceStore._({
    required this.api,
    required this.vault,
    this.accessToken,
    this.phoneNumber,
    this.displayName = 'Finance user',
    this.currencyCode = 'USD',
    List<FinanceTransaction> transactions = const [],
    List<RecurringTemplate> recurringTemplates = const [],
    FinanceSummary? summary,
  })  : _transactions = List.of(transactions),
        _recurringTemplates = List.of(recurringTemplates),
        _summary = summary ?? FinanceSummary.empty(currencyCode) {
    api.setAccessToken(accessToken);
  }

  static const _tokenKey = 'finance_access_token_v2';
  static const _phoneKey = 'finance_phone_number_v2';
  static const _nameKey = 'finance_display_name_v2';
  static const _currencyKey = 'finance_currency_v2';
  static const _transactionsKey = 'finance_transactions_cache_v2';
  static const _recurringKey = 'finance_recurring_cache_v2';
  static const _summaryKey = 'finance_summary_cache_v2';

  factory FinanceStore.forTesting({
    required FinanceApi api,
    required SecureVault vault,
    String? accessToken,
    String? phoneNumber,
    List<FinanceTransaction> transactions = const [],
  }) =>
      FinanceStore._(
        api: api,
        vault: vault,
        accessToken: accessToken,
        phoneNumber: phoneNumber,
        transactions: transactions,
      );

  final FinanceApi api;
  final SecureVault vault;
  final List<FinanceTransaction> _transactions;
  final List<RecurringTemplate> _recurringTemplates;

  String? accessToken;
  String? phoneNumber;
  String displayName;
  String currencyCode;
  FinanceSummary _summary;
  TransactionFilters filters = const TransactionFilters();
  bool isLoading = false;
  bool isOffline = false;
  String? errorMessage;

  bool get isSignedIn => accessToken != null;
  List<FinanceTransaction> get transactions => List.unmodifiable(_transactions);
  List<RecurringTemplate> get recurringTemplates =>
      List.unmodifiable(_recurringTemplates);
  int get balanceMinor => _summary.balanceMinor;
  int get incomeMinor => _summary.incomeMinor;
  int get expenseMinor => _summary.expenseMinor;

  static Future<FinanceStore> load({
    required FinanceApi api,
    required SecureVault vault,
  }) async {
    final token = await vault.read(_tokenKey);
    final cachedTransactions = await _readList(vault, _transactionsKey);
    final cachedRecurring = await _readList(vault, _recurringKey);
    final cachedSummary = await vault.read(_summaryKey);
    FinanceSummary? summary;
    if (cachedSummary != null) {
      try {
        summary = FinanceSummary.fromJson(
          Map<String, dynamic>.from(jsonDecode(cachedSummary) as Map),
        );
      } on FormatException {
        summary = null;
      } on TypeError {
        summary = null;
      }
    }

    final currency = await vault.read(_currencyKey) ?? 'USD';
    return FinanceStore._(
      api: api,
      vault: vault,
      accessToken: token,
      phoneNumber: await vault.read(_phoneKey),
      displayName: await vault.read(_nameKey) ?? 'Finance user',
      currencyCode: CurrencyOption.fromCode(currency).code,
      transactions: cachedTransactions
          .map(FinanceTransaction.fromCache)
          .toList(),
      recurringTemplates: cachedRecurring
          .map(RecurringTemplate.fromJson)
          .toList(),
      summary: summary?.currency == CurrencyOption.fromCode(currency).code
          ? summary
          : null,
    );
  }

  Future<void> requestPhoneCode(String phone) async {
    _beginRequest();
    try {
      await api.startPhoneVerification(phone);
    } catch (error) {
      errorMessage = _messageFor(error);
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<void> verifyPhoneCode(String phone, String code) async {
    _beginRequest();
    try {
      accessToken = await api.verifyPhone(phone, code);
      phoneNumber = phone;
      api.setAccessToken(accessToken);
      await vault.write(_tokenKey, accessToken!);
      await vault.write(_phoneKey, phone);
      errorMessage = null;
      isOffline = false;
      await refreshAll(materializeRecurring: true, notify: false);
      if (!isSignedIn) {
        throw const FinanceApiException(
          'Your session was rejected. Request a new verification code.',
          statusCode: 401,
        );
      }
    } catch (error) {
      if (accessToken == null) errorMessage = _messageFor(error);
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<void> refreshAll({
    bool materializeRecurring = false,
    bool notify = true,
  }) async {
    if (!isSignedIn) return;
    if (notify) {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
    }
    try {
      if (materializeRecurring) {
        await api.materializeDueRecurringTransactions();
      }
      final results = await Future.wait<Object>([
        api.getTransactions(filters.copyWith(currency: currencyCode)),
        api.getSummary(currencyCode),
        api.getRecurringTemplates(),
      ]);
      _transactions
        ..clear()
        ..addAll(results[0] as List<FinanceTransaction>);
      _summary = results[1] as FinanceSummary;
      _recurringTemplates
        ..clear()
        ..addAll(results[2] as List<RecurringTemplate>);
      isOffline = false;
      errorMessage = null;
      await _cacheData();
    } catch (error) {
      _handleApiError(error);
      if (error is FinanceApiException && error.statusCode == 401) {
        await signOut(notify: false);
      }
    } finally {
      if (notify) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshTransactions({TransactionFilters? nextFilters}) async {
    if (!isSignedIn) return;
    if (nextFilters != null) filters = nextFilters;
    _beginRequest();
    try {
      final result = await api.getTransactions(
        filters.copyWith(currency: currencyCode),
      );
      _transactions
        ..clear()
        ..addAll(result);
      isOffline = false;
      errorMessage = null;
      await vault.write(
        _transactionsKey,
        jsonEncode(result.map((transaction) => transaction.toCacheJson()).toList()),
      );
    } catch (error) {
      _handleApiError(error);
      if (error is FinanceApiException && error.statusCode == 401) {
        await signOut(notify: false);
      }
    } finally {
      _endRequest();
    }
  }

  Future<void> changeCurrency(String value) async {
    currencyCode = CurrencyOption.fromCode(value).code;
    filters = filters.copyWith(clearCurrency: true);
    _summary = FinanceSummary.empty(currencyCode);
    await vault.write(_currencyKey, currencyCode);
    notifyListeners();
    await refreshAll();
  }

  Future<void> updateDisplayName(String name) async {
    displayName = name;
    await vault.write(_nameKey, name);
    notifyListeners();
  }

  Future<void> addTransaction(FinanceTransactionDraft draft) async {
    _beginRequest();
    try {
      await api.createTransaction(draft);
      await refreshAll(notify: false);
    } catch (error) {
      _handleApiError(error);
      if (error is FinanceApiException && error.statusCode == 401) {
        await signOut(notify: false);
      }
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<void> updateTransaction(
    int id,
    FinanceTransactionDraft draft,
  ) async {
    _beginRequest();
    try {
      await api.updateTransaction(id, draft);
      await refreshAll(notify: false);
    } catch (error) {
      _handleApiError(error);
      if (error is FinanceApiException && error.statusCode == 401) {
        await signOut(notify: false);
      }
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<void> deleteTransaction(int id) async {
    _beginRequest();
    try {
      await api.deleteTransaction(id);
      await refreshAll(notify: false);
    } catch (error) {
      _handleApiError(error);
      if (error is FinanceApiException && error.statusCode == 401) {
        await signOut(notify: false);
      }
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<void> refreshRecurringTemplates() async {
    if (!isSignedIn) return;
    try {
      final templates = await api.getRecurringTemplates();
      _recurringTemplates
        ..clear()
        ..addAll(templates);
      await vault.write(
        _recurringKey,
        jsonEncode(templates.map((template) => template.toCacheJson()).toList()),
      );
      errorMessage = null;
    } catch (error) {
      _handleApiError(error);
      if (error is FinanceApiException && error.statusCode == 401) {
        await signOut(notify: false);
      }
    }
    notifyListeners();
  }

  Future<void> addRecurringTemplate(RecurringTemplateDraft draft) async {
    _beginRequest();
    try {
      await api.createRecurringTemplate(draft);
      await refreshAll(notify: false);
    } catch (error) {
      _handleApiError(error);
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<void> deleteRecurringTemplate(int id) async {
    _beginRequest();
    try {
      await api.deleteRecurringTemplate(id);
      await refreshAll(notify: false);
    } catch (error) {
      _handleApiError(error);
      rethrow;
    } finally {
      _endRequest();
    }
  }

  Future<String> exportTransactions() => api.exportTransactions(
        filters.copyWith(currency: currencyCode),
      );

  Future<void> signOut({bool notify = true}) async {
    accessToken = null;
    phoneNumber = null;
    displayName = 'Finance user';
    api.setAccessToken(null);
    await Future.wait([
      vault.delete(_tokenKey),
      vault.delete(_phoneKey),
      vault.delete(_nameKey),
      vault.delete(_transactionsKey),
      vault.delete(_recurringKey),
      vault.delete(_summaryKey),
    ]);
    _transactions.clear();
    _recurringTemplates.clear();
    _summary = FinanceSummary.empty(currencyCode);
    isOffline = false;
    errorMessage = null;
    if (notify) notifyListeners();
  }

  Future<void> _cacheData() async {
    await Future.wait([
      vault.write(
        _transactionsKey,
        jsonEncode(
          _transactions.map((transaction) => transaction.toCacheJson()).toList(),
        ),
      ),
      vault.write(
        _recurringKey,
        jsonEncode(
          _recurringTemplates.map((template) => template.toCacheJson()).toList(),
        ),
      ),
      vault.write(
        _summaryKey,
        jsonEncode({
          'balance_minor': _summary.balanceMinor,
          'income_minor': _summary.incomeMinor,
          'expense_minor': _summary.expenseMinor,
          'currency': _summary.currency,
        }),
      ),
    ]);
  }

  void _beginRequest() {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
  }

  void _endRequest() {
    isLoading = false;
    notifyListeners();
  }

  void _handleApiError(Object error) {
    errorMessage = _messageFor(error);
    if (error is FinanceApiException && error.isNetworkError) {
      isOffline = true;
    }
  }

  String _messageFor(Object error) {
    if (error is FinanceApiException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  static Future<List<Map<String, dynamic>>> _readList(
    SecureVault vault,
    String key,
  ) async {
    final value = await vault.read(key);
    if (value == null) return [];
    try {
      final decoded = jsonDecode(value) as List<dynamic>;
      return decoded
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }
}


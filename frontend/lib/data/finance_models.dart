class CurrencyOption {
  const CurrencyOption(this.code, this.symbol, this.label);

  final String code;
  final String symbol;
  final String label;

  static const supported = [
    CurrencyOption('USD', r'$', 'US dollar'),
    CurrencyOption('EUR', '€', 'Euro'),
    CurrencyOption('GBP', '£', 'British pound'),
    CurrencyOption('INR', '₹', 'Indian rupee'),
    CurrencyOption('CAD', r'C$', 'Canadian dollar'),
    CurrencyOption('AUD', r'A$', 'Australian dollar'),
  ];

  static CurrencyOption fromCode(String code) => supported.firstWhere(
    (currency) => currency.code == code,
    orElse: () => supported.first,
  );
}

int? parseAmountMinorUnits(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  if (parts.first.length > 14) return null;
  final whole = int.tryParse(parts.first);
  const maxSafeWhole = 90071992547409;
  if (whole == null || whole > maxSafeWhole) return null;
  final fraction = parts.length == 1 ? '' : parts[1].padRight(2, '0');
  final minorFraction = fraction.isEmpty ? 0 : int.parse(fraction);
  if (whole == maxSafeWhole && minorFraction > 91) return null;
  final minor = whole * 100 + minorFraction;
  return minor > 0 ? minor : null;
}

String formatMinorUnits(int amountMinor, String currencyCode) {
  final matchingCurrencies = CurrencyOption.supported.where(
    (option) => option.code == currencyCode,
  );
  final currency = matchingCurrencies.isEmpty ? null : matchingCurrencies.first;
  final absolute = amountMinor.abs();
  final whole = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final sign = amountMinor < 0 ? '−' : '';
  if (currency == null) return '$sign$whole.$fraction $currencyCode';
  return '$sign${currency.symbol}$whole.$fraction ${currency.code}';
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    required this.transactionType,
  });

  final int id;
  final String description;
  final String? category;
  final int amountMinor;
  final String currency;
  final DateTime occurredAt;
  final String transactionType;

  bool get isIncome => transactionType == 'income';
  int get signedAmountMinor => isIncome ? amountMinor : -amountMinor;

  factory FinanceTransaction.fromApi(Map<String, dynamic> json) =>
      FinanceTransaction(
        id: json['id'] as int,
        description: json['description'] as String,
        category: json['category'] as String?,
        amountMinor: json['amount_minor'] as int,
        currency: json['currency'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        transactionType: json['transaction_type'] as String,
      );

  factory FinanceTransaction.fromCache(Map<String, dynamic> json) =>
      FinanceTransaction(
        id: json['id'] as int,
        description: json['description'] as String,
        category: json['category'] as String?,
        amountMinor: json['amount_minor'] as int,
        currency: json['currency'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        transactionType: json['transaction_type'] as String,
      );

  Map<String, Object?> toCacheJson() => {
    'id': id,
    'description': description,
    'category': category,
    'amount_minor': amountMinor,
    'currency': currency,
    'occurred_at': occurredAt.toIso8601String(),
    'transaction_type': transactionType,
  };
}

class FinanceTransactionDraft {
  const FinanceTransactionDraft({
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.currency,
    required this.transactionType,
    required this.occurredAt,
  });

  final String description;
  final String? category;
  final int amountMinor;
  final String currency;
  final String transactionType;
  final DateTime occurredAt;

  Map<String, Object?> toApiJson() => {
    'description': description,
    'category': category,
    'amount_minor': amountMinor,
    'currency': currency,
    'transaction_type': transactionType,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}

class FinanceSummary {
  const FinanceSummary({
    required this.balanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.currency,
  });

  const FinanceSummary.empty(this.currency)
    : balanceMinor = 0,
      incomeMinor = 0,
      expenseMinor = 0;

  final int balanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final String currency;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) => FinanceSummary(
    balanceMinor: json['balance_minor'] as int,
    incomeMinor: json['income_minor'] as int,
    expenseMinor: json['expense_minor'] as int,
    currency: json['currency'] as String,
  );
}

class TransactionFilters {
  const TransactionFilters({
    this.search,
    this.category,
    this.transactionType,
    this.dateFrom,
    this.dateTo,
    this.currency,
  });

  final String? search;
  final String? category;
  final String? transactionType;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? currency;

  TransactionFilters copyWith({
    String? search,
    String? category,
    String? transactionType,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? currency,
    bool clearSearch = false,
    bool clearCategory = false,
    bool clearTransactionType = false,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearCurrency = false,
  }) => TransactionFilters(
    search: clearSearch ? null : search ?? this.search,
    category: clearCategory ? null : category ?? this.category,
    transactionType: clearTransactionType
        ? null
        : transactionType ?? this.transactionType,
    dateFrom: clearDateFrom ? null : dateFrom ?? this.dateFrom,
    dateTo: clearDateTo ? null : dateTo ?? this.dateTo,
    currency: clearCurrency ? null : currency ?? this.currency,
  );

  Map<String, String> toQueryParameters() => {
    if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
    if (category != null && category!.trim().isNotEmpty)
      'category': category!.trim(),
    if (transactionType != null) 'transaction_type': transactionType!,
    if (dateFrom != null) 'date_from': _dateOnly(dateFrom!),
    if (dateTo != null) 'date_to': _dateOnly(dateTo!),
    if (currency != null) 'currency': currency!,
    'limit': '100',
    'offset': '0',
  };
}

class RecurringTemplate {
  const RecurringTemplate({
    required this.id,
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.currency,
    required this.transactionType,
    required this.frequency,
    required this.startDate,
    required this.nextOccurrence,
    this.endDate,
  });

  final int id;
  final String description;
  final String? category;
  final int amountMinor;
  final String currency;
  final String transactionType;
  final String frequency;
  final DateTime startDate;
  final DateTime nextOccurrence;
  final DateTime? endDate;

  factory RecurringTemplate.fromJson(Map<String, dynamic> json) =>
      RecurringTemplate(
        id: json['id'] as int,
        description: json['description'] as String,
        category: json['category'] as String?,
        amountMinor: json['amount_minor'] as int,
        currency: json['currency'] as String,
        transactionType: json['transaction_type'] as String,
        frequency: json['frequency'] as String,
        startDate: DateTime.parse(json['start_date'] as String),
        nextOccurrence: DateTime.parse(json['next_occurrence'] as String),
        endDate: json['end_date'] == null
            ? null
            : DateTime.parse(json['end_date'] as String),
      );

  Map<String, Object?> toCacheJson() => {
    'id': id,
    'description': description,
    'category': category,
    'amount_minor': amountMinor,
    'currency': currency,
    'transaction_type': transactionType,
    'frequency': frequency,
    'start_date': _dateOnly(startDate),
    'next_occurrence': _dateOnly(nextOccurrence),
    'end_date': endDate == null ? null : _dateOnly(endDate!),
  };
}

class RecurringTemplateDraft {
  const RecurringTemplateDraft({
    required this.description,
    required this.category,
    required this.amountMinor,
    required this.currency,
    required this.transactionType,
    required this.frequency,
    required this.startDate,
    this.endDate,
  });

  final String description;
  final String? category;
  final int amountMinor;
  final String currency;
  final String transactionType;
  final String frequency;
  final DateTime startDate;
  final DateTime? endDate;

  Map<String, Object?> toJson() => {
    'description': description,
    'category': category,
    'amount_minor': amountMinor,
    'currency': currency,
    'transaction_type': transactionType,
    'frequency': frequency,
    'start_date': _dateOnly(startDate),
    'end_date': endDate == null ? null : _dateOnly(endDate!),
  };
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

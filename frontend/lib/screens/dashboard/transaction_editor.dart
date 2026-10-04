import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/data/finance_store.dart';

Future<FinanceTransactionDraft?> showTransactionEditor(
  BuildContext context, {
  required String currency,
  required bool isIncome,
  FinanceTransaction? initial,
}) =>
    showDialog<FinanceTransactionDraft>(
      context: context,
      builder: (_) => _TransactionEditor(
        currency: currency,
        isIncome: isIncome,
        initial: initial,
      ),
    );

class _TransactionEditor extends StatefulWidget {
  const _TransactionEditor({
    required this.currency,
    required this.isIncome,
    this.initial,
  });

  final String currency;
  final bool isIncome;
  final FinanceTransaction? initial;

  @override
  State<_TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<_TransactionEditor> {
  static const _expenseCategories = [
    'Food',
    'Housing',
    'Transport',
    'Bills',
    'Shopping',
    'Health',
    'Other',
  ];
  static const _incomeCategories = [
    'Salary',
    'Freelance',
    'Gift',
    'Refund',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  late final _descriptionController = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final _amountController = TextEditingController(
    text: _initialAmountText(widget.initial?.amountMinor),
  );
  late bool _isIncome = widget.initial?.isIncome ?? widget.isIncome;
  late String _category = widget.initial?.category ?? 'Other';
  late DateTime _occurredAt = widget.initial?.occurredAt ?? DateTime.now();

  List<String> get _categories {
    final categories = _isIncome ? _incomeCategories : _expenseCategories;
    if (!categories.contains(_category)) return [...categories, _category];
    return categories;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amountMinor = parseAmountMinorUnits(_amountController.text);
    if (amountMinor == null) return;
    Navigator.of(context).pop(
      FinanceTransactionDraft(
        description: _descriptionController.text.trim(),
        category: _category,
        amountMinor: amountMinor,
        currency: widget.currency,
        transactionType: _isIncome ? 'income' : 'expense',
        occurredAt: _occurredAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit transaction' : 'Add transaction'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'income', label: Text('Income')),
                ],
                selected: {_isIncome ? 'income' : 'expense'},
                onSelectionChanged: (selection) {
                  setState(() {
                    _isIncome = selection.first == 'income';
                    if (!_categories.contains(_category)) _category = 'Other';
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('transaction-description'),
                controller: _descriptionController,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a description'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('transaction-amount'),
                controller: _amountController,
                decoration: InputDecoration(labelText: 'Amount (${widget.currency})'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                validator: (value) => parseAmountMinorUnits(value ?? '') == null
                    ? 'Enter a positive amount with up to two decimals'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_isIncome),
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Transaction date'),
                subtitle: Text(_dateLabel(_occurredAt)),
                onTap: _chooseDate,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final firstDate = DateTime(2000);
    final initialDate = _occurredAt.isAfter(today)
        ? today
        : _occurredAt.isBefore(firstDate)
            ? firstDate
            : _occurredAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: today,
    );
    if (date != null) setState(() => _occurredAt = date);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}

String _initialAmountText(int? amountMinor) {
  if (amountMinor == null) return '';
  return '${amountMinor ~/ 100}.${(amountMinor % 100).toString().padLeft(2, '0')}';
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

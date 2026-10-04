import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:provider/provider.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            tooltip: 'Add recurring transaction',
            onPressed: store.isLoading ? null : () => _addRecurring(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Recurring rules create ledger entries when the app syncs. '
                  'They do not schedule or execute bank payments.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (store.errorMessage != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(store.errorMessage!),
                ),
              ),
            if (store.isLoading) const LinearProgressIndicator(),
            if (store.recurringTemplates.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No recurring entries yet. Add a rule to get started.'),
                ),
              )
            else
              ...store.recurringTemplates.map(
                (template) => Card(
                  child: ListTile(
                    leading: Icon(
                      template.transactionType == 'income'
                          ? Icons.south_west
                          : Icons.north_east,
                    ),
                    title: Text(template.description),
                    subtitle: Text(
                      '${template.frequency} · Next: ${_dateLabel(template.nextOccurrence)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatMinorUnits(template.amountMinor, template.currency)),
                        PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'delete') {
                              _deleteRecurring(context, template.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('Delete rule')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: store.isLoading ? null : () => _addRecurring(context),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
    );
  }

  Future<void> _addRecurring(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final draft = await showDialog<RecurringTemplateDraft>(
      context: context,
      builder: (_) => _RecurringEditor(currency: store.currencyCode),
    );
    if (draft == null || !context.mounted) return;
    try {
      await store.addRecurringTemplate(draft);
    } catch (_) {
      if (context.mounted) _showError(context, store.errorMessage);
    }
  }

  Future<void> _deleteRecurring(BuildContext context, int id) async {
    final store = context.read<FinanceStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recurring rule?'),
        content: const Text('Already-created ledger entries will remain.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.deleteRecurringTemplate(id);
    } catch (_) {
      if (context.mounted) _showError(context, store.errorMessage);
    }
  }
}

class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({required this.currency});

  final String currency;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  static const _categories = [
    'Housing',
    'Bills',
    'Food',
    'Transport',
    'Salary',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String _transactionType = 'expense';
  String _category = 'Other';
  String _frequency = 'monthly';
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recurring transaction'),
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
                selected: {_transactionType},
                onSelectionChanged: (value) =>
                    setState(() => _transactionType = value.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a description'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: 'Amount (${widget.currency})'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                validator: (value) => parseAmountMinorUnits(value ?? '') == null
                    ? 'Enter an amount with up to two decimals'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _frequency = value);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starts'),
                subtitle: Text(_dateLabel(_startDate)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () => _chooseDate(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ends (optional)'),
                subtitle: Text(_endDate == null ? 'Never' : _dateLabel(_endDate!)),
                trailing: const Icon(Icons.event_busy_outlined),
                onTap: () => _chooseDate(isStart: false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Create rule')),
      ],
    );
  }

  Future<void> _chooseDate({required bool isStart}) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? _startDate),
      firstDate: isStart ? now.subtract(const Duration(days: 3650)) : _startDate,
      lastDate: DateTime(now.year + 20),
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _startDate = selected;
        if (_endDate != null && _endDate!.isBefore(selected)) _endDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amountMinor = parseAmountMinorUnits(_amountController.text);
    if (amountMinor == null) return;
    Navigator.pop(
      context,
      RecurringTemplateDraft(
        description: _descriptionController.text.trim(),
        category: _category,
        amountMinor: amountMinor,
        currency: widget.currency,
        transactionType: _transactionType,
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _showError(BuildContext context, String? message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message ?? 'The request failed. Please try again.')),
  );
}

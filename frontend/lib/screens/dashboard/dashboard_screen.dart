import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:frontend/screens/dashboard/transaction_editor.dart';
import 'package:frontend/widgets/quick_action_button.dart';
import 'package:frontend/widgets/summary_card.dart';
import 'package:provider/provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _categories = [
    'Food', 'Housing', 'Transport', 'Bills', 'Shopping', 'Health', 'Salary',
    'Freelance', 'Gift', 'Refund', 'Other',
  ];

  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh transactions',
            onPressed: store.isLoading
                ? null
                : () => store.refreshAll(materializeRecurring: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            onSelected: (value) {
              if (value == 'csv') _exportCsv(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('Copy filtered CSV')),
            ],
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => store.refreshAll(materializeRecurring: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _ConnectionNotice(isOffline: store.isOffline),
            if (store.errorMessage != null) ...[
              const SizedBox(height: 8),
              _ErrorNotice(message: store.errorMessage!),
            ],
            if (store.isLoading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance · ${store.currencyCode}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatMinorUnits(store.balanceMinor, store.currencyCode),
                      key: const ValueKey('current-balance'),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text('Calculated from your recorded transactions'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SummaryCard(
              title: 'All-time income',
              value: formatMinorUnits(store.incomeMinor, store.currencyCode),
              icon: Icons.trending_up,
            ),
            SummaryCard(
              title: 'All-time expenses',
              value: formatMinorUnits(store.expenseMinor, store.currencyCode),
              icon: Icons.trending_down,
            ),
            const SizedBox(height: 12),
            Text('Add a transaction', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: QuickActionButton(
                    title: 'Add expense',
                    icon: Icons.remove_circle_outline,
                    onPressed: store.isLoading
                        ? null
                        : () => _editTransaction(context, isIncome: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionButton(
                    title: 'Add income',
                    icon: Icons.add_circle_outline,
                    onPressed: store.isLoading
                        ? null
                        : () => _editTransaction(context, isIncome: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Transactions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _buildFilters(context, store),
            const SizedBox(height: 8),
            if (store.transactions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No matching transactions.'),
                ),
              )
            else
              ...store.transactions.map(
                (transaction) => _transactionTile(context, transaction),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context, FinanceStore store) {
    final filters = store.filters;
    final hasDateRange = filters.dateFrom != null || filters.dateTo != null;
    return Column(
      children: [
        TextField(
          key: const ValueKey('transaction-search'),
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search transactions',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _searchController.clear();
                _applyFilters(
                  store,
                  store.filters.copyWith(clearSearch: true),
                );
              },
              icon: const Icon(Icons.close),
            ),
          ),
          onChanged: (value) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              _applyFilters(
                store,
                store.filters.copyWith(
                  search: value,
                  clearSearch: value.trim().isEmpty,
                ),
              );
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: filters.transactionType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('All types')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                ],
                onChanged: (value) => _applyFilters(
                  store,
                  filters.copyWith(
                    transactionType: value,
                    clearTransactionType: value == null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _chooseDateRange(context, store),
                icon: const Icon(Icons.date_range),
                label: Text(hasDateRange ? 'Date set' : 'Date range'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: filters.category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories'),
            ),
            ..._categories.map(
              (category) => DropdownMenuItem<String?>(
                value: category,
                child: Text(category),
              ),
            ),
          ],
          onChanged: (value) => _applyFilters(
            store,
            filters.copyWith(category: value, clearCategory: value == null),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: filters.search == null &&
                    filters.category == null &&
                    filters.transactionType == null &&
                    !hasDateRange
                ? null
                : () {
                    _searchController.clear();
                    _applyFilters(
                      store,
                      const TransactionFilters(),
                    );
                  },
            child: const Text('Clear filters'),
          ),
        ),
      ],
    );
  }

  Widget _transactionTile(
    BuildContext context,
    FinanceTransaction transaction,
  ) {
    final isIncome = transaction.isIncome;
    final color = isIncome ? Colors.green : Colors.red;
    return Card(
      child: ListTile(
        onTap: () => _editTransaction(
          context,
          initial: transaction,
          isIncome: isIncome,
        ),
        leading: CircleAvatar(
          child: Icon(
            isIncome ? Icons.south_west : Icons.north_east,
            color: color,
          ),
        ),
        title: Text(transaction.description),
        subtitle: Text(
          '${transaction.category ?? 'Uncategorized'} · ${_dateLabel(transaction.occurredAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isIncome ? '+' : '−'}${formatMinorUnits(transaction.amountMinor, transaction.currency)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            PopupMenuButton<String>(
              tooltip: 'Transaction options',
              onSelected: (action) {
                if (action == 'edit') {
                  _editTransaction(context, initial: transaction, isIncome: isIncome);
                } else if (action == 'delete') {
                  _deleteTransaction(context, transaction);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTransaction(
    BuildContext context, {
    required bool isIncome,
    FinanceTransaction? initial,
  }) async {
    final store = context.read<FinanceStore>();
    final draft = await showTransactionEditor(
      context,
      currency: initial?.currency ?? store.currencyCode,
      isIncome: isIncome,
      initial: initial,
    );
    if (draft == null || !context.mounted) return;
    try {
      if (initial == null) {
        await store.addTransaction(draft);
      } else {
        await store.updateTransaction(initial.id, draft);
      }
    } catch (_) {
      if (context.mounted) _showMessage(context, store.errorMessage);
    }
  }

  Future<void> _deleteTransaction(
    BuildContext context,
    FinanceTransaction transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('Delete “${transaction.description}” from your ledger?'),
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
    final store = context.read<FinanceStore>();
    try {
      await store.deleteTransaction(transaction.id);
    } catch (_) {
      if (context.mounted) _showMessage(context, store.errorMessage);
    }
  }

  Future<void> _chooseDateRange(BuildContext context, FinanceStore store) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: store.filters.dateFrom == null || store.filters.dateTo == null
          ? null
          : DateTimeRange(
              start: store.filters.dateFrom!,
              end: store.filters.dateTo!,
            ),
    );
    if (range == null) return;
    _applyFilters(
      store,
      store.filters.copyWith(dateFrom: range.start, dateTo: range.end),
    );
  }

  void _applyFilters(FinanceStore store, TransactionFilters filters) {
    store.refreshTransactions(nextFilters: filters);
  }

  Future<void> _exportCsv(BuildContext context) async {
    final store = context.read<FinanceStore>();
    try {
      final csv = await store.exportTransactions();
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        _showMessage(context, 'Filtered CSV copied to clipboard.');
      }
    } catch (_) {
      if (context.mounted) _showMessage(context, store.errorMessage);
    }
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice({required this.isOffline});

  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOffline
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isOffline ? Icons.cloud_off_outlined : Icons.verified_user_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isOffline
                  ? 'Offline · showing encrypted data saved on this device'
                  : 'Connected to your finance account · no bank payments are enabled',
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(message),
        ),
      );
}

void _showMessage(BuildContext context, String? message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message ?? 'The request failed. Please try again.')),
  );
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

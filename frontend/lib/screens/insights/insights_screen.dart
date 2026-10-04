import 'package:flutter/material.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:frontend/widgets/activity_heatmap.dart';
import 'package:frontend/widgets/dual_axis_line_chart.dart';
import 'package:provider/provider.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final categoryTotals = <String, int>{};
    for (final transaction in store.transactions) {
      if (!transaction.isIncome) {
        final category = transaction.category ?? 'Uncategorized';
        categoryTotals.update(
          category,
          (total) => total + transaction.amountMinor,
          ifAbsent: () => transaction.amountMinor,
        );
      }
    }
    final topCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Totals use all recorded transactions in ${store.currencyCode}. '
            'Category and chart details use the current transaction filters.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'All-time income',
                  value: formatMinorUnits(store.incomeMinor, store.currencyCode),
                  icon: Icons.south_west,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  title: 'All-time expenses',
                  value: formatMinorUnits(store.expenseMinor, store.currencyCode),
                  icon: Icons.north_east,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const DualAxisLineChart(),
          const SizedBox(height: 16),
          const ActivityHeatmap(),
          const SizedBox(height: 16),
          Text(
            'Spending by category',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (topCategories.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No expenses match the current filters.'),
              ),
            )
          else
            ...topCategories.map(
              (entry) => Card(
                child: ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(entry.key),
                  trailing: Text(formatMinorUnits(entry.value, store.currencyCode)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
      ),
    );
  }
}

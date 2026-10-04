import 'package:flutter/material.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:provider/provider.dart';

class DualAxisLineChart extends StatelessWidget {
  const DualAxisLineChart({super.key});

  @override
  Widget build(BuildContext context) {
    final transactions = context.watch<FinanceStore>().transactions;
    final days = List.generate(7, (index) {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - index));
      var incomeMinor = 0;
      var expenseMinor = 0;
      for (final transaction in transactions) {
        if (!DateUtils.isSameDay(transaction.occurredAt, day)) continue;
        if (transaction.isIncome) {
          incomeMinor += transaction.amountMinor;
        } else {
          expenseMinor += transaction.amountMinor;
        }
      }
      return _DayTotals(
        date: day,
        incomeMinor: incomeMinor,
        expenseMinor: expenseMinor,
      );
    });
    final maxAmountMinor = days.fold<int>(1, (maximum, day) {
      final income = day.incomeMinor > maximum ? day.incomeMinor : maximum;
      return day.expenseMinor > income ? day.expenseMinor : income;
    });
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Income and expenses · 7 days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              children: [
                _Legend(color: theme.colorScheme.primary, label: 'Income'),
                _Legend(color: theme.colorScheme.tertiary, label: 'Expenses'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: days.map((day) {
                  final incomeHeight = day.incomeMinor / maxAmountMinor * 105;
                  final expenseHeight = day.expenseMinor / maxAmountMinor * 105;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Bar(height: incomeHeight, color: theme.colorScheme.primary),
                              const SizedBox(width: 3),
                              _Bar(height: expenseHeight, color: theme.colorScheme.tertiary),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(_weekday(day.date.weekday), style: theme.textTheme.labelSmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTotals {
  const _DayTotals({
    required this.date,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final DateTime date;
  final int incomeMinor;
  final int expenseMinor;
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: height == 0 ? 2 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

String _weekday(int weekday) {
  const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return names[weekday - 1];
}

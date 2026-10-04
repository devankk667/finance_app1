import 'package:flutter/material.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:provider/provider.dart';

class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key});

  @override
  Widget build(BuildContext context) {
    final transactions = context.watch<FinanceStore>().transactions;
    final now = DateTime.now();
    final days = List.generate(28, (index) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 27 - index));
      final count = transactions
          .where((transaction) => DateUtils.isSameDay(transaction.occurredAt, date))
          .length;
      return _ActivityDay(date: date, count: count);
    });
    final maxCount = days.fold<int>(
      0,
      (max, day) => day.count > max ? day.count : max,
    );
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transaction activity · last 28 days',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final day = days[index];
                final intensity = maxCount == 0 ? 0.0 : day.count / maxCount;
                final background = day.count == 0
                    ? theme.colorScheme.surfaceContainerHighest
                    : Color.lerp(
                        theme.colorScheme.primary.withValues(alpha: 0.2),
                        theme.colorScheme.primary,
                        intensity,
                      )!;
                return Tooltip(
                  message:
                      '${_dateLabel(day.date)} · ${day.count} transactions',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '${day.date.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: intensity > 0.6
                              ? theme.colorScheme.onPrimary
                              : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Each square represents a day; brighter days have more entries.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityDay {
  const _ActivityDay({required this.date, required this.count});

  final DateTime date;
  final int count;
}

String _dateLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

import 'package:flutter/material.dart';

class SecurityLog extends StatelessWidget {
  const SecurityLog({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Security', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline),
              title: Text('Monitoring is not configured'),
              subtitle: Text(
                'Phone verification is active, but account and device events are not monitored.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

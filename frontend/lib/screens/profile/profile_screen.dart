import 'package:flutter/material.dart';
import 'package:frontend/data/finance_store.dart';
import 'package:frontend/screens/onboarding/login_screen.dart';
import 'package:frontend/widgets/security_log.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile and settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    child: Text(
                      store.displayName.isEmpty
                          ? '?'
                          : store.displayName[0].toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    store.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Verified phone ${_maskPhone(store.phoneNumber)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _editName(context, store),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit display name'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Display currency', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: store.currencyCode,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: CurrencyOption.supported
                        .map(
                          (option) => DropdownMenuItem(
                            value: option.code,
                            child: Text('${option.code} · ${option.label}'),
                          ),
                        )
                        .toList(),
                    onChanged: store.isLoading
                        ? null
                        : (value) {
                            if (value != null) store.changeCurrency(value);
                          },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Currency changes filter totals and new entries; no exchange-rate conversion is applied.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Transactions in current view'),
              trailing: Text('${store.transactions.length}'),
            ),
          ),
          const SizedBox(height: 12),
          const SecurityLog(),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Your access token and offline cache are kept in platform secure storage. '
                'Security-event monitoring and biometric login are not configured.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: store.isLoading ? null : () => _signOut(context, store),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, FinanceStore store) async {
    final controller = TextEditingController(text: store.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    await store.updateDisplayName(name);
  }

  Future<void> _signOut(BuildContext context, FinanceStore store) async {
    await store.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

String _maskPhone(String? phone) {
  if (phone == null || phone.length < 4) return '••••';
  return '••••${phone.substring(phone.length - 4)}';
}

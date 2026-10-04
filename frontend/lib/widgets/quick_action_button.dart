import 'package:flutter/material.dart';

class QuickActionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onPressed;

  const QuickActionButton({
    required this.title,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(title),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        textStyle: const TextStyle(fontSize: 16),
      ),
    );
  }
}

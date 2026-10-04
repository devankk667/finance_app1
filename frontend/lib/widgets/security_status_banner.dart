
import 'package:flutter/material.dart';

class SecurityStatusBanner extends StatelessWidget {
  final bool isAllClear;

  const SecurityStatusBanner({required this.isAllClear, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: isAllClear ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isAllClear ? Icons.check_circle : Icons.warning,
            color: isAllClear ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 10),
          Text(
            isAllClear ? 'All Clear' : 'Security Alert: SIM Swap Detected!',
            style: TextStyle(
              color: isAllClear ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

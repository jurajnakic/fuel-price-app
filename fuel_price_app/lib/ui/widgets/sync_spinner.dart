import 'package:flutter/material.dart';

class SyncSpinner extends StatelessWidget {
  const SyncSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Preuzimanje podataka...'),
        ],
      ),
    );
  }
}

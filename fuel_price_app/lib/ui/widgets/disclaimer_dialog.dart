import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _disclaimerKey = 'disclaimer_acknowledged';

const disclaimerText =
    'Ovo je neslužbena aplikacija. Prikazane cijene su procjena temeljena na '
    'javno dostupnim podacima i važećoj regulativi. Moguća su odstupanja od '
    'stvarnih cijena zbog intervencija Vlade, promjena regulatornog okvira ili '
    'nedostupnosti podataka. Aplikacija ne preuzima odgovornost za točnost '
    'prikazanih cijena.';

Future<void> showDisclaimerIfNeeded(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_disclaimerKey) == true) return;

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Napomena'),
      content: const Text(disclaimerText),
      actions: [
        FilledButton(
          onPressed: () async {
            await prefs.setBool(_disclaimerKey, true);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Postavke'),
      ),
      body: ListView(
        children: [
          // Display section
          _SectionHeader(title: 'Prikaz'),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Vidljivost goriva'),
            subtitle: const Text('Odaberite koja goriva prikazati'),
            onTap: () {
              // TODO: fuel visibility dialog
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Tema'),
            subtitle: const Text('Sustav'),
            onTap: () {
              // TODO: theme picker
            },
          ),

          const Divider(indent: 16, endIndent: 16),

          // Notifications section
          _SectionHeader(title: 'Obavijesti'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Obavijesti o promjeni cijena'),
            value: true,
            onChanged: (value) {
              // TODO: toggle notifications
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Dan obavijesti'),
            subtitle: const Text('Ponedjeljak'),
            onTap: () {
              // TODO: day picker
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Vrijeme obavijesti'),
            subtitle: const Text('09:00'),
            onTap: () {
              // TODO: time picker
            },
          ),

          const Divider(indent: 16, endIndent: 16),

          // Regulatory info
          _SectionHeader(title: 'Regulativa'),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Uredba o cijenama'),
            subtitle: const Text('NN 31/2025'),
            onTap: () {
              // TODO: open NN link
            },
          ),

          const Divider(indent: 16, endIndent: 16),

          // About
          _SectionHeader(title: 'O aplikaciji'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Disclaimer'),
            onTap: () {
              // TODO: show disclaimer
            },
          ),
          ListTile(
            leading: const Icon(Icons.functions_outlined),
            title: const Text('Formula za izračun'),
            onTap: () {
              // TODO: show formula explanation
            },
          ),
          const ListTile(
            leading: Icon(Icons.tag),
            title: Text('Verzija'),
            subtitle: Text('1.0.0'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

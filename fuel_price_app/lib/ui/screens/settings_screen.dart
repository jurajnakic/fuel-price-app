import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fuel_price_app/blocs/settings_cubit.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/ui/widgets/disclaimer_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Postavke')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            children: [
              // --- Display ---
              _SectionHeader(title: 'Prikaz'),
              ..._buildVisibilityTiles(context, state),
              _buildThemeTile(context, state),

              const Divider(indent: 16, endIndent: 16),

              // --- Notifications ---
              _SectionHeader(title: 'Obavijesti'),
              _NotificationToggle(state: state),
              if (state.notificationsEnabled) ...[
                _buildDayTile(context, state),
                _buildHourTile(context, state),
              ],

              const Divider(indent: 16, endIndent: 16),

              // --- Regulatory ---
              _SectionHeader(title: 'Regulativa'),
              _buildRegulationTile(context),

              const Divider(indent: 16, endIndent: 16),

              // --- About ---
              _SectionHeader(title: 'O aplikaciji'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Disclaimer'),
                onTap: () => _showDisclaimerDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.functions_outlined),
                title: const Text('Formula za izračun'),
                onTap: () => _showFormulaDialog(context),
              ),
              const ListTile(
                leading: Icon(Icons.tag),
                title: Text('Verzija'),
                subtitle: Text('2.0.0'),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildVisibilityTiles(BuildContext context, SettingsState state) {
    return FuelType.values.map((ft) {
      final visible = state.fuelVisibility[ft.name] ?? true;
      return CheckboxListTile(
        secondary: const Icon(Icons.visibility_outlined),
        title: Text(ft.displayName),
        value: visible,
        onChanged: (_) {
          context.read<SettingsCubit>().toggleFuelVisibility(ft.name);
          // Reload fuel list to reflect changes
          context.read<FuelListCubit>().load();
        },
      );
    }).toList();
  }

  Widget _buildThemeTile(BuildContext context, SettingsState state) {
    final label = switch (state.themeMode) {
      ThemeMode.system => 'Sustav',
      ThemeMode.light => 'Svijetla',
      ThemeMode.dark => 'Tamna',
    };

    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Tema'),
      subtitle: Text(label),
      onTap: () async {
        final selected = await showDialog<ThemeMode>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Odaberite temu'),
            children: [
              _themeOption(ctx, 'Sustav', ThemeMode.system),
              _themeOption(ctx, 'Svijetla', ThemeMode.light),
              _themeOption(ctx, 'Tamna', ThemeMode.dark),
            ],
          ),
        );
        if (selected != null && context.mounted) {
          context.read<SettingsCubit>().setThemeMode(selected);
        }
      },
    );
  }

  Widget _themeOption(BuildContext context, String label, ThemeMode mode) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, mode),
      child: Text(label),
    );
  }

  Widget _buildDayTile(BuildContext context, SettingsState state) {
    final dayLabels = {
      'saturday': 'Subota',
      'sunday': 'Nedjelja',
      'monday': 'Ponedjeljak',
    };

    return ListTile(
      leading: const Icon(Icons.calendar_today_outlined),
      title: const Text('Dan obavijesti'),
      subtitle: Text(dayLabels[state.notificationDay] ?? state.notificationDay),
      onTap: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Dan obavijesti'),
            children: dayLabels.entries.map((e) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e.key),
                child: Text(e.value),
              );
            }).toList(),
          ),
        );
        if (selected != null && context.mounted) {
          context.read<SettingsCubit>().setNotificationDay(selected);
        }
      },
    );
  }

  Widget _buildHourTile(BuildContext context, SettingsState state) {
    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: const Text('Vrijeme obavijesti'),
      subtitle: Text('${state.notificationHour.toString().padLeft(2, '0')}:00'),
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: state.notificationHour, minute: 0),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            );
          },
        );
        if (time != null && context.mounted) {
          context.read<SettingsCubit>().setNotificationHour(time.hour);
        }
      },
    );
  }

  Widget _buildRegulationTile(BuildContext context) {
    final params = FuelParams.defaultParams;
    return ListTile(
      leading: const Icon(Icons.gavel_outlined),
      title: Text(params.priceRegulation.name),
      subtitle: Text(params.priceRegulation.nnReference),
      onTap: () async {
        final url = params.priceRegulation.nnUrl;
        if (url != null) {
          try {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          } catch (_) {
            // Ignore launch failures
          }
        }
      },
    );
  }

  void _showDisclaimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Napomena'),
        content: const Text(disclaimerText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }

  void _showFormulaDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Formula za izračun'),
        content: const SingleChildScrollView(
          child: Text(
            'Cijena goriva izračunava se prema Uredbi NN 31/2025:\n\n'
            'PC = [Σ(CIF Med × ρ ÷ T) ÷ (n × 1000)] + P\n\n'
            'Maloprodajna cijena = (PC + trošarina) × 1,25\n\n'
            'Gdje je:\n'
            '• CIF Med — cijena nafte na Mediteranu (USD/t)\n'
            '• ρ — gustoća goriva (kg/L)\n'
            '• T — tečaj USD/EUR\n'
            '• n — broj dana u obračunskom razdoblju (14)\n'
            '• P — premija\n'
            '• 1,25 — PDV 25%\n\n'
            'Izvor cijena: Yahoo Finance (BZ=F)\n'
            'Izvor tečaja: HNB API',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zatvori'),
          ),
        ],
      ),
    );
  }
}

class _NotificationToggle extends StatefulWidget {
  final SettingsState state;
  const _NotificationToggle({required this.state});

  @override
  State<_NotificationToggle> createState() => _NotificationToggleState();
}

class _NotificationToggleState extends State<_NotificationToggle> {
  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (!widget.state.notificationsEnabled) return;

    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.areNotificationsEnabled();
      if (granted != true && mounted) {
        // Permission revoked at OS level — turn off our toggle
        context.read<SettingsCubit>().toggleNotifications();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Obavijesti o promjeni cijena'),
      value: widget.state.notificationsEnabled,
      onChanged: (_) => _toggle(),
    );
  }

  Future<void> _toggle() async {
    if (!widget.state.notificationsEnabled) {
      // Turning ON — request permission
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // First try the system dialog
        final granted = await android.requestNotificationsPermission();
        if (granted != true) {
          // System dialog was suppressed (user denied before or revoked in settings)
          // Offer to open app notification settings directly
          if (!mounted) return;
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Obavijesti su isključene'),
              content: const Text(
                'Obavijesti za ovu aplikaciju su isključene na razini uređaja. '
                'Želite li otvoriti postavke za uključivanje?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Ne'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Otvori postavke'),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            // Open app notification settings via Android intent
            const channel = MethodChannel('app.settings');
            try {
              await channel.invokeMethod('openNotificationSettings');
            } catch (_) {
              // Fallback: ignored if channel not set up
            }
          }
          return;
        }
      }
    }
    if (mounted) {
      context.read<SettingsCubit>().toggleNotifications();
    }
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

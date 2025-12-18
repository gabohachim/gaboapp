import 'package:flutter/material.dart';

import '../services/backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _auto = false;
  bool _loading = true;
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await BackupService.isAutoEnabled();
    final last = await BackupService.getLastBackupTime();
    setState(() {
      _auto = v;
      _lastBackup = last;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    try {
      await BackupService.saveListNow();
      final last = await BackupService.getLastBackupTime();
      if (mounted) setState(() => _lastBackup = last);
      _snack('Lista guardada ✅');
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _cargar() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cargar lista'),
            content: const Text('Esto reemplazará tu lista actual. ¿Continuar?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reemplazar')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    try {
      await BackupService.loadList();
      // al cargar, refrescamos también la fecha del último respaldo (por si el usuario guardó desde otro lado)
      final last = await BackupService.getLastBackupTime();
      if (mounted) setState(() => _lastBackup = last);
      _snack('Lista cargada (reemplazada) ✅');
    } catch (e) {
      _snack('No se pudo cargar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.save_alt),
                        title: const Text('Guardar lista'),
                        subtitle: const Text('Crea/actualiza un respaldo local (JSON).'),
                        onTap: _guardar,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.upload_file),
                        title: const Text('Cargar lista'),
                        subtitle: const Text('Reemplaza tu lista por el último respaldo.'),
                        onTap: _cargar,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Último respaldo'),
                    subtitle: Text(_lastBackup == null
                        ? 'Aún no hay respaldo guardado.'
                        : BackupService.formatDateTime(_lastBackup!)),
                  ),
                ),
                const SizedBox(height: 16),

                Card(
                  child: SwitchListTile(
                    value: _auto,
                    onChanged: (v) async {
                      setState(() => _auto = v);
                      await BackupService.setAutoEnabled(v);

                      if (v) {
                        // En automático, hacemos un primer guardado inmediato.
                        try {
                          await BackupService.saveListNow();
                          final last = await BackupService.getLastBackupTime();
                          if (mounted) setState(() => _lastBackup = last);
                          _snack('Guardado automático: ACTIVADO ☁️');
                        } catch (e) {
                          _snack('No se pudo guardar en automático: $e');
                        }
                      } else {
                        _snack('Guardado automático: MANUAL ☁️');
                      }
                    },
                    secondary: Icon(_auto ? Icons.cloud_done : Icons.cloud_off),
                    title: const Text('Guardado automático'),
                    subtitle: Text(_auto
                        ? 'Se respalda solo cuando agregas o borras vinilos (con pequeña espera para evitar guardar muchas veces).'
                        : 'Debes usar “Guardar lista” manualmente.'),
                  ),
                ),
              ],
            ),
    );
  }
}

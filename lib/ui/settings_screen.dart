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
  bool _cloudOk = false;
  DateTime? _lastCloud;
  String? _driveEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await BackupService.isAutoEnabled();
    final last = await BackupService.getLastBackupTime();
    final cloudOk = await BackupService.getLastCloudOk();
    final lastCloud = await BackupService.getLastCloudTime();
    final email = await BackupService.getDriveEmail();
    setState(() {
      _auto = v;
      _lastBackup = last;
      _cloudOk = cloudOk;
      _lastCloud = lastCloud;
      _driveEmail = email;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guardar() async {
    try {
      await BackupService.connectDrive();
      await BackupService.saveListNow();
      final last = await BackupService.getLastBackupTime();
      final cloudOk = await BackupService.getLastCloudOk();
      final lastCloud = await BackupService.getLastCloudTime();
      final email = await BackupService.getDriveEmail();
      if (mounted) setState(() => _lastBackup = last);
      if (mounted) {
        setState(() {
          _cloudOk = cloudOk;
          _lastCloud = lastCloud;
          _driveEmail = email;
        });
      }
      _snack(cloudOk ? 'Lista guardada en Google Drive ✅' : 'Lista guardada (solo local) ✅');
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
      await BackupService.connectDrive();
      await BackupService.loadList();
      // al cargar, refrescamos también la fecha del último respaldo (por si el usuario guardó desde otro lado)
      final last = await BackupService.getLastBackupTime();
      final cloudOk = await BackupService.getLastCloudOk();
      final lastCloud = await BackupService.getLastCloudTime();
      final email = await BackupService.getDriveEmail();
      if (mounted) setState(() => _lastBackup = last);
      if (mounted) {
        setState(() {
          _cloudOk = cloudOk;
          _lastCloud = lastCloud;
          _driveEmail = email;
        });
      }
      _snack('Lista cargada (reemplazada) ✅');
    } catch (e) {
      _snack('No se pudo cargar: $e');
    }
  }

  Future<void> _conectar() async {
    try {
      await BackupService.connectDrive();
      final email = await BackupService.getDriveEmail();
      if (mounted) setState(() => _driveEmail = email);
      _snack('Conectado a Google Drive ✅');
    } catch (e) {
      _snack('No se pudo conectar: $e');
    }
  }

  Future<void> _desconectar() async {
    try {
      await BackupService.disconnectDrive();
      if (mounted) setState(() => _driveEmail = null);
      _snack('Desconectado de Google Drive');
    } catch (e) {
      _snack('No se pudo desconectar: $e');
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
                        leading: const Icon(Icons.cloud_upload),
                        title: const Text('Guardar lista'),
                        subtitle: const Text('Crea/actualiza un respaldo en Google Drive (privado de la app).'),
                        onTap: _guardar,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.cloud_download),
                        title: const Text('Cargar lista'),
                        subtitle: const Text('Trae el respaldo de Google Drive y reemplaza tu lista.'),
                        onTap: _cargar,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.account_circle),
                        title: const Text('Google Drive'),
                        subtitle: Text(_driveEmail == null ? 'No conectado' : 'Conectado: $_driveEmail'),
                        trailing: _driveEmail == null
                            ? TextButton(onPressed: _conectar, child: const Text('Conectar'))
                            : TextButton(onPressed: _desconectar, child: const Text('Desconectar')),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(_cloudOk ? Icons.verified : Icons.warning_amber_rounded),
                        title: const Text('Estado de Drive'),
                        subtitle: Text(_lastCloud == null
                            ? 'Sin sincronizaciones aún.'
                            : '${_cloudOk ? 'Última sync OK' : 'Última sync falló'}: ${BackupService.formatDateTime(_lastCloud!)}'),
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
                          await BackupService.connectDrive();
                          await BackupService.saveListNow();
                          final last = await BackupService.getLastBackupTime();
                          final cloudOk = await BackupService.getLastCloudOk();
                          final lastCloud = await BackupService.getLastCloudTime();
                          final email = await BackupService.getDriveEmail();
                          if (mounted) setState(() => _lastBackup = last);
                          if (mounted) {
                            setState(() {
                              _cloudOk = cloudOk;
                              _lastCloud = lastCloud;
                              _driveEmail = email;
                            });
                          }
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

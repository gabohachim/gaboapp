import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/vinyl_db.dart';

class BackupService {
  static const _kAuto = 'auto_backup_enabled';
  static const _kLast = 'last_backup_epoch_ms';
  static const _kFile = 'vinyl_backup.json';

  static Future<bool> isAutoEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAuto) ?? false;
  }

  static Future<void> setAutoEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, value);
  }

  static Future<File> _backupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _kFile));
  }

  /// Guarda la lista completa (toda la DB) a un JSON local.
  static Future<void> saveListNow() async {
    final vinyls = await VinylDb.instance.getAll();
    // Guardamos solo los campos que sabemos restaurar
    final payload = vinyls
        .map((v) => <String, dynamic>{
              'numero': v['numero'],
              'artista': v['artista'],
              'album': v['album'],
              'year': v['year'],
              'genre': v['genre'],
              'country': v['country'],
              'artistBio': v['artistBio'],
              'coverPath': v['coverPath'],
              'mbid': v['mbid'],
            })
        .toList();

    final f = await _backupFile();
    await f.writeAsString(jsonEncode(payload));
  }

  /// Carga la lista desde el JSON local y reemplaza la DB completa.
  static Future<void> loadList() async {
    final f = await _backupFile();
    if (!await f.exists()) {
      throw Exception('No existe un respaldo aún.');
    }
    final raw = await f.readAsString();
    final data = jsonDecode(raw);
    if (data is! List) throw Exception('Respaldo inválido.');

    final vinyls = data.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    await VinylDb.instance.replaceAll(vinyls);
  }


  static Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLast);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static String formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  static Timer? _autoTimer;

  /// En modo automático, programa un guardado con debounce para no escribir el archivo muchas veces seguidas.
  static Future<void> queueAutoSave({Duration delay = const Duration(seconds: 2)}) async {
    final on = await isAutoEnabled();
    if (!on) return;

    _autoTimer?.cancel();
    _autoTimer = Timer(delay, () async {
      try {
        await saveListNow();
      } catch (_) {
        // silencioso: el UI mostrará estado solo cuando el usuario guarde/cargue manualmente
      }
    });
  }

  /// Si el modo automático está activo, guarda.
  static Future<void> autoSaveIfEnabled() async {
    final on = await isAutoEnabled();
    if (on) {
      await saveListNow();
    }
  }
}

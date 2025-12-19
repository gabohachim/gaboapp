import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Backup a Google Drive usando el *appDataFolder* (privado para la app).
///
/// - Guarda/lee un solo archivo: `vinyl_backup.json`
/// - Requiere que el usuario inicie sesión con Google.
/// - Requiere habilitar Drive API en Google Cloud + OAuth (ver README).
class DriveBackupService {
  DriveBackupService._();

  static const String backupFileName = 'vinyl_backup.json';

  static final GoogleSignIn _signIn = GoogleSignIn(
    scopes: <String>[drive.DriveApi.driveAppdataScope],
  );

  static GoogleSignInAccount? get currentUser => _signIn.currentUser;

  static Future<GoogleSignInAccount?> ensureSignedIn({bool interactiveIfNeeded = true}) async {
    // 1) intenta silencioso
    final silent = await _signIn.signInSilently();
    if (silent != null) return silent;
    if (!interactiveIfNeeded) return null;

    // 2) interactivo
    return _signIn.signIn();
  }

  static Future<void> signOut() => _signIn.signOut();

  static Future<drive.DriveApi> _driveApi() async {
    final user = await ensureSignedIn(interactiveIfNeeded: true);
    if (user == null) {
      throw Exception('Debes iniciar sesión con Google para usar Drive.');
    }

    final headers = await user.authHeaders;
    final client = _GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  static Future<String?> _findBackupFileId(drive.DriveApi api) async {
    // Buscar SOLO dentro de appDataFolder
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$backupFileName' and trashed=false",
      $fields: 'files(id,name,modifiedTime)',
      pageSize: 10,
    );
    final files = list.files ?? const <drive.File>[];
    if (files.isEmpty) return null;
    return files.first.id;
  }

  static Future<DateTime?> getBackupModifiedTime() async {
    final api = await _driveApi();
    final id = await _findBackupFileId(api);
    if (id == null) return null;
    final f = await api.files.get(id, $fields: 'modifiedTime') as drive.File;
    return f.modifiedTime;
  }

  /// Sube el JSON a Drive (appDataFolder). Crea o actualiza el archivo.
  static Future<DateTime> uploadJson(String json) async {
    final api = await _driveApi();
    final id = await _findBackupFileId(api);

    final bytes = Uint8List.fromList(utf8.encode(json));
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);

    if (id == null) {
      final meta = drive.File()
        ..name = backupFileName
        ..parents = <String>['appDataFolder']
        ..mimeType = 'application/json';
      final created = await api.files.create(meta, uploadMedia: media, $fields: 'id,modifiedTime');
      return created.modifiedTime ?? DateTime.now();
    } else {
      final meta = drive.File()..mimeType = 'application/json';
      final updated = await api.files.update(meta, id, uploadMedia: media, $fields: 'modifiedTime');
      return updated.modifiedTime ?? DateTime.now();
    }
  }

  /// Descarga el JSON desde Drive (appDataFolder).
  static Future<String> downloadJson() async {
    final api = await _driveApi();
    final id = await _findBackupFileId(api);
    if (id == null) {
      throw Exception('No hay respaldo en Google Drive todavía.');
    }

    final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final chunks = <int>[];
    await for (final c in media.stream) {
      chunks.addAll(c);
    }
    return utf8.decode(chunks);
  }
}

/// Cliente HTTP que inyecta los headers OAuth.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

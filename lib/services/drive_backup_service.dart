import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DriveBackupService {
  static const String _backupFileName = 'vinyl_backup.json';
  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize(scopes: _scopes);
    _initialized = true;
  }

  static Future<GoogleSignInAccount?> signInInteractive() async {
    await _ensureInitialized();
    return _googleSignIn.authenticate();
  }

  static Future<GoogleSignInAccount?> signInSilentlyOrNull() async {
    await _ensureInitialized();
    try {
      return await _googleSignIn.attemptLightweightAuthentication();
    } catch (_) {
      return null;
    }
  }

  static Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
  }

  static Future<String?> _getAccessToken(GoogleSignInAccount user) async {
    await _ensureInitialized();

    // Try to reuse existing authorization
    final auth = await user.authorizationClient.authorizationForScopes(_scopes);
    if (auth != null && auth.accessToken.isNotEmpty) return auth.accessToken;

    // Request scopes if not yet granted
    final ok = await user.authorizationClient.authorizeScopes(_scopes);
    if (!ok) return null;

    final auth2 = await user.authorizationClient.authorizationForScopes(_scopes);
    if (auth2 == null || auth2.accessToken.isEmpty) return null;

    return auth2.accessToken;
  }

  static Future<File> _localBackupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_backupFileName');
  }

  static Future<void> saveLocalAndUploadToDrive({
    required Map<String, dynamic> data,
  }) async {
    // 1) Save locally
    final file = await _localBackupFile();
    await file.writeAsString(jsonEncode(data));

    // 2) Upload to Drive (appDataFolder)
    final user = await signInSilentlyOrNull() ?? await signInInteractive();
    if (user == null) throw Exception('No se pudo iniciar sesión en Google.');

    final token = await _getAccessToken(user);
    if (token == null) throw Exception('No se pudo obtener token de Google Drive.');

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
    };

    // Find existing file in appDataFolder
    final q = Uri.encodeQueryComponent("name='$_backupFileName'");
    final listUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?spaces=appDataFolder&q=$q&fields=files(id,name)',
    );

    final listRes = await http.get(listUrl, headers: headers);
    if (listRes.statusCode >= 400) {
      throw Exception('Error listando Drive: ${listRes.statusCode} ${listRes.body}');
    }

    final files = (jsonDecode(listRes.body)['files'] as List?) ?? <dynamic>[];
    final existingId = files.isNotEmpty ? files.first['id'] as String? : null;

    final uploadMeta = {
      'name': _backupFileName,
      'parents': ['appDataFolder'],
    };

    final boundary = '----gaboLPBoundary${DateTime.now().millisecondsSinceEpoch}';
    final multipartHeaders = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'multipart/related; boundary=$boundary',
    };

    final metadataPart = jsonEncode(uploadMeta);
    final fileBytes = await file.readAsBytes();

    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode('$metadataPart\r\n'))
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json\r\n\r\n'))
      ..add(fileBytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final uploadUrl = existingId == null
        ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart')
        : Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$existingId'
            '?uploadType=multipart',
          );

    final uploadRes = existingId == null
        ? await http.post(uploadUrl, headers: multipartHeaders, body: body.toBytes())
        : await http.patch(uploadUrl, headers: multipartHeaders, body: body.toBytes());

    if (uploadRes.statusCode >= 400) {
      throw Exception('Error subiendo a Drive: ${uploadRes.statusCode} ${uploadRes.body}');
    }
  }

  static Future<Map<String, dynamic>> downloadFromDriveAndLoadLocal() async {
    final user = await signInSilentlyOrNull() ?? await signInInteractive();
    if (user == null) throw Exception('No se pudo iniciar sesión en Google.');

    final token = await _getAccessToken(user);
    if (token == null) throw Exception('No se pudo obtener token de Google Drive.');

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
    };

    final q = Uri.encodeQueryComponent("name='$_backupFileName'");
    final listUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?spaces=appDataFolder&q=$q&fields=files(id,name)',
    );

    final listRes = await http.get(listUrl, headers: headers);
    if (listRes.statusCode >= 400) {
      throw Exception('Error listando Drive: ${listRes.statusCode} ${listRes.body}');
    }

    final files = (jsonDecode(listRes.body)['files'] as List?) ?? <dynamic>[];
    if (files.isEmpty) throw Exception('No hay respaldo en Drive todavía.');

    final fileId = files.first['id'] as String;

    final downloadUrl = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final dlRes = await http.get(downloadUrl, headers: headers);
    if (dlRes.statusCode >= 400) {
      throw Exception('Error descargando Drive: ${dlRes.statusCode} ${dlRes.body}');
    }

    final decoded = jsonDecode(dlRes.body) as Map<String, dynamic>;

    // Save locally too
    final file = await _localBackupFile();
    await file.writeAsString(jsonEncode(decoded));

    return decoded;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DriveBackupService {
  static const String backupFileName = 'vinyl_backup.json';

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

  static Future<String?> _accessToken(GoogleSignInAccount user) async {
    await _ensureInitialized();

    final auth = await user.authorizationClient.authorizationForScopes(_scopes);
    if (auth != null && auth.accessToken.isNotEmpty) return auth.accessToken;

    final ok = await user.authorizationClient.authorizeScopes(_scopes);
    if (!ok) return null;

    final auth2 = await user.authorizationClient.authorizationForScopes(_scopes);
    if (auth2 == null || auth2.accessToken.isEmpty) return null;

    return auth2.accessToken;
  }

  static Future<File> _localBackupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$backupFileName');
  }

  /// Guarda local + sube a Google Drive (appDataFolder).
  static Future<void> saveLocalAndUpload({
    required Map<String, dynamic> data,
  }) async {
    // 1) Guardar local
    final local = await _localBackupFile();
    await local.writeAsString(jsonEncode(data));

    // 2) Login
    final user = await signInSilentlyOrNull() ?? await signInInteractive();
    if (user == null) throw Exception('No se pudo iniciar sesión en Google.');

    final token = await _accessToken(user);
    if (token == null) throw Exception('No se pudo obtener token de Google Drive.');

    final headers = <String, String>{'Authorization': 'Bearer $token'};

    // 3) Buscar si existe archivo en appDataFolder
    final q = Uri.encodeQueryComponent("name='$backupFileName'");
    final listUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,name)',
    );
    final listRes = await http.get(listUrl, headers: headers);
    if (listRes.statusCode >= 400) {
      throw Exception('Error listando Drive: ${listRes.statusCode} ${listRes.body}');
    }

    final files = (jsonDecode(listRes.body)['files'] as List?) ?? <dynamic>[];
    final existingId = files.isNotEmpty ? files.first['id'] as String? : null;

    // 4) Subir (multipart/related)
    final meta = <String, dynamic>{
      'name': backupFileName,
      'parents': ['appDataFolder'],
    };

    final boundary = '----gaboBoundary${DateTime.now().millisecondsSinceEpoch}';
    final uploadHeaders = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'multipart/related; boundary=$boundary',
    };

    final metaPart = jsonEncode(meta);
    final fileBytes = await local.readAsBytes();

    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode('$metaPart\r\n'))
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json\r\n\r\n'))
      ..add(fileBytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final uploadUrl = existingId == null
        ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart')
        : Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$existingId?uploadType=multipart',
          );

    final uploadRes = existingId == null
        ? await http.post(uploadUrl, headers: uploadHeaders, body: body.toBytes())
        : await http.patch(uploadUrl, headers: uploadHeaders, body: body.toBytes());

    if (uploadRes.statusCode >= 400) {
      throw Exception('Error subiendo a Drive: ${uploadRes.statusCode} ${uploadRes.body}');
    }
  }

  /// Descarga desde Drive y devuelve el JSON (también lo guarda local).
  static Future<Map<String, dynamic>> downloadAndLoad() async {
    final user = await signInSilentlyOrNull() ?? await signInInteractive();
    if (user == null) throw Exception('No se pudo iniciar sesión en Google.');

    final token = await _accessToken(user);
    if (token == null) throw Exception('No se pudo obtener token de Google Drive.');

    final headers = <String, String>{'Authorization': 'Bearer $token'};

    final q = Uri.encodeQueryComponent("name='$backupFileName'");
    final listUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,name)',
    );
    final listRes = await http.get(listUrl, headers: headers);
    if (listRes.statusCode >= 400) {
      throw Exception('Error listando Drive: ${listRes.statusCode} ${listRes.body}');
    }

    final files = (jsonDecode(listRes.body)['files'] as List?) ?? <dynamic>[];
    if (files.isEmpty) throw Exception('No hay respaldo en Drive todavía.');

    final fileId = files.first['id'] as String;

    final dlUrl = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final dlRes = await http.get(dlUrl, headers: headers);
    if (dlRes.statusCode >= 400) {
      throw Exception('Error descargando Drive: ${dlRes.statusCode} ${dlRes.body}');
    }

    final decoded = jsonDecode(dlRes.body) as Map<String, dynamic>;

    // Guardar local también
    final local = await _localBackupFile();
    await local.writeAsString(jsonEncode(decoded));

    return decoded;
  }
}

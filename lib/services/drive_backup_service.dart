import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class DriveBackupService {
  static const String backupFileName = 'vinyl_backup.json';

  // Scope recomendado para respaldos ocultos en Drive (appDataFolder).
  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static final GoogleSignIn _signIn = GoogleSignIn.instance;

  static bool _initialized = false;
  static GoogleSignInAccount? _currentUser;

  static GoogleSignInAccount? get currentUser => _currentUser;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // En google_sign_in v7+ NO se pasan scopes aquí.
    // La autorización de scopes se hace con authorizationClient.
    await _signIn.initialize();

    // Guardar usuario actual vía eventos.
    _signIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _currentUser = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _currentUser = null;
      }
    });

    _initialized = true;
  }

  /// Intenta “silencioso” primero; si no, devuelve null.
  static Future<GoogleSignInAccount?> _tryLightweight() async {
    await _ensureInitialized();
    try {
      return await _signIn.attemptLightweightAuthentication();
    } catch (_) {
      return null;
    }
  }

  /// Login interactivo (botón/acción usuario).
  static Future<GoogleSignInAccount?> _interactive() async {
    await _ensureInitialized();
    return await _signIn.authenticate();
  }

  /// Lo que tu backup_service.dart espera.
  static Future<GoogleSignInAccount?> ensureSignedIn({
    required bool interactiveIfNeeded,
  }) async {
    final u1 = _currentUser ?? await _tryLightweight();
    if (u1 != null) {
      _currentUser = u1;
      return u1;
    }
    if (!interactiveIfNeeded) return null;

    final u2 = await _interactive();
    _currentUser = u2;
    return u2;
  }

  static Future<void> signOut() async {
    await _ensureInitialized();
    await _signIn.signOut();
    _currentUser = null;
  }

  static Future<String> _getAccessToken(GoogleSignInAccount user) async {
    // 1) Si ya está autorizado, devuelve token.
    final existing = await user.authorizationClient.authorizationForScopes(_scopes);
    if (existing != null && existing.accessToken.isNotEmpty) {
      return existing.accessToken;
    }

    // 2) Si no, pide autorización (esto devuelve un objeto, NO bool).
    final granted = await user.authorizationClient.authorizeScopes(_scopes);
    if (granted.accessToken.isNotEmpty) {
      return granted.accessToken;
    }

    throw Exception('No se pudo obtener access token para Drive.');
  }

  static Future<String?> _findBackupFileId(String token) async {
    final headers = <String, String>{'Authorization': 'Bearer $token'};

    final q = Uri.encodeQueryComponent("name='$backupFileName'");
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?spaces=appDataFolder'
      '&q=$q'
      '&fields=files(id,name,modifiedTime)',
    );

    final res = await http.get(url, headers: headers);
    if (res.statusCode >= 400) {
      throw Exception('Drive list error: ${res.statusCode} ${res.body}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final files = (body['files'] as List?) ?? <dynamic>[];
    if (files.isEmpty) return null;

    return files.first['id'] as String?;
  }

  /// Lo que tu backup_service.dart espera:
  /// Sube JSON y devuelve DateTime? (modifiedTime en Drive).
  static Future<DateTime?> uploadJson(String json) async {
    final user = await ensureSignedIn(interactiveIfNeeded: true);
    if (user == null) throw Exception('No se pudo iniciar sesión en Google.');

    final token = await _getAccessToken(user);

    final existingId = await _findBackupFileId(token);

    final boundary = '----gaboBoundary${DateTime.now().millisecondsSinceEpoch}';
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'multipart/related; boundary=$boundary',
    };

    final meta = jsonEncode(<String, dynamic>{
      'name': backupFileName,
      'parents': ['appDataFolder'],
    });

    final bytes = Uint8List.fromList(utf8.encode(json));

    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode('$meta\r\n'))
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final uploadUrl = existingId == null
        ? Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=modifiedTime')
        : Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$existingId?uploadType=multipart&fields=modifiedTime');

    final res = existingId == null
        ? await http.post(uploadUrl, headers: headers, body: body.toBytes())
        : await http.patch(uploadUrl, headers: headers, body: body.toBytes());

    if (res.statusCode >= 400) {
      throw Exception('Drive upload error: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final mt = data['modifiedTime'] as String?;
    return mt == null ? null : DateTime.tryParse(mt);
  }

  /// Lo que tu backup_service.dart espera:
  /// Descarga el JSON desde appDataFolder (si no existe, lanza error).
  static Future<String> downloadJson() async {
    final user = await ensureSignedIn(interactiveIfNeeded: true);
    if (user == null) throw Exception('No se pudo iniciar sesión en Google.');

    final token = await _getAccessToken(user);

    final fileId = await _findBackupFileId(token);
    if (fileId == null) {
      throw Exception('No hay respaldo en Drive todavía.');
    }

    final headers = <String, String>{'Authorization': 'Bearer $token'};
    final url = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');

    final res = await http.get(url, headers: headers);
    if (res.statusCode >= 400) {
      throw Exception('Drive download error: ${res.statusCode} ${res.body}');
    }

    return res.body;
  }

  /// Lo que tu backup_service.dart espera:
  static Future<DateTime?> getBackupModifiedTime() async {
    final user = await ensureSignedIn(interactiveIfNeeded: false);
    if (user == null) return null;

    final token = await _getAccessToken(user);

    final headers = <String, String>{'Authorization': 'Bearer $token'};
    final q = Uri.encodeQueryComponent("name='$backupFileName'");
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?spaces=appDataFolder'
      '&q=$q'
      '&fields=files(modifiedTime)',
    );

    final res = await http.get(url, headers: headers);
    if (res.statusCode >= 400) return null;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final files = (body['files'] as List?) ?? <dynamic>[];
    if (files.isEmpty) return null;

    final mt = files.first['modifiedTime'] as String?;
    return mt == null ? null : DateTime.tryParse(mt);
  }
}

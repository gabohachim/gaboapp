# GaBoLP (Colección de vinilos)

Proyecto Flutter para mantener tu lista de vinilos y (ahora) **respaldarla en Google Drive**.

## Respaldo en Google Drive (para no perder la lista)

La app guarda un archivo llamado **`vinyl_backup.json`** en el **`appDataFolder`** de Google Drive.
Ese espacio es **privado para la app** (no aparece como archivo normal en “Mi unidad”).

### 1) Habilitar Drive API + OAuth en Google Cloud

1. Crea (o usa) un proyecto en Google Cloud Console.
2. Activa **Google Drive API**.
3. Crea credenciales OAuth:
   - Tipo: **Android**
   - `packageName`: el de tu app (ej: `com.tuempresa.gabolp`)
   - SHA-1: el de tu firma (debug o release)

> Si no tienes el SHA-1 a mano: en Android Studio/terminal puedes sacarlo con `./gradlew signingReport`.

### 2) Configurar Google Sign-In en Android (Flutter)

En tu proyecto Flutter, asegúrate de tener la carpeta `android/` y configurar el `applicationId` en:

`android/app/build.gradle`

Luego sigue la guía oficial de Flutter para Google APIs (Google Sign-In, OAuth, etc.).

Referencia:
- Documentación de Flutter “Google APIs” (docs.flutter.dev)

### 3) Uso dentro de la app

En **Ajustes**:
- **Guardar lista** → sube el respaldo a Drive.
- **Cargar lista** → descarga de Drive y **reemplaza** la lista local.
- **Guardado automático** → sube a Drive al agregar/borrar vinilos (con debounce para no subir mil veces).

## Paquetes usados

- `google_sign_in`
- `googleapis` (Drive v3)

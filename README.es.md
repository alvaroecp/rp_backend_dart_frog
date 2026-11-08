# rp_backend_dart_frog

## Descripción general

Backend de un *Relying Party* (RP) hecho con [Dart Frog](https://dart-frog.dev). Permite que una aplicación de escritorio en Flutter (en adelante la **APP**) inicie sesión con eSignet 2.0.0 (OpenID Connect).

Actores:

- **APP**: la aplicación de escritorio en Flutter. Es quien usa la API de este proyecto.
- **BACKEND**: este proyecto. Es el RP frente a eSignet y el servidor frente a la APP.
- **NAVEGADOR**: el navegador web del sistema, donde el USUARIO se autentica en eSignet.
- **USUARIO**: la persona que inicia sesión.
- **eSignet**: el proveedor de identidad (servidor OpenID Connect).

Cómo funciona:

- El BACKEND actúa como cliente confidencial: hace todo el protocolo con eSignet (código de autorización con PKCE y autenticación del cliente con `private_key_jwt`).
- La APP nunca ve la clave privada ni los tokens de eSignet. Recibe del BACKEND un `app_token` propio, opaco, que vale 30 minutos y no se renueva.
- El inicio de sesión funciona por ticket: la APP pide un ticket al BACKEND y abre el NAVEGADOR. Mientras tanto, consulta el estado al BACKEND hasta recibir el `app_token`.
- El USUARIO se autentica directamente en eSignet, a través del NAVEGADOR: ni la APP ni el BACKEND ven sus credenciales.
- Todo el estado (tickets, transacciones de login y sesiones) vive en la memoria del BACKEND: reiniciarlo cierra todas las sesiones.

**Estado.** Proyecto de aprendizaje. Funciona de punta a punta con la APP en Windows. Limitaciones conocidas: **no verifica las firmas** del `id_token` ni del `userinfo`, no tiene pruebas automáticas propias y no añade cabeceras de seguridad ni límite de peticiones.

## API

URL base del BACKEND: `http://localhost:3005`. Las respuestas de `/api/*` son JSON.

| Método y ruta | Quién | Autenticación | Respuesta correcta | Errores |
| --- | --- | --- | --- | --- |
| `POST /api/login/start` | APP | Ninguna | `200` con `ticket`, `poll_secret`, `login_url`, `expires_in` e `interval` | `429` `too_many_pending_logins` |
| `GET /app/login?ticket=…` | NAVEGADOR | Ninguna | `302` a eSignet | `400` (texto): ticket caducado, ya usado o inexistente; `502` |
| `GET /callback` | NAVEGADOR | Cookie del NAVEGADOR | `200` (página): "¡Autenticación Exitosa!" | `400`; `502` si falla el canje |
| `GET /api/login/status?ticket=…` | APP | Cabecera `X-Poll-Secret` | `200` con `status` (`pending`, `complete` o `error`) | `403`, `404`, `410` |
| `GET /api/me` | APP | `Authorization: Bearer <app_token>` | `200` con el perfil | `401` |
| `POST /api/logout` | APP | `Authorization: Bearer <app_token>` | `204` | — |
| `GET /health` | Cualquiera | Ninguna | `200` | — |

La APP solo usa `start`, `status`, `me` y `logout`. `/app/login` y `/callback` los recorre el NAVEGADOR: la APP se limita a abrir el `login_url` que devuelve `start`.

Reglas:

- El ticket vale 300 s y sirve para un solo inicio de sesión.
- El resultado de `status` (`complete` o `error`) se entrega una sola vez: la consulta siguiente da `404`.
- Un ticket cuyo resultado se recoge pasados 300 s desde su creación da `410`, aunque el login ya estuviera completado. El sondeo cada 2 s lo evita en la práctica.
- La sesión vale 1800 s. Cuando `me` responde `401`, la APP debe pedir al USUARIO que inicie sesión otra vez.
- `auth_time` y `session_expires_at` viajan en segundos desde 1970.
- El campo `picture` del perfil llega como una imagen en línea (`data:image/jpeg;base64,…`), no como una URL.
- Un método no permitido da `405`.

Ejemplos:

`POST /api/login/start` → `200`:

```json
{
  "ticket": "…",
  "poll_secret": "…",
  "login_url": "http://localhost:3005/app/login?ticket=…",
  "expires_in": 300,
  "interval": 2
}
```

`GET /api/login/status` → `200`, según el estado:

```json
{ "status": "pending", "expires_in": 241 }
{ "status": "complete", "app_token": "…", "expires_in": 1800 }
{ "status": "error", "error": "texto técnico con el motivo" }
```

`GET /api/me` → `200`:

```json
{
  "profile": { "sub": "…", "name": "…", "email": "…", "picture": "data:image/jpeg;base64,…" },
  "sub": "…",
  "acr": "mosip:idp:acr:generated-code",
  "auth_time": 1700000000,
  "session_expires_at": 1700001800
}
```

## Cómo ejecutarlo

Requisitos:

- [Dart SDK](https://dart.dev/get-dart) 3.13 o superior y el CLI de Dart Frog (`dart pub global activate dart_frog_cli`).
- eSignet 2.0.0 en marcha, con un cliente registrado cuya clave pública corresponda a la clave privada (JWK) que usará el BACKEND.
- Un archivo `rp.env` y la clave privada (JWK) del cliente, ambos **fuera del proyecto**, para que nunca lleguen a git.

Configuración: el BACKEND lee `~/rp-app/rp.env`, o el archivo cuya ruta esté en la variable de entorno `RP_ENV`. Las variables de entorno mandan sobre el archivo. Un `rp.env` mínimo:

```env
CLIENT_ID=demo-rp-app
REDIRECT_URI=http://localhost:3005/callback
PRIVATE_JWK_PATH=/home/<usuario>/rp-app/client-private.jwk
ISSUER=http://localhost:8080
ALLOW_INSECURE_ISSUER=true
```

- `REDIRECT_URI` debe ser la registrada en eSignet. Su puerto es en el que debe escuchar el BACKEND.
- `ALLOW_INSECURE_ISSUER=true` es obligatorio con un emisor `http`, lo cual solo es aceptable en local. En producción el emisor debe ser `https`.
- Si no se define `PRIVATE_JWK_PATH`, el BACKEND busca `~/rp-app/client-private.jwk`.

Arráncalo desde la carpeta del proyecto:

```bash
dart pub get
dart_frog dev --port 3005
```

Usa `--port 3005`: `dart_frog dev` escucha por defecto en el 8080, que es el puerto de eSignet. El puerto debe coincidir con `REDIRECT_URI`, y solo un proceso puede usarlo.

Comprueba que está en marcha:

```bash
curl http://localhost:3005/health
```

Debe responder `{"status":"ok","service":"rp-backend-dartfrog"}`.

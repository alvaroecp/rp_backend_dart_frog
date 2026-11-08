# rp_backend_dart_frog

## Overview

Backend of a *Relying Party* (RP) built with [Dart Frog](https://dart-frog.dev). It lets a Flutter desktop application (hereafter the **APP**) sign in with eSignet 2.0.0 (OpenID Connect).

Actors:

- **APP**: the Flutter desktop application. It is the one that uses this project's API.
- **BACKEND**: this project. It is the RP towards eSignet and the server towards the APP.
- **BROWSER**: the system's web browser, where the USER authenticates with eSignet.
- **USER**: the person who signs in.
- **eSignet**: the identity provider (OpenID Connect server).

How it works:

- The BACKEND acts as a confidential client: it performs the whole protocol with eSignet (authorization code flow with PKCE and client authentication with `private_key_jwt`).
- The APP never sees the private key or the eSignet tokens. It receives from the BACKEND its own opaque `app_token`, which is valid for 30 minutes and is not renewed.
- Sign-in works with a ticket: the APP asks the BACKEND for a ticket and opens the BROWSER. Meanwhile, it polls the BACKEND for the status until it receives the `app_token`.
- The USER authenticates directly with eSignet, through the BROWSER: neither the APP nor the BACKEND sees the USER's credentials.
- All state (tickets, login transactions and sessions) lives in the BACKEND's memory: restarting it ends all sessions.

**Status.** Learning project. It works end to end with the APP on Windows. Known limitations: it **does not verify the signatures** of the `id_token` or the `userinfo`, it has no automated tests of its own, and it adds no security headers or rate limiting.

## API

Base URL of the BACKEND: `http://localhost:3005`. The responses of `/api/*` are JSON.

| Method and path | Who | Authentication | Success response | Errors |
| --- | --- | --- | --- | --- |
| `POST /api/login/start` | APP | None | `200` with `ticket`, `poll_secret`, `login_url`, `expires_in` and `interval` | `429` `too_many_pending_logins` |
| `GET /app/login?ticket=…` | BROWSER | None | `302` to eSignet | `400` (text): ticket expired, already used or nonexistent; `502` |
| `GET /callback` | BROWSER | BROWSER cookie | `200` (page): "¡Autenticación Exitosa!" | `400`; `502` if the code exchange fails |
| `GET /api/login/status?ticket=…` | APP | `X-Poll-Secret` header | `200` with `status` (`pending`, `complete` or `error`) | `403`, `404`, `410` |
| `GET /api/me` | APP | `Authorization: Bearer <app_token>` | `200` with the profile | `401` |
| `POST /api/logout` | APP | `Authorization: Bearer <app_token>` | `204` | — |
| `GET /health` | Anyone | None | `200` | — |

The APP only uses `start`, `status`, `me` and `logout`. `/app/login` and `/callback` are visited by the BROWSER: the APP just opens the `login_url` returned by `start`.

Rules:

- The ticket is valid for 300 s and can be used for a single sign-in.
- The result of `status` (`complete` or `error`) is delivered only once: the next request returns `404`.
- A ticket whose result is collected more than 300 s after its creation returns `410`, even if the login had already completed. Polling every 2 s avoids this in practice.
- The session is valid for 1800 s. When `me` responds `401`, the APP must ask the USER to sign in again.
- `auth_time` and `session_expires_at` are in seconds since 1970.
- The `picture` field of the profile arrives as an inline image (`data:image/jpeg;base64,…`), not as a URL.
- A method that is not allowed returns `405`.

Examples:

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

`GET /api/login/status` → `200`, depending on the status:

```json
{ "status": "pending", "expires_in": 241 }
{ "status": "complete", "app_token": "…", "expires_in": 1800 }
{ "status": "error", "error": "technical text with the reason" }
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

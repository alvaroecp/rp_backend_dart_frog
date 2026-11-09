# rp_backend_dart_frog

## Overview

Backend of a *Relying Party* (RP) built with [Dart Frog](https://dart-frog.dev). It lets a Flutter desktop application (hereafter the **APP**) sign in with eSignet 2.0.0 (OpenID Connect).

This RP is made of three repositories:

- [rp_backend_dart_frog](https://github.com/alvaroecp/rp_backend_dart_frog): this one, the BACKEND.
- [rp_frontend_windows_flutter](https://github.com/alvaroecp/rp_frontend_windows_flutter): the APP.
- [esignet_local_docker](https://github.com/alvaroecp/esignet_local_docker): how the local eSignet used for the tests was installed and operated, and how to create the key pair, register the client and create a test person.

Actors:

- **APP**: the Flutter desktop application. It is the one that uses this project's API.
- **BACKEND**: this project. It is the RP towards eSignet and the server towards the APP.
- **BROWSER**: the system's web browser, where the USER authenticates with eSignet.
- **USER**: the person who signs in.
- **eSignet**: the identity provider (OpenID Connect server).

How it works:

- The BACKEND acts as a confidential client: it performs the whole protocol with eSignet (authorization code flow with PKCE and client authentication with `private_key_jwt`).
- By design, the APP does not receive the private key or the eSignet tokens. It receives from the BACKEND its own opaque `app_token`, which is valid for 30 minutes and is not renewed.
- Sign-in works with a ticket: the APP asks the BACKEND for a ticket and opens the BROWSER. Meanwhile, it polls the BACKEND for the status until it receives the `app_token`.
- The USER authenticates directly with eSignet, through the BROWSER: neither the APP nor the BACKEND sees the USER's credentials.
- All state (tickets, login transactions and sessions) lives in the BACKEND's memory: restarting it ends all sessions.

**Status.** Developing project. In the tests it worked end to end with the APP on Windows, but the tests were limited and not exhaustive. See "What is missing for production" below.

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
- A ticket whose result is collected more than 300 s after its creation returns `410`, even if the login had already completed. Polling every 2 s should avoid this in practice.
- The session is valid for 1800 s. When `me` responds `401`, the APP must ask the USER to sign in again.
- `auth_time` and `session_expires_at` are in seconds since 1970.
- In the tests, the `picture` field of the profile arrived as an inline image (`data:image/jpeg;base64,…`), not as a URL.
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

## Running

Requirements:

- [Dart SDK](https://dart.dev/get-dart) 3.13 or later and the Dart Frog CLI (`dart pub global activate dart_frog_cli`).
- A running eSignet 2.0.0, a client registered in it, and the matching private key (JWK). The steps below say how to get them.
- To run the APP, Flutter: see the [APP's README](https://github.com/alvaroecp/rp_frontend_windows_flutter).

Steps, to be done once and in this order:

1. **eSignet.** Install and start it as described in [esignet_local_docker](https://github.com/alvaroecp/esignet_local_docker#installation).
2. **Key pair.** Create it with the commands of [Key pair of a client](https://github.com/alvaroecp/esignet_local_docker#key-pair-of-a-client). They write `client-public.jwk`, which goes into the registration, and `client-private.jwk`, which is the one this BACKEND uses. Keep the private one **outside this project**, for example in `~/rp-app/client-private.jwk`, so it never reaches git.
3. **Client registration.** Follow Client registration, with two changes to its example: redirectUris has to be ["http://localhost:3005/callback"], and clientId is the one you will put in CLIENT_ID (demo-rp-app in the tests). userClaims should include at least name, email and picture.
4. **A test person.** Create one as in [User registration](https://github.com/alvaroecp/esignet_local_docker#user-registration), or use the demo person that the official eSignet guide mentions.
5. **Configuration.** Create `rp.env` (see below).
6. **Start the BACKEND** (see below).
7. **Run the APP** and press its sign-in button. The BROWSER opens eSignet's page: sign in with the UIN of the test person. In the tests, the OTP `111111` worked. After that, the APP shows the profile.

Configuration: the BACKEND reads `~/rp-app/rp.env`, or the file whose path is in the `RP_ENV` environment variable. Environment variables take precedence over the file. The format is `NAME=value`, one per line; lines starting with `#` are comments. A minimal `rp.env`:

```env
CLIENT_ID=demo-rp-app
REDIRECT_URI=http://localhost:3005/callback
PRIVATE_JWK_PATH=/home/<user>/rp-app/client-private.jwk
ISSUER=http://localhost:8080
ALLOW_INSECURE_ISSUER=true
```

| Variable | Default | What it is |
| --- | --- | --- |
| `CLIENT_ID` | required | The client registered in eSignet |
| `REDIRECT_URI` | required | The return address registered in eSignet. Its port is the one the BACKEND has to listen on |
| `PRIVATE_JWK_PATH` | `~/rp-app/client-private.jwk` | The private key, as a JWK with a `kid` |
| `ISSUER` | `http://localhost:8080` | eSignet's issuer |
| `ALLOW_INSECURE_ISSUER` | `false` | Allows an `http` issuer, acceptable only locally. Without it, an `http` issuer is rejected |
| `ASSERTION_ALG` | `PS256` | Algorithm of the client assertion. `RS256` was also accepted by eSignet in the tests |
| `COOKIE_NAME` | `esignet_session_id` | Name of the cookie of the login transaction |
| `PUBLIC_BASE_URL` | `http://localhost:3005` | Base of the `login_url` returned to the APP |

The ticket lifetime (300 s), the session lifetime (1800 s), the polling interval (2 s) and the scope (`openid profile email`) are fixed in the code.

Start the BACKEND from the project folder:

```bash
dart pub get
dart_frog dev --port 3005
```

Use `--port 3005`: `dart_frog dev` listens on 8080 by default, which is eSignet's port. The port has to match `REDIRECT_URI`, and only one process can use it.

Check that it is up:

```bash
curl http://localhost:3005/health
```

It should answer `{"status":"ok","service":"rp-backend-dartfrog"}`.

## Architecture decisions

The reasons below are the ones that guided the design. Some are inferences from the documentation and from the tests, not guarantees.

| Decision | Why | Cost or open point |
| --- | --- | --- |
| The RP is split into two parts: a BACKEND that does the whole protocol, and a desktop APP that does not talk to eSignet directly | eSignet's discovery document lists only `private_key_jwt` as a client authentication method, so the RP needs a private key to sign a client assertion, and a desktop application cannot reliably keep a key secret from whoever installs it. The key stays in the BACKEND; the APP only holds a session token | The BACKEND is an extra process to run, and the APP does not work without it |
| A desktop APP (Flutter, Windows) as the front | It was chosen on purpose, to exercise scenarios that a purely web RP might not show. An Android APP was also in the plans, but it has not been developed yet | A web front was not tried and would apparently need CORS, which the BACKEND does not implement yet |
| Authorization code flow with PKCE (`S256`), `state` and `nonce`, kept in the BACKEND and tied to a BROWSER cookie | eSignet announces `S256` as its only PKCE method. Keeping the verifier, `state` and `nonce` on the server means the APP does not hold what is needed to finish a login | The cookie is basic: `HttpOnly` and `SameSite=Lax`, without `Secure` or `Max-Age` |
| The login happens in the system BROWSER, and eSignet redirects back to the BACKEND (`http://localhost:3005/callback`) | The USER types credentials only in eSignet's page, and a plain `http` return address avoids custom URL schemes in a desktop app | The BROWSER and the APP are not connected: the APP has to find out when the login ends |
| A ticket and a `poll_secret` to connect the BROWSER login with the APP | The `ticket` travels in the BROWSER's address and can only start a login. The `poll_secret`, needed to collect the result, stays with the APP by design | The result is delivered only once. A result collected more than 300 s after the ticket was created returns `410`, even if the login completed in time (known bug) |
| The APP asks for the result by polling (`/api/login/status`), not through a link back to the APP | Polling was chosen because it seemed easier. A link (a custom URL scheme registered with the operating system) was the other option: the page shown after the callback would open the APP. A link would need a registration on Windows and a Flutter plugin | Extra traffic and a delay of up to one polling interval. A link or a push channel was not tried, and could replace or complement the polling later |
| The BACKEND issues its own opaque `app_token` (1800 s) instead of passing eSignet's tokens to the APP | In the tests eSignet's tokens lasted about 120 s and no refresh token was seen, so they do not look suitable as a session. The BACKEND checks the claims once and keeps the profile | The session length is a demo choice, and there is no renewal |
| State kept in memory | The simplest option for a demo: no database to install | One instance only; restarting ends every session |
| The protocol is written by hand, without an OpenID Connect library | An OpenID Connect library for Dart that supports `private_key_jwt`, the only client authentication method listed by eSignet's discovery document, was not confirmed: the documentation of `openid_client` and `oidc_core` does not clearly mention it. They were not tried | More security-sensitive code to maintain, and not certified. Signature verification is still missing |
| A JWT library (`dart_jsonwebtoken`) is used only to sign the client assertion | eSignet signs with PS256, and the standard Dart `jose` package lists no PS* algorithms. `dart_jsonwebtoken` supports PS256 and RSA keys in JWK format | For now it is used only to sign: it is not yet used to verify tokens |
| Dart Frog as the BACKEND framework | It lets the BACKEND be written in Dart, the same language as the APP, which looked like a solid bet | Dart Frog is probably small compared with the Java or Node ecosystems, so fewer ready-made libraries are available |
| Configuration and keys outside the repository | So that secrets are less likely to be committed by accident | The default path assumes a `~/rp-app` folder |

## Private keys in production

In this demo the private key is a JWK file with permissions `600`, outside the repository. That is acceptable for a local test and not for production. What follows is how it would be handled; none of it was implemented or tried here.

- **Where the key lives.** In a KMS or an HSM, generated there and not exportable. The BACKEND would ask the service to sign each client assertion and would never hold the key material, neither in memory nor on disk. The signing algorithm has to be supported by the service: AWS KMS, Azure Key Vault and Google Cloud KMS appear to offer RSA-PSS signatures (PS256), to be confirmed for the chosen service and key size. Without an HSM, a secrets manager with encryption at rest and short-lived access would be the minimum; never the repository, an image or the CI logs.
- **Who can use it.** An identity for the BACKEND with permission only to sign with that key, no export, an audit log of every signature, and a different key for each environment.
- **Rotation.** Create a new key pair with a new `kid`, register its public key for the client, make the BACKEND sign with it, and retire the old key after the logins in flight have finished (a client assertion lasts 60 s). It should be periodic, and immediate if a compromise is suspected. How to replace or add a key for a registered client in eSignet is not known: the Postman collection has update (`PUT`) and modify (`PATCH`) operations for clients, which were not tried, and whether a client can hold more than one key was not checked.
- **Loss.** In the tests, losing a private key left the client unusable, and no way to recover it was found; the way out was to register a new client. A production setup would need a recovery plan, or a confirmed way to update the key of a client.

## What is missing for production

| Area | Today | What would be needed |
| --- | --- | --- |
| Validation | The `id_token` is checked for `iss`, `aud`, `exp`, `nonce` and `sub`. The signatures of the `id_token`, the `access_token` and the `userinfo` are **not verified** (planned next); neither are `iat`, `nbf`, `auth_time`, `acr`, `at_hash` and the `iss` parameter of the callback. An encrypted (JWE) `userinfo` is not supported | Verification against eSignet's keys, with a list of allowed algorithms. In the tests the `userinfo` was signed with RS256 while the key set publishes its key as PS256, so a verifier needs a policy for that |
| Error handling | The BROWSER can receive the text of an exception, and the APP receives technical text (up to 300 characters). A login that fails while preparing the redirect leaves its ticket used. Timeouts and retries on the calls to eSignet were not reviewed | Generic messages for the USER, a timeout and retry policy, and one error format |
| Logging | No request log; only a `print` when the token exchange fails | Structured logs with a correlation identifier and without tickets, codes or tokens, plus security events |
| Rate limits | Only a cap of 100 pending tickets | Limits per client on `/api/login/start`, `/app/login` and the polling |
| Sessions and state | In memory, one instance. Some entries are not purged and there is no cap on login transactions or sessions | A shared store with expiry (for example Redis) and caps |
| Transport and cookies | Plain `http`; cookie with `Path=/` and without `Secure` or `Max-Age`; no security headers | HTTPS everywhere, a stricter cookie, and headers such as `nosniff`, `no-store` and a content security policy |
| Configuration and tests | Lifetimes and scope fixed in the code; a default path that assumes one specific home folder; only the template test; no CI | Configurable values, unit and integration tests against a simulated eSignet, and a pipeline |
| Known bug | The `status` route checks the ticket's age before its state (see above) | Check the state first |

## Problems found and how they were solved

These are the problems that were actually met. The cause given for each is the one that fitted the evidence at the time, and it may be incomplete.

| Problem | Where | Cause as understood | Resolution |
| --- | --- | --- | --- |
| Port 8080 was already in use | eSignet deployment | A container of an earlier, unrelated project was publishing it | That project was stopped before starting eSignet |
| The mock identity system exits from its third start with `mv: cannot overwrite 'hsm-client/client'` | eSignet deployment, after switching the PC off and on | Its start script seems to reinstall the HSM client on every start | A one-line change to that script inside the stopped container (see [Daily operation](https://github.com/alvaroecp/esignet_local_docker#daily-operation)) |
| The login interface started and stopped again by itself | eSignet deployment, same restart | Not confirmed | It was recreated, which seemed harmless because it keeps no data |
| The client assertion was rejected with `401 invalid_client` | Integration | eSignet required a `kid` in its header, and in the tests it rejected the token endpoint URL as `aud` and expected the issuer | The `kid` is taken from the JWK, and `aud` is the issuer |
| The first version of the BACKEND failed with a `RangeError` | Integration | The configuration was read only from environment variables and ignored `rp.env`, so the key path was empty. The callback also still used an older assertion without `kid` | `rp.env` is read, and the callback uses the corrected assertion |
| The APP did not receive its `app_token` | Integration | The `status` route read it from the wrong place and the whole eSignet response was being stored | The callback creates a session with its own `app_token`, and `status` returns that |
| The standard Dart JWT package could not sign with PS256 | Integration | `jose` lists no PS* algorithms and eSignet signs with PS256 | `dart_jsonwebtoken` was used instead |
| A set of improvements ended in a `500` on `/api/login/start` | Development | Some files imported with relative paths and others with `package:`, so Dart saw two different `AppConfig` classes | One import style per project. The improvements were set aside and the previous version from GitHub was restored |
| The profile photo did not appear in the APP | Integration | In the tests `picture` arrived as an inline image, and the APP tried to load it as a web address | The APP decodes the base64 and draws the image from memory |
| Creating a test person failed with `HTTP 200` and `invalid_postalcode`, and the login screen rejected an 8-digit UIN | Test data | The postal code seems to be required, and the login screen asked for a UIN of 10 to 16 digits | Both are documented in [User registration](https://github.com/alvaroecp/esignet_local_docker#user-registration) |
| A client became unusable after its private key was lost | Test data | A client seems to be tied to the key registered for it, and no way to recover it was found | A new client was registered under another name |
| The `userinfo` is signed with RS256, its key is published as PS256 and its `iss` differs from the issuer | Integration, observed | Probably a quirk of the mock identity system; not verified | **Open**: it matters when the signature verification is added |

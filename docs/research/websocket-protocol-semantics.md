# WebSocket protocol: sessions, events, identity and versioning

Research for [#3](https://github.com/doobnet/airdc-mac/issues/3): how the
Daemon's WebSocket API handles the concerns every feature shares. This builds
on the per-feature mapping in
[`v1-feature-api.md`](https://github.com/doobnet/airdc-mac/blob/b64b9f8016afafd4526e464eb5bb781e8a6fc664/docs/research/v1-feature-api.md#how-calls-map-to-the-websocket) and does not
repeat it.

**Sources.** Every claim is cited to the source that owns it, pinned to a
commit:

- `apib:` is the AirDC++ Web API Blueprint. In the repo the file is
  `apiary.apib`; `v1-feature-api.md` calls it `airdcpp.apib`, and the line
  numbers match
  ([airdcpp-apidocs@51ddd04](https://github.com/airdcpp-web/airdcpp-apidocs/tree/51ddd0436ec4a3c1123d71295d55b2442b335496)).
- `comm:` is `communication-protocols.md` in the same repo and commit.
- `wc:` is the Daemon's source,
  [airdcpp-webclient@56bf01a](https://github.com/airdcpp-web/airdcpp-webclient/tree/56bf01a929d68e11fca1445e73207995727a50e1)
  (`master`). Every cited file there is identical to tag `2.14.0`, the latest
  stable release. `wc@develop:` is
  [`develop`@4ca27a5](https://github.com/airdcpp-web/airdcpp-webclient/tree/4ca27a5edfe01d12273c004693257f97f26872d4),
  which is unreleased.
- `ui:` is the official Web UI,
  [airdcpp-webui@eeeea50](https://github.com/airdcpp-web/airdcpp-webui/tree/eeeea5025a5e720f38dac53ced8e002940f00a74).
- `js:` is the vendor's socket library the Web UI is built on,
  [airdcpp-apisocket-js@17c1e74](https://github.com/airdcpp-web/airdcpp-apisocket-js/tree/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510).

Each claim is marked as **Docs** (the blueprint or protocol doc says it),
**Source** (read in the Daemon's or the vendor clients' code) or **Inferred**
(my conclusion from those). Items to confirm are collected in
[Check against a live Daemon](#check-against-a-live-daemon).

**Two kinds of "session".** In `CONTEXT.md`, a **Session** is a Hub, private
conversation, file list or search that the Daemon holds and the App lets the
user switch between. The Daemon's Web API also has "sessions": a logged-in web
user with an `auth_token`. This document calls the second kind an
**auth session**. A **Connection** (the App's authenticated link to its
Daemon) is one WebSocket attached to one auth session.

---

## 1. Authorization and auth session lifetime

### Logging in

- **Docs.** `POST /sessions/authorize {username, password, max_inactivity}`
  creates an auth session ([`apib:3659-3674`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3659-L3674)). The response is Authentication
  info: `session_id` (FL4), `auth_token`, `token_type`, `system_info`, `user`
  and `wizard_pending` ([`apib:3778-3785`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3778-L3785)).
- **Source.** The Daemon also accepts
  `{grant_type: "refresh_token", refresh_token}` instead of a username and
  password ([`wc:airdcpp-webapi/api/SessionApi.cpp:101-132`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L101-L132)). Every successful
  `authorize` returns a new `refresh_token`
  ([`wc:airdcpp-webapi/api/SessionApi.cpp:141`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L141), [`wc:airdcpp-webapi/api/SessionApi.cpp:155-157`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L155-L157)).
  **Neither the blueprint nor the protocol doc mentions refresh tokens.** The
  feature has been in the Daemon since 2.5.0 (December 2018, found by checking
  `SessionApi.cpp` at each release tag).
- **Source.** `auth_token` is a random UUID
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:95-98`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L95-L98),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:347-350`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L347-L350)). `session_id` is a
  random 32-bit number ([`wc:airdcpp-webapi/web-server/Session.cpp:56-57`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/Session.cpp#L56-L57)). It
  is not a secret; the admin-only session list shows it
  ([`apib:3767-3776`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3767-L3776)).
- **Source.** A wrong password returns 401; a bad refresh token returns 400
  ([`wc:airdcpp-webapi/api/SessionApi.cpp:112-128`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L112-L128)). After 5 failed password
  attempts within 45 seconds, the Daemon refuses logins from that IP
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:41-42`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L41-L42),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:124-133`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L124-L133)).
- **Source.** `authorize` and `socket` work only on a socket that has no auth
  session yet. On an authenticated socket they fail with 412 "This method
  can't be used after authentication"
  ([`wc:airdcpp-webapi/api/SessionApi.cpp:43-45`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L43-L45),
  [`wc:airdcpp-webapi/api/SessionApi.cpp:65-68`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L65-L68),
  [`wc:airdcpp-webapi/web-server/ApiRouter.cpp:43-45`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L43-L45)). A socket that is attached
  to an auth session can't switch to another one; that needs a new socket. A
  socket whose `POST /sessions/socket` failed has no auth session yet, so it
  can go on to `authorize`.
- **Source.** A socket must authenticate within 60 seconds of opening. The
  check runs on the 30-second ping timer, so the Daemon closes an
  unauthenticated socket after 60 to 90 seconds with close code 1008
  "Authentication timeout"
  ([`wc:airdcpp-webapi/web-server/SocketManager.cpp:34`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L34),
  [`wc:airdcpp-webapi/web-server/SocketManager.cpp:109-128`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L109-L128)).
- **Source.** On an unauthenticated socket, requests to any section other than
  `sessions` fail with 401 "Not authorized"
  ([`wc:airdcpp-webapi/web-server/ApiRouter.cpp:47-51`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L47-L51)), and other `sessions`
  requests fail with 400 ([`wc:airdcpp-webapi/web-server/ApiRouter.cpp:77-86`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L77-L86)).

### Token expiry

There are two tokens, and they expire very differently.

**`auth_token` (the auth session):**

- **Docs.** `max_inactivity` is in minutes, default 20, configurable in the
  web server settings. "Sessions with a connected websocket won't expire"
  ([`apib:3671-3672`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3671-L3672)).
- **Source.** The default comes from the `default_idle_timeout` setting (20
  minutes, 0 allowed) ([`wc:airdcpp-webapi/web-server/WebServerSettings.cpp:71`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebServerSettings.cpp#L71)).
  `max_inactivity: 0` means the auth session never expires
  ([`wc:airdcpp-webapi/web-server/Session.cpp:127-134`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/Session.cpp#L127-L134)).
- **Source.** An auth session with an attached socket never times out. The
  inactivity clock restarts when the socket disconnects, and every API request
  (socket or HTTP) also restarts it
  ([`wc:airdcpp-webapi/web-server/Session.cpp:109-134`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/Session.cpp#L109-L134),
  [`wc:airdcpp-webapi/web-server/ApiRouter.cpp:59`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L59)). A 30-second timer removes
  expired auth sessions
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:221-235`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L221-L235),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:269-276`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L269-L276)).
- **Source.** Auth sessions live only in memory. The Daemon saves web users
  and refresh tokens to `web-users.json`, but not auth sessions
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:517-551`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L517-L551)). **A Daemon
  restart invalidates every `auth_token`.**

**`refresh_token`:**

- **Source.** Refresh tokens are persisted, so they survive Daemon restarts
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:486-508`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L486-L508),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:539-548`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L539-L548)).
- **Source.** A refresh token works once. Using it deletes it, and the
  response carries a new one
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:100-122`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L100-L122)).
- **Source.** The intended lifetime is 30 days, but the code adds
  `30 × 24 × 60 × 60 × 1000` to a time in **seconds**
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:44`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L44),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:352-354`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L352-L354); `GET_TIME()` is
  `time(NULL)`, [`wc:airdcpp-core/airdcpp/core/timer/TimerManager.cpp:84-86`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/core/timer/TimerManager.cpp#L84-L86)).
  **Inferred:** refresh tokens effectively last about 82 years.
- **Source.** Refresh tokens are deleted when the web user is changed with
  "remove sessions" or deleted
  ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:365-383`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L365-L383),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:401-429`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L401-L429)). Logging out does
  **not** delete them ([`wc:airdcpp-webapi/web-server/WebUserManager.cpp:215-219`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L215-L219)).

### Re-attaching a socket to an existing auth session

- **Docs.** `POST /sessions/socket {auth_token}` attaches a socket to an
  existing auth session. It works only over a WebSocket ([`apib:3676-3685`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3676-L3685),
  [`comm:68-90`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L68-L90)).
- **Source.** It returns 200 with Authentication info, but **no**
  `refresh_token` ([`wc:airdcpp-webapi/api/SessionApi.cpp:162-186`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L162-L186)). The
  blueprint agrees ([`apib:3684-3685`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3684-L3685)). The protocol doc's example shows
  `204` with no body ([`comm:83-90`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L83-L90)); that example is wrong.
- **Source.** An unknown or expired `auth_token` returns 400 "Invalid session
  token". The socket must also use the same scheme as the login: an auth
  session made over `wss` can't be re-attached over `ws`, and vice versa (400
  "Invalid protocol") ([`wc:airdcpp-webapi/api/SessionApi.cpp:171-180`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L171-L180)).
- **Source.** An auth session has **at most one socket**. Attaching a second
  socket detaches the first and closes it with code 1008 "Another socket was
  connected to this session"
  ([`wc:airdcpp-webapi/web-server/SocketManager.cpp:181-192`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L181-L192)).
- **Source.** Detaching a socket, whether by disconnect or by replacement,
  switches off every event subscription of that auth session
  ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:58-65`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L58-L65),
  [`wc:airdcpp-webapi/web-server/Session.cpp:114-121`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/Session.cpp#L114-L121)). Re-attaching keeps the
  auth session and everything it owns (see search instances below), but not
  its subscriptions.
- **Source (vendor clients).** `airdcpp-apisocket-js` re-attaches with
  `POST /sessions/socket` after a disconnect. If that returns 400 ("the session
  was lost, most likely the client was restarted") it logs in again with the
  stored credentials
  ([`js:src/SocketBase.ts:78-105`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketBase.ts#L78-L105), [`js:src/SocketBase.ts:166-175`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketBase.ts#L166-L175),
  [`js:src/SocketBase.ts:213-225`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketBase.ts#L213-L225)). Between connect attempts it waits a fixed
  `reconnectInterval` (10 seconds by default,
  [`js:src/SocketBase.ts:27-31`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketBase.ts#L27-L31), [`js:src/SocketBase.ts:249-262`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketBase.ts#L249-L262)).
- **Source (vendor clients).** The Web UI turns the library's auto-reconnect
  off and drives the same steps itself, retrying every 5 seconds
  ([`ui:src/services/SocketService.ts:15-25`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/services/SocketService.ts#L15-L25)). It keeps the Authentication info
  in `sessionStorage` and re-attaches with its `auth_token`
  ([`ui:src/stores/app/loginSlice.ts:82-95`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/stores/app/loginSlice.ts#L82-L95),
  [`ui:src/components/main/effects/LoginGuardEffect.ts:21-26`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/components/main/effects/LoginGuardEffect.ts#L21-L26),
  [`ui:src/actions/store/LoginActions.ts:46-54`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/actions/store/LoginActions.ts#L46-L54)). If that fails, it forgets the
  auth session. If "remember me" was ticked, it logs in with the refresh token
  kept in `localStorage`, and otherwise it shows the login page
  ([`ui:src/routes/Login/effects/LoginStateEffect.ts:54-62`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/routes/Login/effects/LoginStateEffect.ts#L54-L62),
  [`ui:src/actions/store/LoginActions.ts:29-40`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/actions/store/LoginActions.ts#L29-L40)).
- **Source (vendor clients).** The Web UI detects a computer waking from sleep
  (a 2-second timer that fell more than 30 seconds behind) and closes the
  socket to force a fresh reconnect
  ([`ui:src/components/main/effects/ActivityTrackerEffect.tsx:30-44`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/components/main/effects/ActivityTrackerEffect.tsx#L30-L44),
  [`ui:src/components/main/effects/ActivityTrackerEffect.tsx:105-108`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/components/main/effects/ActivityTrackerEffect.tsx#L105-L108)).

### Keep-alive

- **Source.** The Daemon pings every socket every 30 seconds and closes it with
  code 1011 "PONG timed out" if no pong arrives within 10 seconds
  ([`wc:airdcpp-webapi/web-server/WebServerSettings.cpp:72-73`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebServerSettings.cpp#L72-L73),
  [`wc:airdcpp-webapi/web-server/SocketManager.cpp:43-50`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L43-L50),
  [`wc:airdcpp-webapi/web-server/SocketManager.cpp:94-107`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L94-L107),
  [`wc:airdcpp-webapi/web-server/WebServerManager.cpp:126-131`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebServerManager.cpp#L126-L131)). On `develop`,
  which swaps websocketpp for Boost.Beast, the pong timeout setting is a no-op
  ([`wc@develop:airdcpp-webapi/web-server/BeastServerAdapter.h:38`](https://github.com/airdcpp-web/airdcpp-webclient/blob/4ca27a5edfe01d12273c004693257f97f26872d4/airdcpp-webapi/web-server/BeastServerAdapter.h#L38)).
- **Docs.** `POST /sessions/activity {user_active}` keeps an HTTP-only auth
  session alive and feeds the Daemon's idle-away detection ([`apib:3697-3709`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3697-L3709)).
  **Source.** The Web UI sends `user_active: true` once a minute while the user
  is active ([`ui:src/components/main/effects/ActivityTrackerEffect.tsx:55-69`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/components/main/effects/ActivityTrackerEffect.tsx#L55-L69),
  [`ui:src/components/main/effects/ActivityTrackerEffect.tsx:104-110`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/components/main/effects/ActivityTrackerEffect.tsx#L104-L110)).
  **Inferred:** with a socket attached the App needs this only for away
  tracking, not to stay logged in.

### Logout

- **Docs.** `DELETE /sessions/self` ends the current auth session
  ([`apib:3711-3715`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3711-L3715)). An admin can end any auth session with
  `DELETE /sessions/{session_id}` ([`apib:3729-3737`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3729-L3737)).
- **Source.** Ending an auth session does not close its socket. The socket is
  detached and left unauthenticated, so later requests fail with 401 until the
  ping timer closes it with 1008 "Authentication timeout"
  ([`wc:airdcpp-webapi/web-server/SocketManager.cpp:194-206`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L194-L206),
  [`wc:airdcpp-webapi/web-server/SocketManager.cpp:118-126`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L118-L126)). The exception is
  a change to the web user (password or permissions, with "remove sessions"):
  then the socket is closed with code 1000 "Re-authentication required", and
  the user's refresh tokens are gone too
  ([`wc:airdcpp-webapi/web-server/SocketManager.cpp:203-205`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/SocketManager.cpp#L203-L205),
  [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:401-410`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L401-L410)).
- **Source.** Admins can subscribe to `session_removed`, which says whether the
  auth session `timed_out` ([`wc:airdcpp-webapi/api/SessionApi.cpp:38-41`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L38-L41),
  [`wc:airdcpp-webapi/api/SessionApi.cpp:250-257`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L250-L257)). The blueprint omits the
  `timed_out` field ([`apib:3759-3763`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3759-L3763)).

### What dies with an auth session

- **Source.** Each auth session holds its own set of API modules
  ([`wc:airdcpp-webapi/web-server/Session.cpp:54-87`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/Session.cpp#L54-L87)). When the auth session
  ends (logout or timeout), its `SearchApi` module removes every search
  instance whose owner is `session:<session_id>`
  ([`wc:airdcpp-webapi/api/SearchApi.cpp:81-95`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SearchApi.cpp#L81-L95),
  [`wc:airdcpp-webapi/api/SearchApi.cpp:169-189`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SearchApi.cpp#L169-L189)). **The App's searches never
  outlive its auth session.**
- **Docs.** Search instances also expire `expiration` minutes after creation
  (default 30, 0 = never), counted from creation, not from last use
  ([`apib:3264-3266`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3264-L3266)). **Source** agrees
  ([`wc:airdcpp-webapi/api/SearchApi.cpp:35`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SearchApi.cpp#L35),
  [`wc:airdcpp-webapi/api/SearchApi.cpp:191-201`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SearchApi.cpp#L191-L201),
  [`wc:airdcpp-core/airdcpp/search/SearchInstance.cpp:42-48`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/search/SearchInstance.cpp#L42-L48),
  [`wc:airdcpp-core/airdcpp/search/SearchManager.cpp:337-353`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/search/SearchManager.cpp#L337-L353)).
- **Inferred.** Hub, private chat and file list Sessions, and the Queue, belong
  to the Daemon and do not depend on any auth session. That is why ADR 0002 can
  mirror them.

---

## 2. Event subscriptions (listeners)

### Subscribing and unsubscribing

- **Docs.** `POST /<section>/listeners/<event>` subscribes; `DELETE` on the same
  path unsubscribes. Events arrive as `{event, data}` ([`comm:157-187`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L157-L187)).
- **Source.** Subscribing needs a socket. Over plain HTTP it returns 428
  "Socket required". An unknown event name returns 404
  ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:67-78`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L67-L78)). Success is
  204 ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:80-90`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L80-L90)). The
  section's permission applies to both methods
  ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:29-36`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L29-L36)).
- **Source.** A subscription is an on/off flag per event per auth session, not
  a counter ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.h:36`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.h#L36),
  [`wc:airdcpp-webapi/api/base/SubscribableApiModule.h:46-48`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.h#L46-L48)). Subscribing
  twice and unsubscribing once switches it off. `airdcpp-apisocket-js`
  therefore counts listeners itself and sends the `POST` for the first and the
  `DELETE` for the last ([`js:src/SocketSubscriptionHandler.ts:117-147`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketSubscriptionHandler.ts#L117-L147),
  [`js:src/SocketSubscriptionHandler.ts:47-72`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketSubscriptionHandler.ts#L47-L72)).

### Per-entity versus global

- **Docs.** `POST /<section>/<entity id>/listeners/<event>` subscribes to one
  entity. The same events can be subscribed globally, and both kinds carry the
  entity `id` ([`comm:189-212`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L189-L212)).
- **Source.** An entity's event is sent if the global flag **or** that entity's
  flag is on ([`wc:airdcpp-webapi/api/base/HierarchicalApiModule.h:203-219`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/HierarchicalApiModule.h#L203-L219)).
  The two are independent. Removing a per-entity subscription does not stop
  the global one, and the reverse.
- **Source.** A per-entity subscription needs the entity to exist. Otherwise
  the Daemon returns 404 "Entity … was not found"
  ([`wc:airdcpp-webapi/api/base/HierarchicalApiModule.h:118-128`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/HierarchicalApiModule.h#L118-L128)). The
  subscription belongs to the entity's module, which is destroyed when the
  entity is removed ([`wc:airdcpp-webapi/api/base/HierarchicalApiModule.h:148-156`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/HierarchicalApiModule.h#L148-L156)).
  **Inferred:** per-entity subscriptions vanish with their entity, and a later
  entity with the same ID starts unsubscribed.
- **Source.** `airdcpp-apisocket-js` rejects entity ID `0`
  ([`js:src/SocketSubscriptionHandler.ts:28-31`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketSubscriptionHandler.ts#L28-L31)). This matches the Daemon: hub
  IDs start at 1 (see [Entity identity](#3-entity-identity)).
- This confirms the recommendation in `v1-feature-api.md`: one **global**
  subscription per event type per Connection, routed by `id`.

### Delivery guarantees

The docs say nothing about delivery beyond "all added subscriptions will be
reset when the socket gets disconnected" ([`comm:184`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L184)). The source shows:

- **Source. At most once, no replay.** An event is sent at the moment the
  Daemon's core fires it, if the flag is on and a socket is attached. With no
  socket it is dropped ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:92-122`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L92-L122)).
  There is no sequence number, no acknowledgement and no buffer for a
  reconnecting socket. Events that fire while the App is disconnected are
  lost. The App must re-fetch its snapshots after every reconnect.
- **Source. No per-event ordering guarantee across sources.** Events are
  written from whichever Daemon thread fired them
  ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:92-107`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L92-L107),
  [`wc:airdcpp-webapi/web-server/WebSocket.cpp:120-140`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L120-L140)). Responses to requests
  share the same socket. **Inferred:** events from one thread keep their order,
  but events from different threads can interleave, and a response can arrive
  before or after the events its request caused (for example the `POST /hubs`
  response and `hub_created`).
- **Docs.** Responses can arrive in a different order from the requests
  ([`comm:129-130`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L129-L130)).
- **Source. No backpressure.** Outgoing messages are queued without limit. On
  `develop` the queue is a plain `std::deque`
  ([`wc@develop:airdcpp-webapi/web-server/BeastServerAdapter.h:316-319`](https://github.com/airdcpp-web/airdcpp-webclient/blob/4ca27a5edfe01d12273c004693257f97f26872d4/airdcpp-webapi/web-server/BeastServerAdapter.h#L316-L319),
  [`wc@develop:airdcpp-webapi/web-server/BeastServerAdapter.h:369`](https://github.com/airdcpp-web/airdcpp-webclient/blob/4ca27a5edfe01d12273c004693257f97f26872d4/airdcpp-webapi/web-server/BeastServerAdapter.h#L369)).
  **Inferred:** the released websocketpp transport also queues without limit.
  An App that stops reading makes the Daemon's memory grow; it gets no error.

### Subscriptions on reconnect

- **Docs and Source agree.** A disconnect switches every subscription off
  ([`comm:184`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L184), [`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:58-65`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L58-L65)).
  This applies even when the socket re-attaches to the same auth session.
- **Source (vendor clients).** `airdcpp-apisocket-js` drops all local
  listeners on disconnect and does not re-subscribe
  ([`js:src/SocketSubscriptionHandler.ts:221-224`](https://github.com/airdcpp-web/airdcpp-apisocket-js/blob/17c1e7458b1b0f0c35036dd7cae83e4b6dbcd510/src/SocketSubscriptionHandler.ts#L221-L224)). Each Web UI view subscribes
  again when it is mounted again.

---

## 3. Entity identity

`v1-feature-api.md` lists the ID *types* ([IDs vary by entity](https://github.com/doobnet/airdc-mac/blob/b64b9f8016afafd4526e464eb5bb781e8a6fc664/docs/research/v1-feature-api.md#ids-vary-by-entity)).
This section adds where each ID comes from and whether it survives a Daemon
restart.

| Entity | ID | Generated by | Survives restart? |
|---|---|---|---|
| Hub Session | number | Counter from 1 per Daemon run. A reconnect or redirect of the same Hub keeps it ([`wc:airdcpp-core/airdcpp/hub/Client.cpp:41`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/hub/Client.cpp#L41), [`wc:airdcpp-core/airdcpp/hub/Client.cpp:50`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/hub/Client.cpp#L50), [`wc:airdcpp-webapi/api/HubApi.cpp:206`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/HubApi.cpp#L206)) | **No, and reused**: after a restart, ID 1 is whichever Hub connects first |
| Favorite hub | number | Random at load; not saved ([`wc:airdcpp-core/airdcpp/favorites/HubEntry.cpp:28-29`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/favorites/HubEntry.cpp#L28-L29), [`wc:airdcpp-core/airdcpp/favorites/FavoriteManager.cpp:304-323`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/favorites/FavoriteManager.cpp#L304-L323)) | **No**. Key favorites by `hub_url` |
| Private chat Session | the other user's CID | [`wc:airdcpp-webapi/api/PrivateChatApi.cpp:163`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/PrivateChatApi.cpp#L163) | Yes, as far as the CID is stable (below) |
| File list Session | the other user's CID | [`wc:airdcpp-webapi/api/FilelistApi.cpp:210`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/FilelistApi.cpp#L210) | Same |
| User | CID | ADC: chosen by the user's own client. NMDC: a hash of nick and Hub URL ([`wc:airdcpp-core/airdcpp/hub/ClientManager.cpp:1159-1167`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/hub/ClientManager.cpp#L1159-L1167)) | ADC: yes. NMDC: changes if the nick or Hub URL changes |
| The Daemon itself | `system_info.cid` | [`wc:airdcpp-webapi/api/SystemApi.cpp:150`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SystemApi.cpp#L150) | Yes (**Inferred**: the Daemon's own CID is saved in its settings) |
| Search instance | number | Counter from 1 per Daemon run ([`wc:airdcpp-core/airdcpp/search/SearchInstance.cpp:29-30`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/search/SearchInstance.cpp#L29-L30)) | **No**; instances are not saved at all |
| Grouped search result | TTH string | [`wc:airdcpp-core/airdcpp/search/GroupedSearchResult.h:31`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/search/GroupedSearchResult.h#L31), [`wc:airdcpp-core/airdcpp/search/GroupedSearchResult.h:66`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/search/GroupedSearchResult.h#L66) | Content hash, so stable, but the instance holding it is not |
| Bundle | number | Random when created, saved in the Bundle's XML file ([`wc:airdcpp-core/airdcpp/queue/Bundle.cpp:55-57`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/queue/Bundle.cpp#L55-L57), [`wc:airdcpp-core/airdcpp/queue/Bundle.cpp:217-219`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/queue/Bundle.cpp#L217-L219), [`wc:airdcpp-core/airdcpp/queue/QueueManager.cpp:2533-2556`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/queue/QueueManager.cpp#L2533-L2556)) | **Yes** |
| Queue file | number | Counter per Daemon run ([`wc:airdcpp-core/airdcpp/queue/QueueItem.cpp:35`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/queue/QueueItem.cpp#L35), [`wc:airdcpp-core/airdcpp/queue/QueueItem.cpp:51`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/queue/QueueItem.cpp#L51)) | **No** |
| Transfer | number | Counter per Daemon run ([`wc:airdcpp-core/airdcpp/transfer/TransferInfoManager.cpp:35`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/transfer/TransferInfoManager.cpp#L35)) | **No** |
| Chat message, Event | number | One counter from 1 shared by chat and log messages ([`wc:airdcpp-core/airdcpp/message/Message.cpp:28-37`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/message/Message.cpp#L28-L37)) | **No**, but it only grows within one run |
| Auth session | `session_id` number, `auth_token` UUID | [`wc:airdcpp-webapi/web-server/Session.cpp:56-57`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/Session.cpp#L56-L57), [`wc:airdcpp-webapi/web-server/WebUserManager.cpp:347-350`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebUserManager.cpp#L347-L350) | **No** |

Notes:

- **Source. Detecting a Daemon restart.** `system_info.client_started` is the
  Daemon's start time ([`apib:4746`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L4746)). It is computed on every call as "now minus
  uptime" ([`wc:airdcpp-webapi/api/SystemApi.cpp:152`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SystemApi.cpp#L152),
  [`wc:airdcpp-core/airdcpp/core/timer/TimerManager.cpp:89-95`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/core/timer/TimerManager.cpp#L89-L95)), so two
  readings can differ by a second. **Inferred:** a change of more than a few
  seconds means the Daemon restarted, and every ID marked "No" above is
  invalid. In practice a successful `POST /sessions/socket` already proves
  there was no restart, because auth sessions don't survive one.
- **Correction to ADR 0002.** It says hub IDs "change across Daemon restarts".
  They do, but they also **repeat**: they restart from 1. A stale hub ID can
  silently point at a different Hub.
- **Inferred.** Because message IDs only grow within one Daemon run, the App
  can merge a re-fetched message history into what it already shows by `id`,
  as long as the Daemon did not restart.
- **Recognising the App's own search instances** (left open in ADR 0002).
  **Docs.** Instances take an optional `owner_suffix` (FL4), and their `owner`
  is `session:<session_id>[:suffix]` ([`apib:3264-3266`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3264-L3266), [`apib:3423`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3423)).
  **Inferred:** the App recognises its own instances as those whose `owner`
  starts with `session:<its session_id>`. That is stable across socket
  reconnects that re-attach to the same auth session. It cannot survive a new
  auth session, since the old auth session's instances are deleted when it
  ends.

---

## 4. API versioning and the minimum Daemon version

### What the numbers mean

- **Docs.** API version 1 dates from 2017-05-05 and works with Web Client 2.0.0
  or newer ([`apib:12-20`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L12-L20)). `system_info` carries `api_version` and
  `api_feature_level` ([`apib:4737-4747`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L4737-L4747)). Individual methods and fields are
  marked "**Minimum API feature level**: N". Deprecated fields "will be removed
  in the next major API version" ([`apib:4394-4399`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L4394-L4399)).
- **Source.** Both are compile-time constants, now `API_VERSION 1` and
  `API_FEATURE_LEVEL 10` ([`wc:airdcpp-webapi/web-server/version.h:23-24`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/version.h#L23-L24)),
  returned by `GET /system/system_info` and in every Authentication info
  ([`wc:airdcpp-webapi/api/SystemApi.cpp:142-155`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SystemApi.cpp#L142-L155),
  [`wc:airdcpp-webapi/api/SessionApi.cpp:151`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L151)).
- **Source.** The API version is taken from the URL, so `/api/v1/` selects
  version 1. Any other version returns 412 "Unsupported API version"
  ([`wc:airdcpp-webapi/web-server/ApiRequest.cpp:34-38`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRequest.cpp#L34-L38),
  [`wc:airdcpp-webapi/web-server/ApiRequest.cpp:66-78`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRequest.cpp#L66-L78),
  [`wc:airdcpp-webapi/web-server/ApiRouter.cpp:35-38`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L35-L38)). For a socket, the
  version comes from the socket URL, and each request's `path` is appended to
  it ([`wc:airdcpp-webapi/web-server/WebSocket.cpp:61-65`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L61-L65),
  [`wc:airdcpp-webapi/web-server/WebSocket.cpp:223`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L223)).
- **Inferred.** The feature level is a counter bumped in releases that add API
  features. Features are only added within version 1, so a higher level is a
  superset. There is no negotiation: the App reads the level and hides what the
  Daemon lacks.

### Feature level by release

Found by reading `version.h` at each release tag; release dates from the
GitHub releases list.

| Feature level | First release | Released |
|---|---|---|
| 0 | 2.0.0 | 2017-05 |
| 1 | 2.4.0 | 2018-11 |
| 2 | 2.6.0 | 2019-04 |
| 3 | 2.7.0 | 2019-11 |
| 4 | 2.8.0 | 2020-07 |
| 5 | 2.9.0 | 2020-10 |
| 6 | 2.10.0 | 2020-12 |
| 7 | 2.11.0 | 2021-01 |
| 8 | 2.12.0 (first published: 2.12.1) | 2023-05 |
| 9 | 2.13.1 (first published: 2.13.2) | 2024-12 |
| 10 | 2.14.0 | 2025-09 |

`develop` is still at 10 ([`wc@develop:airdcpp-webapi/web-server/version.h:24`](https://github.com/airdcpp-web/airdcpp-webclient/blob/4ca27a5edfe01d12273c004693257f97f26872d4/airdcpp-webapi/web-server/version.h#L24)).
Refresh-token login needs 2.5.0 or newer. The 2.14.0 release notes do not
mention feature levels.

### What the App's v1 features need

From the FL column in `v1-feature-api.md`:

- **FL4:** `session_id` in Authentication info, which the App needs to spot its
  own search instances; hub user `id`/`hub_session_id`;
  `search_hinted_user`; search `owner` and `query`.
- **FL5:** Hub settings, highlights, `mention` unread counts.
- **FL8:** message `type`, `owner`, the `verbose` severity and unread count.
- **FL9:** `supports` fields, queue files by TTH, `name`/`tth`/`size`/`type`
  on user search results.
- **FL10:** `GET /transfers/transferred_bytes` (misspelled before 10) and
  granting a slot.

The Web UI does not gate anything on the feature level; it only shows it on
its About page ([`ui:src/routes/Settings/routes/About/components/ApplicationPage.tsx:33`](https://github.com/airdcpp-web/airdcpp-webui/blob/eeeea5025a5e720f38dac53ced8e002940f00a74/src/routes/Settings/routes/About/components/ApplicationPage.tsx#L33)).
It ships with the Daemon, so it never meets an older one.

---

## 5. Where HTTP is unavoidable

- **Source.** Every `/api/v1/` method goes through the same router for HTTP and
  WebSocket ([`wc:airdcpp-webapi/web-server/ApiRouter.cpp:33-75`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L33-L75)), so every API
  method works over the socket. The exceptions are the reverse: event
  listeners **need** a socket ([`wc:airdcpp-webapi/api/base/SubscribableApiModule.cpp:67-70`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/base/SubscribableApiModule.cpp#L67-L70)),
  and `POST /sessions/socket` works only on one
  ([`wc:airdcpp-webapi/api/SessionApi.cpp:164-167`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L164-L167)).
- **Source.** Three non-API routes are HTTP only. The Daemon's file server
  handles them outside `/api` ([`wc:airdcpp-webapi/web-server/FileServer.cpp:171-194`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/FileServer.cpp#L171-L194),
  [`wc:airdcpp-webapi/web-server/FileServer.cpp:228-241`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/FileServer.cpp#L228-L241)):
  - `GET /view/<file id>`: viewed-file content ([`apib:5188-5206`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L5188-L5206)).
  - `POST /temp`: upload a file's bytes. It returns an ID used by temp shares
    ([`apib:3996`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3996)) and needs the `filesystem_edit` permission.
  - `GET /proxy…`: fetch a remote URL through the Daemon.
- **Inferred.** None of these is in scope for v1, which confirms
  `v1-feature-api.md`, Gap 13. If the App ever needs them, it can send the
  `auth_token` as `Authorization: Bearer <token>` over HTTP ([`comm:35-37`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L35-L37)).
  The request must use the same scheme as the login, or the Daemon answers 406
  "Protocol mismatch" ([`wc:airdcpp-webapi/web-server/ApiRouter.cpp:53-57`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/ApiRouter.cpp#L53-L57)).

---

## Corrections to `v1-feature-api.md`

1. **"Without a `callback_id` the Daemon sends no response"** (from
   [`comm:129-130`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/communication-protocols.md?plain=1#L129-L130)). **Source disagrees:** the Daemon still sends the response,
   just without `callback_id`
   ([`wc:airdcpp-webapi/web-server/WebSocket.cpp:72-91`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L72-L91),
   [`wc:airdcpp-webapi/web-server/WebSocket.cpp:231-233`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L231-L233)). It also treats
   `callback_id` 0 or negative as missing, and parses it as a 32-bit signed
   integer ([`wc:airdcpp-webapi/web-server/WebSocket.cpp:75`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L75),
   [`wc:airdcpp-webapi/web-server/WebSocket.cpp:179`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L179)).
2. **`POST /sessions/socket` returns 200 with Authentication info**, not 204
   (see above).
3. **"After each reconnect the App must re-authenticate."** It should first
   **re-attach** with `POST /sessions/socket`. That keeps the auth session and
   its search instances, and it avoids minting a new refresh token. It should
   log in again only when re-attaching returns 400.
4. The blueprint file is named `apiary.apib` in the repo; `airdcpp.apib` is
   the name `v1-feature-api.md` gives it. The line numbers match.

---

## What this means for the current code

- **`callback_id` can be 0.** `DefaultContinuations.append` draws IDs from
  `0..<Int32.max` ([`AirDCKit/Continuations.swift:51`](../../AirDCKit/Continuations.swift#L51)).
  The Daemon treats 0 as "no callback ID" and answers without one. The reply
  then fails to decode, because `ResponseHeader` requires `callback_id`
  ([`AirDCKit/Response.swift:17-30`](../../AirDCKit/Response.swift#L17-L30)),
  and the caller waits forever. IDs must start at 1.
- **Events are thrown away.** `AirDCConnection.route` treats every message
  without `callback_id` as an undecodable reply
  ([`AirDCKit/AirDCConnection.swift:89-105`](../../AirDCKit/AirDCConnection.swift#L89-L105)).
  Event messages (`{event, data, id?}`) need their own path.
- **`Method` has only `POST` and `GET`**
  ([`AirDCKit/AirDCConnection.swift:8-11`](../../AirDCKit/AirDCConnection.swift#L8-L11)).
  Unsubscribing and logging out need `DELETE`, and other features need
  `PATCH` and `PUT`.
- **Pending requests hang on disconnect.** When the socket closes, the receive
  loop in `connect()` ends
  ([`AirDCKit/AirDCConnection.swift:76-82`](../../AirDCKit/AirDCConnection.swift#L76-L82)),
  but waiting continuations are not failed. The Daemon never answers a request
  from a dead socket. The only bulk resume, `resumeAll(with:)`, resumes with
  *success* ([`AirDCKit/Continuations.swift:35-45`](../../AirDCKit/Continuations.swift#L35-L45)).
- **WebSocketKit's `AutoReconnect` hides reconnects.** When enabled, it
  silently swaps in a new connection inside `withRetry`
  ([`WebSocketKit/WebSocket.swift:167-185`](../../WebSocketKit/WebSocket.swift#L167-L185)).
  A new socket has no auth session and no subscriptions, so retried requests
  get 401 and events stop. Reconnection has to be visible to AirDCKit so it
  can re-attach and re-subscribe. The default is off; keep it off for the
  Daemon Connection, or make it report reconnects.
- **Keep `autoReplyPing(true)`**
  ([`WebSocketKit/WebSocket.swift:232`](../../WebSocketKit/WebSocket.swift#L232)).
  Without pongs, the Daemon drops the socket within 40 seconds.
- **`OldAirDCApp.swift` sends `auth_token` inside every request's `data`**
  ([`AirDC/OldAirDCApp.swift:70-72`](../../AirDC/OldAirDCApp.swift#L70-L72),
  [`AirDC/OldAirDCApp.swift:204-212`](../../AirDC/OldAirDCApp.swift#L204-L212)).
  The Daemon ignores it; the socket is what is authenticated
  ([`wc:airdcpp-webapi/web-server/WebSocket.cpp:223`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L223)). Its `authorize()` sends
  no `max_inactivity` and throws away the `refresh_token`
  ([`AirDC/OldAirDCApp.swift:179-194`](../../AirDC/OldAirDCApp.swift#L179-L194)).
  None of this should carry over into AirDCKit.
- The endpoint path `/api/v1` without a trailing slash is fine. The Daemon
  adds the slash, and a leading `/` on request paths is ignored
  ([`wc:airdcpp-webapi/web-server/WebSocket.cpp:62-65`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/web-server/WebSocket.cpp#L62-L65),
  [`wc:airdcpp-core/airdcpp/util/text/StringTokenizer.h:37-45`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-core/airdcpp/util/text/StringTokenizer.h#L37-L45)).

---

## Recommendations for the App

### Connect and reconnect procedure

1. Open `wss://<Daemon address host>:<port>/api/v1/` (or `ws://` when the
   Daemon address is plain `http`). Always use the same scheme for a given auth
   session.
2. If the App holds an `auth_token` for this Daemon, send
   `POST /sessions/socket {auth_token}`. Do this within 60 seconds of
   opening.
   - **200:** the same Daemon run and the same auth session. All IDs are still
     valid, and the App's search instances still exist. Go to step 4.
   - **400:** the auth session is gone (timeout, logout or Daemon restart).
     The socket still has no auth session, so go on to step 3 on the same
     socket.
3. Send `POST /sessions/authorize` with
   `{grant_type: "refresh_token", refresh_token, max_inactivity}`. Store the
   new `refresh_token` from the response **before** doing anything else,
   because the old one is now spent.
   - **400** (bad refresh token): ask the user for their password and send
     `{username, password, max_inactivity}`.
   - **401** (wrong password): stop and ask again. Never retry automatically;
     five failures in 45 seconds lock the App out.
4. Check `system_info.api_version == 1` and
   `system_info.api_feature_level >= 10`. Refuse to continue otherwise, and
   show the Daemon's `client_version`.
5. Compare `system_info.client_started` (a few seconds of tolerance) and
   `system_info.cid` with the values from the last Connection. If either
   changed, drop every cached hub, search, queue file, transfer and message ID.
6. Subscribe **globally** to every event the open views need, and wait for each
   204. Then fetch the snapshots with `GET`, then apply buffered events on top.
   (This is the order `v1-feature-api.md` recommends.)
7. On any socket close, fail every pending request with a "disconnected"
   error. Never resend a request that changes state automatically, since the
   Daemon may already have done it.
8. Reconnect with backoff: start near the vendor's 5 to 10 seconds, and cap it.
   Reconnect immediately when the Mac wakes from sleep or the network changes,
   as the Web UI does.
9. Close code **1008 "Another socket was connected to this session"** means
   another Connection took over this auth session. Do not re-attach
   automatically, or two App instances will steal it from each other forever.
   Close code **1000 "Re-authentication required"** means the web user
   changed. Refresh tokens are gone, so go straight to the password prompt.

### What to request and send

- Send an explicit `max_inactivity` of around **60 minutes**. That lets a short
  sleep or network drop end with a re-attach instead of a new login, and lets
  the App's search instances survive it. The auth session never expires while
  the socket is attached anyway.
- Create search instances with `expiration: 0` and an `owner_suffix` such as
  `airdc-mac`, and delete them when the user closes the search. The auth
  session's lifetime still limits leaks after a crash.
- On quit, send `DELETE /sessions/self`. That ends the auth session and its
  searches at once, and keeps the refresh token valid for the next launch.
- Send `POST /sessions/activity {user_active: true}` about once a minute while
  the user is active, as the Web UI does, so the Daemon's idle-away works.

### What to persist

| Persist | Where | Why |
|---|---|---|
| `refresh_token` | Keychain | Survives Daemon restarts; effectively never expires, so treat it like a password |
| Daemon address, web username | Preferences | Reconnecting |
| `system_info.cid` and `client_started` of the last Connection | Preferences | Detecting a different Daemon or a restart |
| Bundle IDs, if the App keeps per-Bundle state | Anywhere | Stable across restarts |
| Favorites and Hubs by `hub_url`; users, private chats and file lists by CID | Anywhere | The stable keys |

Do **not** persist hub Session IDs, favorite hub IDs, search instance IDs,
queue file IDs, transfer IDs or message IDs. Keep the `auth_token` in memory
(or at most until the next launch), because it dies with the Daemon anyway. Do
not store the password; the refresh token replaces it.

### Minimum Daemon version: 2.14.0, API version 1, feature level 10

- **2.14.0 (September 2025) is the current stable release.** Nothing newer is
  published except the 2.14.1b beta. `develop` is still at feature level 10.
- It covers every v1 feature in `v1-feature-api.md` without fallbacks. Going
  down to 2.13.2 (FL9) would lose slot granting and need the old
  `tranferred_bytes` spelling. Going to 2.12.1 (FL8) would also lose
  `supports`, queue files by TTH and the richer user search results.
- The end-to-end tests pin one Daemon build (ADR 0001). Any older version the
  App claimed to support would be untested.
- If users need an older Daemon later, the floor could drop to **2.12.1
  (FL8)** by gating the FL9/FL10 features. It should not go below **FL4
  (2.8.0)**, because without `session_id` the App cannot recognise its own
  search instances.

---

## Surprises

1. **Refresh tokens exist but are undocumented.** The blueprint and protocol
   doc never mention `grant_type: "refresh_token"`, yet the Web UI has used it
   since 2.5.0.
2. **Refresh tokens effectively never expire.** A units bug turns 30 days into
   about 82 years. Logging out does not revoke them; only changing or deleting
   the web user does.
3. **Every login mints a new refresh token that is saved to disk.** A client
   that logs in with a password on every reconnect leaves a trail of valid
   tokens in `web-users.json`.
4. **Search instances die with the auth session.** A fresh login, instead of a
   re-attach, loses the App's searches once the old auth session times out.
   By default they also expire 30 minutes after creation, however much they
   are used.
5. **One socket per auth session.** A second socket silently takes over and
   the first is closed with 1008.
6. **Hub IDs restart at 1 on every Daemon run**, so an old ID can name a
   different Hub. Favorite hub IDs are random and change on every restart.
7. **Requests without `callback_id` still get a response** (without the
   field), and `callback_id: 0` counts as missing. The protocol doc says no
   response is sent.
8. **Subscriptions are on/off flags, not counters.** Two subscribers in the
   App sharing one event must be counted in the App.
9. **Logging out leaves the socket open but unauthenticated** until the ping
   timer closes it.
10. **The protocol doc's `POST /sessions/socket` example is wrong**: 204 with no
    body, where the Daemon returns 200 with Authentication info.
11. **No backpressure.** A slow reader grows the Daemon's memory without
    limit.
12. The blueprint's `Session.type` enum says `basic_http`; the Daemon sends
    `basic_auth` ([`apib:3772-3775`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/51ddd0436ec4a3c1123d71295d55b2442b335496/apiary.apib#L3772-L3775), [`wc:airdcpp-webapi/api/SessionApi.cpp:220-230`](https://github.com/airdcpp-web/airdcpp-webclient/blob/56bf01a929d68e11fca1445e73207995727a50e1/airdcpp-webapi/api/SessionApi.cpp#L220-L230)).

---

## Check against a live Daemon

1. `POST /sessions/socket` returns 200 with Authentication info and no
   `refresh_token`. Attaching a second socket closes the first with 1008.
2. `grant_type: "refresh_token"` works, returns a new token, and the old token
   then fails with 400.
3. The refresh token's `expires_on` in `web-users.json` is decades in the
   future.
4. A request with `callback_id: 0` or without one gets a response without
   `callback_id`.
5. After a socket reconnect and re-attach, no events arrive until the App
   re-subscribes; after re-subscribing, they do.
6. An App-created search instance survives a socket re-attach, and disappears
   after `DELETE /sessions/self` and after the auth session times out.
7. After `DELETE /sessions/self`, requests on the same socket get 401, and the
   socket is closed with 1008 within about 30 seconds.
8. The Daemon closes a socket that does not answer pings (1011 "PONG timed
   out"), and `autoReplyPing(true)` keeps the App's socket alive.
9. After a Daemon restart, hub IDs start from 1 again, favorite hub IDs have
   changed, Bundle IDs have not, and `client_started` has changed.
10. What happens to a per-entity subscription when a Hub is redirected or
    reconnected with the same ID.
11. Whether private chat and file list Sessions are reopened after a Daemon
    restart.
12. How the App's memory and the Daemon's behave when the App stops reading
    under a heavy event load (search results, transfer updates).
13. `api_feature_level` is 10 on the pinned end-to-end test Daemon build.

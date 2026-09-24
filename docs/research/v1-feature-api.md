# v1 features: API calls, events and data shapes

Research for [#4](https://github.com/doobnet/airdc-mac/issues/4): which calls
and events the App needs from the Daemon's API for each v1 feature, what comes
back, and where the API falls short.

**Sources.** The primary source is the AirDC++ Web API Blueprint (API version 1),
cited as `airdcpp.apib:<line>`. For the WebSocket wire format I also used
[`communication-protocols.md`](https://github.com/airdcpp-web/airdcpp-apidocs/blob/master/communication-protocols.md),
cited as `comm:<line>` (line numbers from the raw file). "FL" means **Minimum API
feature level**. "—" means the blueprint states no permission or feature level.
Where a blueprint section states a permission once for all its listeners, the
tables repeat it.

---

## How calls map to the WebSocket

- **Endpoint.** `wss://<host>:<https port>/api/v1/` (`comm:60-63`). The Daemon
  documents HTTP at `/api/v1/` too (`airdcpp.apib:30-34`).
- **Authentication.** Send `POST /sessions/authorize` with `username`/`password`
  (and optionally `max_inactivity`) over the socket (`comm:92-106`,
  `airdcpp.apib:3661-3674`). Basic HTTP auth is not enough for WebSockets
  (`comm:65`). The response is **Authentication info**: `auth_token`,
  `session_id` (FL4), `user` (the web user, with `permissions`), and
  `system_info` (`airdcpp.apib:3778-3785`). A socket can also attach to an
  existing session with `POST /sessions/socket {auth_token}`
  (`airdcpp.apib:3676-3685`, `comm:68-90`). Sessions with a connected socket
  never expire (`airdcpp.apib:3671`). `AirDC/OldAirDCApp.swift` already makes
  this call, and then `GET /favorite_hubs/{start}/{count}`, which was the one
  call proven to work.
- **Feature level.** `system_info.api_feature_level` (`airdcpp.apib:4737-4740`)
  comes back in the authorize response. The App should read it once per
  Connection and gate features on it. The highest FL the blueprint mentions is 10
  (e.g. `airdcpp.apib:474`, `4801`).
- **Permissions.** `user.permissions` (`airdcpp.apib:3784`, `5152-5157`) lists the
  web user's permissions. `admin` grants everything (`airdcpp.apib:5161`). A
  missing permission comes back as `code: 403` with an error message
  (`comm:144-154`). The App should hide or disable features the user lacks
  permissions for.
- **Requests.** Each request is a JSON object
  `{method, path, callback_id, data}` whose `method`/`path` match the HTTP
  routes in the blueprint. The response is `{code, callback_id, data}` or
  `{code, callback_id, error: {message}}` (`comm:111-154`). Responses may arrive
  out of order. Without a `callback_id` the Daemon sends no response
  (`comm:129-130`). **Every method in this document works over the WebSocket this
  way.**
- **Event listeners.** Subscribe with `POST /<section>/listeners/<event>`.
  Unsubscribe with `DELETE` on the same path (`comm:157-182`). Event messages
  look like `{event, data}`. The blueprint shows only the `data` part as a
  "response" (`comm:186-187`).
  - **Per-entity** listeners are added with
    `POST /<section>/<entity id>/listeners/<event>`. Their events also carry
    `id` (the entity ID) (`comm:189-206`).
  - Every per-entity listener can also be added **globally**, without the
    entity ID. Global events still carry `id` (`comm:208-212`). The blueprint
    says the same for each group, e.g. hubs `airdcpp.apib:1710`, private chat
    `2333`, filelists `1102`, search `3357`.
  - **All subscriptions are reset when the socket disconnects** (`comm:184`).
    After each reconnect the App must re-authenticate, re-subscribe and
    re-fetch its snapshots.
- **Hooks** (`comm:215-284`) make the Daemon block until the subscriber resolves
  or rejects each event. The App should use only listeners, never hooks
  (`airdcpp.apib:1728`, `2351`, `2908`).
- **The pattern the App will use everywhere:** subscribe to the listeners first,
  then fetch the snapshot with `GET`, then apply events on top of it. If the App
  fetches first, it can miss events that fire between the fetch and the
  subscription.

---

## 1. Favorite hubs

### Methods

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /favorite_hubs/{start}/{count}` | List favorites (paged) (`airdcpp.apib:499-512`) | favorite_hubs_view | — |
| `GET /favorite_hubs/{hub_id}` | Get one (`airdcpp.apib:540-550`) | favorite_hubs_view | — |
| `POST /favorite_hubs` | Create (`airdcpp.apib:514-522`) | favorite_hubs_edit | — |
| `PATCH /favorite_hubs/{hub_id}` | Update given fields (`airdcpp.apib:526-538`) | favorite_hubs_edit | — |
| `DELETE /favorite_hubs/{hub_id}` | Remove (`airdcpp.apib:552-556`) | favorite_hubs_edit | — |
| `POST /hubs` `{hub_url}` | **Connect** a favorite, i.e. open a hub session (`airdcpp.apib:1613-1623`) | hubs_edit | — |
| `DELETE /hubs/{session_id}` | Disconnect (`airdcpp.apib:1701-1705`) | hubs_edit | — |
| `POST /hubs/{session_id}/favorite` | Save an open hub as a favorite (`airdcpp.apib:1920-1927`) | hubs_edit | — |

### Event listeners (global only, `/favorite_hubs/listeners/…`, permission favorite_hubs_view, `airdcpp.apib:559-561`)

| Listener | Payload | When |
|---|---|---|
| `favorite_hub_created` | Favorite hub | A favorite was added (`airdcpp.apib:563-566`) |
| `favorite_hub_updated` | Favorite hub | A favorite changed, including its `connect_state` (`airdcpp.apib:568-571`) |
| `favorite_hub_removed` | Favorite hub | A favorite was removed (`airdcpp.apib:573-576`) |

### Key data shapes

**Favorite hub** (`airdcpp.apib:580-610`):
- `id` (number)
- `name`, `hub_url`, `hub_description`
- `nick`, `user_description`: nullable; `null` means "use the global value"
- `auto_connect`
- `connect_state {id: connecting|connected|disconnected, str, current_hub_id}`:
  `current_hub_id` is the hub session ID, 0 when not connected (`airdcpp.apib:602-608`)
- `share_profile` (Share profile basic `{id, str}`, `airdcpp.apib:4557-4560`)
- `has_password`
- Per-hub connectivity overrides (`connection_mode_v4/v6` etc.) and chat
  settings (`show_joins`, `use_main_chat_notify`, `away_message`, `log_main`,
  all FL5) (`airdcpp.apib:588-596`)

**Favorite hub request** (`airdcpp.apib:612-616`): the same base fields, with
`share_profile` as a **number**, a write-only `password`, and `auto_connect`.

### Gaps & surprises

- **There is no "connect favorite" method.** To connect, the App opens a hub
  session with the favorite's `hub_url` (`airdcpp.apib:1613-1623`). The link
  back is `Hub.favorite_hub` (0 = none, `airdcpp.apib:1775`), and the
  favorite's `connect_state.current_hub_id` points forward
  (`airdcpp.apib:608`). Disconnecting means deleting the hub session.
- The favorite list is paged, but the response has no total count
  (`airdcpp.apib:499-512`). The App has to keep paging until a page comes back
  short. The old App asked for `count = Int16.max`, which works in practice.
- `share_profile` is a number in requests but an object `{id, str}` in
  responses (`airdcpp.apib:609` vs `614`). The App needs separate request and
  response types.
- The password is write-only. Responses expose only `has_password`
  (`airdcpp.apib:610`).
- The favorite listeners are global only; there is no per-favorite listener
  (`airdcpp.apib:559`).
- The blueprint does not say whether `favorite_hub_updated` sends the whole
  object or only the changed fields. The queue and transfer update events say
  "only the updated properties" explicitly (`airdcpp.apib:2800`, `4837`). The
  App should decode every field as optional and merge.
- Choosing a share profile needs the Share profiles API (`/share_profiles`,
  `airdcpp.apib:4464`), which belongs to share management and is out of scope.
  v1 can show `share_profile.str` read-only.
- Connectivity fields are Daemon settings, so they are out of scope.

---

## 2. Hub chat

### Methods

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /hubs` | All open hub sessions (`airdcpp.apib:1604-1611`) | hubs_view | — |
| `GET /hubs/{session_id}` | One session (`airdcpp.apib:1677-1686`) | hubs_view | — |
| `POST /hubs` `{hub_url}` | Open a session (connect) (`airdcpp.apib:1613-1623`) | hubs_edit | — |
| `POST /hubs/find_by_url` | Find a session by exact URL (`airdcpp.apib:1625-1636`) | hubs_view | — |
| `DELETE /hubs/{session_id}` | Close the session (`airdcpp.apib:1701-1705`) | hubs_edit | — |
| `PATCH /hubs/{session_id}` | Update Hub settings (joins, notify) (`airdcpp.apib:1688-1699`) | hubs_edit | 5 |
| `GET /hubs/{session_id}/messages/{max_count}` | Cached message history, 0 = all (`airdcpp.apib:1797-1809`) | hubs_view | — |
| `POST /hubs/{session_id}/chat_message` | Send a message (`airdcpp.apib:1823-1832`) | hubs_send | — |
| `POST /hubs/{session_id}/status_message` | Show a local-only status line (`airdcpp.apib:1834-1843`) | hubs_edit | — |
| `POST /hubs/{session_id}/messages/read` | Mark all as read (`airdcpp.apib:1817-1821`) | hubs_view | — |
| `DELETE /hubs/{session_id}/messages` | Clear the message cache (`airdcpp.apib:1811-1815`) | hubs_edit | — |
| `GET /hubs/{session_id}/messages/highlights/{highlight_id}` | One highlight (`airdcpp.apib:1845-1852`) | hubs_view | 5 |
| `POST /hubs/{session_id}/password` | Answer the `password` state (`airdcpp.apib:1892-1902`) | hubs_edit | — |
| `POST /hubs/{session_id}/redirect` | Follow the `redirect` state (`airdcpp.apib:1904-1910`) | hubs_edit | — |
| `POST /hubs/{session_id}/reconnect` | Reconnect (`airdcpp.apib:1912-1918`) | hubs_edit | — |
| `GET /hubs/{session_id}/counts` | User and share totals (`airdcpp.apib:1929-1936`) | hubs_view | — |
| `POST /hubs/chat_message` | Broadcast to several hubs (`airdcpp.apib:1646-1658`) | hubs_send | — |

### Event listeners

| Listener | Payload | When |
|---|---|---|
| `/hubs/listeners/hub_created` | Hub | A session was opened, by anyone (`airdcpp.apib:1714-1718`) |
| `/hubs/listeners/hub_removed` | Hub | A session was closed (`airdcpp.apib:1720-1723`) |
| `/hubs/{id}/listeners/hub_updated` | Hub | Connect state, identity, message counts etc. changed (`airdcpp.apib:1945-1948`) |
| `/hubs/{id}/listeners/hub_counts_updated` | Hub counts | User or share totals changed (`airdcpp.apib:1950-1953`) |
| `/hubs/{id}/listeners/hub_message` | Chat message | A public chat message arrived, or the App's own message was echoed (`airdcpp.apib:1955-1958`) |
| `/hubs/{id}/listeners/hub_status` | Status message | A local status line was added (`airdcpp.apib:1960-1963`) |
| `/hubs/{id}/listeners/hub_text_command` | Chat command info | Text starting with `/` was submitted (`airdcpp.apib:1982-1989`, FL4) |

All of these need hubs_view (`airdcpp.apib:1712`, `1943`).

### Key data shapes

**Hub** (`airdcpp.apib:1755-1779`):
- `id` (number)
- `hub_url`
- `connect_state {id: connecting|password|connected|keyprint_mismatch|disconnected|redirect, str, data.hub_url}`:
  `data.hub_url` is set in the `redirect` state
- `identity {name, description, supports (FL9)}`
- `share_profile`
- `favorite_hub` (0 = none)
- `message_counts` (Chat message info)
- `encryption {str, trusted}`: nullable (`airdcpp.apib:5391-5394`)
- `settings {nick, show_joins, fav_show_joins, use_main_chat_notify}` (FL5)

**Message list** (`airdcpp.apib:1804-1809`): an array of single-key wrappers,
either `{chat_message: …}` or `{status_message: …}`. The App needs an enum to
decode it.

**Message base** (`airdcpp.apib:5551-5556`): `id`, `time`, `is_read`,
`highlights[]` (FL5).

**Chat message** (`airdcpp.apib:5532-5541`): `text`, `third_person`, `from`
(a full **Hub user**), and optionally `reply_to` and `to`.

**Status message** (`airdcpp.apib:5543-5549`):
- `text`
- `severity`: notify|verbose (FL8)|info|warning|error (`airdcpp.apib:5580-5586`)
- `label` (FL6)
- `type`: system|server|private|log|spam (FL8) (`airdcpp.apib:5524-5530`)

**Message highlight** (`airdcpp.apib:5558-5567`):
- `text`
- `type`: link_text|link_url|bold|user (`airdcpp.apib:5588-5593`)
- `tag`
- `position {start, end}`
- `dupe`
- `content_type`

**Chat message info** (`airdcpp.apib:5476-5479`, `5486-5492`): `total` and
`unread {mention (FL5), user, bot, status, verbose (FL8)}`.

**Chat message request** (`airdcpp.apib:5500-5504`): `text`, `third_person`.

**Hub counts** (`airdcpp.apib:1781-1784`): `share_size`, `user_count`.

### Gaps & surprises

- **Hub sessions are identified by a numeric ID, and the URL can change within
  one session**, for example after a redirect (`airdcpp.apib:1600`). The App
  must key hubs by `id`, never by URL. Favorites and history are keyed by URL,
  so the App has to translate between the two.
- **Chat history is the Daemon's in-memory cache only.** `max_count` returns the
  N most recent messages and nothing older. There is no way to page backwards
  and no way to read logs (`airdcpp.apib:1797-1802`). Scrolling back past the
  cache is not possible over the API.
- `connect_state` has two states that ask for action from the user:
  `password` (answer with `POST …/password`) and `redirect` (answer with
  `POST …/redirect`) (`airdcpp.apib:1762-1766`). **`keyprint_mismatch` has no
  API action.** The App can only show it (`airdcpp.apib:1764`).
- **Highlight `position` offsets are UTF-8 byte indices** (`airdcpp.apib:5563`).
  In Swift, map them through `String.utf8`, not through `Character` indices.
- The unread counts live on the entity (`Hub.message_counts`) and arrive with
  `hub_updated`. "Mark as read" is a separate call (`airdcpp.apib:1776`,
  `1817`). No separate event exists for unread-count changes.
- The Daemon interprets text starting with `/` as a chat command and fires
  `hub_text_command` for it (`airdcpp.apib:1982-1989`, `1743`). If the App sends
  such text through `chat_message`, the Daemon may not send it as plain chat.
  The App should decide how it treats a leading `/`.
- `GET /hubs/stats` has no documented response body (`airdcpp.apib:1638-1644`).
- Hub sessions are shared with the Web UI and every other API session. A
  `hub_created` or `hub_removed` event can come from somewhere other than the
  App.
- Message cache size and logging are Daemon settings, which are out of scope.

---

## 3. User lists (hub users)

### Methods

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /hubs/{session_id}/users/{start}/{count}` | Online users in a hub (paged) (`airdcpp.apib:1858-1869`) | hubs_view | — |
| `GET /hubs/{session_id}/users/{cid}` | One user by CID (`airdcpp.apib:1871-1878`) | hubs_view | — |
| `GET /hubs/{session_id}/users/{id}` | One user by hub user ID (`airdcpp.apib:1880-1887`) | hubs_view | — |
| `GET /hubs/{session_id}/counts` | Total user count (`airdcpp.apib:1929-1936`) | hubs_view | — |
| `POST /users/search_nicks` | Nick autocomplete across hubs (`airdcpp.apib:4969-4982`) | — | — |
| `POST /users/search_hinted_user` `{cid, hub_url}` | Resolve a Hinted user, falling back to any hub (`airdcpp.apib:4984-4996`) | — | 4 |
| `GET /users/{cid}` | Global user (all hubs) (`airdcpp.apib:4960-4967`) | — | 1 |
| `GET /users/ignores`, `POST`/`DELETE /users/ignore/{cid}` | Ignore list (`airdcpp.apib:4934-4955`) | settings_view / settings_edit | — |
| `POST /users/slots/{cid}` | Grant an upload slot (`airdcpp.apib:5000-5016`) | settings_edit | 10 |

### Event listeners

| Listener | Payload | When |
|---|---|---|
| `/hubs/{id}/listeners/hub_user_connected` | Hub user | A user joined the hub (`airdcpp.apib:1965-1968`) |
| `/hubs/{id}/listeners/hub_user_updated` | Hub user (**ID plus changed fields only**) | A user's info changed (`airdcpp.apib:1970-1975`) |
| `/hubs/{id}/listeners/hub_user_disconnected` | Hub user | A user left the hub (`airdcpp.apib:1977-1980`) |
| `/users/listeners/user_connected` | `{user: User, was_offline}` | The user came online in any hub (`airdcpp.apib:5023-5028`) |
| `/users/listeners/user_updated` | User | A global user changed (`airdcpp.apib:5030-5033`) |
| `/users/listeners/user_disconnected` | `{user: User, went_offline}` | The user left a hub (`airdcpp.apib:5035-5040`) |
| `/users/listeners/ignored_user_added` / `_removed` | User | The ignore list changed (`airdcpp.apib:5042-5050`) |

The hub listeners need hubs_view (`airdcpp.apib:1943`). The `/users` listeners
state no permission (`airdcpp.apib:5019-5021`).

### Key data shapes

**Hub user** (`airdcpp.apib:5623-5642`), which extends Hinted user base
`{cid, hub_url}`:
- `id` (numeric, per hub, FL4)
- `hub_session_id` (FL4)
- `hub_name`
- `nick`, `description`, `tag`, `email`
- `share_size`, `file_count`
- `upload_speed`, `download_speed`
- `flags[]`: User flags `self|bot|asch|ccpm|ignored|favorite|nmdc|offline`
  (`airdcpp.apib:5650-5659`) plus Hub user flags `away|op|hidden|noconnect`
  (`airdcpp.apib:5661-5666`)
- `supports[]` (FL9)
- `ip4 {country_id, ip, str}` (nullable), `ip6` (IP)

**User** (global, `airdcpp.apib:5596-5603`): `id` (FL4, same value as `cid`),
`cid`, `nicks[]`, `hub_names[]`, `hub_urls[]`, `flags[]`.

### Gaps & surprises

- **`hub_user_updated` sends only the user ID and the changed fields**
  (`airdcpp.apib:1972`). The App needs a partial-update type keyed by `id`,
  which requires FL4 (`airdcpp.apib:5625`).
- **The user list has no Daemon-side sort, filter or search, and its ordering is
  unspecified.** The only knobs are `start`/`count` (`airdcpp.apib:1864-1866`).
  For hubs with thousands of users, the App should page the whole list once,
  keep it locally (subscribe first), and sort and filter in the App. The total
  comes from `/counts`.
- Two "get user" routes have the same path shape. The Daemon tells them apart
  by the form of the value: a 39-character CID or a numeric ID
  (`airdcpp.apib:1871-1887`).
- One person appears once per hub. There are two parallel identities: `cid`,
  which is global, and `id` / `hub_session_id`, which are per hub. The `/users`
  API is the cross-hub view (`airdcpp.apib:5021`).
- **Ignoring a user requires `settings_view` / `settings_edit`**, not a hub or
  chat permission (`airdcpp.apib:4938`, `4946`).
- Opening a user's private chat, file list or search goes through the other
  features' APIs with a Hinted user base `{cid, hub_url}` built from the Hub
  user.

---

## 4. Private messages

### Methods

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /private_chat` | All PM sessions (`airdcpp.apib:2268-2273`) | private_chat_view | — |
| `POST /private_chat` `{user: Hinted user base}` | Open a session (`airdcpp.apib:2275-2285`) | private_chat_edit | — |
| `GET /private_chat/{session_id}` | One session (`airdcpp.apib:2300-2309`) | private_chat_view | — |
| `PATCH /private_chat/{session_id}` `{hub_url}` | Change which hub messages go through (`airdcpp.apib:2311-2321`) | — | 1 |
| `DELETE /private_chat/{session_id}` | Close (`airdcpp.apib:2324-2328`) | private_chat_edit | — |
| `GET /private_chat/{session_id}/messages/{max_count}` | Cached history (`airdcpp.apib:2403-2415`) | private_chat_view | — |
| `POST /private_chat/{session_id}/chat_message` | Send (`airdcpp.apib:2417-2426`) | private_chat_send | — |
| `POST /private_chat/{session_id}/status_message` | Local status line (`airdcpp.apib:2428-2437`) | private_chat_edit | — |
| `POST /private_chat/{session_id}/read` | Mark read (`airdcpp.apib:2445-2449`) | private_chat_view | — |
| `POST /private_chat/{session_id}/clear` | Clear the cache (`airdcpp.apib:2439-2443`) | private_chat_edit | — |
| `GET /private_chat/{session_id}/messages/highlights/{highlight_id}` | Highlight (`airdcpp.apib:2451-2458`) | private_chat_view | 5 |
| `POST` / `DELETE /private_chat/{session_id}/ccpm` | Start or stop an encrypted direct channel (`airdcpp.apib:2460-2476`) | private_chat_edit | — |
| `POST /private_chat/chat_message` | One-off "announcement" send without a session (`airdcpp.apib:2287-2296`) | private_chat_send | — |

### Event listeners

| Listener | Payload | When |
|---|---|---|
| `/private_chat/listeners/private_chat_created` | Private chat | A session was opened, **including by an incoming message from a new user** (`airdcpp.apib:2337-2341`) |
| `/private_chat/listeners/private_chat_removed` | Private chat | A session was closed (`airdcpp.apib:2343-2346`) |
| `/private_chat/{id}/listeners/private_chat_updated` | `{session: Private chat}` | The CCPM state or message counts changed (`airdcpp.apib:2485-2489`) |
| `/private_chat/{id}/listeners/private_chat_message` | Chat message | A message was received or sent (`airdcpp.apib:2491-2494`) |
| `/private_chat/{id}/listeners/private_chat_status` | Status message | A status line was added (`airdcpp.apib:2496-2499`) |
| `/private_chat/{id}/listeners/private_chat_text_command` | Chat command info | A `/command` was submitted (`airdcpp.apib:2501-2508`, FL4) |

All of these need private_chat_view (`airdcpp.apib:2335`, `2483`).

### Key data shapes

**Private chat** (`airdcpp.apib:2379-2390`):
- `id`: the **CID string**
- `user` (Hinted user base in the blueprint)
- `ccpm_state {id: connecting|connected|disconnected, str, encryption}`
- `message_counts` (Chat message info)

Messages use the same Chat message / Status message shapes as hub chat. For
PMs, `to` and `reply_to` matter: a bot or chat room can relay messages, so
`from` differs from `reply_to` (`airdcpp.apib:5536-5541`).

### Gaps & surprises

- **A PM session ID is the other user's CID, a string**
  (`airdcpp.apib:2381`), while hub session IDs are numbers. That means one
  session per *user*, not per user and hub. The hub the messages go through is
  a mutable property, set with `PATCH …{hub_url}` (`airdcpp.apib:2319`).
- **To see new incoming conversations, the App must listen globally.** No
  session exists until the first message arrives (`airdcpp.apib:2357`), so the
  App needs the global `private_chat_created` listener plus global (not
  per-session) `private_chat_message` to catch the first message.
- `private_chat_updated` wraps its payload as `{session: …}`
  (`airdcpp.apib:2488-2489`), unlike `hub_updated`, which sends the bare Hub
  (`airdcpp.apib:1947-1948`). This could be a blueprint inaccuracy and should be
  checked against a live Daemon.
- The blueprint types `Private chat.user` as the bare `Hinted user base`
  (`{cid, hub_url}`, `airdcpp.apib:2382`, `5605-5608`), which has no nick. If
  that is accurate, the App must resolve nicks with
  `POST /users/search_hinted_user` (FL4). This also needs live verification.
- The endpoints are inconsistent with hub chat. Clearing the cache is
  `POST …/clear` here but `DELETE …/messages` for hubs
  (`airdcpp.apib:2439` vs `1811`). Mark-read is `POST …/read` here but
  `POST …/messages/read` for hubs (`airdcpp.apib:2445` vs `1817`).
- `PATCH /private_chat/{id}` lists no required permission
  (`airdcpp.apib:2311-2321`).
- History has the same limit as hub chat: the in-memory cache only, and no
  paging.
- The one-off `POST /private_chat/chat_message` is meant for announcements. It
  creates a session only with `echo: true` or when the other user replies
  (`airdcpp.apib:2289`, `2395`). The App should use sessions.

---

## 5. Search

### Methods

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `POST /search` `{expiration, owner_suffix}` | Create a search instance (`airdcpp.apib:3258-3268`) | search | owner_suffix: 4 |
| `GET /search` | List instances (`airdcpp.apib:3250-3255`) | search | — |
| `GET /search/{instance_id}` | Instance state (result count, queue time) (`airdcpp.apib:3270-3279`) | search | — |
| `DELETE /search/{instance_id}` | Remove the instance (`airdcpp.apib:3281-3285`) | search | — |
| `POST /search/{instance_id}/hub_search` `{query, priority, hub_urls}` | Run a hub search (`airdcpp.apib:3500-3514`) | search | — |
| `POST /search/{instance_id}/user_search` `{query, user, options}` | Search one ADC user (`airdcpp.apib:3516-3536`) | search | — |
| `GET /search/{instance_id}/results/{start}/{count}` | Grouped results by relevance (`airdcpp.apib:3540-3557`) | search | — |
| `GET /search/{instance_id}/results/{result_id}` | One grouped result (`airdcpp.apib:3560-3567`) | search | — |
| `GET /search/{instance_id}/results/{result_id}/children` | Per-user results in a group (`airdcpp.apib:3599-3606`) | search | — |
| `POST /search/{instance_id}/results/{result_id}/download` | Queue a result (`airdcpp.apib:3570-3596`) | download | — |
| `GET /search/types` | File-type choices, including custom ones (`airdcpp.apib:3290-3296`) | — | — |
| `GET /histories/strings/search_pattern` | Past search terms (`airdcpp.apib:1494-1514`) | — | — |
| `POST /histories/strings/search_pattern` | Save a search term (`airdcpp.apib:1516-1527`) | — | — |

### Event listeners (per instance `/search/{id}/listeners/…`, or global `/search/listeners/…`; permission search, `airdcpp.apib:3613`)

| Listener | Payload | When |
|---|---|---|
| `search_hub_searches_queued` | Search queue info | Hub searches entered the Daemon's outgoing queue (`airdcpp.apib:3615-3622`, FL4) |
| `search_hub_searches_sent` | `{sent, search_id, query (FL4)}` | All queued hub searches were sent (`airdcpp.apib:3624-3632`) |
| `search_result_added` | `{result: Grouped search result, search_id}` | A new group appeared (`airdcpp.apib:3634-3639`) |
| `search_result_updated` | `{result: Grouped search result, search_id}` | An existing group got more hits (`airdcpp.apib:3641-3646`) |
| `search_user_result` | User search result | Any single user hit arrived (`airdcpp.apib:3648-3651`) |
| `search_instance_created` / `_removed` (global) | Search instance | An instance was created or removed (`airdcpp.apib:3362-3378`, FL4) |
| `search_types_updated` (global) | none | Search types changed (`airdcpp.apib:3380-3386`, FL3) |

### Key data shapes

**Search query** (`airdcpp.apib:5345-5358`):
- `pattern`
- `file_type`: any|tth|directory|file, a File content ID, or a custom type ID
  (`airdcpp.apib:5348-5365`, `5452-5460`)
- `extensions[]`: conflicts with `file_type`
- `min_size`, `max_size`
- `excluded[]`

**Search instance** (`airdcpp.apib:3418-3428`):
- `id` (number)
- `expires_in` (milliseconds)
- `current_search_id`
- `owner` (FL4)
- `queue_time`, `queued_count`
- `result_count`
- `searches_sent_ago`
- `query` (FL4)

**Search queue info** (`airdcpp.apib:3787-3792`): `queued_count`, `search_id`,
`queue_time` (milliseconds), `query`.

**Grouped search result** (`airdcpp.apib:3454-3470`):
- `id`: a **string**, TTH-like
- `name`, `path`
- `type`: File item type, which is a Folder type
  `{id: directory, str, files, directories}` or a File type
  `{id: file, str, content_type}` (`airdcpp.apib:5427-5443`, `5462-5467`)
- `size`, `time`
- `tth` (nullable)
- `relevance`
- `hits`
- `users {count, user: Hinted user}`
- `slots {free, total, str}`
- `connection`
- `dupe {id: share_*|queue_*|finished_*|share_queue, paths[]}` (`airdcpp.apib:5396-5406`)

**User search result** (`airdcpp.apib:3472-3486`): `id`, `user`, `slots`,
`connection`, `ip`, `time`, `path`. The fields `name`, `tth`, `dupe`, `size`
and `type` require FL9.

**Download response** (`airdcpp.apib:3592-3596`): *either*
`{bundle_info: Queue bundle add info}` for a file *or*
`{directory_downloads: [Directory download item]}` for a directory.

### Gaps & surprises

- **Results belong to a search instance, and each new search in an instance
  clears the old results.** `hub_search` and `user_search` both "cancel possible
  hub searches that were queued earlier and clear the cached results"
  (`airdcpp.apib:3502`, `3518`). For search tabs, the App should use one
  instance per tab. Result events carry `search_id` (`airdcpp.apib:3639`,
  `3646`), so the App can drop late events from an older search in the same
  instance.
- **Instances expire after 30 minutes by default**
  (`airdcpp.apib:3264-3265`). A search tab that stays open must pass
  `expiration: 0` or handle `search_instance_removed`.
- **Searches are not instant.** They pass through a per-hub, priority-ordered
  outgoing queue, and the send time is unknown when they are queued
  (`airdcpp.apib:3155-3164`). Hubs may kick users for search spam, and the
  Daemon may reject searches when its queue is too long
  (`airdcpp.apib:3157`, `3195`).
- **No event says a search is done.** Results trickle in from peers
  (`airdcpp.apib:3098-3105`). The recommended approach is to wait a few seconds
  after `search_hub_searches_sent`, then treat the search as complete and show
  "no results" if `result_count == 0` (`airdcpp.apib:3221-3235`). The App needs
  a local timer for its "searching…" state.
- **Results are grouped by the Daemon.** Files are grouped by TTH. ADC
  directories are grouped by exact size plus name. NMDC directories are not
  grouped (`airdcpp.apib:3544-3548`). The list is sorted by relevance only,
  with no sort parameter. A view sorted any other way requires fetching every
  result and sorting in the App.
- **Priority numbers conflict.** The Priority ID enum is 2 = Lowest … 6 =
  Highest (`airdcpp.apib:5408-5414`). `hub_search` says "Defaults to 'Low'"
  with `Default: 2` (`airdcpp.apib:3509-3510`), but 2 is Lowest. The code
  samples use `priority: 1 // Lowest (1-5)` and `5` for manual searches
  (`airdcpp.apib:3186`, `3242`). The App should send `5`/`6` for searches the
  user starts, and confirm the valid range against a live Daemon.
- `user_search` works only with ADC users. The `options` field needs a user
  with the `asch` flag (`airdcpp.apib:3520-3522`).
- **Downloading a directory result is a two-step operation.** The Daemon first
  downloads the peer's file list, then creates a bundle
  (`airdcpp.apib:3580-3584`). The App must track the returned Directory
  download items through the file list directory-download listeners (see
  §7).
- The download target is `target_directory`, a path on the **Daemon's** disk
  (`airdcpp.apib:5370`), defaulting to the Daemon's download directory. To let
  the user pick a folder, the App would need `POST /filesystem/list_items`
  (filesystem_view, `airdcpp.apib:1299-1312`) or
  `GET /histories/strings/download_target` (`airdcpp.apib:1502`). v1 could use
  the default and recent targets only.
- The `/histories` endpoints and `GET /search/types` list no required
  permission.

---

## 6. Download queue & transfers

### Methods: queue

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /queue/bundles/{start}/{count}` | List bundles (`airdcpp.apib:2529-2538`) | queue_view | — |
| `GET /queue/bundles/{bundle_id}` | One bundle (`airdcpp.apib:2595-2600`) | queue_view | — |
| `GET /queue/bundles/{bundle_id}/files/{start}/{count}` | Files in a bundle (`airdcpp.apib:2613-2622`) | queue_view | — |
| `GET /queue/bundles/{bundle_id}/sources` | Bundle sources (`airdcpp.apib:2624-2629`) | queue_view | — |
| `POST /queue/bundles/{bundle_id}/priority` `{priority}` | Set priority, including **pause** (`airdcpp.apib:2639-2647`) | queue_edit | — |
| `POST /queue/bundles/priority` `{priority}` | Set priority on all bundles (pause or resume all) (`airdcpp.apib:2550-2560`) | queue_edit | — |
| `POST /queue/bundles/{bundle_id}/remove` `{remove_finished}` | Remove a bundle (`airdcpp.apib:2602-2611`) | queue_edit | — |
| `POST /queue/bundles/remove_completed` | Clear completed bundles (`airdcpp.apib:2540-2548`) | queue_edit | — |
| `POST /queue/bundles/{bundle_id}/search` | Search for alternate sources (`airdcpp.apib:2649-2658`) | queue_edit | — |
| `DELETE /queue/bundles/{bundle_id}/sources/{cid}` | Drop a source (`airdcpp.apib:2631-2637`) | queue_edit | — |
| `POST /queue/bundles/file` | Queue one file by TTH, size and user (`airdcpp.apib:2562-2576`) | queue_edit | — |
| `GET /queue/files/{file_id}` | One queued file (`airdcpp.apib:2676-2681`) | queue_view | — |
| `GET /queue/files/{tth}` | Files by TTH (`airdcpp.apib:2683-2693`) | queue_view | 9 |
| `POST /queue/files/{file_id}/priority` | File priority inside its bundle (`airdcpp.apib:2706-2714`) | queue_edit | — |
| `POST /queue/files/{file_id}/remove` | Remove a file (`airdcpp.apib:2695-2704`) | queue_edit | — |
| `POST /queue/files/{file_id}/search` | Search for alternates (`airdcpp.apib:2716-2720`) | queue_edit | — |
| `GET /queue/files/{file_id}/sources` | File sources (`airdcpp.apib:2722-2727`) | queue_view | — |
| `GET /queue/files/{file_id}/segments` | Segment map, for a progress bar (`airdcpp.apib:2735-2744`) | queue_view | — |
| `DELETE /queue/sources/{cid}` | Remove a user from every file (`airdcpp.apib:2780-2788`) | queue_edit | — |

### Methods: transfers

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /transfers` | All transfer connections (`airdcpp.apib:4763-4768`) | transfers | — |
| `GET /transfers/{transfer_id}` | One transfer (`airdcpp.apib:4773-4778`) | transfers | — |
| `POST /transfers/{transfer_id}/disconnect` | Disconnect; it often reconnects (`airdcpp.apib:4780-4786`) | transfers | — |
| `POST /transfers/{transfer_id}/force` | Connect now (`airdcpp.apib:4788-4794`) | transfers | — |
| `GET /transfers/stats` | Totals: speeds, limits, counts (`airdcpp.apib:4814-4821`) | transfers | — |
| `GET /transfers/transferred_bytes` | Session and all-time bytes (`airdcpp.apib:4799-4812`) | transfers | 10 (earlier misspelled `tranferred_bytes`) |

### Event listeners

Queue listeners are **global only**. The blueprint states no permission for them
(`airdcpp.apib:2791`, `2848`); `queue_view` is the natural requirement.

| Listener | Payload | When |
|---|---|---|
| `/queue/listeners/queue_bundle_added` | Queue bundle | A new bundle was created (`airdcpp.apib:2793-2796`) |
| `/queue/listeners/queue_bundle_removed` | Queue bundle | A bundle was removed (`airdcpp.apib:2842-2845`) |
| `/queue/listeners/queue_bundle_tick` | Queue bundle | About once per second while downloading (`airdcpp.apib:2821-2826`) |
| `/queue/listeners/queue_bundle_status` | Queue bundle | The status ID changed, e.g. completed or failed (`airdcpp.apib:2807-2812`) |
| `/queue/listeners/queue_bundle_priority` | Queue bundle | The priority changed (`airdcpp.apib:2814-2819`) |
| `/queue/listeners/queue_bundle_content` | Queue bundle | Files were added or removed; directory bundles only (`airdcpp.apib:2828-2833`) |
| `/queue/listeners/queue_bundle_sources` | Queue bundle | Sources changed (`airdcpp.apib:2835-2840`) |
| `/queue/listeners/queue_bundle_updated` | Queue bundle (partial) | Every change; very noisy (`airdcpp.apib:2798-2805`) |
| `/queue/listeners/queue_file_{added,removed,tick,status,priority,sources,updated}` | Queue file | The same set of events for individual files (`airdcpp.apib:2848-2897`) |

Transfer listeners need the transfers permission (`airdcpp.apib:4826`).

| Listener | Payload | When |
|---|---|---|
| `/transfers/listeners/transfer_added` | Transfer item | A connection was created (`airdcpp.apib:4828-4833`) |
| `/transfers/listeners/transfer_updated` | Transfer item (partial) | Every change; noisy (`airdcpp.apib:4835-4842`) |
| `/transfers/listeners/transfer_starting` | Transfer item | A new chunk started (`airdcpp.apib:4844-4849`) |
| `/transfers/listeners/transfer_completed` | Transfer item | A chunk finished (`airdcpp.apib:4851-4856`) |
| `/transfers/listeners/transfer_failed` | Transfer item | The transfer failed, e.g. no slots or the connection closed (`airdcpp.apib:4858-4863`) |
| `/transfers/listeners/transfer_removed` | Transfer item | The connection was removed (`airdcpp.apib:4865-4868`) |
| `/transfers/listeners/transfer_statistics` | Transfer stats (changed values only) | Totals changed (`airdcpp.apib:4870-4875`) |

### Key data shapes

**Queue item base** (`airdcpp.apib:2998-3006`):
- `size`, `downloaded_bytes`
- `priority {id, str, auto}`
- `time_added`, `time_finished`
- `speed`, `seconds_left`

**Queue bundle** (`airdcpp.apib:3008-3030`):
- `id`, `name`
- `target`: a Daemon path
- `type`: File item type, either a directory `{files, directories}` or a file
- `sources {online, total, str}`
- `status {id, failed, downloaded, completed, str, hook_error}`, where `id` is
  new|queued|download_error|recheck|downloaded|completion_validation_running|completion_validation_error|completed|shared

**Queue file** (`airdcpp.apib:3032-3054`):
- `id`, `name`, `target`
- `type` (File type)
- `bundle`: the bundle ID, 0 = none
- `tth`
- `sources`
- `status {id, str, downloaded, completed, failed, hook_error}`

**Queue priority ID** (`airdcpp.apib:5416-5425`): -1 Default, 0 Paused
(forced), 1 Paused, 2 Lowest … 6 Highest. **Queue source** / **Queue bundle
source** (`airdcpp.apib:3068-3076`): `user`, `last_speed`, and for bundles also
`files`, `size`.

**Queue bundle add info** (`airdcpp.apib:2985-2988`): `id`, `merged`.

**Transfer item** (`airdcpp.apib:4880-4906`):
- `id`
- `name`, `target`
- `download`: bool, false = upload
- `type`: File type, which can be "filelist"
- `size`: the **segment** size
- `bytes_transferred`, `time_started`
- `speed`, `seconds_left`
- `user` (Hinted user)
- `status {id: waiting|finished|running|failed, str, finished}`
- `tth`
- `flags[]` (`airdcpp.apib:4908-4916`)
- `encryption`, `ip`
- `supports` (FL9)
- `queue_file_id`: downloads only

**Transfer stats** (`airdcpp.apib:4918-4929`): `speed_down/up`,
`limit_down/up`, `uploads`, `downloads`, `upload_bundles`, `download_bundles`,
`session_downloaded/uploaded`.

### Gaps & surprises

- **The queue is made of bundles. A bundle is the thing the user queued, either
  a file or a directory** (`airdcpp.apib:2514`). **Directory bundles are not
  static.** When something new is queued under an existing bundle's target, the
  Daemon merges it into that bundle (`airdcpp.apib:2520`). This is why the add
  info returns `merged: true|false` (`airdcpp.apib:2988`). Files within a bundle
  have their own priorities, which order downloads *inside* that bundle
  (`airdcpp.apib:2522`).
- **The files → bundle link is one-way in the snapshot APIs.** A Queue file has
  `bundle` (`airdcpp.apib:3038`). There is no listing of every queued file, only
  per bundle (paged) or by TTH (FL9). A queue view with expandable bundles has
  to fetch files when a bundle is expanded.
- **There is no pause or resume method.** Pausing means setting the priority to
  `1` (Paused) or `0` (Paused, forced). Resuming means setting a real priority,
  or omitting `priority` to get auto (`airdcpp.apib:2645`, `5416-5421`).
- **Removal is `POST …/remove`, not `DELETE`** (`airdcpp.apib:2602`, `2695`).
  `remove_finished` decides whether finished files on the Daemon's disk are
  deleted too.
- **Transfers are connections, not files.** One connection can carry many
  files and chunks, and `size` is the segment size (`airdcpp.apib:4757-4759`,
  `4887`). For per-file progress the blueprint points to the queue. A transfer
  links to the queue through `queue_file_id` only, never directly to a bundle
  (`airdcpp.apib:4906`). The transfer list includes uploads and file list
  transfers (`airdcpp.apib:4757`, `4886`).
- **Update and statistics events are partial.** `queue_bundle_updated`,
  `queue_file_updated` and `transfer_updated` send "only the updated
  properties" (`airdcpp.apib:2800`, `2859`, `4837`). `transfer_statistics`
  sends only changed values (`airdcpp.apib:4872`). The blueprint recommends the
  narrower events (tick, status, priority, sources) over `…_updated`
  (`airdcpp.apib:2802`). The App needs partial-merge decoding keyed by `id`.
- **`GET /queue/bundles/{start}/{count}` has no total count or sort.** The App
  pages until a short page comes back. The count comes from
  `Transfer stats.download_bundles` only for running bundles
  (`airdcpp.apib:4925`).
- **The ID types are loosely documented.** Queue bundle `id`, Queue file `id`
  and Transfer `id` have no `(number)` annotation (`airdcpp.apib:3010`, `3034`,
  `4882`). Queue bundle add info declares the bundle ID a number
  (`airdcpp.apib:2987`). The App should decode them leniently or check a live
  Daemon.
- The App never opens finished files; they live on the Daemon's disk. The App
  does not need `POST /queue/find_dupe_paths` (`airdcpp.apib:2749`) or
  `POST /queue/check_path_queued` (FL7, `airdcpp.apib:2764`). Showing "already
  in queue/share" comes from the `dupe` field on search results and file list
  items.
- Speed limits (`limit_down/up`) can be read from Transfer stats. Changing them
  requires `POST /settings/set` (settings_edit, `airdcpp.apib:3823-3836`),
  which is out of scope.
- Queue hooks (completion validation, add-bundle) are for extensions, so the
  App skips them (`airdcpp.apib:2900-2966`).

---

## 7. File lists

### Methods

| Method + path | Purpose | Permission | FL |
|---|---|---|---|
| `GET /filelists` | All file list sessions (`airdcpp.apib:969-976`) | filelists_view | — |
| `POST /filelists` `{user, directory}` | Open (download) a user's file list (`airdcpp.apib:978-990`) | filelists_edit | — |
| `POST /filelists/self` `{share_profile}` | Browse the Daemon's own share (`airdcpp.apib:992-1002`) | filelists_edit | — |
| `GET /filelists/{session_id}` | One session (`airdcpp.apib:1022-1029`) | filelists_view | — |
| `PATCH /filelists/{session_id}` `{hub_url | share_profile}` | Change the hub or profile (`airdcpp.apib:1031-1042`) | — | 1 |
| `DELETE /filelists/{session_id}` | Close (`airdcpp.apib:1044-1048`) | filelists_edit | — |
| `POST /filelists/{session_id}/directory` `{list_path, reload}` | **Change the current directory** (`airdcpp.apib:1251-1262`) | filelists_view | — |
| `GET /filelists/{session_id}/items/{start}/{count}` | Contents of the current directory (`airdcpp.apib:1214-1231`) | filelists_view | — |
| `GET /filelists/{session_id}/items/{item_id}` | One item in the current directory (`airdcpp.apib:1235-1247`) | filelists_view | 1 |
| `POST /filelists/{session_id}/read` | Mark read (`airdcpp.apib:1264-1268`) | filelists_view | — |
| `POST /filelists/directory_downloads` | Queue a directory from a list (`airdcpp.apib:1063-1078`) | download | log_bundle_errors: 6 |
| `GET /filelists/directory_downloads` | Pending directory downloads (`airdcpp.apib:1053-1060`) | download | — |
| `GET` / `DELETE /filelists/directory_downloads/{download_id}` | Poll or cancel one (`airdcpp.apib:1083-1096`) | download | GET: 3 |
| `POST /queue/bundles/file` | Queue a **file** from a list (TTH, size, user, name) (`airdcpp.apib:2562-2576`) | queue_edit | — |
| `POST /filelists/match_queue` `{user, directory}` | Add the user as a source for matching queued files (`airdcpp.apib:1004-1015`) | queue_edit | — |

### Event listeners (permission filelists_view, `airdcpp.apib:1104`, `1275`)

| Listener | Payload | When |
|---|---|---|
| `/filelists/listeners/filelist_created` | Filelist | A session was opened, by anyone (`airdcpp.apib:1106-1110`) |
| `/filelists/listeners/filelist_removed` | Filelist | A session was closed (`airdcpp.apib:1112-1115`) |
| `/filelists/{id}/listeners/filelist_updated` | Filelist | Download state, current `location`, or `read` changed (`airdcpp.apib:1277-1280`) |
| `/filelists/listeners/filelist_directory_download_added` | Directory download item | A directory download was queued (`airdcpp.apib:1117-1120`) |
| `/filelists/listeners/filelist_directory_download_processed` | `{directory_download, result: Queue directory bundle add info}` | The list was fetched and a bundle was created (`airdcpp.apib:1127-1132`) |
| `/filelists/listeners/filelist_directory_download_failed` | `{directory_download, error}` | Queueing the directory failed (`airdcpp.apib:1134-1139`) |
| `/filelists/listeners/filelist_directory_download_removed` | Directory download item | The directory download was removed (`airdcpp.apib:1122-1125`) |

### Key data shapes

**Filelist** (`airdcpp.apib:1173-1183`):
- `id`: the user's **CID string**
- `user` (Hinted user)
- `location` (Filelist item, nullable until the list is downloaded)
- `share_profile`: own list only
- `state`: Downloadable item state
  `{id: download_failed|download_pending|downloading|loading|downloaded, str, time_finished}`
  (`airdcpp.apib:5373-5382`)
- `read`
- `partial_list`
- `total_files`, `total_size`

**Filelist item** (`airdcpp.apib:1186-1196`):
- `id` (number)
- `name`, `path`
- `type` (Folder type or File type)
- `tth`: files only
- `dupe`
- `time`
- `size`
- `complete`: whether the directory's content has been downloaded

**Items response** (`airdcpp.apib:1224-1227`): `{list_path, items[]}`.

**Directory download item** (`airdcpp.apib:1199-1206`), which extends Download
params:
- `id`, `list_path`, `user`
- `state`: pending|queued|failed (FL3, `airdcpp.apib:5384-5388`)
- `queue_info` (FL3)
- `error` (FL3)
- `target_name`, `target_directory`, `priority`

**Queue directory bundle add info** (`airdcpp.apib:2990-2996`): `files_queued`,
`files_updated`, `files_failed`, `error`, `bundle {id, merged}`.

### Gaps & surprises

- **Each file list session has exactly one "current directory", and that
  cursor is shared with every API and UI session.** Filelist sessions are
  shared across API/UI sessions (`airdcpp.apib:962`), and `items` returns the
  contents of *the* current location (`airdcpp.apib:1216`). If the App and the
  Web UI browse the same user's list at once, each one's
  `POST …/directory` moves the other's view. A tree or column browser that
  shows several directories at once is not possible without repeatedly changing
  directory. The App must check `list_path` in each items response.
- **Browsing is asynchronous.** `POST …/directory` returns 204 before the
  content is ready. The Daemon uses partial lists and fetches directories on
  demand, which is slow for NMDC users (`airdcpp.apib:964`). Until the content
  arrives, `GET …/items` fails with **503** "Content of this directory is not
  yet available" (`airdcpp.apib:1229-1231`). The App should wait for
  `filelist_updated` with a `location` whose `path` matches and whose
  `complete` is true, then fetch the items.
- **The session ID is the user's CID**, so there is one list per user
  (`airdcpp.apib:1175`). Opening a list that is already open presumably reuses
  the session. The hub is changed with `PATCH {hub_url}`.
- **Filelist item `id` values are scoped to the current directory**
  (`airdcpp.apib:1237`). They are not stable across navigation.
- **Downloading uses two different APIs.** Directories go through
  `POST /filelists/directory_downloads`, where the Daemon does a recursive
  partial list fetch and then creates a bundle (`airdcpp.apib:1063-1067`).
  Files go through the generic `POST /queue/bundles/file` with the item's
  `tth`, `size` and `name` plus the list's `user` (`airdcpp.apib:2562-2576`).
  The "create directory bundle" method is not meant for this
  (`airdcpp.apib:2580`).
- Lists from non-AirDC++ users carry less directory information
  (`airdcpp.apib:962`, `1190`, `1194-1195`). The UI must accept a missing
  `time` and a directory `size` of 0.
- `PATCH /filelists/{id}` lists no required permission
  (`airdcpp.apib:1031-1042`). The per-session `filelist_updated` listener is
  documented under the global path `/filelists/listeners/filelist_updated`
  (`airdcpp.apib:1277`).
- Browsing the Daemon's own share (`/filelists/self`) is read-only browsing, so
  v1 could include it, but choosing a share profile touches share management.
- **Viewed files** (`/view_files`, `airdcpp.apib:5188-5331`) are out of scope,
  because the App never opens downloaded content. Worth knowing: their
  content is served **only over plain HTTP** at `GET /view/<file id>`, not over
  the WebSocket, and the Daemon loads the whole file into memory to serve it
  (`airdcpp.apib:5190-5206`).

---

## Cross-cutting

### User identity

There are three shapes.

- **Hinted user base** `{cid, hub_url}` (`airdcpp.apib:5605-5608`) is what the
  App *sends* to identify a user and the hub to reach them through.
- **Hinted user** (`airdcpp.apib:5610-5615`) adds display fields. `nicks` and
  `hub_names` are **preformatted strings**, e.g. `"Developer ([100]Developer)"`,
  not arrays. `hub_urls` is an array. `flags` hold the flags in the hinted hub.
- **Hub user** (`airdcpp.apib:5623-5642`) is a presence in one hub. Its
  numeric `id` and `hub_session_id` need FL4.
- **User** (`airdcpp.apib:5596-5603`) is the global view, with *arrays* for
  `nicks` and `hub_names`.

`cid` is the stable identity everywhere. The App should build a Hinted user
base from any of these shapes when calling private chat, file list, search or
queue methods.

### IDs vary by entity

| Entity | ID | Line |
|---|---|---|
| Hub session | number (URL can change) | `airdcpp.apib:1600`, `1757` |
| Favorite hub | number | `airdcpp.apib:600` |
| Private chat | CID string | `airdcpp.apib:2381` |
| File list | CID string | `airdcpp.apib:1175` |
| Search instance | number | `airdcpp.apib:3420` |
| Grouped search result | string (TTH-like) | `airdcpp.apib:3456` |
| Queue bundle / file, Transfer | not typed in the blueprint (numbers in the examples) | `airdcpp.apib:3010`, `3034`, `4882` |

Entity events carry the entity ID in the envelope's `id`, which may be a number
or a string (`comm:195-206`). The App's event envelope must decode `id`
polymorphically.

### Per-entity vs global listeners

Hubs, private chats, file lists and search instances support both kinds, and
global events still carry the entity `id` (`comm:208-212`). Favorite hubs, the
queue, transfers and users are global only. For a multi-window App, the
simplest model is **one global subscription per event type** per Connection,
routed by `id`. Subscribing per entity means extra subscribe and unsubscribe
calls on every open and close. It also misses new private chats and file lists,
since they don't exist yet when the App would subscribe.

### Partial updates

Partial updates (`airdcpp.apib:1972`, `2800`, `2859`, `4837`, `4872`) mean
most model types need an "apply patch" step: decode every field as optional and
merge by `id`. For events not marked partial (`hub_updated`,
`favorite_hub_updated`, `filelist_updated`, `private_chat_updated`) the
blueprint doesn't say. The App should assume they can be partial.

### Pagination

Only these use `{start}/{count}`:
- favorite hubs (`airdcpp.apib:499`)
- hub users (`airdcpp.apib:1858`)
- queue bundles (`airdcpp.apib:2529`)
- bundle files (`airdcpp.apib:2613`)
- search results (`airdcpp.apib:3540`)
- file list items (`airdcpp.apib:1214`)

None of them return a total. Totals, where they exist, come from elsewhere:
`Hub counts.user_count`, `Search instance.result_count`, `Folder type.files` /
`directories`. Messages use `max_count`, taking the most recent N. Hubs, private
chats, file lists and transfers return their whole list.

### Read and unread state

The Daemon tracks read state. The App shouldn't track it separately.
- Hubs and private chats carry `message_counts {total, unread {mention, user,
  bot, status, verbose}}` (`airdcpp.apib:5476-5492`), updated through the
  entity's `…_updated` event.
- Messages carry `is_read` (`airdcpp.apib:5556`).
- File lists carry `read` (`airdcpp.apib:1180`).
- Each has a "mark read" call (`airdcpp.apib:1817`, `2445`, `1264`).

Because the state is shared, reading a chat in the Web UI clears the App's badge
too. That is what the user wants.

### Everything is shared with the Web UI

Hub sessions, private chats, file lists, the queue and search instances (listed
with `owner`, `airdcpp.apib:3423`) are Daemon-wide state. `…_created` and
`…_removed` events can come from other sessions. The App must treat itself as
one of several views of the Daemon.

### Display strings

Most enums come with a Daemon-formatted `str`, e.g. `"Running (42.3%)"`,
`"2/3 online"`, `"2 folders, 49 files"`. The Daemon formats them in its own
language (`airdcpp.apib:4743` `language`). The App can show them, or use the
`id` enums and format in the App for proper Mac localisation.

### Time and number units

Timestamps are Unix seconds (e.g. `airdcpp.apib:5554`, `1194`). Speeds are
bytes per second. Durations are mixed: search `expires_in`, `queue_time` and
`searches_sent_ago` are **milliseconds** (`airdcpp.apib:3421-3427`), while
`seconds_left` is seconds (`airdcpp.apib:3006`, `4891`).

### Chat commands

Chat commands starting with `/` are processed by the Daemon and surfaced through
`…_text_command` (FL4). The outgoing-message hooks that handled commands are
deprecated (`airdcpp.apib:1743`, `2370`).

---

## Gaps

1. **Hub and PM history is limited to the Daemon's message cache.** There is no
   paging backwards and no API for chat logs (`airdcpp.apib:1797-1802`,
   `2403-2408`).
2. **The hub user list has no Daemon-side sort, filter or search, and no
   stated order.** The App must mirror the whole list locally
   (`airdcpp.apib:1858-1869`).
3. **The file list current directory is a single cursor shared with the Web
   UI.** Parallel browsing isn't possible, and loading returns 503 until the
   content arrives (`airdcpp.apib:962`, `1216`, `1229`).
4. **No event says a search is complete.** The App needs a heuristic delay after
   `search_hub_searches_sent` (`airdcpp.apib:3104`, `3221-3235`).
5. **Search results can only be sorted by relevance.** Other orders need a full
   fetch (`airdcpp.apib:3542`).
6. **The search priority range is contradictory**: enum 2–6 vs samples 1–5 vs
   "default Low = 2" (`airdcpp.apib:3186`, `3242`, `3509-3510`, `5408-5414`).
7. **There is no explicit pause or resume for the queue.** It is done through
   priority 0/1 (`airdcpp.apib:5419-5420`).
8. **There is no "connect favorite" or "disconnect favorite" method.** The App
   opens or deletes a hub session by URL (`airdcpp.apib:1613`, `1701`).
9. **`keyprint_mismatch` has no API remedy** (`airdcpp.apib:1764`).
10. **Paged lists return no totals** (see Pagination).
11. **Choosing a download target folder needs the filesystem API**
    (filesystem_view) or the download-target history. Otherwise the App uses
    the Daemon's default (`airdcpp.apib:1299-1312`, `1502`, `5370`).
12. **Speed limits are read-only in scope.** Changing them is a Daemon setting
    (`airdcpp.apib:3823`).
13. **HTTP-only:** viewed-file content (`GET /view/<id>`,
    `airdcpp.apib:5190-5206`), which is out of scope anyway. **Every in-scope
    v1 method and listener is available over the WebSocket.**
14. **Missing permission statements**: queue listeners, `/users` methods and
    listeners, `/histories`, `GET /search/types`, `PATCH /private_chat/{id}`,
    `PATCH /filelists/{id}`. Expect them to work for any authenticated user, or
    to need the neighbouring `_view` permission. Check against a live Daemon.
15. **Undocumented or ambiguous**: `GET /hubs/stats` response
    (`airdcpp.apib:1638-1644`); the `private_chat_updated` payload wrapper
    (`airdcpp.apib:2488`); whether `Private chat.user` includes a nick
    (`airdcpp.apib:2382`); the number type of queue and transfer IDs; whether
    non-"partial" update events are full objects; the listener name
    `hub_status` (`airdcpp.apib:1960`) vs `hub_status_message` in the protocol
    doc's example (`comm:193-199`). The blueprint is the likelier to be right.
16. **Ignore list and slot granting need `settings_*` permissions**, not chat
    or hub permissions (`airdcpp.apib:4938`, `4946`, `5006`).

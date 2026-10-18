# Re-authorize with a refresh token, falling back to the stored password

When the Connection can't re-attach to its auth session (`POST /sessions/socket` returns 400, as after a Daemon restart or a long sleep), the App logs in with a refresh token (`grant_type: refresh_token`) and, only if that is rejected, with the password; both are kept in the Keychain. The Daemon supports refresh tokens but doesn't document them; the Web UI has used them since 2.5.0. Each successful login, password logins included, makes a new refresh token that the Daemon saves to disk and that effectively never expires. Logging in with the last refresh token uses it up, so routine launches and Daemon restarts leave no unused tokens behind. Keeping the password means a lost token never makes the user sign in again: `airdcppd` saves its tokens only at a clean shutdown, so after a Daemon crash or power loss the App's newest token is gone.

## Considered Options

- **Password only** (the original credentials decision): rejected. Every launch would add another never-expiring refresh token to the Daemon's disk, and no one would hold it.
- **Refresh token only, no stored password**: rejected. Every Daemon crash, power cut or failed Keychain write would make the user sign in again, and the App is meant to reconnect without the user's help.

## Consequences

- A new refresh token is written to the Keychain before anything else happens on the Connection, because the old one is already used up.
- Sign Out deletes both Keychain items and ends the auth session (`DELETE /sessions/self`). The refresh token stays valid on the Daemon, because no API revokes it; only changing or deleting the web user does.
- Rejected credentials (401, or close code 1000 "Re-authentication required") are never retried automatically: five failed logins within 45 seconds lock out the IP address.

# Distribute self-signed and sandboxed, without notarization

The App ships as a direct download signed with a self-signed code-signing certificate, not notarized, and with the App Sandbox on. Notarization needs a paid Apple Developer Program membership, which this project doesn't have. Without an Apple-issued identity, the signing identity has to be one whose designated requirement stays stable across releases: the Daemon password lives in the file-based Keychain, whose item ACLs are keyed on that requirement. A self-signed certificate gives a stable requirement (identifier plus certificate leaf hash); an ad hoc signature does not. The sandbox stays because the App displays text from strangers (hub chat, nicks, file lists) and holds almost no state of its own, so the sandbox is cheap to keep and cheap to drop later.

## Considered Options

- **Developer ID and notarization**: rejected — needs the paid Apple Developer Program.
- **Ad hoc signing**: rejected — its designated requirement is the build's cdhash, so every update prompts for the Keychain password and most likely loses the Local Network permission.
- **A free Personal Team "Apple Development" certificate**: rejected — valid for one year, unconfirmed whether its requirement survives renewal, and the Xcode licence grants Apple certificate services only "to test and develop".
- **Drop the App Sandbox now, for the future local Daemon**: rejected — v1 would lose containment while displaying untrusted text, to remove an obstacle that does not exist yet.

## Consequences

- Every user's first launch goes through System Settings › Privacy & Security › Open Anyway; Sparkle strips quarantine from the updates it installs, so later versions open directly. Homebrew's main cask list is closed to the App.
- The certificate and Sparkle's EdDSA key must be kept for good. Replacing the certificate costs every user one Keychain prompt; losing the EdDSA key ends updates for existing installs, since without Developer ID there is no key-rotation fallback.
- With no Team ID, library validation rejects the App's own frameworks and Sparkle, so the hardened runtime is kept with `com.apple.security.cs.disable-library-validation`.
- A sandboxed App cannot start a non-sandboxed `airdcppd`: a child process inherits the sandbox, and since macOS 14.2 an `SMAppService` agent or daemon must be sandboxed if the App is. The future local, App-managed Daemon is expected to drop the sandbox. The system cannot move the App's sandbox folder back out, so users would re-enter the Daemon address and username, while the password survives in the Keychain.
- Joining the paid program later is possible but changes the designated requirement: one Keychain prompt per user, as for a replaced certificate.

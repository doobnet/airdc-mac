# Trust the Daemon's certificate on first use, ignoring hostname and expiry

When system trust rejects an `https` Daemon's certificate, the App shows it to the user once and, if accepted, connects from then on only while the Daemon presents exactly that certificate (SHA-256 of the DER), whatever its hostname or expiry. The Daemon's default certificate is its self-signed Direct Connect client certificate: its CN is the Daemon's CID and it has no subjectAltName, so it fails hostname validation even when installed in the Keychain, and the Daemon exposes no fingerprint over its API to verify it against. Pinning is the only policy that works with that certificate and still authenticates the Daemon after first contact. Expiry is ignored because the Daemon renews its certificate only at startup, so a long-running Daemon keeps serving it past `notAfter`.

## Considered Options

- **System trust only**: rejected — the default certificate can never pass it, so every user would need a reverse proxy or a custom certificate before signing in.
- **Trust any certificate from the configured host** (what `OldAirDCApp.swift` does for `nas`): rejected — encrypted but unauthenticated; anything that can answer for the name receives the password.
- **Pin the public key instead of the certificate**: rejected — every renewal generates a new key pair, so it survives no more than a certificate pin does.

## Consequences

- A certificate system trust accepted is recorded as such; if system trust later rejects the Daemon's certificate, that is treated as a change, not a first use.
- The user is asked again about once a year, after the Daemon restarts and renews its certificate. The App never accepts a changed certificate on its own: the CID is broadcast to hubs, so a forged certificate can look like a renewal.
- Sign Out, or changing the Daemon address's scheme, host or port, forgets the trusted certificate.

# Two-Daemon transfer proof (throwaway)

Evidence for the Wayfinder ticket "Do two local Daemons search and transfer
through a local Luadch Hub?" (doobnet/airdc-mac#12). Not production code; the
real harness is `EndToEndSupport` from the end-to-end decision (#9).

- `../EndToEndProofTests/` — **unhosted** Swift Testing bundle (no `TEST_HOST`)
  plus the `EndToEndProof` scheme. Starts a Luadch Hub and two `airdcppd`
  Daemons on loopback, seeds Daemon B's share and both Daemons' config by
  files, then drives Daemon A over the raw HTTP API: hub search → B's file
  list → download → SHA-256 check.
- `luadch` — stand-in for the planned `luadch-builder` `bin/luadch` launcher:
  per-instance dir, symlinked code, patched `cfg.tbl` (guests allowed, no
  traffic manager, no nick/desc prefixes, plain ADC only, given port).
- `build-airdcppd.sh` + `airdcpp-header-only-boost-regex.patch` — how the
  Daemon (2.14.0, dynamically linked) was built for the proof.
- `proof.py` — the same flow in Python, used to discover the API shapes.

Binaries are found on `PATH` only. The scheme's Test action prepends
`$(PROJECT_DIR)/.e2e-bin` (a local, uncommitted symlink to a directory holding
`airdcppd` and `luadch`).

# Native, statically linked Hub and Daemon binaries for end-to-end tests

End-to-end tests run a real Luadch Hub and real `airdcppd` Daemons as plain macOS processes, built by two dedicated repos (`doobnet/airdcpp-builder`, `doobnet/luadch-builder`) that publish arm64 binaries statically linked against everything outside macOS itself. We chose this over Docker because GitHub's Apple silicon runners cannot run containers (no nested virtualization), the only `airdcppd` image is amd64-only, and every test gets a fresh Hub and Daemons, so startup cost matters; static linking guards against Homebrew libraries disappearing from CI runners, which has broken us before.

## Considered Options

- **Docker (`gangefors/airdcpp-webclient`)**: rejected — amd64-only, emulated on Apple silicon, and unavailable on arm64 macOS runners; only Intel runners with Colima could run it.
- **Build from source in this repo's CI on every run**: rejected — slow, and couples App CI to the Daemon's C++ toolchain.
- **uhub instead of Luadch**: works on macOS unpatched, but Luadch was preferred for its realistic permission behaviour; Luadch needs a small macOS patch carried in its builder repo.

## Consequences

- Locally, both binaries are expected on `PATH`; CI downloads pinned releases verified by SHA-256 from a manifest in this repo. Bumping the Daemon is a manifest PR.
- A builder release fails if `otool -L` lists any library outside `/usr/lib` or `/System`.
- End-to-end tests must run in an unsandboxed process (an unhosted test bundle or the UI test runner), since sandboxed children cannot listen on ports.

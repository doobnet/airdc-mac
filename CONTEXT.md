# AirDC

A macOS-native front end for AirDC++: it drives an AirDC++ Web Client daemon rather than speaking Direct Connect itself.

## Language

**Daemon**:
A running AirDC++ Web Client server (`airdcppd`), the process that actually joins hubs and exchanges files with peers.
_Avoid_: Server, client, backend, AirDC++ Web Client (when meaning the process)

**App**:
This macOS application; a remote control for exactly one Daemon.
_Avoid_: Client, GUI

**Web UI**:
The browser interface bundled with the Daemon; the fallback for anything the App does not cover.
_Avoid_: Web client

**Hub**:
A Direct Connect server that users join to chat and to find peers to exchange files with.
_Avoid_: Server, DC server

**Daemon address**:
The base URL the Daemon serves its Web UI on (e.g. `https://nas:5601`); the App reaches the Daemon's API from it. May be plain `http` — the Daemon can be local.
_Avoid_: Host, endpoint, server URL

**Connection**:
An authenticated link between the App and its Daemon.
_Avoid_: Client, socket, session

**Session**:
Something the Daemon holds open for the user and the App lets them switch between: a connected Hub, a private conversation with one user, a browsed file list, or a search.
_Avoid_: Tab, instance, conversation, window

**Event**:
An information, warning or error message the Daemon reports about itself, such as a Hub disconnecting or a disk filling up.
_Avoid_: Log message, system log, notification

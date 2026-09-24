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

**Connection**:
An authenticated session between the App and its Daemon.
_Avoid_: Client, socket

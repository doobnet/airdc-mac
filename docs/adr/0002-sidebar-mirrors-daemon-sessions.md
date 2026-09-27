# The sidebar mirrors the Daemon's Sessions

The App's sidebar lists every hub, private message and file list Session the Daemon holds, whoever opened it — the App, the Web UI, an incoming message, or the Daemon auto-connecting a favorite hub — while Searches list only the App's own search instances. The Daemon already owns these Sessions, lists them, and announces every one opened or closed, so mirroring leaves the App with no Session bookkeeping of its own; after any reconnect, which drops all subscriptions anyway, the sidebar rebuilds from the Daemon. Search instances are the exception because every client creates its own (each has an `owner`) and they expire, so mirroring them would show other programs' searches — the Web UI keeps its searches per browser window for the same reason.

## Considered Options

- **Show only Sessions the App opened**: rejected — the App would have to persist the Session IDs it opened, reconcile them on every reconnect (hub IDs change across Daemon restarts), and special-case incoming private messages and auto-connected hubs; a Hub you are in, with people talking to you, could be invisible in the App.

## Consequences

- Closing a Session in the App closes it on the Daemon, and so in the Web UI too.
- A Session opened elsewhere appears quietly (with a badge when unread) and never takes the selection; the selected Session closed elsewhere shows a "closed" placeholder until the user moves.
- A file list's current directory is shared with every client, so it moves when the Web UI browses the same list.
- How the App recognises its own search instances across reconnects is still open (see the search Session ticket).

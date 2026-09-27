"""Throwaway: Hub + two Daemons over localhost; search -> file list -> download."""
import base64, json, os, shutil, socket, subprocess, sys, tempfile, time, urllib.request, hashlib

S = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(S, "bin")
AIRDCPPD = os.path.join(BIN, "airdcppd")
root = tempfile.mkdtemp(prefix="e2e-")
procs = []


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


def wait_port(port, timeout=10):
    end = time.time() + timeout
    while time.time() < end:
        try:
            socket.create_connection(("127.0.0.1", port), 0.2).close(); return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError(f"port {port} never opened")


class Daemon:
    def __init__(self, name, hub_port, share=None):
        self.name = name
        self.dir = os.path.join(root, name)
        self.cfg = os.path.join(self.dir, "cfg")
        self.downloads = os.path.join(self.dir, "downloads") + "/"
        os.makedirs(self.cfg); os.makedirs(self.downloads)
        self.web_port, self.tcp, self.udp, self.tls = free_port(), free_port(), free_port(), free_port()
        self.write_config(hub_port, share)

    def write_config(self, hub_port, share):
        json.dump({"version": 1, "settings": {"web_plain_port": self.web_port, "web_plain_bind_address": "127.0.0.1",
                                              "web_tls_port": 0}},
                  open(os.path.join(self.cfg, "web-server.json"), "w"))
        json.dump({"version": 1, "settings": {"users": [{"username": "test", "password": "test-password",
                                                         "permissions": ["admin"], "last_login": 0}]}},
                  open(os.path.join(self.cfg, "web-users.json"), "w"))
        share_xml = f'<Share Token="0" Name="Default"><Directory Virtual="Seed">{share}</Directory></Share>' if share else ""
        open(os.path.join(self.cfg, "DCPlusPlus.xml"), "w").write(f"""<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<DCPlusPlus><Settings>
<Nick>{self.name}</Nick>
<DownloadDirectory>{self.downloads}</DownloadDirectory>
<IncomingConnections>0</IncomingConnections>
<IncomingConnections6>-1</IncomingConnections6>
<AutoDetectIncomingConnection>0</AutoDetectIncomingConnection>
<AutoDetectIncomingConnection6>0</AutoDetectIncomingConnection6>
<ExternalIp>127.0.0.1</ExternalIp>
<NoIpOverride>1</NoIpOverride>
<MinimumSearchInterval>1</MinimumSearchInterval>
<TCPPort>{self.tcp}</TCPPort><UDPPort>{self.udp}</UDPPort><TLSPort>{self.tls}</TLSPort>
</Settings>{share_xml}</DCPlusPlus>""")
        open(os.path.join(self.cfg, "Favorites.xml"), "w").write(f"""<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<Favorites><Hubs><Hub Name="Local" Connect="1" Server="adc://127.0.0.1:{hub_port}"/></Hubs></Favorites>""")

    def start(self):
        log = open(os.path.join(self.dir, "stdout.log"), "w")
        self.proc = subprocess.Popen([AIRDCPPD, f"-c={self.cfg}"], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        procs.append(self.proc)
        wait_port(self.web_port, 20)

    def api(self, method, path, body=None):
        req = urllib.request.Request(f"http://127.0.0.1:{self.web_port}/api/v1/{path}", method=method,
                                     data=json.dumps(body).encode() if body is not None else None)
        req.add_header("Authorization", "Basic " + base64.b64encode(b"test:test-password").decode())
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=10) as r:
            data = r.read()
            return json.loads(data) if data else None


def until(desc, fn, timeout=30, every=0.2):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        last = fn()
        if last:
            return last
        time.sleep(every)
    raise RuntimeError(f"timed out: {desc} (last={last})")


t0 = time.time()
def step(msg): print(f"[{time.time()-t0:6.2f}s] {msg}", flush=True)

try:
    # Seed
    seed = os.path.join(root, "seed"); os.makedirs(os.path.join(seed, "Album"))
    payload = os.urandom(3 * 1024 * 1024 + 17)
    open(os.path.join(seed, "Album", "wayfinder-proof.bin"), "wb").write(payload)
    open(os.path.join(seed, "Album", "other.txt"), "w").write("hello\n")

    hub_port = free_port()
    hub = subprocess.Popen([os.path.join(BIN, "luadch"), os.path.join(root, "hub"), str(hub_port)],
                           stdout=open(os.path.join(root, "hub.log"), "w"), stderr=subprocess.STDOUT)
    procs.append(hub); wait_port(hub_port); step(f"hub up on {hub_port}")

    a = Daemon("daemon-a", hub_port)
    b = Daemon("daemon-b", hub_port, share=seed + "/")
    a.start(); b.start(); step(f"daemons up (web {a.web_port}, {b.web_port})")

    def joined(d):
        hubs = d.api("GET", "hubs")
        return hubs and all(h.get("connect_state", {}).get("id") == "connected" for h in hubs) and hubs
    until("A joined", lambda: joined(a)); until("B joined", lambda: joined(b)); step("both joined hub")

    def hashed():
        st = b.api("GET", "hash/stats")
        return st if st.get("hash_files_left", 1) == 0 and not st.get("hashers") else None
    until("B hashed", hashed)
    stats = until("B share has files", lambda: (lambda s: s if s.get("total_file_count", 0) >= 2 else None)(b.api("GET", "share/stats")))
    step(f"B share hashed: {stats.get('total_file_count')} files, {stats.get('total_size')} bytes")

    # Search
    inst = a.api("POST", "search", {"expiration": 10})
    sid = inst["id"]
    step(f"search instance {sid}")
    r = a.api("POST", f"search/{sid}/hub_search", {"priority": 5, "query": {"pattern": "wayfinder-proof"}})
    step(f"hub_search -> {r}")
    results = until("search results", lambda: a.api("GET", f"search/{sid}/results/0/10"), timeout=20)
    step(f"search results: {[ (x['name'], x.get('tth')) for x in results]}")
    res = results[0]

    # File list
    user = res["users"]["user"] if "users" in res else None
    step(f"result user: {json.dumps(res.get('users', {}))[:200]}")
    hinted = user or res.get("user")
    fl = a.api("POST", "filelists", {"user": {"cid": hinted["cid"], "hub_url": hinted["hub_url"]}, "directory": "/"})
    step(f"filelist posted: state={fl.get('state')}")
    cid = hinted["cid"]
    until("filelist loaded", lambda: a.api("GET", f"filelists/{cid}").get("state", {}).get("id") == "loaded", timeout=30)
    items = a.api("GET", f"filelists/{cid}/items/0/100"); print(json.dumps(items)[:600]); items = items.get("items", items)
    step(f"filelist root items: {[i['name'] for i in items]}")

    # Download
    dl = a.api("POST", f"search/{sid}/results/{res['id']}/download", {"target_directory": a.downloads})
    step(f"download queued: {dl}")
    target = os.path.join(a.downloads, "wayfinder-proof.bin")
    until("file downloaded", lambda: os.path.exists(target) and os.path.getsize(target) == len(payload), timeout=60)
    ok = hashlib.sha256(open(target, "rb").read()).digest() == hashlib.sha256(payload).digest()
    step(f"downloaded {os.path.getsize(target)} bytes; content match={ok}")
    print("PROOF", "PASSED" if ok else "FAILED")
finally:
    for p in reversed(procs):
        p.terminate()
    for p in procs:
        try: p.wait(5)
        except subprocess.TimeoutExpired: p.kill()
    print("artifacts in", root)

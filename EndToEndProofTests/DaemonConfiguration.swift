import Foundation

/// The config files an `airdcppd` reads from its `-c=` directory at startup.
struct DaemonConfiguration {
  let nick: String
  let webPort: Int
  let connectionPorts: (tcp: Int, udp: Int, tls: Int)
  let downloads: URL
  let hubURL: String
  let shareRoot: URL?
  let username = "test"
  let password = "test-password"

  func write(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try webServer.write(to: directory.appending(path: "web-server.json"), atomically: true, encoding: .utf8)
    try webUsers.write(to: directory.appending(path: "web-users.json"), atomically: true, encoding: .utf8)
    try settings.write(to: directory.appending(path: "DCPlusPlus.xml"), atomically: true, encoding: .utf8)
    try favorites.write(to: directory.appending(path: "Favorites.xml"), atomically: true, encoding: .utf8)
  }

  private var webServer: String {
    """
    {"version": 1, "settings": {"web_plain_port": \(webPort), "web_plain_bind_address": "127.0.0.1", "web_tls_port": 0}}
    """
  }

  private var webUsers: String {
    """
    {"version": 1, "settings": {"users": [{"username": "\(username)", "password": "\(password)", \
    "permissions": ["admin"], "last_login": 0}]}}
    """
  }

  private var settings: String {
    """
    <?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <DCPlusPlus><Settings>
    <Nick>\(nick)</Nick>
    <DownloadDirectory>\(downloads.path(percentEncoded: false))/</DownloadDirectory>
    <IncomingConnections>0</IncomingConnections>
    <IncomingConnections6>-1</IncomingConnections6>
    <AutoDetectIncomingConnection>0</AutoDetectIncomingConnection>
    <AutoDetectIncomingConnection6>0</AutoDetectIncomingConnection6>
    <ExternalIp>127.0.0.1</ExternalIp>
    <NoIpOverride>1</NoIpOverride>
    <MinimumSearchInterval>5</MinimumSearchInterval>
    <TCPPort>\(connectionPorts.tcp)</TCPPort>
    <UDPPort>\(connectionPorts.udp)</UDPPort>
    <TLSPort>\(connectionPorts.tls)</TLSPort>
    </Settings>\(share)</DCPlusPlus>
    """
  }

  private var share: String {
    guard let shareRoot else { return "" }
    return """
      <Share Token="0" Name="Default"><Directory Virtual="Seed">\(shareRoot.path(percentEncoded: false))/</Directory></Share>
      """
  }

  private var favorites: String {
    """
    <?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <Favorites><Hubs><Hub Name="Local" Connect="1" Server="\(hubURL)"/></Hubs></Favorites>
    """
  }
}

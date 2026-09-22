import Foundation
import Network
import Security

extension WebSocket {
  /// How the peer's certificate is verified during the TLS handshake.
  ///
  /// Only consulted for `wss` URLs.
  public struct CertificateValidation: Sendable {
    public typealias Validator =
      @isolated(any) @Sendable (sec_protocol_metadata_t, sec_trust_t) async ->
        Bool

    private let validator: Validator?

    /// Defer to the system's trust evaluation.
    ///
    /// Correct for any server with a certificate from a recognised authority,
    /// and for a self-signed one whose root is installed in the Keychain.
    public static let system = Self(validator: nil)

    /// Verify the peer with `validator` in place of the system's trust
    /// evaluation.
    ///
    /// The validator returns `true` to let the handshake proceed. It may be
    /// called more than once per connection.
    public static func custom(_ validator: @escaping Validator) -> Self {
      Self(validator: validator)
    }

    /// Accept whatever certificate `host` presents, and evaluate every other
    /// host normally.
    ///
    /// For reaching a server whose self-signed certificate you cannot install,
    /// such as a NAS on a local network. This disables authentication of that
    /// host: anything able to answer for the name is trusted, so the
    /// connection is encrypted but not proven to reach the intended machine.
    /// Prefer installing the server's root certificate and using ``system``.
    public static func trustingAnyCertificate(from host: String) -> Self {
      custom { metadata, trust in
        serverName(of: metadata) == host || isTrustedBySystem(trust)
      }
    }

    /// The protocol options to hand to `Network.WebSocket`.
    var tls: TLS {
      guard let validator else { return TLS() }
      return TLS().certificateValidator(validator)
    }
  }
}

/// The name the handshake was addressed to, as sent in the SNI extension.
private func serverName(
  of metadata: sec_protocol_metadata_t
) -> String? {
  guard let name = sec_protocol_metadata_copy_server_name(metadata) else {
    return nil
  }

  return String(validatingCString: name)
}

private func isTrustedBySystem(_ trust: sec_trust_t) -> Bool {
  SecTrustEvaluateWithError(sec_trust_copy_ref(trust).takeRetainedValue(), nil)
}

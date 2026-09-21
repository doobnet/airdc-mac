import Foundation

extension AirDCConnection {
  /// The envelope AirDC++ wraps every reply in, carrying a typed payload.
  ///
  /// Only callers that know which endpoint they asked for can decode this;
  /// the connection routes replies using ``AirDCConnection/ResponseHeader``.
  struct Response<Value: Decodable>: Decodable {
    let data: Value
  }

  /// The part of a reply that is present regardless of which endpoint
  /// produced it, and regardless of whether it succeeded.
  ///
  /// Deliberately excludes `data`: its shape varies per endpoint, and a
  /// failed request may omit it entirely.
  struct ResponseHeader: Decodable {
    struct Failure: Decodable {
      let message: String
    }

    let code: Int
    let callbackId: Int
    let error: Failure?

    enum CodingKeys: String, CodingKey {
      case code
      case callbackId = "callback_id"
      case error
    }

    /// What this reply's status code means for the request that produced it,
    /// carrying `body` through on success so the caller can decode it.
    func result(carrying body: Data) -> Result<Data, AirDCConnection.Error> {
      switch code {
      case 200..<400:
        .success(body)
      case 400..<500:
        .failure(.clientError(code: code, message: message))
      default:
        .failure(.serverError(code: code, message: message))
      }
    }

    private var message: String {
      error?.message ?? "No message provided"
    }
  }
}

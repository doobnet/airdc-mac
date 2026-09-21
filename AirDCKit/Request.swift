import Foundation

extension AirDCConnection {
  /// The envelope AirDC++ expects around an outgoing API request.
  ///
  /// Generic over the payload so it is encoded as a nested JSON value. A
  /// `Foundation.Data` payload would be encoded as a base64 string instead,
  /// which the server rejects.
  struct Request<Payload: Encodable>: Encodable {
    let method: Method
    let path: String
    let callbackId: Int
    let data: Payload

    enum CodingKeys: String, CodingKey {
      case method
      case path
      case callbackId = "callback_id"
      case data
    }
  }
}

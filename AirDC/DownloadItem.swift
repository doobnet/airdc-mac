import Foundation

struct DownloadItem: Identifiable {
  var id = UUID()
  var name: String
  var size: String
  var content: String
  var status: String
  var timeLeft: String
  var sources: String
  var priority: String
  var speed: String
  var added: String
  var finished: String
  var user: String
  var segment: String
  var flags: String
  var ip: String
}

import Foundation
import Security
import CryptoKit

final class RouteCache {
  struct Material {
    var archive: Data
    var passcode: [UInt8]
    let expiration: Date?

    mutating func wipe() {
      archive.resetBytes(in: 0..<archive.count)
      for i in passcode.indices { passcode[i] = 0 }
      passcode.removeAll(keepingCapacity: false)
    }
  }

  struct ProfileInfo {
    let url: URL
    let team: String
    let applicationIdentifier: String
    let expiration: Date?
    let isAdHoc: Bool
    let debugAllowed: Bool

    func permits(bundleId: String) -> Bool {
      guard !bundleId.isEmpty else { return true }
      let prefix = team + "."
      guard applicationIdentifier.hasPrefix(prefix) else { return false }
      let pattern = String(applicationIdentifier.dropFirst(prefix.count))
      if pattern == "*" { return true }
      if pattern.hasSuffix(".*") {
        let root = String(pattern.dropLast(1))
        return bundleId.hasPrefix(root)
      }
      return bundleId == pattern
    }

    func routedBundleId(for sourceBundleId: String) -> String? {
      guard !sourceBundleId.isEmpty else { return nil }
      if permits(bundleId: sourceBundleId) { return sourceBundleId }

      let prefix = team + "."
      guard applicationIdentifier.hasPrefix(prefix) else { return nil }
      let pattern = String(applicationIdentifier.dropFirst(prefix.count))
      guard pattern.hasSuffix(".*") else { return nil }

      let root = String(pattern.dropLast(1))
      var cleaned = sourceBundleId
        .lowercased()
        .map { ch -> Character in
          if ch.isLetter || ch.isNumber || ch == "." || ch == "-" { return ch }
          return "-"
        }
      var suffix = String(cleaned)
      while suffix.contains("..") { suffix = suffix.replacingOccurrences(of: "..", with: ".") }
      suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
      if suffix.isEmpty { suffix = "app" }

      let digest = SHA256.hash(data: Data(sourceBundleId.utf8))
      let tag = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
      let maxSuffix = max(1, 250 - root.count - tag.count - 1)
      if suffix.count > maxSuffix { suffix = String(suffix.prefix(maxSuffix)) }
      suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
      if suffix.isEmpty { suffix = "app" }
      return "\(root)\(suffix)-\(tag)"
    }
  }

  private static let k0: [UInt8] = [
    25, 164, 195, 67, 4, 167, 193, 136
  ]
  private static let k1: [UInt8] = [
    163, 68, 63, 220, 74, 99, 110, 175
  ]
  private static let k2: [UInt8] = [
    3, 93, 189, 235, 155, 171, 42, 83
  ]
  private static let k3: [UInt8] = [
    43, 114, 129, 246, 80, 149, 193, 253
  ]
  private static let px: [UInt8] = [
    90, 93, 215, 117, 126, 57, 118, 242, 26, 219, 116, 210, 204, 202, 239, 141
  ]

  private static let q2: [UInt8] = [
    138, 115, 37, 83, 32, 122, 46, 30, 114, 160, 15, 26, 17, 104, 236, 95, 132, 73, 169, 186,
    83, 59, 101, 83, 96, 97, 172, 29, 87, 111, 142, 153, 85, 166, 203, 53, 10, 190, 132, 132,
    59, 38, 87, 204, 151, 57, 81, 141, 135, 1, 159, 168, 145, 85, 199, 65, 26, 88, 240, 134,
    83, 120, 110, 170, 49, 221, 240, 215, 159, 207, 228, 235, 180, 11, 24, 209, 197, 64, 147, 165,
    45, 48, 123, 52, 177, 38, 151, 247, 214, 139, 1, 229, 198, 225, 213, 118, 25, 89, 22, 15,
    172, 62, 1, 29, 83, 245, 223, 156, 158, 181, 50, 155, 183, 141, 90, 219, 51, 42, 105, 113,
    207, 189, 128, 31, 3, 15, 121, 38, 72, 255, 157, 98, 197, 75, 197, 56, 176, 240, 250, 108,
    93, 205, 12, 147, 43, 128, 11, 49, 100, 179, 140, 186, 112, 156, 116, 142, 91, 184, 140, 225,
    69, 136, 121, 3, 232, 75, 231, 163, 17, 193, 205, 127, 171, 241, 232, 89, 12, 79, 224, 34,
    144, 207, 80, 98, 33, 126, 13, 222, 65, 228, 196, 83, 236, 239, 168, 213, 144, 178, 93, 57,
    95, 51, 167, 137, 160, 12, 7, 235, 35, 215, 69, 211, 84, 138, 136, 13, 8, 215, 221, 237,
    223, 243, 49, 10, 150, 81, 63, 99, 94, 49, 233, 225, 242, 10, 216, 162, 38, 124, 172, 26,
    124, 137, 117, 214, 112, 60, 238, 84, 15, 176, 52, 212, 147, 58, 85, 5, 87, 128, 73, 96,
    206, 185, 103, 108, 28, 51, 198, 22, 16, 50, 13, 173, 239, 208, 147, 107, 127, 51, 151, 89,
    69, 73, 218, 124, 69, 191, 66, 96, 152, 219, 186, 133, 136, 50, 126, 83, 34, 236, 31, 143,
    23, 129, 43, 18, 178, 245, 60, 208, 14, 4, 212, 159, 108, 29, 62, 217, 78, 183, 149, 184,
    184, 121, 108, 255, 18, 172, 179, 61, 13, 23, 34, 0, 81, 74, 36, 141, 143, 213, 29, 27,
    194, 105, 62, 234, 38, 155, 197, 91, 55, 191, 252, 51, 141, 242, 191, 184, 114, 41, 29, 51,
    65, 148, 176, 116, 174, 141, 17, 167, 93, 215, 162, 1, 26, 226, 216, 30, 81, 148, 203, 238,
    19, 162, 118, 34, 229, 238, 85, 195, 84, 33, 238, 21, 112, 51, 189, 107, 216, 112, 57, 138,
    96, 4, 94, 145, 167, 80, 186, 236, 200, 45, 38, 139, 144, 170, 113, 158, 78, 20, 123, 79,
    10, 62, 216, 218, 84, 148, 254, 203, 40, 32, 19, 236, 207, 119, 87, 231, 252, 95, 107, 147,
    141, 37, 216, 96, 220, 138, 219, 190, 153, 8, 55, 235, 227, 114, 83, 11, 249, 108, 245, 230,
    227, 67, 10, 243, 182, 177, 112, 227, 55, 111, 70, 163, 196, 72, 85, 188, 2, 223, 79, 27,
    213, 235, 97, 13, 93, 249, 22, 36, 134, 48, 61, 5, 30, 57, 208, 178, 64, 86, 143, 60,
    147, 44, 33, 163, 8, 72, 255, 180, 153, 73, 87, 156, 186, 2, 179, 95, 81, 152, 220, 125,
    230, 240, 60, 104, 213, 148, 191, 202, 86, 121, 72, 127, 189, 111, 100, 233, 203, 194, 153, 60,
    162, 208, 166, 141, 163, 99, 127, 165, 248, 109, 226, 204, 133, 145, 8, 196, 220, 203, 18, 170,
    176, 48, 118, 245, 158, 178, 123, 162, 100, 54, 208, 146, 130, 19, 226, 142, 55, 218, 114, 5,
    222, 219, 43, 37, 205, 158, 84, 58, 230, 185, 54, 82, 33, 41, 124, 124, 95, 5, 12, 99,
    79, 129, 34, 179, 49, 1, 71, 76, 204, 49, 172, 121, 163, 38, 184, 123, 90, 147, 80, 65,
    112, 7, 204, 229, 240, 7, 36, 143, 220, 209, 220, 23, 169, 37, 217, 251, 202, 114, 111, 47,
    209, 55, 43, 163, 249, 95, 151, 45, 107, 143, 163, 83, 20, 114, 115, 25, 185, 70, 93, 125,
    213, 26, 197, 245, 175, 214, 70, 102, 189, 239, 131, 245, 61, 167, 102, 119, 56, 88, 230, 11,
    153, 132, 61
  ]
  private static let q0: [UInt8] = [
    106, 28, 209, 136, 102, 243, 156, 172, 221, 51, 244, 101, 59, 0, 45, 161, 3, 116, 70, 7,
    25, 125, 159, 172, 120, 40, 3, 22, 193, 130, 136, 79, 43, 47, 215, 109, 85, 135, 179, 7,
    173, 35, 106, 248, 252, 129, 111, 46, 3, 218, 227, 106, 5, 222, 31, 123, 119, 29, 78, 244,
    148, 167, 145, 48, 169, 61, 157, 164, 194, 219, 98, 27, 100, 30, 46, 53, 200, 147, 135, 110,
    91, 161, 35, 204, 48, 95, 186, 208, 2, 198, 217, 28, 71, 24, 23, 213, 175, 243, 234, 155,
    117, 30, 9, 51, 91, 239, 169, 184, 176, 30, 96, 52, 76, 83, 63, 73, 221, 9, 134, 202,
    129, 39, 175, 241, 177, 174, 225, 104, 20, 42, 164, 111, 54, 220, 228, 78, 34, 213, 224, 79,
    12, 82, 88, 186, 101, 233, 183, 96, 215, 83, 11, 181, 145, 227, 11, 25, 150, 214, 154, 180,
    106, 220, 167, 96, 227, 75, 193, 144, 69, 169, 244, 169, 108, 138, 67, 230, 68, 117, 230, 205,
    23, 233, 168, 51, 248, 84, 201, 121, 121, 95, 161, 234, 178, 38, 255, 150, 233, 159, 234, 28,
    130, 227, 25, 188, 128, 239, 83, 130, 242, 87, 16, 177, 196, 246, 10, 194, 168, 53, 122, 28,
    228, 148, 152, 109, 106, 110, 109, 53, 189, 46, 251, 81, 26, 225, 1, 65, 104, 65, 143, 252,
    7, 60, 98, 53, 6, 98, 58, 82, 56, 12, 251, 143, 38, 142, 186, 227, 65, 89, 31, 131,
    75, 68, 231, 131, 172, 77, 17, 193, 79, 216, 192, 192, 28, 90, 19, 17, 13, 156, 182, 180,
    225, 228, 7, 16, 136, 191, 163, 71, 49, 205, 84, 60, 96, 247, 136, 165, 147, 29, 227, 4,
    238, 248, 95, 211, 139, 121, 170, 43, 202, 120, 202, 243, 64, 20, 150, 230, 117, 44, 203, 24,
    192, 244, 152, 51, 66, 106, 24, 30, 124, 204, 191, 100, 142, 235, 94, 179, 134, 156, 100, 23,
    45, 150, 138, 207, 64, 105, 138, 70, 6, 108, 45, 135, 230, 175, 216, 10, 86, 194, 72, 72,
    7, 14, 126, 24, 211, 127, 192, 154, 202, 141, 14, 70, 80, 51, 182, 243, 7, 5, 208, 130,
    92, 64, 159, 201, 212, 224, 0, 6, 69, 204, 97, 125, 170, 112, 240, 126, 166, 189, 7, 173,
    53, 228, 52, 179, 48, 254, 225, 46, 85, 198, 12, 118, 147, 228, 148, 102, 209, 78, 133, 26,
    202, 10, 95, 21, 128, 40, 188, 74, 96, 44, 182, 149, 128, 117, 142, 6, 53, 148, 66, 216,
    30, 20, 28, 215, 177, 103, 51, 218, 24, 116, 108, 156, 166, 100, 123, 172, 168, 202, 53, 90,
    104, 166, 225, 106, 202, 194, 204, 0, 25, 24, 22, 93, 251, 166, 165, 120, 91, 2, 82, 155,
    103, 239, 3, 44, 177, 122, 253, 57, 90, 85, 71, 199, 18, 75, 46, 81, 15, 100, 40, 229,
    29, 106, 131, 108, 74, 110, 31, 176, 62, 226, 197, 141, 210, 219, 84, 149, 54, 201, 186, 126,
    191, 11, 208, 238, 53, 163, 1, 219, 60, 173, 61, 138, 49, 161, 38, 117, 60, 82, 8, 67,
    36, 93, 251, 152, 38, 178, 185, 120, 115, 91, 243, 0, 148, 64, 244, 72, 61, 193, 236, 236,
    101, 244, 245, 2, 98, 45, 73, 139, 217, 26, 226, 211, 147, 154, 150, 248, 229, 116, 160, 104,
    101, 143, 68, 175, 219, 22, 191, 65, 199, 30, 173, 176, 4, 120, 56, 232, 123, 137, 69, 86,
    23, 69, 118, 238, 165, 139, 101, 59, 95, 163, 174, 188, 255, 10, 49, 32, 170, 158, 249, 12,
    83, 18, 48, 111, 211, 204, 77, 197, 234, 76, 231, 171, 114, 37, 50, 168, 24, 0, 219, 79,
    43, 197, 3, 133, 36, 0, 158, 102, 82, 168, 124, 176, 130, 218, 167, 223, 214, 178, 107, 192,
    41, 77, 63, 68, 142, 181, 252, 216, 38, 104, 20, 195, 216, 53, 81, 140, 55, 1, 55, 43,
    85, 223, 106
  ]
  private static let q4: [UInt8] = [
    81, 58, 118, 133, 233, 252, 156, 140, 255, 152, 147, 207, 101, 139, 91, 123, 80, 140, 58, 56,
    49, 90, 20, 183, 191, 12, 30, 215, 229, 185, 235, 130, 213, 37, 162, 150, 227, 122, 25, 242,
    50, 210, 204, 72, 231, 27, 182, 217, 198, 36, 190, 173, 178, 41, 67, 244, 98, 8, 255, 162,
    117, 173, 96, 99, 236, 153, 67, 51, 129, 19, 119, 205, 100, 143, 83, 165, 136, 36, 79, 3,
    97, 38, 168, 163, 246, 79, 167, 168, 117, 110, 34, 119, 57, 241, 180, 88, 21, 109, 140, 61,
    218, 154, 114, 176, 10, 0, 130, 207, 157, 194, 230, 237, 150, 87, 5, 61, 237, 51, 188, 77,
    162, 62, 12, 222, 169, 8, 253, 176, 170, 42, 207, 12, 221, 43, 97, 7, 245, 116, 143, 58,
    140, 195, 9, 214, 221, 23, 166, 203, 232, 252, 212, 233, 104, 217, 213, 148, 241, 54, 189, 69,
    247, 245, 81, 27, 2, 26, 79, 113, 180, 112, 7, 15, 197, 57, 48, 203, 53, 44, 250, 94,
    60, 226, 244, 115, 123, 143, 204, 97, 114, 251, 179, 216, 214, 126, 126, 79, 102, 206, 174, 104,
    15, 180, 138, 68, 135, 71, 191, 211, 118, 58, 72, 93, 124, 224, 62, 198, 136, 79, 115, 36,
    51, 68, 68, 198, 98, 65, 68, 53, 137, 230, 170, 54, 124, 182, 154, 42, 240, 51, 21, 210,
    183, 145, 96, 169, 169, 97, 154, 44, 247, 178, 138, 11, 248, 4, 118, 116, 57, 171, 6, 140,
    111, 50, 225, 188, 229, 245, 34, 168, 136, 231, 151, 54, 36, 6, 122, 241, 42, 39, 53, 90,
    46, 197, 241, 232, 198, 50, 168, 147, 27, 139, 253, 85, 46, 72, 59, 99, 1, 3, 15, 253,
    219, 179, 65, 146, 89, 206, 43, 18, 78, 77, 203, 53, 244, 117, 206, 189, 45, 104, 156, 127,
    220, 238, 124, 30, 203, 167, 55, 5, 200, 213, 133, 162, 136, 23, 29, 78, 1, 185, 63, 8,
    80, 160, 55, 8, 14, 124, 77, 101, 252, 3, 45, 24, 17, 225, 250, 87, 178, 105, 205, 42,
    163, 208, 169, 19, 224, 153, 74, 181, 233, 213, 161, 196, 220, 179, 219, 141, 169, 10, 208, 148,
    213, 165, 121, 28, 248, 243, 33, 168, 192, 153, 19, 222, 73, 86, 84, 69, 23, 222, 178, 40,
    223, 83, 231, 212, 117, 218, 56, 145, 82, 131, 88, 240, 85, 166, 216, 61, 222, 146, 189, 168,
    212, 24, 114, 53, 117, 51, 24, 205, 3, 248, 121, 150, 0, 165, 174, 192, 229, 99, 232, 71,
    171, 226, 252, 130, 62, 223, 42, 176, 48, 52, 201, 4, 174, 54, 40, 36, 246, 220, 97, 144,
    88, 155, 214, 142, 176, 181, 184, 242, 197, 9, 226, 20, 15, 47, 232, 57, 187, 120, 186, 164,
    48, 241, 24, 237, 244, 150, 218, 144, 80, 138, 28, 123, 70, 41, 15, 42, 128, 252, 124, 123,
    179, 194, 60, 243, 235, 5, 73, 65, 5, 119, 5, 18, 88, 73, 173, 94, 75, 137, 130, 188,
    170, 6, 63, 138, 69, 184, 178, 104, 248, 57, 222, 76, 20, 114, 245, 255, 237, 51, 2, 41,
    51, 233, 150, 199, 232, 86, 113, 57, 16, 234, 78, 99, 223, 63, 16, 255, 224, 151, 190, 58,
    4, 3, 204, 240, 227, 103, 244, 62, 251, 122, 118, 61, 173, 131, 192, 224, 101, 248, 241, 238,
    10, 192, 115, 43, 15, 20, 237, 125, 20, 112, 77, 227, 232, 50, 171, 106, 9, 84, 40, 88,
    217, 215, 96, 40, 233, 220, 237, 28, 139, 210, 86, 212, 92, 31, 219, 126, 225, 171, 15, 39,
    33, 152, 186, 73, 21, 210, 111, 84, 18, 5, 131, 192, 30, 3, 26, 86, 156, 172, 187, 53,
    105, 100, 63, 251, 200, 172, 38, 2, 247, 31, 101, 55, 20, 233, 239, 197, 251, 25, 25, 50,
    221, 54, 96, 209, 225, 61, 142, 67, 7, 181, 37, 210, 129, 112, 239, 87, 218, 67, 177, 54
  ]
  private static let q1: [UInt8] = [
    33, 178, 152, 105, 33, 129, 97, 69, 253, 14, 132, 195, 69, 78, 113, 213, 103, 162, 47, 130,
    162, 94, 141, 253, 58, 91, 117, 100, 161, 136, 97, 89, 159, 34, 6, 97, 7, 124, 13, 195,
    149, 233, 86, 235, 234, 221, 71, 149, 177, 184, 195, 88, 26, 58, 223, 39, 20, 106, 251, 221,
    90, 16, 83, 165, 52, 1, 187, 92, 239, 173, 2, 245, 5, 29, 147, 106, 195, 108, 151, 119,
    81, 129, 135, 248, 232, 218, 142, 12, 232, 68, 115, 180, 168, 43, 53, 155, 18, 226, 142, 211,
    249, 201, 209, 95, 247, 158, 193, 160, 65, 8, 192, 85, 19, 150, 155, 253, 136, 104, 188, 53,
    226, 32, 66, 145, 85, 166, 48, 159, 56, 82, 142, 150, 164, 92, 40, 106, 26, 124, 84, 239,
    204, 218, 90, 113, 75, 110, 38, 167, 81, 33, 146, 174, 241, 140, 64, 143, 221, 100, 8, 189,
    129, 204, 186, 109, 167, 120, 165, 116, 10, 155, 28, 64, 140, 176, 59, 22, 164, 152, 193, 231,
    139, 167, 210, 77, 209, 159, 0, 159, 98, 39, 42, 83, 16, 138, 87, 150, 236, 88, 161, 78,
    139, 111, 204, 85, 254, 14, 177, 208, 105, 213, 49, 139, 98, 205, 129, 66, 203, 187, 154, 25,
    41, 75, 59, 152, 193, 199, 162, 188, 98, 32, 203, 7, 238, 140, 203, 5, 139, 192, 7, 144,
    177, 78, 211, 59, 151, 128, 199, 228, 92, 34, 64, 186, 82, 143, 253, 35, 64, 234, 139, 218,
    236, 52, 138, 134, 22, 97, 152, 32, 126, 210, 229, 79, 97, 146, 179, 161, 135, 116, 34, 93,
    187, 221, 158, 217, 247, 80, 85, 221, 176, 80, 232, 229, 95, 151, 255, 230, 68, 188, 209, 154,
    118, 79, 27, 41, 37, 253, 30, 254, 200, 143, 245, 194, 17, 46, 220, 247, 148, 89, 124, 79,
    23, 37, 70, 200, 122, 50, 88, 29, 158, 177, 13, 89, 251, 255, 239, 156, 175, 92, 79, 105,
    8, 43, 101, 134, 0, 207, 196, 40, 75, 137, 57, 43, 16, 188, 204, 93, 112, 248, 152, 14,
    49, 244, 184, 233, 21, 8, 52, 120, 216, 223, 105, 209, 202, 82, 0, 57, 98, 7, 115, 11,
    236, 51, 97, 132, 99, 40, 253, 85, 119, 78, 83, 78, 64, 154, 226, 249, 60, 78, 73, 63,
    80, 102, 167, 94, 117, 52, 181, 233, 44, 39, 50, 30, 118, 191, 165, 76, 78, 106, 72, 200,
    196, 128, 112, 122, 26, 19, 204, 29, 106, 112, 164, 101, 36, 49, 56, 53, 189, 207, 10, 227,
    67, 236, 5, 89, 186, 103, 70, 133, 191, 13, 167, 79, 189, 91, 172, 53, 156, 77, 111, 219,
    110, 160, 36, 138, 24, 244, 75, 178, 32, 177, 14, 80, 237, 225, 38, 244, 173, 94, 128, 182,
    72, 138, 134, 153, 142, 111, 157, 112, 61, 151, 223, 138, 241, 108, 66, 206, 225, 21, 164, 48,
    169, 160, 21, 16, 92, 41, 171, 164, 127, 94, 228, 218, 171, 146, 145, 147, 204, 87, 144, 103,
    62, 110, 184, 70, 229, 208, 193, 231, 83, 184, 73, 17, 49, 170, 174, 104, 139, 219, 87, 96,
    127, 147, 59, 163, 218, 104, 47, 234, 100, 87, 236, 80, 189, 35, 47, 120, 235, 86, 68, 36,
    225, 167, 6, 130, 131, 56, 173, 105, 137, 153, 189, 254, 6, 147, 176, 23, 25, 182, 155, 252,
    88, 136, 25, 48, 134, 224, 63, 188, 193, 7, 151, 158, 89, 88, 32, 249, 37, 183, 91, 246,
    237, 17, 125, 93, 13, 160, 159, 169, 159, 254, 173, 213, 44, 69, 231, 117, 152, 251, 238, 156,
    72, 113, 244, 34, 192, 162, 42, 7, 29, 106, 209, 32, 112, 197, 96, 36, 194, 241, 188, 253,
    158, 16, 105, 30, 216, 24, 183, 196, 221, 39, 182, 248, 122, 73, 177, 228, 87, 149, 16, 150,
    45, 120, 108, 2, 127, 71, 26, 116, 44, 100, 134, 218, 200, 104, 190, 145, 58, 208, 129, 175,
    255, 242, 250
  ]
  private static let q3: [UInt8] = [
    90, 133, 213, 90, 165, 38, 214, 171, 51, 21, 87, 153, 196, 117, 110, 131, 22, 62, 83, 13,
    157, 169, 29, 147, 112, 57, 96, 38, 47, 185, 40, 225, 226, 124, 93, 122, 21, 177, 171, 168,
    9, 12, 97, 213, 93, 238, 115, 36, 129, 38, 107, 90, 186, 10, 164, 142, 57, 24, 56, 23,
    21, 158, 254, 244, 220, 104, 247, 222, 54, 195, 33, 180, 221, 72, 150, 192, 197, 163, 107, 139,
    92, 197, 214, 78, 180, 93, 95, 221, 60, 145, 143, 112, 29, 234, 124, 86, 109, 58, 39, 244,
    136, 101, 44, 238, 145, 132, 114, 216, 20, 126, 113, 111, 59, 184, 159, 112, 17, 123, 16, 158,
    120, 20, 91, 16, 198, 135, 238, 170, 107, 39, 10, 183, 163, 69, 9, 200, 37, 32, 165, 8,
    253, 117, 55, 219, 131, 71, 235, 152, 162, 198, 129, 204, 168, 109, 104, 33, 79, 217, 207, 43,
    124, 155, 18, 56, 238, 224, 117, 138, 224, 3, 106, 101, 248, 187, 179, 143, 59, 65, 79, 210,
    191, 42, 189, 164, 105, 186, 119, 7, 7, 99, 112, 16, 20, 172, 227, 194, 211, 124, 146, 15,
    225, 65, 190, 203, 195, 206, 138, 82, 245, 118, 17, 24, 12, 187, 109, 100, 137, 108, 23, 105,
    88, 39, 186, 254, 139, 111, 112, 35, 186, 185, 24, 44, 10, 182, 196, 82, 239, 152, 162, 228,
    240, 221, 191, 245, 49, 157, 65, 248, 126, 34, 128, 8, 194, 62, 214, 243, 81, 253, 238, 180,
    55, 198, 175, 226, 196, 169, 193, 70, 129, 171, 16, 147, 106, 179, 106, 176, 158, 14, 145, 191,
    2, 215, 67, 59, 187, 92, 75, 138, 146, 106, 185, 102, 36, 29, 106, 70, 166, 15, 66, 31,
    77, 66, 149, 149, 150, 223, 208, 170, 82, 207, 228, 131, 182, 188, 203, 253, 176, 117, 201, 193,
    81, 225, 222, 222, 229, 5, 141, 37, 175, 89, 224, 147, 232, 54, 209, 172, 130, 13, 242, 80,
    35, 65, 109, 201, 27, 240, 42, 69, 67, 254, 231, 248, 141, 92, 236, 97, 126, 48, 240, 254,
    119, 222, 5, 189, 169, 235, 32, 228, 24, 194, 49, 26, 179, 38, 154, 229, 0, 46, 191, 113,
    5, 77, 60, 188, 32, 223, 131, 193, 10, 90, 241, 0, 172, 71, 123, 69, 194, 167, 202, 158,
    65, 210, 159, 66, 190, 58, 156, 181, 77, 160, 126, 125, 185, 242, 163, 218, 162, 12, 244, 235,
    135, 149, 141, 67, 180, 217, 152, 13, 47, 220, 146, 112, 161, 7, 39, 16, 163, 30, 94, 45,
    215, 93, 112, 161, 14, 232, 72, 128, 156, 58, 38, 157, 33, 225, 213, 172, 175, 26, 110, 1,
    115, 212, 55, 179, 189, 186, 109, 79, 242, 42, 116, 232, 6, 21, 136, 179, 104, 0, 28, 158,
    55, 244, 245, 90, 163, 213, 188, 220, 178, 26, 201, 234, 140, 44, 241, 51, 119, 172, 31, 74,
    13, 127, 123, 162, 191, 232, 255, 134, 142, 60, 128, 77, 154, 152, 168, 63, 194, 22, 59, 251,
    189, 25, 32, 163, 125, 120, 59, 249, 62, 16, 131, 61, 0, 175, 231, 84, 255, 102, 102, 168,
    192, 220, 180, 41, 86, 250, 238, 162, 83, 51, 153, 105, 189, 240, 0, 241, 253, 242, 172, 189,
    153, 79, 132, 129, 102, 161, 252, 164, 109, 86, 87, 168, 59, 206, 55, 163, 92, 48, 94, 251,
    54, 34, 68, 120, 31, 15, 143, 141, 14, 118, 43, 224, 230, 70, 71, 164, 94, 23, 138, 61,
    186, 178, 57, 64, 172, 41, 158, 217, 140, 106, 135, 137, 33, 49, 38, 213, 143, 65, 163, 10,
    188, 30, 44, 86, 100, 200, 195, 156, 213, 186, 79, 106, 197, 235, 103, 38, 65, 250, 136, 111,
    73, 28, 87, 203, 232, 14, 19, 237, 52, 73, 128, 15, 2, 76, 204, 253, 132, 138, 32, 149,
    156, 66, 55, 2, 185, 83, 229, 86, 230, 61, 154, 102, 33, 3, 57, 81, 122, 242, 161, 83,
    47, 35, 12
  ]

  private static let service = "io.booma.route.v4"
  private static let keySlot = "n7"
  private static let fileName = ".r4-cache"
  private static let gate = NSLock()

  static func prime() throws { _ = try material() }

  static func state() -> [String: Any] {
    do {
      let profile = try profileInfo()
      guard profile.isAdHoc, !profile.debugAllowed else { return ["ready": false] }
      if let d = profile.expiration, d <= Date() { return ["ready": false] }
      var value = try material()
      defer { value.wipe() }
      if let d = value.expiration, d <= Date() { return ["ready": false] }
      guard !value.archive.isEmpty, !value.passcode.isEmpty else { return ["ready": false] }
      let validUntil: Date? = {
        switch (profile.expiration, value.expiration) {
        case let (a?, b?): return min(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
      }()
      let formatter = ISO8601DateFormatter()
      var out: [String: Any] = ["ready": true]
      if let validUntil { out["expiresAt"] = formatter.string(from: validUntil) }
      out["scope"] = profile.applicationIdentifier.contains("*") ? "wide" : "fixed"
      return out
    } catch { return ["ready": false] }
  }

  static func profileInfo() throws -> ProfileInfo {
    let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let startMarker = Data("<plist".utf8)
    let endMarker = Data("</plist>".utf8)
    guard let start = data.range(of: startMarker)?.lowerBound,
          let endRange = data.range(of: endMarker, options: [], in: start..<data.endIndex) else {
      throw NSError(domain: "Route", code: 21, userInfo: [NSLocalizedDescriptionKey: "Runtime configuration is unavailable"])
    }
    let plistData = data.subdata(in: start..<endRange.upperBound)
    guard let root = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
      throw NSError(domain: "Route", code: 22, userInfo: [NSLocalizedDescriptionKey: "Runtime configuration is invalid"])
    }
    let entitlements = root["Entitlements"] as? [String: Any] ?? [:]
    let appId = (entitlements["application-identifier"] as? String) ?? ""
    let teamFromList = (root["TeamIdentifier"] as? [String])?.first
    let teamFromEntitlement = appId.split(separator: ".", maxSplits: 1).first.map(String.init)
    guard let team = teamFromList ?? teamFromEntitlement, !team.isEmpty, !appId.isEmpty else {
      throw NSError(domain: "Route", code: 23, userInfo: [NSLocalizedDescriptionKey: "Runtime configuration is incomplete"])
    }
    let devices = root["ProvisionedDevices"] as? [String] ?? []
    let allDevices = (root["ProvisionsAllDevices"] as? Bool) ?? false
    let debugAllowed = (entitlements["get-task-allow"] as? Bool) ?? false
    return ProfileInfo(url: url, team: team, applicationIdentifier: appId, expiration: root["ExpirationDate"] as? Date, isAdHoc: !devices.isEmpty && !allDevices, debugAllowed: debugAllowed)
  }

  static func material() throws -> Material {
    gate.lock()
    defer { gate.unlock() }
    let profile = try profileInfo()
    guard profile.isAdHoc, !profile.debugAllowed else {
      throw NSError(domain: "Route", code: 24, userInfo: [NSLocalizedDescriptionKey: "Runtime configuration is not available for this build"])
    }
    if let d = profile.expiration, d <= Date() {
      throw NSError(domain: "Route", code: 25, userInfo: [NSLocalizedDescriptionKey: "Runtime configuration has expired"])
    }
    if let deviceKey = loadDeviceKey(), let wrapped = try? Data(contentsOf: cacheURL()),
       let payload = try? open(wrapped, keyData: deviceKey, aad: binding(profile: profile, phase: "d")),
       let parsed = try? parse(payload) { return parsed }

    let payload = try open(bootstrapData(), keyData: bootstrapKey(profile: profile), aad: binding(profile: profile, phase: "b"))
    let parsed = try parse(payload)
    if let d = parsed.expiration, d <= Date() {
      throw NSError(domain: "Route", code: 26, userInfo: [NSLocalizedDescriptionKey: "Runtime material has expired"])
    }
    var key = Data(count: 32)
    let status = key.withUnsafeMutableBytes { raw -> Int32 in
      guard let base = raw.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, 32, base)
    }
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil) }
    try saveDeviceKey(key)
    let wrapped = try seal(payload, keyData: key, aad: binding(profile: profile, phase: "d"))
    try writeCache(wrapped)
    return parsed
  }

  private static func bootstrapData() -> Data {
    var bytes = [UInt8](); bytes.reserveCapacity(q0.count + q1.count + q2.count + q3.count + q4.count)
    bytes.append(contentsOf: q0); bytes.append(contentsOf: q1); bytes.append(contentsOf: q2); bytes.append(contentsOf: q3); bytes.append(contentsOf: q4)
    return Data(bytes)
  }

  private static func bootstrapKey(profile: ProfileInfo) -> Data {
    var seed = [UInt8](repeating: 0, count: 32)
    for i in 0..<8 { seed[i] = k0[i] ^ UInt8((0x37 + i * 17) & 0xff) }
    for i in 0..<8 { seed[8 + i] = k1[7 - i] ^ UInt8((0x37 + 29 + i * 17) & 0xff) }
    for i in 0..<8 { seed[16 + i] = k2[i] ^ UInt8((0x37 + 58 + i * 17) & 0xff) }
    for i in 0..<8 { seed[24 + i] = k3[7 - i] ^ UInt8((0x37 + 87 + i * 17) & 0xff) }
    var pepper = [UInt8](repeating: 0, count: 16)
    for i in 0..<16 { pepper[i] = px[i] ^ UInt8((0x91 + i * 11) & 0xff) }
    var input = Data(seed); input.append(Data(profile.team.utf8)); input.append(Data((Bundle.main.bundleIdentifier ?? "").utf8)); input.append(Data(pepper))
    let digest = SHA256.hash(data: input)
    for i in seed.indices { seed[i] = 0 }; for i in pepper.indices { pepper[i] = 0 }
    return Data(digest)
  }

  private static func binding(profile: ProfileInfo, phase: String) -> Data {
    let suffix = phase == "b" ? "r4" : "d4"
    return Data((profile.team + "|" + (Bundle.main.bundleIdentifier ?? "") + "|" + suffix).utf8)
  }

  private static func parse(_ payload: Data) throws -> Material {
    guard let object = try PropertyListSerialization.propertyList(from: payload, options: [], format: nil) as? [String: Any],
          let archive = object["x"] as? Data, let pass = object["y"] as? Data, let expected = object["z"] as? Data,
          !archive.isEmpty, !pass.isEmpty else {
      throw NSError(domain: "Route", code: 31, userInfo: [NSLocalizedDescriptionKey: "Runtime material is invalid"])
    }
    guard Data(SHA256.hash(data: archive)) == expected else {
      throw NSError(domain: "Route", code: 32, userInfo: [NSLocalizedDescriptionKey: "Runtime material integrity check failed"])
    }
    return Material(archive: archive, passcode: [UInt8](pass), expiration: object["e"] as? Date)
  }

  private static func seal(_ data: Data, keyData: Data, aad: Data) throws -> Data {
    let box = try AES.GCM.seal(data, using: SymmetricKey(data: keyData), authenticating: aad)
    guard let combined = box.combined else { throw NSError(domain: "Route", code: 40, userInfo: nil) }
    return combined
  }

  private static func open(_ data: Data, keyData: Data, aad: Data) throws -> Data {
    let box = try AES.GCM.SealedBox(combined: data)
    return try AES.GCM.open(box, using: SymmetricKey(data: keyData), authenticating: aad)
  }

  private static func cacheURL() throws -> URL {
    let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let folder = root.appendingPathComponent(".r4", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    return folder.appendingPathComponent(fileName)
  }

  private static func writeCache(_ data: Data) throws {
    let url = try cacheURL()
    try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
  }

  private static func saveDeviceKey(_ data: Data) throws {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: keySlot]
    SecItemDelete(query as CFDictionary)
    var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil) }
  }

  private static func loadDeviceKey() -> Data? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: keySlot, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var item: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &item)
    return status == errSecSuccess ? item as? Data : nil
  }
}

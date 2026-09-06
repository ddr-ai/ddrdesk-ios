import Foundation
import UIKit

enum Msg: UInt8 {
    case clientHello = 0x01
    case serverHello = 0x02
    case authFail = 0x03
    case viewport = 0x04
    case input = 0x05
    case video = 0x06
    case ping = 0x07
    case pong = 0x08
    case requestKeyframe = 0x09
    case status = 0x0A
    case goodbye = 0x0B
    case bitrateHint = 0x0C
    case cursor = 0x0D
}

enum OrientationName {
    static func current() -> String {
        let s = UIScreen.main.bounds
        return s.width >= s.height ? "landscape" : "portrait"
    }
}

enum FrameCodec {
    static let maxFrame = 8 * 1024 * 1024

    static func encode(type: Msg, payload: Data) -> Data {
        var len = UInt32(1 + payload.count).bigEndian
        var out = Data(bytes: &len, count: 4)
        out.append(type.rawValue)
        out.append(payload)
        return out
    }

    static func encodeJSON<T: Encodable>(type: Msg, value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        return encode(type: type, payload: payload)
    }
}

struct ClientHello: Codable {
    var id: String
    var device: String
    var w: UInt32
    var h: UInt32
    var points_w: Float
    var points_h: Float
    var scale: Float
    var orientation: String
    var proto: UInt32
    var session: String?
}

struct ServerHello: Codable {
    var ok: Bool
    var name: String
    var fp: String
    var endpoints: [String]
    var screen_w: UInt32
    var screen_h: UInt32
    var session: String
}

struct ViewportMsg: Codable {
    var w: UInt32
    var h: UInt32
    var points_w: Float
    var points_h: Float
    var scale: Float
    var orientation: String
}

struct AuthFail: Codable { var error: String }
struct StatusMsg: Codable { var state: String; var msg: String }
struct BitrateHint: Codable { var kbps: UInt32 }
struct CursorPos: Codable {
    var x: Float
    var y: Float
    var w: UInt32
    var h: UInt32
    var visible: Bool
}

enum InputJSON {
    static func move(dx: Float, dy: Float) -> Data {
        let s = String(format: "{\"t\":\"move\",\"dx\":%.3f,\"dy\":%.3f}", dx, dy)
        return Data(s.utf8)
    }
    static func btn(_ b: String, down: Bool) -> Data {
        Data("{\"t\":\"btn\",\"b\":\"\(b)\",\"d\":\(down)}".utf8)
    }
    static func wheel(dx: Float, dy: Float) -> Data {
        let s = String(format: "{\"t\":\"wheel\",\"dx\":%.2f,\"dy\":%.2f}", dx, dy)
        return Data(s.utf8)
    }
    static func key(_ k: String, down: Bool) -> Data {
        Data("{\"t\":\"key\",\"k\":\"\(k)\",\"d\":\(down)}".utf8)
    }
    static func text(_ s: String) -> Data {
        let enc = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data("{\"t\":\"text\",\"s\":\"\(enc)\"}".utf8)
    }
}

enum ScreenMetrics {
    static func current() -> (pixelsW: UInt32, pixelsH: UInt32, pointsW: Float, pointsH: Float, scale: Float, orientation: String) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let screen = scene?.screen ?? UIScreen.main
        let bounds = scene?.windows.first?.bounds ?? screen.bounds
        let scale = Float(screen.scale)
        let pw = Float(bounds.width)
        let ph = Float(bounds.height)
        return (
            UInt32((bounds.width * screen.scale).rounded()),
            UInt32((bounds.height * screen.scale).rounded()),
            pw, ph, scale,
            pw >= ph ? "landscape" : "portrait"
        )
    }
}

import Foundation

public struct MumbleURL: Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var username: String?
    public var channelPath: [String]

    public init(host: String, port: UInt16 = 64738, username: String? = nil, channelPath: [String] = []) {
        self.host = host
        self.port = port
        self.username = username
        self.channelPath = channelPath
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "mumble", let host = url.host, !host.isEmpty else { return nil }
        self.host = host
        // URL.port is an unclamped Int; a crafted link like mumble://host:99999
        // would trap on UInt16(...). Reject an out-of-range port instead.
        if let rawPort = url.port {
            guard let port = UInt16(exactly: rawPort) else { return nil }
            self.port = port
        } else {
            port = 64738
        }
        username = url.user?.removingPercentEncoding
        channelPath = url.pathComponents.dropFirst().compactMap { component in
            let decoded = component.removingPercentEncoding ?? component
            return decoded.isEmpty ? nil : decoded
        }
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = "mumble"
        components.host = host
        components.port = port == 64738 ? nil : Int(port)
        components.user = username?.nilIfEmpty
        components.path = channelPath.isEmpty ? "" : "/" + channelPath.joined(separator: "/")
        return components.url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

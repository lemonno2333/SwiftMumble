import Foundation

struct PublicMumbleServer: Identifiable, Hashable, Sendable {
    var id: String { "\(host)|\(port)" }
    var name: String
    var host: String
    var port: UInt16
    var country: String
    var countryCode: String
}

enum PublicServerDirectory {
    static func fetch() async throws -> [PublicMumbleServer] {
        let url = URL(string: "https://publist.mumble.info/v1/list?version=1.5.0")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let parser = PublicServerXMLParser(data: data)
        return try parser.parse()
    }
}

private final class PublicServerXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var servers: [PublicMumbleServer] = []
    private var parseError: Error?

    init(data: Data) { parser = XMLParser(data: data); super.init(); parser.delegate = self }
    func parse() throws -> [PublicMumbleServer] {
        guard parser.parse() else { throw parseError ?? parser.parserError ?? URLError(.cannotParseResponse) }
        return servers
    }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { self.parseError = parseError }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "server", let host = attributes["ip"],
              let port = UInt16(attributes["port"] ?? "") else { return }
        servers.append(PublicMumbleServer(
            name: attributes["name"] ?? host, host: host, port: port,
            country: attributes["country"] ?? "", countryCode: attributes["country_code"] ?? ""
        ))
    }
}

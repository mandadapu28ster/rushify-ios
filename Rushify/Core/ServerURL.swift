import Foundation

/// Validates user input as scheme://host[:port] (port 1-65535); no path, query or credentials.
enum ServerURL {
    struct Parsed: Equatable {
        let url: String          // normalised: scheme://host[:port], no trailing slash
        let scheme: String
        let host: String
        let port: Int?
        var isCleartext: Bool { scheme == "http" }
    }
    enum Result: Equatable { case ok(Parsed), bad(String) }

    static func parse(_ input: String) -> Result {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.isEmpty { return .bad("Enter a server address") }
        guard let sep = text.range(of: "://") else { return .bad("Start with http:// or https://") }
        let scheme = text[..<sep.lowerBound].lowercased()
        if scheme != "http" && scheme != "https" { return .bad("Only http:// or https:// is supported") }

        let rest = String(text[sep.upperBound...])
        var authority = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        authority = authority.components(separatedBy: "@").last ?? authority
        if let cut = authority.firstIndex(where: { $0 == "?" || $0 == "#" }) { authority = String(authority[..<cut]) }
        let rawPort: String
        if authority.hasPrefix("[") { rawPort = authority.components(separatedBy: "]").dropFirst().first.map { $0.hasPrefix(":") ? String($0.dropFirst()) : $0 } ?? "" }
        else { rawPort = authority.contains(":") ? String(authority[authority.index(after: authority.firstIndex(of: ":")!)...]) : "" }
        if !rawPort.isEmpty, !((Int(rawPort) ?? -1) >= 1 && (Int(rawPort) ?? -1) <= 65535) { return .bad("Port must be between 1 and 65535") }

        guard let comps = URLComponents(string: text), let host = comps.host, !host.isEmpty else { return .bad("That does not look like a valid address") }
        if comps.user != nil || comps.password != nil { return .bad("Do not include credentials in the address") }
        if !comps.path.isEmpty || comps.query != nil || comps.fragment != nil { return .bad("Use only scheme://host[:port], without a path") }
        if let p = comps.port, !(1...65535).contains(p) { return .bad("Port must be between 1 and 65535") }

        let shownHost = host.contains(":") ? "[\(host)]" : host
        let normalised = "\(scheme)://\(shownHost)" + (comps.port.map { ":\($0)" } ?? "")
        return .ok(Parsed(url: normalised, scheme: String(scheme), host: host, port: comps.port))
    }
}

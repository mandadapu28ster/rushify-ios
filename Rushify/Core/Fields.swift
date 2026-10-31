import Foundation

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(_ s: String) { stringValue = s }
}

/// Lenient JSON reader: a missing or mistyped key gives nil (or a default), never a decoding failure.
/// Backend decimals arrive as strings and sometimes as numbers; they are never parsed through Double.
struct Fields {
    let c: KeyedDecodingContainer<AnyKey>
    init(_ decoder: Decoder) throws { c = try decoder.container(keyedBy: AnyKey.self) }

    func str(_ k: String) -> String? { (try? c.decodeIfPresent(String.self, forKey: AnyKey(k))) ?? nil }
    func bool(_ k: String) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: AnyKey(k))) ?? nil }
    func int(_ k: String) -> Int? {
        if let v = (try? c.decodeIfPresent(Int.self, forKey: AnyKey(k))) ?? nil { return v }
        return str(k).flatMap { Int($0) }
    }
    func dec(_ k: String) -> Decimal? {
        if let s = str(k) { return Decimal(string: s.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX")) }
        return (try? c.decodeIfPresent(Decimal.self, forKey: AnyKey(k))) ?? nil
    }
    func list<T: Decodable>(_ k: String) -> [T] { ((try? c.decodeIfPresent([T].self, forKey: AnyKey(k))) ?? nil) ?? [] }
    func obj<T: Decodable>(_ k: String) -> T? { (try? c.decodeIfPresent(T.self, forKey: AnyKey(k))) ?? nil }
}

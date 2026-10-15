import Foundation

/// Minimal RFC 4180 parser: quoted fields, doubled quotes, and newlines inside quotes.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var chars = Array(text.unicodeScalars.filter { $0 != "\u{FEFF}" }.map(Character.init))[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" { if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false } }
                else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" {
                // Swift treats "\r\n" as a single Character.
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Rows as dictionaries keyed by the header row.
    static func records(_ text: String) -> [[String: String]] {
        let rows = parse(text)
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { r in Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0 < r.count ? r[$0] : "") }) }
    }
}

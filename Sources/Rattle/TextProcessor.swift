import Foundation

/// Turns raw Whisper output into the text Rattle inserts: cleanup, dictionary, snippets, per-app tone.
enum TextProcessor {
    struct Output { var text: String; var corrected = 0; var dictFixes = 0 }

    static func process(raw: String, settings: Settings, dictionary: [DictionaryEntry], snippets: [Snippet], category: StyleCategory) -> String {
        processDetailed(raw: raw, settings: settings, dictionary: dictionary, snippets: snippets, category: category).text
    }

    private static func matches(_ pattern: String, in s: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) ?? 0
    }

    static func processDetailed(raw: String, settings: Settings, dictionary: [DictionaryEntry], snippets: [Snippet], category: StyleCategory) -> Output {
        var out = Output(text: "")
        var t = raw.replacingOccurrences(of: "\n", with: " ")
        t = t.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: " ", options: .regularExpression) // [BLANK_AUDIO], (music)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return out }

        // Snippets: whole-utterance match first, then inline.
        let norm = { (s: String) in s.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }
        if let s = snippets.first(where: { norm($0.trigger) == norm(t) }) { out.text = s.expansion; return out }
        for s in snippets where !s.trigger.isEmpty { t = replaceWord(t, s.trigger, s.expansion) }

        if settings.cleanup != .none {
            out.corrected += matches(#"(?i)(^|[\s,])(?:u\.?m\.?|um+|uh+|uhm|erm|er|ah|hmm+|mm+)(?=[\s,.!?]|$)"#, in: t)
            t = t.replacingOccurrences(of: #"(?i)(^|[\s,])(?:u\.?m\.?|um+|uh+|uhm|erm|er|ah|hmm+|mm+)(?=[\s,.!?]|$)[,]?"#, with: "$1", options: .regularExpression)
            if settings.cleanup == .high {
                // "X, no wait, Y" / "scratch that" self-corrections.
                t = t.replacingOccurrences(of: #"(?i)[^.!?]*\b(?:scratch that|never mind that)\b[,.]?\s*"#, with: "", options: .regularExpression)
                out.corrected += matches(#"(?i)\b(\w+)(?:\s+\1\b)+"#, in: t)
                t = t.replacingOccurrences(of: #"(?i)\b(\w+)(?:\s+\1\b)+"#, with: "$1", options: .regularExpression) // stutters
            }
            t = t.replacingOccurrences(of: #"(?i)\bnew paragraph\b[,.]?"#, with: "\n\n", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)\bnew line\b[,.]?"#, with: "\n", options: .regularExpression)
            t = t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            t = t.replacingOccurrences(of: #" +([,.!?;:])"#, with: "$1", options: .regularExpression)
            t = t.replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            t = capitalizeSentences(t)
        }

        for d in dictionary {
            if let r = d.replacement, !r.isEmpty {
                let pat = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: d.word) + "(?![\\p{L}\\p{N}])"
                out.dictFixes += matches("(?i)" + pat, in: t)
                t = replaceWord(t, d.word, r)
            } else { t = replaceWord(t, d.word, d.word) }
        }

        let tone = settings.tones[category.rawValue] ?? .formal
        t = applyTone(t, tone)
        out.text = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    private static func replaceWord(_ text: String, _ word: String, _ with: String) -> String {
        let pat = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
        return text.replacingOccurrences(of: pat, with: NSRegularExpression.escapedTemplate(for: with), options: [.regularExpression, .caseInsensitive])
    }

    private static func capitalizeSentences(_ s: String) -> String {
        var out = "", cap = true
        for ch in s {
            if cap, ch.isLetter { out += ch.uppercased(); cap = false }
            else { out.append(ch) }
            if ".!?\n".contains(ch) { cap = true }
        }
        return out
    }

    private static func applyTone(_ s: String, _ tone: Tone) -> String {
        switch tone {
        case .formal: return s
        case .casual:
            return s.hasSuffix(".") && s.filter({ ".!?".contains($0) }).count == 1 ? String(s.dropLast()) : s
        case .veryCasual:
            var r = s.lowercased()
            if r.hasSuffix(".") && r.filter({ ".!?".contains($0) }).count == 1 { r.removeLast() }
            return r.replacingOccurrences(of: #"\bi\b"#, with: "i", options: .regularExpression)
        }
    }
}

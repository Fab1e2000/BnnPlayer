import Foundation

struct LRCParser {
    func parse(fileURL: URL) -> [LyricLine] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let text = decodeLRCText(from: data)
        else {
            return []
        }

        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var offsetMs = 0
        var textBucketsByTimestampMs: [Int: [String]] = [:]

        for line in normalizedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            if let parsedOffset = parseOffset(from: trimmedLine) {
                offsetMs = parsedOffset
                continue
            }

            let timestampMatches = Self.timestampRegex.matches(
                in: trimmedLine,
                range: NSRange(trimmedLine.startIndex..., in: trimmedLine)
            )

            guard !timestampMatches.isEmpty else {
                continue
            }

            let lyricText = Self.timestampRegex.stringByReplacingMatches(
                in: trimmedLine,
                range: NSRange(trimmedLine.startIndex..., in: trimmedLine),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            for match in timestampMatches {
                guard let timestampMs = parseTimestamp(match: match, in: trimmedLine) else {
                    continue
                }

                let resolvedTimestamp = max(0, timestampMs + offsetMs)
                let resolvedText = lyricText.isEmpty ? "..." : lyricText
                textBucketsByTimestampMs[resolvedTimestamp, default: []].append(resolvedText)
            }
        }

        return textBucketsByTimestampMs
            .keys
            .sorted()
            .compactMap { timestampMs in
                guard let entries = textBucketsByTimestampMs[timestampMs], !entries.isEmpty else {
                    return nil
                }

                let compactEntries = entries
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard !compactEntries.isEmpty else {
                    return nil
                }

                if compactEntries.count == 1,
                   let splitPair = splitBilingualText(compactEntries[0])
                {
                    return LyricLine(
                        timestampMs: timestampMs,
                        primaryText: splitPair.primary,
                        secondaryText: splitPair.secondary
                    )
                }

                let primary = compactEntries[0]
                let secondary = compactEntries.dropFirst().joined(separator: " / ")

                return LyricLine(
                    timestampMs: timestampMs,
                    primaryText: primary,
                    secondaryText: secondary.isEmpty ? nil : secondary
                )
            }
    }

    private func parseOffset(from line: String) -> Int? {
        guard
            let match = Self.offsetRegex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ),
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return Int(line[valueRange])
    }

    private func parseTimestamp(match: NSTextCheckingResult, in line: String) -> Int? {
        guard
            let minuteRange = Range(match.range(at: 1), in: line),
            let secondRange = Range(match.range(at: 2), in: line)
        else {
            return nil
        }

        let minutes = Int(line[minuteRange]) ?? 0
        let seconds = Int(line[secondRange]) ?? 0

        var fractionMs = 0
        if let centiRange = Range(match.range(at: 3), in: line) {
            let fraction = String(line[centiRange])
            if let rawFraction = Int(fraction) {
                switch fraction.count {
                case 1:
                    fractionMs = rawFraction * 100
                case 2:
                    fractionMs = rawFraction * 10
                default:
                    fractionMs = rawFraction
                }
            }
        }

        return (minutes * 60 + seconds) * 1000 + fractionMs
    }

    private func splitBilingualText(_ text: String) -> (primary: String, secondary: String)? {
        let separators = [" / ", " | ", " ｜ ", " // "]
        for separator in separators {
            let parts = text.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count == 2 {
                return (parts[0], parts[1])
            }
        }

        return nil
    }

    private func decodeLRCText(from data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let utf8Text = String(data: data, encoding: .utf8)
        {
            return utf8Text
        }

        var bestText: String?
        var bestTimestampScore = -1
        var bestQualityScore = Int.min

        for encoding in Self.candidateEncodings {
            guard let decoded = String(data: data, encoding: encoding) else {
                continue
            }

            let timestampScore = scoreTimestamps(in: decoded)
            let qualityScore = scoreTextQuality(in: decoded)

            if timestampScore > bestTimestampScore
                || (timestampScore == bestTimestampScore && qualityScore > bestQualityScore)
            {
                bestTimestampScore = timestampScore
                bestQualityScore = qualityScore
                bestText = decoded
            }
        }

        return bestText
    }

    private func scoreTimestamps(in text: String) -> Int {
        let range = NSRange(text.startIndex..., in: text)
        return Self.timestampRegex.numberOfMatches(in: text, range: range)
    }

    private func scoreTextQuality(in text: String) -> Int {
        var cjkCount = 0
        var kanaCount = 0
        var letterCount = 0
        var replacementCharCount = 0
        var controlCharCount = 0
        var mojibakeMarkerCount = 0

        for scalar in text.unicodeScalars {
            let value = scalar.value

            if CharacterSet.letters.contains(scalar) {
                letterCount += 1
            }

            if value == 0xFFFD {
                replacementCharCount += 1
            }

            if CharacterSet.controlCharacters.contains(scalar), value != 0x0A, value != 0x0D, value != 0x09 {
                controlCharCount += 1
            }

            if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) {
                cjkCount += 1
            }

            if (0x3040...0x309F).contains(value) || (0x30A0...0x30FF).contains(value) {
                kanaCount += 1
            }

            if Self.mojibakeSuspiciousCharacterSet.contains(scalar) {
                mojibakeMarkerCount += 1
            }
        }

        return cjkCount * 3
            + kanaCount * 3
            + letterCount
            - replacementCharCount * 30
            - controlCharCount * 20
            - mojibakeMarkerCount * 8
    }

    private static let offsetRegex = try! NSRegularExpression(
        pattern: #"^\[\s*offset\s*:\s*([+-]?\d+)\s*\]$"#,
        options: [.caseInsensitive]
    )

    private static let timestampRegex = try! NSRegularExpression(
        pattern: #"\[\s*(\d{1,3})\s*:\s*(\d{1,2})(?:[\.:,](\d{1,3}))?\s*\]"#
    )

    private static let mojibakeSuspiciousCharacterSet = CharacterSet(charactersIn: "ÃÂÅÆÇÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ£¤¦¨©ª«¬®¯°±²³´µ¶·¸¹º»¼½¾¿")

    private static let candidateEncodings: [String.Encoding] = {
        var encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            .unicode,
            .shiftJIS
        ]

        let ianaCandidates = ["GB18030", "GBK", "GB2312", "Big5-HKSCS", "EUC-KR"]
        for name in ianaCandidates {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                encodings.append(String.Encoding(rawValue: nsEncoding))
            }
        }

        encodings.append(contentsOf: [
            .isoLatin1,
            .windowsCP1250,
            .windowsCP1251,
            .windowsCP1252
        ])

        var seen: Set<String.Encoding> = []
        var ordered: [String.Encoding] = []
        for encoding in encodings where !seen.contains(encoding) {
            seen.insert(encoding)
            ordered.append(encoding)
        }

        return ordered
    }()
}

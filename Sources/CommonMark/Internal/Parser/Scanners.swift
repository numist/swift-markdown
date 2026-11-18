/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

// A scan starts at each `](` and each attribute form's `(`, so without this record a run of unclosed `(` is rescanned
// by every scan starting inside it. A recorded result holds only while every scan between resets reads the same bytes
// up to the same `end` through the same `byte` and `terminates`, with the same `maxNesting`.
internal struct BalancedParenthesesScan {
    private var openers: [(offset: Int, balancedEnd: Int?)] = []
    private var unclosed: [(opener: Int, innerNesting: Int)] = []
    private var nextOpener = 0

    mutating func reset() {
        if openers.isEmpty {
            return
        }
        openers.removeAll(keepingCapacity: true)
        nextOpener = 0
    }

    @inline(__always)
    mutating func balancedEnd(from start: Int, end: Int, maxNesting: Int, byte: (Int) -> UInt8, terminates: (UInt8) -> Bool) -> Int? {
        while nextOpener < openers.count, openers[nextOpener].offset < start - 1 {
            nextOpener += 1
        }
        if nextOpener < openers.count, openers[nextOpener].offset == start - 1 {
            return openers[nextOpener].balancedEnd
        }
        reset()
        let maxNesting = max(maxNesting, 0)
        var outerNesting = 0
        var i = start
        while i < end {
            let c = byte(i)
            if c == UInt8(ascii: "\\") && i + 1 < end && byte(i + 1).isASCIIPunct {
                i += 2
                continue
            }
            if c == UInt8(ascii: "(") {
                unclosed.append((openers.count, 0))
                openers.append((i, nil))
            } else if c == UInt8(ascii: ")") {
                guard let closed = unclosed.popLast() else {
                    break
                }
                if closed.innerNesting <= maxNesting {
                    openers[closed.opener].balancedEnd = i
                }
                let nesting = closed.innerNesting + 1
                if unclosed.isEmpty {
                    outerNesting = max(outerNesting, nesting)
                } else {
                    unclosed[unclosed.count - 1].innerNesting = max(unclosed[unclosed.count - 1].innerNesting, nesting)
                }
            } else if terminates(c) {
                break
            }
            i += 1
        }
        guard let innermost = unclosed.last else {
            return outerNesting <= maxNesting ? i : nil
        }
        if innermost.innerNesting <= maxNesting {
            openers[innermost.opener].balancedEnd = i
        }
        unclosed.removeAll(keepingCapacity: true)
        return nil
    }
}

// A `\` before a closer may begin a backslash escape or be literal, so a title closes at the furthest closer either
// reading reaches: `'\')` has the title `\`, since no later `'` completes the escape.
internal struct LinkTitleScan {
    private let opener: UInt8
    private let closer: UInt8
    private var inBody = true
    private var afterBackslash = false

    @inline(__always)
    init?(opener: UInt8) {
        switch opener {
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            closer = opener
        case UInt8(ascii: "("):
            closer = UInt8(ascii: ")")
        default:
            return nil
        }
        self.opener = opener
    }

    var canContinue: Bool {
        inBody
    }

    @inline(__always)
    mutating func read(_ c: UInt8) -> Bool {
        inBody = (c != opener && c != closer) || (afterBackslash && c.isASCIIPunct)
        afterBackslash = c == UInt8(ascii: "\\")
        return c == closer
    }
}

internal struct LabelLengthLimit {
    var characters: Int
    var bytes: Int
}

// The spec matches labels by the code points of their case folds (Links), so a key holds a stand-in for the fold, and
// a non-ASCII one as bytes, since a String compares canonically equivalent strings as equal. A key is `.ascii` exactly
// when its stand-in's bytes are all ASCII, so that equal stand-ins are equal keys.
internal enum NormalizedLabel: Hashable {
    case ascii(String)
    case utf8([UInt8])

    static let empty = NormalizedLabel.ascii("")

    var isEmpty: Bool {
        if case .ascii(let label) = self {
            return label.isEmpty
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .ascii(let label):
            hasher.combine(label)
        case .utf8(let bytes):
            hasher.combine(bytes.count)
            var word: UInt64 = 0
            for (i, byte) in bytes.enumerated() {
                word |= UInt64(byte) << (UInt64(i & 7) * 8)
                if i & 7 == 7 {
                    hasher.combine(word)
                    word = 0
                }
            }
            if bytes.count & 7 != 0 {
                hasher.combine(word)
            }
        }
    }
}

/// Byte-level scanners for link labels, destinations, and titles.
///
/// They're used by both block-level reference-definition parsing (`BlockParser`) and inline link parsing (the InlineParser extensions).
extension BlockParser {

    // MARK: - Link label

    @inline(__always)
    private func scanLinkLabel(
        from start: Int,
        end: Int,
        crlfIsOneCharacter: Bool,
        byte: (Int) -> UInt8,
        countsLazyLineWhitespace: Bool = false,
        lazyLineWhitespace: (Int) -> Int = { _ in 0 }
    ) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end || byte(start) != UInt8(ascii: "[") {
            return nil
        }
        let limit = linkLabelLimit
        let interiorStart = start + 1
        // A content byte counts at least half a byte (a CRLF's two count one), so a label of more than twice
        // `limit.bytes` content bytes doesn't fit and the scan can stop there.
        let maxBytes = max(limit.bytes, 0)
        let scanEnd = maxBytes < (end - interiorStart) / 2 ? interiorStart + 2 * maxBytes + 1 : end
        var i = interiorStart
        var characters = 0
        while i < scanEnd {
            let b = byte(i)
            if b == UInt8(ascii: "[") {
                return nil
            }
            if b == UInt8(ascii: "]") {
                let interior = interiorStart..<i
                let fits = labelBytesFit(
                    interior,
                    maxBytes: maxBytes,
                    crlfIsOneCharacter: crlfIsOneCharacter,
                    byte: byte,
                    countsLazyLineWhitespace: countsLazyLineWhitespace,
                    lazyLineWhitespace: lazyLineWhitespace
                )
                return fits ? (interior, i + 1) : nil
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                characters += 1
                if i < end {
                    characters += labelCharacterWeight(byte(i))
                    i += 1
                }
            } else {
                characters += labelCharacterWeight(b)
                if crlfIsOneCharacter, b == UInt8(ascii: "\n"), byte(i - 1) == UInt8(ascii: "\r") {
                    characters -= 1
                }
                i += 1
            }
            if characters > limit.characters {
                return nil
            }
        }
        return nil
    }

    @inline(__always)
    private func labelBytesFit(
        _ interior: Range<Int>,
        maxBytes: Int,
        crlfIsOneCharacter: Bool,
        byte: (Int) -> UInt8,
        countsLazyLineWhitespace: Bool,
        lazyLineWhitespace: (Int) -> Int
    ) -> Bool {
        // Without a lazy continuation line's whitespace, a content byte counts at most three bytes (a NUL).
        if interior.count <= maxBytes / 3 && !countsLazyLineWhitespace {
            return true
        }
        var bytes = 0
        for i in interior {
            let b = byte(i)
            bytes += labelByteWeight(b)
            if crlfIsOneCharacter, b == UInt8(ascii: "\n"), byte(i - 1) == UInt8(ascii: "\r") {
                bytes -= 1
            }
            if countsLazyLineWhitespace, b == UInt8(ascii: "\n") {
                bytes += lazyLineWhitespace(i)
            }
        }
        return bytes <= maxBytes
    }

    private func lazyLineWhitespaceBytes(afterLineJoinAt offset: Int, in content: borrowing ContentSpan, recorded: LazyLineWhitespace) -> Int {
        let next = offset + 1
        guard next < content.endOffset else {
            return 0
        }
        if content.isMultiSegment {
            guard let source = content.sourceOffset(ofMultiSegmentVirtual: next) else {
                return 0
            }
            return recorded.bySourceOffset[source] ?? 0
        }
        return (content.inSource ? recorded.bySourceOffset[next] : recorded.byArenaOffset[next]) ?? 0
    }

    internal func matchLinkLabel(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        if let recorded = lazyLineWhitespace {
            return matchLinkLabelCountingLazyLineWhitespace(from: start, end: end, in: content, recorded: recorded)
        }
        if let label = content.withForwardReader(from: start, { byte in scanLinkLabel(from: start, end: end, crlfIsOneCharacter: false, byte: byte) }) {
            return label
        }
        return contentHoldsCR ? matchLinkLabelCountingCRLFOnce(from: start, end: end, in: content) : nil
    }

    @inline(never)
    private func matchLinkLabelCountingLazyLineWhitespace(
        from start: Int,
        end: Int,
        in content: borrowing ContentSpan,
        recorded: LazyLineWhitespace
    ) -> (interior: Range<Int>, afterEnd: Int)? {
        // Only inline-only content parsed in place holds a CR, and it has no lazy continuation lines.
        content.withForwardReader(from: start) { byte in
            scanLinkLabel(from: start, end: end, crlfIsOneCharacter: false, byte: byte, countsLazyLineWhitespace: true) {
                lazyLineWhitespaceBytes(afterLineJoinAt: $0, in: content, recorded: recorded)
            }
        }
    }

    // A label that closes on a later line also holds the line ending before that line, so the scan reads a line ending
    // and then a `]` past `end`.
    internal func linkLabelIsOpen(from start: Int, end: Int, in content: borrowing ContentSpan) -> Bool {
        let recorded = lazyLineWhitespace
        return content.withForwardReader(from: start) { byte in
            let label = scanLinkLabel(
                from: start,
                end: end + 2,
                crlfIsOneCharacter: contentHoldsCR,
                byte: { i in i == end ? UInt8(ascii: "\n") : i == end + 1 ? UInt8(ascii: "]") : byte(i) },
                countsLazyLineWhitespace: recorded != nil,
                lazyLineWhitespace: { i in
                    guard i < end, let recorded else {
                        return 0
                    }
                    return lazyLineWhitespaceBytes(afterLineJoinAt: i, in: content, recorded: recorded)
                }
            )
            return label?.afterEnd == end + 2
        }
    }

    @inline(never)
    private func matchLinkLabelCountingCRLFOnce(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        content.withForwardReader(from: start) { byte in scanLinkLabel(from: start, end: end, crlfIsOneCharacter: true, byte: byte) }
    }

    internal func labelFits(_ limit: LabelLengthLimit, virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> Bool {
        let recorded = lazyLineWhitespace
        // A content byte counts at most one character and three bytes (a NUL, as U+FFFD), plus the leading
        // whitespace of a lazy continuation line it begins. UTF-8 encodes a character in at most four bytes and a CRLF
        // counts one byte, so four content bytes count at least one character and two at least one byte. Settling a
        // label by these bounds, without weighing each byte, keeps a label that spans many nested brackets cheap.
        if range.count <= limit.characters && range.count <= limit.bytes / 3 && recorded == nil {
            return true
        }
        if (range.count + 3) / 4 > limit.characters || (range.count + 1) / 2 > limit.bytes {
            return false
        }
        var characters = 0
        var bytes = 0
        for i in range {
            let b = content[i]
            characters += labelCharacterWeight(b)
            bytes += labelByteWeight(b)
            if contentHoldsCR, b == UInt8(ascii: "\n"), content[i - 1] == UInt8(ascii: "\r") {
                characters -= 1
                bytes -= 1
            }
            if let recorded, b == UInt8(ascii: "\n") {
                bytes += lazyLineWhitespaceBytes(afterLineJoinAt: i, in: content, recorded: recorded)
            }
            if characters > limit.characters || bytes > limit.bytes {
                return false
            }
        }
        return true
    }

    internal var linkLabelLimit: LabelLengthLimit {
        LabelLengthLimit(characters: limits.maxLinkLabelCharacters, bytes: limits.maxLinkLabelBytes)
    }

    internal var footnoteLabelLimit: LabelLengthLimit {
        LabelLengthLimit(characters: limits.maxFootnoteLabelCharacters, bytes: limits.maxFootnoteLabelBytes)
    }

    private func labelCharacterWeight(_ byte: UInt8) -> Int {
        return byte & 0xC0 == 0x80 ? 0 : 1
    }

    // A NUL counts the three bytes of the U+FFFD that replaces it (Insecure characters).
    private func labelByteWeight(_ byte: UInt8) -> Int {
        return byte == 0 ? 3 : 1
    }

    // MARK: - Link destination

    @inline(__always)
    private static func scanLinkDestination(from start: Int, end: Int, parentheses: inout BalancedParenthesesScan, maxNesting: Int, byte: (Int) -> UInt8) -> (destination: Range<Int>, afterEnd: Int)? {
        if start >= end {
            return nil
        }
        let first = byte(start)
        if first == UInt8(ascii: "<") {
            var i = start + 1
            while i < end {
                let c = byte(i)
                if c == UInt8(ascii: ">") {
                    return ((start + 1)..<i, i + 1)
                }
                if c == UInt8(ascii: "\\") && i + 1 < end && byte(i + 1).isASCIIPunct {
                    i += 2
                    continue
                }
                if c == UInt8(ascii: "\n") || c == UInt8(ascii: "\r") || c == UInt8(ascii: "<") {
                    return nil
                }
                i += 1
            }
            return nil
        }
        // A NUL stands for U+FFFD (Insecure characters), so it is destination content.
        func terminatesDestination(_ b: UInt8) -> Bool {
            b == UInt8(ascii: " ") || (b != 0 && b < 0x20) || b == 0x7F
        }
        if terminatesDestination(first) {
            return nil
        }
        guard let destinationEnd = parentheses.balancedEnd(from: start, end: end, maxNesting: maxNesting, byte: byte, terminates: terminatesDestination) else {
            return nil
        }
        // Empty bare URL is allowed for inline links - `[a]()` should match with an empty destination.
        return (start..<destinationEnd, destinationEnd)
    }

    internal mutating func matchLinkDestination(from start: Int, end: Int, in content: borrowing ContentSpan) -> (destination: Range<Int>, afterEnd: Int)? {
        let maxNesting = limits.maxLinkDestinationParenthesisNesting
        return content.withForwardReader(from: start) { byte in
            Self.scanLinkDestination(from: start, end: end, parentheses: &destinationParentheses, maxNesting: maxNesting, byte: byte)
        }
    }

    // MARK: - Link title

    @inline(__always)
    private func scanLinkTitle(from start: Int, end: Int, byte: (Int) -> UInt8) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end {
            return nil
        }
        guard var title = LinkTitleScan(opener: byte(start)) else {
            return nil
        }
        var closeAfterEnd: Int? = nil
        var i = start + 1
        while i < end, title.canContinue {
            if title.read(byte(i)) {
                closeAfterEnd = i + 1
            }
            i += 1
        }
        guard let closeAfterEnd else {
            return nil
        }
        return ((start + 1)..<(closeAfterEnd - 1), closeAfterEnd)
    }

    internal func matchLinkTitle(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        content.withForwardReader(from: start) { byte in scanLinkTitle(from: start, end: end, byte: byte) }
    }

    @inline(__always)
    internal func htmlTagNameEnd(from start: Int, end: Int, byte: (Int) -> UInt8) -> Int? {
        guard start < end, byte(start).isASCIILetter else {
            return nil
        }
        var i = start + 1
        while i < end, byte(i).isASCIILetter || byte(i).isASCIIDigit || byte(i) == UInt8(ascii: "-") {
            i += 1
        }
        return i
    }

    @inline(__always)
    internal func htmlTagEnd(afterName nameEnd: Int, isClosing: Bool, end: Int, byte: (Int) -> UInt8) -> Int? {
        func skipWhitespace(from start: Int) -> Int {
            var i = start
            while i < end, byte(i).isWhitespaceCharacter {
                i += 1
            }
            return i
        }
        var i = nameEnd
        while !isClosing {
            let attributeStart = skipWhitespace(from: i)
            guard attributeStart > i, attributeStart < end else {
                break
            }
            let first = byte(attributeStart)
            guard first.isASCIILetter || first == UInt8(ascii: "_") || first == UInt8(ascii: ":") else {
                break
            }
            var k = attributeStart + 1
            while k < end {
                let b = byte(k)
                guard b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: ":") || b == UInt8(ascii: ".")
                        || b == UInt8(ascii: "_") || b == UInt8(ascii: "-") else {
                    break
                }
                k += 1
            }
            i = k
            let equals = skipWhitespace(from: k)
            guard equals < end, byte(equals) == UInt8(ascii: "=") else {
                continue
            }
            let valueStart = skipWhitespace(from: equals + 1)
            guard valueStart < end else {
                return nil
            }
            let opener = byte(valueStart)
            if opener == UInt8(ascii: "\"") || opener == UInt8(ascii: "'") {
                k = valueStart + 1
                while k < end, byte(k) != opener {
                    k += 1
                }
                guard k < end else {
                    return nil
                }
                i = k + 1
            } else {
                k = valueStart
                while k < end {
                    let b = byte(k)
                    if b.isWhitespaceCharacter || b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") || b == UInt8(ascii: "=")
                        || b == UInt8(ascii: "<") || b == UInt8(ascii: ">") || b == UInt8(ascii: "`") {
                        break
                    }
                    k += 1
                }
                guard k > valueStart else {
                    return nil
                }
                i = k
            }
        }
        i = skipWhitespace(from: i)
        if !isClosing, i < end, byte(i) == UInt8(ascii: "/") {
            i += 1
        }
        guard i < end, byte(i) == UInt8(ascii: ">") else {
            return nil
        }
        return i + 1
    }

    // MARK: - Label normalization

    /// Link label normalization (Links): trim outer whitespace, collapse interior whitespace runs to a single space, then full Unicode case-fold so labels match across scripts - `[ΑΓΩ]` and `[αγω]` resolve to the same key.
    internal func normalizeLabel(chunk: Chunk) -> NormalizedLabel {
        let span = if chunk.inSource {
            sourceBytes.extracting(chunk.range)
        } else {
            storage.strings.span.extracting(chunk.range)
        }

        return Self.normalizeLabel(span)
    }

    internal func normalizeLabel(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> NormalizedLabel {
        if let chunk = content.contiguousChunk(fromVirtual: range.lowerBound, limit: range.upperBound),
           chunk.length == range.count {
            return normalizeLabel(chunk: chunk)
        }
        var bytes = UniqueArray<UInt8>()
        bytes.reserveCapacity(range.count)
        for i in range {
            bytes.append(content[i])
        }
        return Self.normalizeLabel(bytes.span)
    }

    /// Link label normalization (Links) over an already-resolved span. The byte-level worker behind `normalizeLabel(chunk:)`; `static` because it touches no parser state.
    private static func normalizeLabel(_ span: Span<UInt8>) -> NormalizedLabel {
        var hasNonASCII = false
        var nulCount = 0
        for i in 0..<span.count where span[i] == 0 {
            nulCount += 1
        }
        // Sizing the buffer to `span.count + 2 * nulCount`, rather than to three bytes per source byte, stores a short
        // label inline instead of in a heap allocation.
        let label = String(unsafeUninitializedCapacity: span.count + 2 * nulCount) { buffer in
            // SAFETY: Every append to `output` is capacity-checked, and `finalize(for:)` checks `buffer` before reporting how many bytes `output` initialized.
            //         No String initializer fills its storage through an `OutputSpan`, and building the bytes elsewhere first would copy them.
            var output = unsafe OutputSpan(buffer: buffer, initializedCount: 0)
            var pendingSpace = false

            for i in 0..<span.count {
                let b = span[i]
                if b.isWhitespaceCharacter {
                    if !output.isEmpty {
                        pendingSpace = true
                    }
                    continue
                }
                if pendingSpace {
                    output.append(UInt8(ascii: " "))
                    pendingSpace = false
                }
                if b == 0 {
                    hasNonASCII = true
                    output.append(0xEF)
                    output.append(0xBF)
                    output.append(0xBD)
                } else if b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z") {
                    output.append(b + (UInt8(ascii: "a") - UInt8(ascii: "A")))
                } else {
                    hasNonASCII = hasNonASCII || b >= 0x80
                    output.append(b)
                }
            }

            return unsafe output.finalize(for: buffer)
        }
        return hasNonASCII ? caseFold(label) : .ascii(label)
    }

    // Lowercasing a scalar, then uppercasing and lowercasing each scalar of the result, gives every case fold one
    // stand-in. Dotless `ı` folds to itself but uppercases to the `I` that `i` folds with, so it stands for itself.
    private static func caseFold(_ label: String) -> NormalizedLabel {
        let scalars = label.unicodeScalars
        var folded = ""
        // Some non-ASCII scalars stand in as ASCII, such as the Kelvin sign as `k`, so whether the key is ASCII is
        // known only once every scalar is replaced.
        var keyIsASCII = true
        var unchangedStart = scalars.startIndex
        var lastUnchanged: Unicode.Scalar = "a"
        var i = scalars.startIndex
        while i != scalars.endIndex {
            let scalar = scalars[i]
            let next = scalars.index(after: i)
            // An ASCII scalar is its own stand-in once `normalizeLabel` has lowercased it.
            if !scalar.isASCII && scalar != lastUnchanged {
                if scalar.properties.changesWhenCaseMapped {
                    folded.append(contentsOf: Substring(scalars[unchangedStart..<i]))
                    for lower in scalar.properties.lowercaseMapping.unicodeScalars {
                        if lower == "ı" {
                            folded.unicodeScalars.append(lower)
                            keyIsASCII = false
                        } else {
                            for upper in lower.properties.uppercaseMapping.unicodeScalars {
                                let standIn = upper.properties.lowercaseMapping
                                keyIsASCII = keyIsASCII && standIn.utf8.allSatisfy { $0 < 0x80 }
                                folded += standIn
                            }
                        }
                    }
                    unchangedStart = next
                } else {
                    lastUnchanged = scalar
                    keyIsASCII = false
                }
            }
            i = next
        }
        if unchangedStart == scalars.startIndex {
            folded = label
        } else {
            folded.append(contentsOf: Substring(scalars[unchangedStart...]))
        }
        return keyIsASCII ? .ascii(folded) : .utf8(Array(folded.utf8))
    }
}

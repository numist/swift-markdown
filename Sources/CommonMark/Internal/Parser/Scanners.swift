/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// Remembers each unescaped `(` that the latest scan for balanced parentheses passed, in a bare link destination
/// (Links) or an attribute form's `(…)`, so that a scan starting just after one of them reads its result rather than
/// the bytes.
///
/// A scan stops at a `)` that closes no `(` it passed, at a byte that ends the run, or at the end, and its parentheses
/// are balanced when it closed every `(` it passed and they nest no deeper than the scan's `maxNesting`. A scan
/// starting just after a `(` the latest scan passed reads the same bytes: it stops at the `)` closing that `(`, or else
/// where the latest scan stopped, balanced only when that `(` is the innermost one left open there, and its
/// parentheses nest as deep as those inside that `(`.
internal struct BalancedParenthesesScan {
    /// Each `(` the latest scan passed, in order, with where a scan starting just after it stops balanced, or nil when
    /// that scan stops unbalanced.
    private var openers: [(offset: Int, balancedEnd: Int?)] = []
    /// During a scan, each `(` not yet closed, innermost last: its index in `openers`, and how deeply the parentheses
    /// it has closed inside it so far nest.
    private var unclosed: [(opener: Int, innerNesting: Int)] = []
    /// The first of `openers` a scan may start after. Scans start further on as inline parsing proceeds.
    private var nextOpener = 0

    /// Forgets the latest scan, for scans of other bytes.
    mutating func reset() {
        if openers.isEmpty {
            return
        }
        openers.removeAll(keepingCapacity: true)
        nextOpener = 0
    }

    /// Where a scan from `start` stops, at a `)` that closes no `(` it passed, at a byte `terminates` accepts, or at
    /// `end`, if its parentheses are balanced there and nest no deeper than `maxNesting`, or than 0 when it is
    /// negative. Between resets every scan reads the same bytes up to the same `end` through `byte` and `terminates`,
    /// with the same `maxNesting`.
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
        // How deeply the parentheses this scan has closed outside every `(` it passed nest.
        var outerNesting = 0
        var i = start
        while i < end {
            let c = byte(i)
            // Only ASCII punctuation can be escaped, so a `\` before a line ending is literal.
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

/// A link title (Links) read a byte at a time from just past its opener, so that a scan can stop at the end of the bytes
/// it has and go on from there when more follow.
///
/// A `\` in the body may begin a backslash escape or be literal, and the title closes at the furthest closer either
/// reading reaches: `'\')` has the title `\`, since no later `'` completes the escape.
internal struct LinkTitleScan {
    private let opener: UInt8
    private let closer: UInt8
    /// Whether the next byte may be a content byte (any byte but a delimiter), begin an escape, or close.
    private var inBody = true
    /// Whether the next byte completes an escape if it is ASCII punctuation.
    private var afterBackslash = false

    /// The scan of a title that `opener` begins, or nil when it begins none.
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

    /// Whether a later byte may still close the title, or close it past a closer already read.
    var canContinue: Bool {
        inBody
    }

    /// Reads the title's next byte, while `canContinue`, returning whether it is a closer, which the title ends after
    /// unless a later one closes it.
    @inline(__always)
    mutating func read(_ c: UInt8) -> Bool {
        inBody = (c != opener && c != closer) || (afterBackslash && c.isASCIIPunct)
        afterBackslash = c == UInt8(ascii: "\\")
        return c == closer
    }
}

/// The most characters and bytes a label can have inside its brackets.
internal struct LabelLengthLimit {
    var characters: Int
    var bytes: Int
}

/// Scanners for link labels, destinations and titles, shared by link reference definitions and inline links, and for raw HTML tags.
extension BlockParser {

    // MARK: - Link label

    /// Scans a link label through `byte`; a label may span line endings. Returns the interior's range and the offset
    /// past `]`, or nil at an unescaped `[`, past `linkLabelLimit`, or at the end. With `crlfIsOneCharacter`, a CRLF's
    /// LF doesn't count toward the length, since a CRLF is one line ending. With `countsLazyLineWhitespace`,
    /// `lazyLineWhitespace` gives the bytes a line join at an offset adds (see
    /// `lazyLineWhitespaceBytes(afterLineJoinAt:in:recorded:)`).
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
        // A byte of the label counts at least half a byte (a CRLF's two count one), so a label of more than twice
        // `limit.bytes` bytes doesn't fit and the scan stops there. The bytes are counted only once the label closes.
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

    /// Whether the label interior `interior`, read through `byte`, has at most `maxBytes` bytes, counted by
    /// `labelByteWeight`, with a CRLF's LF not counted when `crlfIsOneCharacter`, and with `countsLazyLineWhitespace`,
    /// with the bytes `lazyLineWhitespace` gives for each line join.
    @inline(__always)
    private func labelBytesFit(
        _ interior: Range<Int>,
        maxBytes: Int,
        crlfIsOneCharacter: Bool,
        byte: (Int) -> UInt8,
        countsLazyLineWhitespace: Bool,
        lazyLineWhitespace: (Int) -> Int
    ) -> Bool {
        // A byte counts at most three bytes (a NUL).
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

    /// The bytes a label counts, past the line join at offset `offset` of `content`, for the leading whitespace of
    /// the lazy continuation line the join begins, which `content` doesn't hold, as `recorded` holds it.
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

    /// Matches a link label (Links) at virtual offset `start` of `content`, returning its interior and the offset past
    /// its `]`.
    internal func matchLinkLabel(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        if let recorded = lazyLineWhitespace {
            return matchLinkLabelCountingLazyLineWhitespace(from: start, end: end, in: content, recorded: recorded)
        }
        if let label = content.withForwardReader(from: start, { byte in scanLinkLabel(from: start, end: end, crlfIsOneCharacter: false, byte: byte) }) {
            return label
        }
        // A label counted past `linkLabelLimit` with each CRLF as two characters may still fit. Only inline-only
        // content parsed in place holds a CR.
        return contentHoldsCR ? matchLinkLabelCountingCRLFOnce(from: start, end: end, in: content) : nil
    }

    /// `matchLinkLabel` counting the whitespace of each lazy continuation line that keeps some, as `recorded` holds it.
    // Out of line, as only a document with such a line calls it, so that `matchLinkLabel` stays small.
    @inline(never)
    private func matchLinkLabelCountingLazyLineWhitespace(
        from start: Int,
        end: Int,
        in content: borrowing ContentSpan,
        recorded: LazyLineWhitespace
    ) -> (interior: Range<Int>, afterEnd: Int)? {
        if let label = content.withForwardReader(from: start, { byte in
            scanLinkLabel(from: start, end: end, crlfIsOneCharacter: false, byte: byte, countsLazyLineWhitespace: true) {
                lazyLineWhitespaceBytes(afterLineJoinAt: $0, in: content, recorded: recorded)
            }
        }) {
            return label
        }
        guard contentHoldsCR else {
            return nil
        }
        return content.withForwardReader(from: start) { byte in
            scanLinkLabel(from: start, end: end, crlfIsOneCharacter: true, byte: byte, countsLazyLineWhitespace: true) {
                lazyLineWhitespaceBytes(afterLineJoinAt: $0, in: content, recorded: recorded)
            }
        }
    }

    /// Whether a link label that `matchLinkLabel` doesn't match from `start` can still close on a later line: up to `end`
    /// and a line ending after it, it holds no unescaped `[` and fits `linkLabelLimit`. Whitespace that a later lazy
    /// continuation line keeps is not yet counted.
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

    /// `matchLinkLabel` counting a CRLF as one character.
    // Out of line, as only content holding a CR calls it, so that its callers on every content's path stay small.
    @inline(never)
    private func matchLinkLabelCountingCRLFOnce(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        content.withForwardReader(from: start) { byte in scanLinkLabel(from: start, end: end, crlfIsOneCharacter: true, byte: byte) }
    }

    /// Whether a label that `matchLinkLabel` didn't scan, such as a shortcut reference's link text or a footnote's
    /// label, fits `limit` untrimmed. A longer label matches no definition.
    internal func labelFits(_ limit: LabelLengthLimit, virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> Bool {
        let recorded = lazyLineWhitespace
        // A content byte counts as at most one character and at most three bytes (a NUL), so a label of at most
        // `limit.characters` content bytes and at most a third of `limit.bytes` fits, unless a lazy continuation
        // line's whitespace adds bytes. Four content bytes count as at least one character and two as at least one
        // byte (a CRLF), so a label of more content bytes than four times `limit.characters` or twice `limit.bytes`
        // doesn't. Settling those without weighing each byte keeps a label that spans many nested brackets cheap.
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
            // A CRLF is one line ending. Only inline-only content parsed in place holds a CR.
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

    /// The most characters and bytes a link label can have inside its brackets (Links).
    internal var linkLabelLimit: LabelLengthLimit {
        LabelLengthLimit(characters: limits.maxLinkLabelCharacters, bytes: limits.maxLinkLabelBytes)
    }

    /// The most characters and bytes a footnote reference's label can have inside its brackets.
    internal var footnoteLabelLimit: LabelLengthLimit {
        LabelLengthLimit(characters: limits.maxFootnoteLabelCharacters, bytes: limits.maxFootnoteLabelBytes)
    }

    /// Counts characters (code points): a UTF-8 continuation byte counts 0 and every other byte 1.
    private func labelCharacterWeight(_ byte: UInt8) -> Int {
        return byte & 0xC0 == 0x80 ? 0 : 1
    }

    /// Counts bytes: a NUL counts as the 3 bytes of the U+FFFD that replaces it (Insecure characters) and every other
    /// byte 1.
    private func labelByteWeight(_ byte: UInt8) -> Int {
        return byte == 0 ? 3 : 1
    }

    // MARK: - Link destination

    /// Scans a link destination through `byte`, and a bare one's parentheses, nested at most `maxNesting` deep,
    /// through `parentheses`. Returns the destination's range, without any `<` `>`, and the offset past it.
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
                // Only ASCII punctuation can be escaped (Backslash escapes), so a `\` before a line ending leaves it in
                // the destination, which a `<…>` destination may not contain (Links).
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
        // A bare destination contains no ASCII space or control character (Links). A NUL stands for
        // U+FFFD (Insecure characters), so it is destination content.
        func terminatesDestination(_ b: UInt8) -> Bool {
            b == UInt8(ascii: " ") || (b != 0 && b < 0x20) || b == 0x7F
        }
        if terminatesDestination(first) {
            return nil
        }
        // A bare destination includes parentheses only when they are escaped or balanced (Links).
        guard let destinationEnd = parentheses.balancedEnd(from: start, end: end, maxNesting: maxNesting, byte: byte, terminates: terminatesDestination) else {
            return nil
        }
        // An inline link's destination may be empty: `[a]()`.
        return (start..<destinationEnd, destinationEnd)
    }

    /// Matches a link destination (Links) at virtual offset `start` of `content`.
    internal mutating func matchLinkDestination(from start: Int, end: Int, in content: borrowing ContentSpan) -> (destination: Range<Int>, afterEnd: Int)? {
        let maxNesting = limits.maxLinkDestinationParenthesisNesting
        return content.withForwardReader(from: start) { byte in
            Self.scanLinkDestination(from: start, end: end, parentheses: &destinationParentheses, maxNesting: maxNesting, byte: byte)
        }
    }

    // MARK: - Link title

    /// Scans a link title through `byte`. A title may span a line ending, and its furthest closer may lie past one that
    /// ends the first line (`'\'` LF `'`). Returns the interior's range and the offset past the closer.
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

    /// Matches a link title (Links) at virtual offset `start` of `content`.
    internal func matchLinkTitle(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        content.withForwardReader(from: start) { byte in scanLinkTitle(from: start, end: end, byte: byte) }
    }

    // MARK: - HTML tags

    /// The offset past an HTML tag name (Raw HTML) at `start`, read through `byte` up to `end`, or nil when no ASCII
    /// letter starts one.
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

    /// The offset past the rest of an open or closing tag (Raw HTML) whose name ends at `nameEnd`: an open tag's
    /// attributes, each after whitespace, then optional whitespace and `/>` or `>`, or a closing tag's optional
    /// whitespace and `>`. nil when the rest forms no tag.
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
                // An unquoted value is nonempty, so `<a b=>` is no tag.
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

    /// Normalizes a link label for matching (Links): trims whitespace (Characters and lines), collapses interior runs to one space, and applies the Unicode case fold.
    internal func normalizeLabel(chunk: Chunk) -> String {
        let span = if chunk.inSource {
            sourceBytes.extracting(chunk.range)
        } else {
            storage.strings.span.extracting(chunk.range)
        }

        return Self.normalizeLabel(span)
    }

    /// A label that one chunk of `content` holds, as any label of single-segment content is, is read from that chunk;
    /// one spanning a line join of multi-segment content is read through `content`, which reads each join as `\n`.
    internal func normalizeLabel(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> String {
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

    /// `span` normalized as `normalizeLabel(chunk:)` describes, with each NUL replaced with U+FFFD (Insecure characters).
    ///
    /// Each NUL takes three bytes, and every other byte at most one, since a whitespace run becomes at most one space.
    /// Sizing the buffer to that, rather than to three bytes per source byte, stores a short label inline instead of in a
    /// heap allocation. ASCII letters are lowercased in the same pass, which completes the case fold of a label with no
    /// non-ASCII bytes.
    private static func normalizeLabel(_ span: Span<UInt8>) -> String {
        var hasNonASCII = false
        var nulCount = 0
        for i in 0..<span.count where span[i] == 0 {
            nulCount += 1
        }
        let label = String(unsafeUninitializedCapacity: span.count + 2 * nulCount) { buffer in
            // SAFETY: The `OutputSpan` starts with none of `buffer` initialized, every append is capacity-checked against `span.count + 2 * nulCount` (the most the label can need), `finalize(for:)` verifies `buffer` before reporting the initialized count, and the initializer repairs invalid UTF-8.
            //         No String initializer fills its UTF-8 storage through an `OutputSpan`. Building the bytes with `Array(capacity:initializingWith:)` and copying them with `String(decoding:as:)` measured up to 21% more parse instructions on reference- and footnote-heavy input. Building them in `withTemporaryAllocation(of:capacity:_:)` and copying them with `String(copying:)` after `UTF8Span(validating:)` exists only on anyAppleOS 26 and measured up to 0.95% more.
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
        // The spec matches labels by their case folds alone (Links). Labels are compared as `String`s, whose equality is
        // canonical equivalence, so labels whose case folds are canonically equivalent but differ in their bytes, such as
        // precomposed `é` and `e` followed by U+0301, also match.
        return hasNonASCII ? caseFold(label) : label
    }

    /// `label` with each scalar replaced by a stand-in for its Unicode case fold, so two labels' results are equal
    /// exactly when their case folds are. Lowercasing a scalar, then uppercasing and lowercasing again each scalar of
    /// the result, yields one stand-in for each case fold, except for dotless `ı`: it folds to itself, but uppercases to
    /// the `I` that `i` folds with, so it stands for itself.
    private static func caseFold(_ label: String) -> String {
        let scalars = label.unicodeScalars
        var folded = ""
        // The scalars from `unchangedStart` up to the current one are their own stand-ins, so they are appended as a run.
        var unchangedStart = scalars.startIndex
        // Labels repeat scalars, so the last non-ASCII one found to be its own stand-in is remembered.
        var lastUnchanged: Unicode.Scalar = "a"
        var i = scalars.startIndex
        while i != scalars.endIndex {
            let scalar = scalars[i]
            let next = scalars.index(after: i)
            // A scalar that doesn't change when case mapped is its own stand-in, as is an ASCII scalar once
            // `normalizeLabel` has lowercased it.
            if !scalar.isASCII && scalar != lastUnchanged {
                if scalar.properties.changesWhenCaseMapped {
                    folded.append(contentsOf: Substring(scalars[unchangedStart..<i]))
                    for lower in scalar.properties.lowercaseMapping.unicodeScalars {
                        if lower == "ı" {
                            folded.unicodeScalars.append(lower)
                        } else {
                            for upper in lower.properties.uppercaseMapping.unicodeScalars {
                                folded += upper.properties.lowercaseMapping
                            }
                        }
                    }
                    unchangedStart = next
                } else {
                    lastUnchanged = scalar
                }
            }
            i = next
        }
        if unchangedStart == scalars.startIndex {
            return label
        }
        folded.append(contentsOf: Substring(scalars[unchangedStart...]))
        return folded
    }
}

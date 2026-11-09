/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// The unescaped `(` that the latest scan for balanced parentheses passed, in a bare link destination (Links) or an
/// attribute form's `(…)`, so that a scan starting just after one of them reads its result rather than the bytes.
///
/// A scan stops at a `)` that closes no `(` it passed, at a byte that ends the run, or at the end, and its parentheses
/// are balanced when it closed every `(` it passed. A scan starting just after a `(` the latest scan passed reads the
/// same bytes: it stops at the `)` closing that `(`, or else where the latest scan stopped, balanced only when that
/// `(` is the innermost one left open there.
internal struct BalancedParenthesesScan {
    /// Each `(` the latest scan passed, in order, with where a scan starting just after it stops balanced, or nil when
    /// that scan stops unbalanced.
    private var openers: [(offset: Int, balancedEnd: Int?)] = []
    /// During a scan, the indices in `openers` of the `(` not yet closed, innermost last.
    private var unclosed: [Int] = []
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
    /// `end`, if its parentheses are balanced there. Between resets every scan reads the same bytes up to the same
    /// `end` through `byte` and `terminates`.
    @inline(__always)
    mutating func balancedEnd(from start: Int, end: Int, byte: (Int) -> UInt8, terminates: (UInt8) -> Bool) -> Int? {
        while nextOpener < openers.count, openers[nextOpener].offset < start - 1 {
            nextOpener += 1
        }
        if nextOpener < openers.count, openers[nextOpener].offset == start - 1 {
            return openers[nextOpener].balancedEnd
        }
        reset()
        var i = start
        while i < end {
            let c = byte(i)
            // Only ASCII punctuation can be escaped, so a `\` before a line ending is literal.
            if c == UInt8(ascii: "\\") && i + 1 < end && byte(i + 1).isASCIIPunct {
                i += 2
                continue
            }
            if c == UInt8(ascii: "(") {
                unclosed.append(openers.count)
                openers.append((i, nil))
            } else if c == UInt8(ascii: ")") {
                guard let opener = unclosed.popLast() else {
                    break
                }
                openers[opener].balancedEnd = i
            } else if terminates(c) {
                break
            }
            i += 1
        }
        guard let innermost = unclosed.last else {
            return i
        }
        openers[innermost].balancedEnd = i
        unclosed.removeAll(keepingCapacity: true)
        return nil
    }
}

/// Scanners for link labels, destinations, titles and the whitespace between them, shared by link reference definitions and inline links, and for raw HTML tags.
extension BlockParser {

    // MARK: - Link label

    internal struct LinkLabelMatch {
        var interior: Chunk
        var afterEnd: Int
    }

    /// Matches a link label (Links), returning its interior and the offset past its `]`.
    internal func matchLinkLabel(_ chunk: Chunk) -> LinkLabelMatch? {
        precondition(!chunk.isEmpty, "a link label scan starts on a content byte")
        let match = scanLinkLabel(from: chunk.offset, end: chunk.range.upperBound) { readByte(at: $0, in: chunk) }
        return match.map { LinkLabelMatch(interior: subchunk(of: chunk, $0.interior), afterEnd: $0.afterEnd) }
    }

    /// The part of `chunk` at `range`.
    private func subchunk(of chunk: Chunk, _ range: Range<Int>) -> Chunk {
        Chunk(offset: range.lowerBound, length: range.count, inSource: chunk.inSource)
    }

    /// Scans a link label through `byte`, for both `matchLinkLabel` overloads. A full reference's label may span a
    /// line ending. Returns the interior's range and the offset past `]`, or nil at an unescaped `[`, past
    /// `maxLinkLabelLength`, or at the end.
    @inline(__always)
    private func scanLinkLabel(from start: Int, end: Int, byte: (Int) -> UInt8) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end || byte(start) != UInt8(ascii: "[") {
            return nil
        }
        let maxLabelLength = Self.maxLinkLabelLength
        let interiorStart = start + 1
        var i = interiorStart
        var length = 0
        while i < end {
            let b = byte(i)
            if b == UInt8(ascii: "[") {
                return nil
            }
            if b == UInt8(ascii: "]") {
                return (interiorStart..<i, i + 1)
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                length += 1
                if i < end {
                    length += labelLengthWeight(byte(i))
                    i += 1
                }
            } else {
                length += labelLengthWeight(b)
                i += 1
            }
            if length > maxLabelLength {
                return nil
            }
        }
        return nil
    }

    /// `matchLinkLabel(_:)` over virtual offsets of inline content.
    internal func matchLinkLabel(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        scanLinkLabel(from: start, end: end) { content[$0] }
    }

    /// Whether a label that `matchLinkLabel` didn't scan, such as a shortcut reference's link text or a footnote
    /// reference's label, fits `maxLinkLabelLength` untrimmed. A longer label matches no definition.
    internal func linkLabelFitsLengthCap(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> Bool {
        let maxLabelLength = Self.maxLinkLabelLength
        // A character takes one to four bytes, so a label of at most `maxLabelLength` bytes fits and one of more than
        // four times that doesn't. Settling those without weighing each byte keeps a label that spans many nested
        // brackets cheap.
        if range.count <= maxLabelLength {
            return true
        }
        if range.count > 4 * maxLabelLength {
            return false
        }
        var length = 0
        for i in range {
            length += labelLengthWeight(content[i])
            if length > maxLabelLength {
                return false
            }
        }
        return true
    }

    /// A link label has at most 999 characters (Links), counted by `labelLengthWeight`.
    private static let maxLinkLabelLength = 999

    /// Counts characters (code points): a UTF-8 continuation byte counts 0 and every other byte 1.
    private func labelLengthWeight(_ byte: UInt8) -> Int {
        return byte & 0xC0 == 0x80 ? 0 : 1
    }

    // MARK: - Link destination

    internal struct LinkDestinationMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Matches a link destination (Links).
    internal func matchLinkDestination(_ chunk: Chunk) -> LinkDestinationMatch? {
        // A definition's offsets address the source or the arena rather than inline content, so it shares no scan.
        var parentheses = BalancedParenthesesScan()
        let match = Self.scanLinkDestination(from: chunk.offset, end: chunk.range.upperBound, parentheses: &parentheses) { readByte(at: $0, in: chunk) }
        return match.map { LinkDestinationMatch(chunk: subchunk(of: chunk, $0.destination), afterEnd: $0.afterEnd) }
    }

    /// Scans a link destination through `byte`, and a bare one's parentheses through `parentheses`, for both
    /// `matchLinkDestination` overloads. Returns the destination's range, without any `<` `>`, and the offset past it.
    @inline(__always)
    private static func scanLinkDestination(from start: Int, end: Int, parentheses: inout BalancedParenthesesScan, byte: (Int) -> UInt8) -> (destination: Range<Int>, afterEnd: Int)? {
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
                if c == UInt8(ascii: "\n") || c == UInt8(ascii: "<") {
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
        guard let destinationEnd = parentheses.balancedEnd(from: start, end: end, byte: byte, terminates: terminatesDestination) else {
            return nil
        }
        // An inline link's destination may be empty: `[a]()`.
        return (start..<destinationEnd, destinationEnd)
    }

    /// `matchLinkDestination(_:)` over virtual offsets of inline content.
    internal mutating func matchLinkDestination(from start: Int, end: Int, in content: borrowing ContentSpan) -> (destination: Range<Int>, afterEnd: Int)? {
        Self.scanLinkDestination(from: start, end: end, parentheses: &destinationParentheses) { content[$0] }
    }

    // MARK: - Link title

    internal struct LinkTitleMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Matches a link title (Links).
    internal func matchLinkTitle(_ chunk: Chunk) -> LinkTitleMatch? {
        let match = scanLinkTitle(from: chunk.offset, end: chunk.range.upperBound) { readByte(at: $0, in: chunk) }
        return match.map { LinkTitleMatch(chunk: subchunk(of: chunk, $0.interior), afterEnd: $0.afterEnd) }
    }

    /// Scans a link title through `byte`, for both `matchLinkTitle` overloads. A title may span a line ending, and
    /// its furthest closer may lie past one that ends the first line (`'\'` LF `'`). Returns the interior's
    /// range and the offset past the closer.
    @inline(__always)
    private func scanLinkTitle(from start: Int, end: Int, byte: (Int) -> UInt8) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end {
            return nil
        }
        let opener = byte(start)
        let closer: UInt8
        switch opener {
        case UInt8(ascii: "\""):
            closer = UInt8(ascii: "\"")
        case UInt8(ascii: "'"):
            closer = UInt8(ascii: "'")
        case UInt8(ascii: "("):
            closer = UInt8(ascii: ")")
        default:
            return nil
        }
        // A `\` in the body may begin a backslash escape or be literal, and the title closes at the furthest
        // closer either reading reaches: `'\')` has the title `\`, since no later `'` completes the escape.
        // `inBody` may take a content byte (any byte but a delimiter), begin an escape, or close;
        // `afterBackslash` needs ASCII punctuation to complete an escape.
        var inBody = true
        var afterBackslash = false
        var closeAfterEnd: Int? = nil
        var i = start + 1
        while i < end, inBody || afterBackslash {
            let c = byte(i)
            var nextInBody = false
            var nextAfterBackslash = false
            if inBody {
                if c == closer {
                    closeAfterEnd = i + 1
                }
                if c != opener && c != closer {
                    nextInBody = true
                }
                if c == UInt8(ascii: "\\") {
                    nextAfterBackslash = true
                }
            }
            if afterBackslash && c.isASCIIPunct {
                nextInBody = true
            }
            inBody = nextInBody
            afterBackslash = nextAfterBackslash
            i += 1
        }
        guard let closeAfterEnd else {
            return nil
        }
        return ((start + 1)..<(closeAfterEnd - 1), closeAfterEnd)
    }

    /// `matchLinkTitle(_:)` over virtual offsets of inline content.
    internal func matchLinkTitle(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        scanLinkTitle(from: start, end: end) { content[$0] }
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
            while i < end, byte(i).isASCIISpace {
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
                    if b.isASCIISpace || b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") || b == UInt8(ascii: "=")
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

    // MARK: - Whitespace

    // These are `mutating` though they only read: a non-mutating method of the large `BlockParser` copies the parser per call, which costs more than the scan.

    /// Skips spaces, tabs, line tabulations and form feeds.
    internal mutating func skipLineWhitespace(from cursor: Int, in chunk: Chunk) -> Int {
        let end = chunk.range.upperBound
        var i = cursor
        while i < end {
            let c = readByte(at: i, in: chunk)
            if !c.isLineWhitespace {
                break
            }
            i += 1
        }
        return i
    }

    /// Skips line whitespace, at most one line ending, and more line whitespace.
    internal mutating func skipSpacesAndOneLineEnd(from cursor: Int, in chunk: Chunk) -> Int {
        let end = chunk.range.upperBound
        var i = skipLineWhitespace(from: cursor, in: chunk)
        if i >= end {
            return i
        }
        let c = readByte(at: i, in: chunk)
        precondition(c != UInt8(ascii: "\r"), "definition content holds no carriage return: lines split on CR and join with LF")
        if c == UInt8(ascii: "\n") {
            i += 1
            i = skipLineWhitespace(from: i, in: chunk)
        }
        return i
    }

    /// The offset past a line ending at `cursor`, `cursor` at the end of `chunk`, or `nil`.
    internal mutating func skipLineEndOrEOF(from cursor: Int, in chunk: Chunk) -> Int? {
        let end = chunk.range.upperBound
        if cursor >= end {
            return cursor
        }
        let c = readByte(at: cursor, in: chunk)
        precondition(c != UInt8(ascii: "\r"), "definition content holds no carriage return: lines split on CR and join with LF")
        if c == UInt8(ascii: "\n") {
            return cursor + 1
        }
        return nil
    }

    // MARK: - Label normalization

    /// Normalizes a link label for matching (Links): trims whitespace, collapses interior runs to one space, and applies the Unicode case fold. Whitespace includes line tabulation and form feed.
    internal func normalizeLabel(chunk: Chunk) -> String {
        let span = if chunk.inSource {
            sourceBytes.extracting(chunk.range)
        } else {
            storage.strings.span.extracting(chunk.range)
        }

        return Self.normalizeLabel(span)
    }

    /// A label within one segment is read from its chunk; one spanning a line ending is read through
    /// `content`, whose line joins read as `\n`.
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

    /// Replaces each NUL with U+FFFD (Insecure characters) in its own buffer rather than `storage.strings`,
    /// because a definition's label can be normalized while that arena is borrowed. Each NUL takes three bytes, and
    /// every other byte at most one, since a whitespace run becomes at most one space. Sizing the buffer to that, rather
    /// than to three bytes per source byte, stores a short label inline instead of in a heap allocation. ASCII letters are
    /// lowercased in the same pass, which completes the case fold of a label with no non-ASCII bytes.
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
                if b.isASCIISpace {
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

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// Byte-level scanners for link labels, destinations, titles, and the whitespace constructs that separate them.
///
/// They sit alongside the other parsing helpers and read `storage`/`sourceBytes` directly instead of taking them as parameters. They're used by both block-level reference-definition parsing (`BlockParser`) and inline link parsing (the InlineParser extensions).
///
/// The shared ASCII byte-classifier predicates (`isASCIISpace`, `isASCIIPunct`, `isASCIILetter`, `isASCIIDigit`) live on `UInt8` in `ASCIIByte.swift` so they're usable without a parser instance.
extension BlockParser {

    // MARK: - Link label

    internal struct LinkLabelMatch {
        var interior: Chunk
        var afterEnd: Int
    }

    /// Parse a `[label]` link label (spec "Links"). Returns the interior chunk (excluding brackets) and the offset just past the closing `]`. Allows ASCII `\X` escapes inside the label. Capped per `maxLinkLabelLength`.
    internal func matchLinkLabel(_ chunk: Chunk) -> LinkLabelMatch? {
        let start = chunk.offset
        let end = chunk.range.upperBound
        precondition(start < end, "a link label scan starts on a content byte")
        if readByte(at: start, in: chunk) != UInt8(ascii: "[") {
            return nil
        }
        let maxLabelLength = Self.maxLinkLabelLength
        let interiorStart = start + 1
        var i = interiorStart
        var length = 0
        while i < end {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "[") {
                return nil
            }
            if b == UInt8(ascii: "]") {
                return LinkLabelMatch(
                    interior: chunk.extracting(1..<(i - start)),
                    afterEnd: i + 1
                )
            }
            if b == UInt8(ascii: "\\") {
                i += 1
                length += 1
                if i < end {
                    length += labelLengthWeight(readByte(at: i, in: chunk))
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

    /// Variant of `matchLinkLabel(_:)` over the virtual offsets of multi-segment inline content, where a
    /// full reference's link label may span a line ending (`[text][la\nbel]`) that `contiguousChunk` can't
    /// image within one source segment. Scans from `start` (which must be `[`) to the closing `]`; returns
    /// the interior's virtual range (excluding the brackets) and the offset just past `]`, or nil on an
    /// interior `[` or at the content end. Allows ASCII `\X` escapes, capped per `maxLinkLabelLength`. The
    /// interior may span segments, so callers resolve it with `normalizeLabel(virtualRange:in:)`, not a
    /// `Chunk`.
    internal func matchLinkLabel(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end || content[start] != UInt8(ascii: "[") {
            return nil
        }
        let maxLabelLength = Self.maxLinkLabelLength
        let interiorStart = start + 1
        var i = interiorStart
        var length = 0
        while i < end {
            let b = content[i]
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
                    length += labelLengthWeight(content[i])
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

    /// Whether a label that is looked up without being scanned by `matchLinkLabel` - the text at
    /// virtual `range` of `content`, measured raw and untrimmed - is within `maxLinkLabelLength`. That is
    /// a shortcut or collapsed reference's link text (between the opener's `[` / `![` and the `]`) or a
    /// footnote reference's label (past its `^`); a longer label matches no definition.
    internal func linkLabelFitsLengthCap(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> Bool {
        let maxLabelLength = Self.maxLinkLabelLength
        var length = 0
        for i in range {
            length += labelLengthWeight(content[i])
            if length > maxLabelLength {
                return false
            }
        }
        return true
    }

    /// The maximum link-label length that `matchLinkLabel` accepts before rewinding and that
    /// `linkLabelFitsLengthCap` accepts for a shortcut or footnote label, in the units of
    /// `labelLengthWeight`: a link label has "at most 999 characters" (spec "Links").
    private static let maxLinkLabelLength = 999

    /// A content byte's contribution to the link-label length against `maxLinkLabelLength`.
    ///
    /// Counts characters (Unicode code points, spec "Characters and lines"): a UTF-8
    /// continuation byte counts 0 and every other byte, NUL included, counts 1.
    private func labelLengthWeight(_ byte: UInt8) -> Int {
        return byte & 0xC0 == 0x80 ? 0 : 1
    }

    // MARK: - Link destination

    internal struct LinkDestinationMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Whether a `\` inside a `<…>` link destination escapes `next`, the byte after it. A backslash escapes
    /// only ASCII punctuation (spec "Backslash escapes"), so a `\` before a line ending leaves the line ending
    /// in the destination, which a `<…>` destination may not contain (spec "Links").
    private func escapesNext(_ next: UInt8?) -> Bool {
        next?.isASCIIPunct ?? false
    }

    /// Parse a link destination - either `<...>` (no internal `<`, `>`, or line ending) or a bare URL (no ASCII space or control character, balanced parens up to depth 32, ASCII `\X` escapes).
    internal func matchLinkDestination(_ chunk: Chunk) -> LinkDestinationMatch? {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start >= end {
            return nil
        }
        let first = readByte(at: start, in: chunk)
        if first == UInt8(ascii: "<") {
            var i = start + 1
            while i < end {
                let c = readByte(at: i, in: chunk)
                if c == UInt8(ascii: ">") {
                    return LinkDestinationMatch(chunk: chunk.extracting(1..<(i - start)), afterEnd: i + 1)
                }
                if c == UInt8(ascii: "\\"), escapesNext(i + 1 < end ? readByte(at: i + 1, in: chunk) : nil) {
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
        // A bare destination contains no ASCII space or control character (spec "Links"). A NUL stands
        // for U+FFFD (spec "Insecure characters"), so it is destination content.
        func terminatesDestination(_ b: UInt8) -> Bool {
            b == UInt8(ascii: " ") || (b != 0 && b < 0x20) || b == 0x7F
        }
        if terminatesDestination(first) {
            return nil
        }
        var i = start
        var nbParen = 0
        while i < end {
            let c = readByte(at: i, in: chunk)
            // A backslash escapes only an ASCII-punctuation byte, so a `\` before a line ending (or any
            // non-punctuation byte) is a literal destination character - a destination never spans a
            // line ending.
            if c == UInt8(ascii: "\\") && i + 1 < end && readByte(at: i + 1, in: chunk).isASCIIPunct {
                i += 2
                continue
            }
            if c == UInt8(ascii: "(") {
                nbParen += 1
                if nbParen > 32 {
                    return nil
                }
                i += 1
                continue
            }
            if c == UInt8(ascii: ")") {
                if nbParen == 0 {
                    break
                }
                nbParen -= 1
                i += 1
                continue
            }
            if terminatesDestination(c) {
                break
            }
            i += 1
        }
        // A bare destination includes parentheses only when they are escaped or balanced (spec "Links").
        if nbParen != 0 {
            return nil
        }
        // Empty bare URL is allowed for inline links - `[a]()` should match with an empty destination.
        return LinkDestinationMatch(chunk: chunk.extracting(0..<(i - start)), afterEnd: i)
    }

    /// Variant of `matchLinkDestination(_:)` over the virtual offsets of inline content, which may be
    /// multi-segment. Scans from `start` to `end`; returns the destination's virtual range (excluding any
    /// `<` `>`) and the offset just past it. A bare destination ends at the first space or line ending,
    /// so it is scanned through the contiguous window by `matchLinkDestination(_:)`. Callers materialize
    /// the range with `materializedChunk`, not a contiguous `Chunk`.
    internal func matchLinkDestination(from start: Int, end: Int, in content: borrowing ContentSpan) -> (destination: Range<Int>, afterEnd: Int)? {
        if start >= end {
            return nil
        }
        if content[start] == UInt8(ascii: "<") {
            var i = start + 1
            while i < end {
                let c = content[i]
                if c == UInt8(ascii: ">") {
                    return ((start + 1)..<i, i + 1)
                }
                if c == UInt8(ascii: "\\"), escapesNext(i + 1 < end ? content[i + 1] : nil) {
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
        guard let window = content.contiguousChunk(fromVirtual: start, limit: end),
              let dest = matchLinkDestination(window) else {
            return nil
        }
        let afterEnd = start + (dest.afterEnd - window.offset)
        return (start..<afterEnd, afterEnd)
    }

    // MARK: - Link title

    internal struct LinkTitleMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Match `"…"`, `'…'`, or `(…)` with ASCII `\X` escapes. Parens form disallows unescaped `(` inside.
    internal func matchLinkTitle(_ chunk: Chunk) -> LinkTitleMatch? {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start >= end {
            return nil
        }
        let opener = readByte(at: start, in: chunk)
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
        // A `\` in the body has two readings at once: the start of a backslash escape (spec "Backslash
        // escapes") or a literal byte. The title closes at the furthest closing delimiter either reading
        // reaches, so `'\')` has the title `\`: no later `'` exists for the escape to land on, so the `\`
        // is literal and the `'` after it closes. Two states track the readings:
        //   - `inBody`: inside the body, able to consume a content byte, begin an escape, or close on
        //     the delimiter;
        //   - `afterBackslash`: just consumed a `\` that begins an escape and needs an ASCII punctuation
        //     byte to complete it.
        // A content byte is any byte other than the opening and closing delimiters (for quote forms
        // `opener == closer`).
        var inBody = true
        var afterBackslash = false
        var closeAfterEnd: Int? = nil
        var i = start + 1
        while i < end, inBody || afterBackslash {
            let c = readByte(at: i, in: chunk)
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
        return LinkTitleMatch(chunk: chunk.extracting(1..<(closeAfterEnd - 1 - start)), afterEnd: closeAfterEnd)
    }

    /// Variant of `matchLinkTitle(_:)` over the virtual offsets of inline content, which may be
    /// multi-segment: a title may span a line ending (`[](f (\n))`) that `contiguousChunk` can't image
    /// within one source segment, and its furthest closing delimiter may lie past one that ends the first
    /// line (`'\'` LF `'` closes on the second line). Scans from `start` (the opening delimiter) to `end`
    /// with the same two-state scan as `matchLinkTitle(_:)`; returns the interior's virtual range
    /// (excluding the delimiters) and the offset just past the closer, or nil when the opener is not a
    /// delimiter or no closer is reached. The interior may span segments, so callers materialize it with
    /// `materializedChunk`, not a contiguous `Chunk`.
    internal func matchLinkTitle(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end {
            return nil
        }
        let opener = content[start]
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
        var inBody = true
        var afterBackslash = false
        var closeAfterEnd: Int? = nil
        var i = start + 1
        while i < end, inBody || afterBackslash {
            let c = content[i]
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

    // MARK: - Whitespace

    /// Skip zero or more space, tab, line tabulation (U+000B) and form feed (U+000C) bytes, from `cursor` up
    /// to the end of `chunk`.
    internal func skipLineWhitespace(from cursor: Int, in chunk: Chunk) -> Int {
        let end = chunk.range.upperBound
        var i = cursor
        while i < end {
            let c = readByte(at: i, in: chunk)
            if !c.isSpaceOrTab && c != 0x0B && c != 0x0C {
                break
            }
            i += 1
        }
        return i
    }

    /// Zero or more whitespace bytes other than line endings (`skipLineWhitespace`), then *at most one* line ending, then more of them. Scans from `cursor` up to the end of `chunk`.
    internal func skipSpacesAndOneLineEnd(from cursor: Int, in chunk: Chunk) -> Int {
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

    /// Match a line ending or end-of-input at `cursor`. Returns the offset just past the line ending, or `nil` if `cursor` is neither at a line ending nor at the end of `chunk`.
    internal func skipLineEndOrEOF(from cursor: Int, in chunk: Chunk) -> Int? {
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

    /// Normalizes a link label for matching (spec "Links"): trims outer whitespace, collapses interior whitespace runs to a single space, then case-folds with `String.lowercased()`, so `[ΑΓΩ]` and `[αγω]` resolve to the same key.
    internal func normalizeLabel(chunk: Chunk) -> String {
        let span = if chunk.inSource {
            sourceBytes.extracting(chunk.range)
        } else {
            storage.strings.span.extracting(chunk.range)
        }

        return Self.normalizeLabel(span)
    }

    /// Label normalization for a label at virtual `range` of multi-segment `content` that spans a line
    /// ending (`[foo\nbar]` used as a reference), which `contiguousChunk` can't image within one source
    /// segment. Reading through `content` resolves each line join to `\n`, which collapses like any other
    /// interior whitespace. A contiguous label goes through `normalizeLabel(chunk:)`.
    internal func normalizeLabel(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> String {
        var bytes = UniqueArray<UInt8>()
        bytes.reserveCapacity(range.count)
        for i in range {
            bytes.append(content[i])
        }
        return Self.normalizeLabel(bytes.span)
    }

    /// Label normalization over a resolved span; `static` because it touches no parser state.
    ///
    /// Replaces each NUL with U+FFFD (spec "Insecure characters") in its own output buffer rather than in
    /// `storage.strings`: a link reference definition's label can be normalized while other borrows of
    /// `storage.strings` are live (while a setext heading underline is examined against the paragraph that holds the
    /// definition), and growing that arena would invalidate them. `span.count * 3` covers every byte
    /// being NUL, so the one-pass loop never resizes.
    private static func normalizeLabel(_ span: Span<UInt8>) -> String {
        String(unsafeUninitializedCapacity: span.count * 3) { buffer in
            // SAFETY: `buffer` is the string's uninitialized storage, valid for this closure only. `OutputSpan(buffer:initializedCount: 0)` claims none of it as initialized, every append is capacity-checked (`span.count * 3` covers the worst case), `output.finalize(for: buffer)` checks that `buffer` is the buffer `output` covers before reporting its initialized count, and the initializer repairs any invalid UTF-8 in that prefix.
            //         No String initializer fills its UTF-8 storage through an `OutputSpan`; the safe route builds the bytes in an owned array and copies them with `String(decoding:as:)`, which measured about 1.2% more spec.txt parse instructions.
            var output = unsafe OutputSpan(buffer: buffer, initializedCount: 0)
            var pendingSpace = false

            for i in 0..<span.count {
                let b = span[i]
                switch b {
                case UInt8(ascii: " "), UInt8(ascii: "\t"),
                     UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                    if !output.isEmpty {
                        pendingSpace = true
                    }
                    continue
                default:
                    break
                }
                if pendingSpace {
                    output.append(UInt8(ascii: " "))
                    pendingSpace = false
                }
                if b == 0 {
                    output.append(0xEF)
                    output.append(0xBF)
                    output.append(0xBD)
                } else {
                    output.append(b)
                }
            }

            return unsafe output.finalize(for: buffer)
        }.lowercased()
    }
}

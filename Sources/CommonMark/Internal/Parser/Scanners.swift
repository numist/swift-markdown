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

    /// Parse `[label]` per CommonMark §6.6 / §6.7. Returns the interior chunk (excluding brackets) and the offset just past the closing `]`. Allows ASCII `\X` escapes inside the label. Capped per `maxLinkLabelLength`.
    internal func matchLinkLabel(_ chunk: Chunk) -> LinkLabelMatch? {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start >= end {
            return nil
        }
        if readByte(at: start, in: chunk) != UInt8(ascii: "[") {
            return nil
        }
        let maxLabelLength = maxLinkLabelLength
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

    /// Cross-line variant of `matchLinkLabel(_:)` for multi-segment inline content. cmark's `link_label`
    /// scans a flat input buffer, so a following full-reference label may span a soft-break join
    /// (`[text][la\nbel]`) that `contiguousChunk` can't image within one source segment. Scans virtual
    /// offsets of `content` from `start` (which must be `[`) to the closing `]`, crossing joins; returns
    /// the interior's virtual range (excluding the brackets) and the offset just past `]`. Returns nil on
    /// an interior `[` or the content end — cmark rewinds in both cases. Allows ASCII `\X` escapes,
    /// capped per `maxLinkLabelLength`. The interior may straddle a join, so callers resolve it with
    /// `normalizeLabel(virtualRange:in:)`, not a `Chunk`.
    internal func matchLinkLabel(from start: Int, end: Int, in content: borrowing ContentSpan) -> (interior: Range<Int>, afterEnd: Int)? {
        if start >= end || content[start] != UInt8(ascii: "[") {
            return nil
        }
        let maxLabelLength = maxLinkLabelLength
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
    /// virtual `range` of `content` - is within `maxLinkLabelLength`. That is a shortcut or collapsed
    /// reference's link text (between the opener's `[` / `![` and the `]`) or a footnote reference's
    /// label (past its `^`). cmark applies the cap to both at lookup: `cmark_map_lookup` (`src/map.c`),
    /// shared by the link and footnote maps, returns no entry for a label over `MAX_LINK_LABEL_LENGTH`
    /// bytes, measured on the raw, untrimmed text.
    internal func linkLabelFitsLengthCap(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> Bool {
        let maxLabelLength = maxLinkLabelLength
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
    /// `labelLengthWeight`.
    /// CommonMark §6.6 caps a label at "at most 999 characters", which the shipped deliverable
    /// enforces (reject `> 999`). cmark-gfm's `MAX_LINK_LABEL_LENGTH` is 1000 and both its
    /// `link_label` (`src/inlines.c`) and `cmark_map_lookup` (`src/map.c`) reject only `> 1000`, so it
    /// accepts a 1000-byte label - an off-by-one against the spec. Under `.cmarkBugCompatibility`
    /// (adopted only by the differential fuzzer) we reproduce that and accept up to 1000; the single
    /// cmark constant governs every label site (inline reference and block reference/attribute
    /// definition).
    private var maxLinkLabelLength: Int {
        storage.options.contains(.cmarkBugCompatibility) ? 1000 : 999
    }

    /// A content byte's contribution to the link-label length against `maxLinkLabelLength`.
    ///
    /// cmark counts bytes of its normalized input buffer: every byte is 1, including each byte of a
    /// multi-byte UTF-8 character, and a source NUL is 3 because `blocks.c`'s `S_parser_feed` replaces
    /// it with the 3-byte U+FFFD encoding before any scanning. Under `.cmarkBugCompatibility` we
    /// reproduce that. Flag-off counts characters (Unicode code points, CommonMark §2.1): a UTF-8
    /// continuation byte counts 0 and every other byte, NUL included, counts 1.
    private func labelLengthWeight(_ byte: UInt8) -> Int {
        if storage.options.contains(.cmarkBugCompatibility) {
            return byte == 0 ? 3 : 1
        }
        return byte & 0xC0 == 0x80 ? 0 : 1
    }

    // MARK: - Link destination

    internal struct LinkDestinationMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Parse a link destination - either `<...>` (no internal `<`, `>`, or unescaped newline) or a bare URL (no whitespace, balanced parens up to depth 32, ASCII `\X` escapes).
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
                if c == UInt8(ascii: "\\") {
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
        // why: cmark's bare-destination scan (`manual_scan_link_url_2`, `src/inlines.c`) ends a
        // destination only on `cmark_isspace` = {space, tab, `\n`, `\r`} (the `cmark_ctype_class`
        // class-1 bytes), so vertical tab (0x0B) and form feed (0x0C) are NOT terminators and cmark
        // keeps them as literal destination content. CommonMark §6.5 excludes ASCII control characters
        // (which VT/FF are) from a bare destination, so terminating there is spec-correct - the shipped
        // deliverable does so (`isASCIISpace`). Under `.cmarkBugCompatibility` (adopted only by the
        // differential fuzzer) we reproduce cmark's bug and stop only on {space, tab, `\n`, `\r`}.
        // The two predicates differ by exactly VT/FF; other bytes are unaffected.
        let bugCompat = storage.options.contains(.cmarkBugCompatibility)
        func terminatesDestination(_ b: UInt8) -> Bool {
            bugCompat ? b.isSpaceTabOrNewline : b.isASCIISpace
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
            // line ending. Mirrors cmark's `manual_scan_link_url_2` (`src/inlines.c`).
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
                if i == start {
                    return nil
                }
                break
            }
            i += 1
        }
        // Empty bare URL is allowed for inline links - `[a]()` should match with an empty destination.
        return LinkDestinationMatch(chunk: chunk.extracting(0..<(i - start)), afterEnd: i)
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
        // cmark's `scan_link_title` (re2c: `['] (escaped_char|[^'\x00])* [']` and the `"…"` / `(…)`
        // forms in `src/scanners.re`, where `escaped_char = [\\]<ascii-punct>`) is a *longest-match*
        // scan. Because `[^'\x00]` also matches `\`, a backslash inside the body admits two readings at
        // once — the start of an `escaped_char`, or an ordinary content byte — and the scanner returns
        // the FURTHEST reachable closing delimiter. A left-to-right "always escape `\X`" scan diverges
        // when a `\` precedes the closer with no later closer to escape onto (`'\')` → title `\`): the
        // eager scan consumes the closer as the escaped byte and never matches, while cmark reads the
        // `\` as content and closes on the following delimiter. We simulate the two DFA threads:
        //   - `inBody`: inside the body, able to consume a content byte, begin an escaped_char, or
        //     close on the delimiter;
        //   - `afterBackslash`: just consumed a `\` that begins an escaped_char and needs an ASCII
        //     punctuation byte to complete it.
        // The furthest position at which the body closed is the match. A content byte is any byte other
        // than the opening/closing delimiters (for quote forms `opener == closer`; the `(…)` form
        // excludes both, matching re2c's `[^()\x00]`).
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

    /// Cross-line variant of `matchLinkTitle(_:)` for multi-segment inline content. cmark's
    /// `scan_link_title` scans a flat input buffer, so an inline link's `"…"` / `'…'` / `(…)` title
    /// may span a soft-break join (`[](f (\n))`) that `contiguousChunk` can't image within one source
    /// segment. Scans virtual offsets of `content` from `start` (the opening delimiter) to `end`,
    /// crossing joins with the same longest-match two-thread DFA as `matchLinkTitle(_:)` (see there for
    /// the DFA rationale); returns the interior's virtual range (excluding the delimiters) and the
    /// offset just past the closer, or nil when the opener is not a delimiter or no closer is reached.
    /// The interior may straddle a join, so callers materialize it with `materializedChunk`, not a
    /// contiguous `Chunk`.
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

    /// Skip zero or more space and tab bytes only, from `cursor` up to the end of `chunk`.
    internal func skipSpacesTabs(from cursor: Int, in chunk: Chunk) -> Int {
        let end = chunk.range.upperBound
        var i = cursor
        while i < end {
            let c = readByte(at: i, in: chunk)
            if c != UInt8(ascii: " ") && c != UInt8(ascii: "\t") {
                break
            }
            i += 1
        }
        return i
    }

    /// `spnl` from cmark: zero or more spaces/tabs, then *at most one* line end (`\n`, `\r\n`, or `\r`), then more spaces/tabs. Scans from `cursor` up to the end of `chunk`.
    internal func skipSpacesAndOneLineEnd(from cursor: Int, in chunk: Chunk) -> Int {
        let end = chunk.range.upperBound
        var i = skipSpacesTabs(from: cursor, in: chunk)
        if i >= end {
            return i
        }
        let c = readByte(at: i, in: chunk)
        if c == UInt8(ascii: "\r") {
            i += 1
            if i < end && readByte(at: i, in: chunk) == UInt8(ascii: "\n") {
                i += 1
            }
            i = skipSpacesTabs(from: i, in: chunk)
        } else if c == UInt8(ascii: "\n") {
            i += 1
            i = skipSpacesTabs(from: i, in: chunk)
        }
        return i
    }

    /// Match `\r\n`, `\n`, `\r`, or end-of-input at `cursor`. Returns the offset just past the line ending, or `nil` if `cursor` is neither at a line end nor at the end of `chunk`.
    internal func skipLineEndOrEOF(from cursor: Int, in chunk: Chunk) -> Int? {
        let end = chunk.range.upperBound
        if cursor >= end {
            return cursor
        }
        let c = readByte(at: cursor, in: chunk)
        if c == UInt8(ascii: "\r") {
            var i = cursor + 1
            if i < end && readByte(at: i, in: chunk) == UInt8(ascii: "\n") {
                i += 1
            }
            return i
        }
        if c == UInt8(ascii: "\n") {
            return cursor + 1
        }
        return nil
    }

    // MARK: - Label normalization

    /// CommonMark §4.7 normalization: trim outer whitespace, collapse interior whitespace runs to a single space, then full Unicode case-fold (`String.lowercased()`) so labels match across scripts - `[ΑΓΩ]` and `[αγω]` resolve to the same key.
    internal func normalizeLabel(chunk: Chunk) -> String {
        let span = if chunk.inSource {
            sourceBytes.extracting(chunk.range)
        } else {
            storage.strings.span.extracting(chunk.range)
        }

        return Self.normalizeLabel(span)
    }

    /// §4.7 normalization for a shortcut/collapsed reference label whose bytes span a virtual `range`
    /// of multi-segment `content` — i.e. the label straddles a soft-break join (`[foo\nbar]` used as a
    /// reference). Reading through `content` resolves the interned newline join to `\n`, which the
    /// normalizer collapses into the interior exactly as a contiguous label's newline would be. Used
    /// when `contiguousChunk` can't image the whole label within one source segment; a contiguous
    /// label goes through `normalizeLabel(chunk:)`.
    internal func normalizeLabel(virtualRange range: Range<Int>, in content: borrowing ContentSpan) -> String {
        var bytes = UniqueArray<UInt8>()
        bytes.reserveCapacity(range.count)
        for i in range {
            bytes.append(content[i])
        }
        return Self.normalizeLabel(bytes.span)
    }

    /// CommonMark §4.7 normalization over an already-resolved span. The byte-level worker behind `normalizeLabel(chunk:)`; `static` because it touches no parser state.
    ///
    /// Also folds a NUL byte to U+FFFD (CommonMark §2.3) inline, into this same local output buffer -
    /// never by materializing into `storage.strings`. A definition's label can reach this normalizer
    /// mid-parse (the setext-underline path, PHASE 2c, keys its label before the paragraph's own content
    /// is drained), while other live borrows of `storage.strings` may still be on the call stack; growing
    /// that shared arena here would risk invalidating them. Sized generously (`span.count * 3`, the
    /// worst case if every byte were NUL) so the one-pass loop never needs to resize.
    private static func normalizeLabel(_ span: Span<UInt8>) -> String {
        String(unsafeUninitializedCapacity: span.count * 3) { buffer in
            var output = OutputSpan(buffer: buffer, initializedCount: 0)
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

            return output.finalize(for: buffer)
        }.lowercased()
    }
}

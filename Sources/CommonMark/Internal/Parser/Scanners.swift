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
        precondition(start < end, "a link label scan starts on a content byte")
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

    /// Whether a `\` inside a `<…>` link destination escapes `next`, the byte after it. A backslash escapes
    /// only ASCII punctuation (spec "Backslash escapes"), so a `\` before a line ending leaves the line ending
    /// in the destination, which a `<…>` destination may not contain (spec "Links").
    private func escapesNext(_ next: UInt8?) -> Bool {
        storage.options.contains(.cmarkBugCompatibility) || (next?.isASCIIPunct ?? false)
    }

    /// Parse a link destination - either `<...>` (no internal `<`, `>`, or unescaped newline) or a bare URL (no ASCII space or control character, balanced parens up to depth 32, ASCII `\X` escapes).
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
        let bugCompat = storage.options.contains(.cmarkBugCompatibility)
        func terminatesDestination(_ b: UInt8) -> Bool {
            bugCompat ? b.isSpaceTabOrNewline : b == UInt8(ascii: " ") || (b != 0 && b < 0x20) || b == 0x7F
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
                break
            }
            i += 1
        }
        // A bare destination includes parentheses only when they are escaped or balanced (spec "Links").
        if nbParen != 0 && !bugCompat {
            return nil
        }
        // Empty bare URL is allowed for inline links - `[a]()` should match with an empty destination.
        return LinkDestinationMatch(chunk: chunk.extracting(0..<(i - start)), afterEnd: i)
    }

    /// Cross-line variant of `matchLinkDestination(_:)` for inline content, which may be multi-segment.
    /// cmark's `manual_scan_link_url` scans a flat input buffer, and its `<…>` form skips the byte after
    /// any `\` - a line ending included - so a `<a\` LF `b>` destination spans a soft-break join that
    /// `contiguousChunk` can't image within one source segment. Scans virtual offsets of `content` from
    /// `start` to `end`; returns the destination's virtual range (excluding any `<` `>`) and the offset
    /// just past it. A bare destination ends at the first space or line ending, so it never reaches a
    /// join and is scanned through the contiguous window by `matchLinkDestination(_:)`. The `<…>` range
    /// may straddle a join, so callers materialize it with `materializedChunk`, not a contiguous `Chunk`.
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
                // why: cmark's `manual_scan_link_url` (`src/inlines.c`) skips the byte after any `\`,
                // a line ending included, so `<a\` LF `b>` is a destination. CommonMark §6.3 forbids line
                // endings inside `<…>`; this replicates cmark, as `matchLinkDestination(_:)` does.
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
            // why: the re2c scanners validate UTF-8, so an orphaned continuation byte in cmark's buffer (the
            // U+FFFD standing for it here) matches no transition and ends the scan (`src/scanners.c`
            // `_scan_link_title`).
            if !chunk.inSource, isOrphanReplacement(at: i) {
                break
            }
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

    /// Cross-line variant of `matchLinkTitle(_:)` for inline content, which may be multi-segment. cmark's
    /// `scan_link_title` scans a flat input buffer, so an inline link's `"…"` / `'…'` / `(…)` title
    /// may span a soft-break join (`[](f (\n))`) that `contiguousChunk` can't image within one source
    /// segment. Its longest match can also pass a closer that ends the first line (`'\'` LF `'` closes
    /// on the second line), so the scan must span the whole content, not one segment. Scans virtual
    /// offsets of `content` from `start` (the opening delimiter) to `end`, crossing joins with the same
    /// longest-match two-thread DFA as `matchLinkTitle(_:)` (see there for
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
            // why: the re2c scanners validate UTF-8, so an orphaned continuation byte in cmark's buffer (the
            // U+FFFD standing for it here) matches no transition and ends the scan (`src/scanners.c`
            // `_scan_link_title`).
            if content.orphanedContinuationByteLength(at: i) != nil {
                break
            }
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

    /// `spnl` from cmark: zero or more spaces/tabs, then *at most one* line end, then more spaces/tabs. Scans from `cursor` up to the end of `chunk`.
    internal func skipSpacesAndOneLineEnd(from cursor: Int, in chunk: Chunk) -> Int {
        let end = chunk.range.upperBound
        var i = skipSpacesTabs(from: cursor, in: chunk)
        if i >= end {
            return i
        }
        let c = readByte(at: i, in: chunk)
        precondition(c != UInt8(ascii: "\r"), "definition content holds no carriage return: lines split on CR and join with LF")
        if c == UInt8(ascii: "\n") {
            i += 1
            i = skipSpacesTabs(from: i, in: chunk)
        }
        return i
    }

    /// Match a line end or end-of-input at `cursor`. Returns the offset just past the line ending, or `nil` if `cursor` is neither at a line end nor at the end of `chunk`.
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
            // SAFETY: `buffer` is the string's uninitialized storage, valid for this closure only. `OutputSpan(buffer:initializedCount: 0)` claims none of it as initialized, every append is capacity-checked (`span.count * 3` covers the worst case), `output.finalize(for: buffer)` checks that `output` still covers `buffer` before reporting its initialized count, and the initializer repairs any invalid UTF-8 in that prefix.
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

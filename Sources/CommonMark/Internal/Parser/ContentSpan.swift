/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A read-only view over a single block's inline content, resolved once before inline parsing begins.
///
/// Two modes, distinguished by `isMultiSegment`:
///
/// - **Single-segment (the overwhelmingly common case).** The content is one contiguous buffer region - a zero-copy slice of the source (`inSource == true`) or of a scratch copy of `storage.strings` (`inSource == false`). Bytes are addressed by *global* offsets (`startOffset..<endOffset`) via a branchless `span[offset - base]`, identical in cost to a plain single-buffer read. For source-backed content the global offset IS the original-source byte offset.
///
/// - **Multi-segment.** The content is an ordered list of `Segment`s - source-line ranges (zero-copy into `sourceBytes`) joined by the shared interned `"\n"` - addressed by flat *virtual* offsets (`0..<virtualLength`). Used for multi-line paragraph/heading bodies whose lines aren't source-contiguous (block-quote/list continuation, CRLF) so no source bytes are copied. Almost all non-source segments are the interned `"\n"` join, read as `\n` without touching the arena. The one exception is a lazy-continuation **split-tab residual** (Quirk E, flag-ON): an outer container's matched prefix partially consumes a tab, and the tab's leftover columns become *synthetic spaces*, each standing for the tab byte - materialized into the arena as one non-source segment interleaved among the source-backed ones (`BlockParser.appendSyntheticResidualSpaces`). A lazy tasklist-retry line whose advance stopped inside a scalar (a NUL's U+FFFD, or a multi-byte source scalar) likewise carries its orphaned-byte U+FFFD replacements, one segment each, standing for the source byte its orphan came from, ahead of the line's source segment (`BlockParser.addLazyLineAfterTasklistAdvance`). Either filler carries no inline-significant byte, so inline syntax only ever lives in source segments (`multiNextSignificant` skips non-newline arena segments whole). To read those bytes without holding the growing `storage.strings` across the inline loop's appends, the multi-segment span carries a stable snapshot of the arena (`arena`) taken before inline parsing; non-source segments then read `arena[offset]` (the interned `\n` sits at offset 0, so it resolves naturally too). When no synthetic segment is present the snapshot is empty and non-source segments synthesize `\n` directly, keeping the common multi-line-paragraph path zero-copy.
///
/// `sourceOffsets(ofVirtual:)` maps a (virtual) offset back to its original-source byte offsets (or `nil` for a synthetic byte with no source image), which is how inline nodes get stamped with source ranges.
internal struct ContentSpan: ~Escapable {
    /// Single-segment: the content bytes (0-based via `base`). Multi-segment: `sourceBytes` (the whole source), indexed directly by a segment's absolute source offset.
    @usableFromInline let span: Span<UInt8>

    /// Single-segment: the global offset of `span[0]` (subtracted from a global offset to index `span`). Multi-segment: unused (0).
    @usableFromInline let base: Int

    /// Single-segment: which buffer `span` is (`true` = source, `false` = arena scratch). Multi-segment: unused.
    @usableFromInline let inSource: Bool

    /// Single-segment arena content that images a source range: an arena→source run map, content-relative (keyed from the first content byte). `sourceOffset` resolves through it to recover per-line source columns for reconstructed content - a flattened non-contiguous setext heading, or (as a single constant-shift run) a `\|`-unescaped table cell. Empty (`count == 0`) for source-backed content or arena content with no source image (in which case `sourceOffset` returns `nil`). Only consulted for `!inSource` single-segment content.
    @usableFromInline let arenaRuns: Span<ArenaRun>

    /// `arenaRunEnds[i]` is the content-relative offset just past run `i` of `arenaRuns` (the running total of run lengths), held in stable storage alongside it; empty when `arenaRuns` is. Non-decreasing, so the run covering an offset is found by binary search (`firstIndex(endingAfter:in:)`) - a flattened heading has a run per line, and positions are resolved once per inline node.
    @usableFromInline let arenaRunEnds: Span<Int>

    /// Multi-segment only: the content's segments (empty for single-segment). A copy held in stable storage for the inline loop's duration (the live `storage.segments` pool grows during parsing).
    @usableFromInline let segments: Span<Segment>

    /// Multi-segment only: `segmentEnds[i]` is the virtual offset just past segment `i` (the running total of segment lengths), held in stable storage alongside `segments`. Non-decreasing, so the segment covering a virtual offset is found by binary search (`segmentIndex(covering:)`) rather than a walk from the first segment - a paragraph has a segment per line, and the inline pass resolves offsets once per byte.
    @usableFromInline let segmentEnds: Span<Int>

    /// Multi-segment only: a stable snapshot of `storage.strings` (from offset 0) that backs the content's non-source segments. Empty unless the content carries a synthetic filler segment (a lazy-continuation split-tab residual's spaces, or a lazy tasklist-retry line's orphaned-byte U+FFFD replacements); when empty, non-source segments synthesize `\n` (the only other non-source segment is the interned newline). Held as an independent copy because `storage.strings` grows - and may reallocate - as the inline loop interns node content.
    @usableFromInline let arena: Span<UInt8>

    /// Multi-segment only: total virtual byte length across `segments`.
    @usableFromInline let multiVirtualLength: Int

    /// The arena byte ranges of the content's U+FFFDs that stand for orphaned UTF-8 continuation bytes in cmark's buffer, one range per U+FFFD, ascending (`BlockParser.orphanReplacementRanges`). Offsets are `storage.strings` offsets: a single-segment arena content's global offsets are exactly those, and a multi-segment content's non-source segment maps to them through its `offset`. Empty for content with no orphan (the common case). Held in stable storage for the inline loop's duration.
    @usableFromInline let orphanReplacements: Span<Range<Int>>

    /// Single-segment initializer (zero-copy source slice or arena scratch) with no arena→source mapping. For source-backed content `sourceOffset` is the identity map; for arena content it returns `nil`.
    @_lifetime(copy span)
    @inlinable
    init(span: Span<UInt8>, base: Int, inSource: Bool) {
        self.span = span
        self.base = base
        self.inSource = inSource
        self.arenaRuns = Span<ArenaRun>()
        self.arenaRunEnds = Span<Int>()
        self.segments = Span<Segment>()
        self.segmentEnds = Span<Int>()
        self.arena = Span<UInt8>()
        self.multiVirtualLength = 0
        self.orphanReplacements = Span<Range<Int>>()
    }

    /// Single-segment arena initializer carrying an arena→source run map (see `arenaRuns`) and its running end offsets (see `arenaRunEnds`) so inline stamping recovers source positions for reconstructed (flattened) content, and the content's orphan replacements (see `orphanReplacements`).
    @_lifetime(copy span, copy arenaRuns, copy arenaRunEnds, copy orphanReplacements)
    @inlinable
    init(span: Span<UInt8>, base: Int, inSource: Bool, arenaRuns: Span<ArenaRun>, arenaRunEnds: Span<Int>, orphanReplacements: Span<Range<Int>>) {
        self.span = span
        self.base = base
        self.inSource = inSource
        self.arenaRuns = arenaRuns
        self.arenaRunEnds = arenaRunEnds
        self.segments = Span<Segment>()
        self.segmentEnds = Span<Int>()
        self.arena = Span<UInt8>()
        self.multiVirtualLength = 0
        self.orphanReplacements = orphanReplacements
    }

    /// Multi-segment initializer: `source` is the borrowed source bytes; `segments` is the content's segment list and `segmentEnds` its running virtual end offsets (both held in stable storage); `virtualLength` is their total length. The content's only non-source segment is the interned `"\n"` join, synthesized directly on read.
    @_lifetime(copy source, copy segments, copy segmentEnds)
    @inlinable
    init(source: Span<UInt8>, segments: Span<Segment>, segmentEnds: Span<Int>, virtualLength: Int) {
        self.span = source
        self.base = 0
        self.inSource = false
        self.arenaRuns = Span<ArenaRun>()
        self.arenaRunEnds = Span<Int>()
        self.segments = segments
        self.segmentEnds = segmentEnds
        self.arena = Span<UInt8>()
        self.multiVirtualLength = virtualLength
        self.orphanReplacements = Span<Range<Int>>()
    }

    /// Multi-segment initializer carrying an arena snapshot: identical to the plain multi-segment initializer, but the content also holds a synthetic filler segment (a lazy-continuation split-tab residual's spaces, or a lazy tasklist-retry line's orphaned-byte U+FFFD replacements, listed in `orphanReplacements`) whose bytes live in `arena` (a stable snapshot of `storage.strings` from offset 0). Non-source segments read `arena[offset]` - synthetic filler resolves to its bytes and the interned `"\n"` (offset 0) resolves to `\n`.
    @_lifetime(copy source, copy segments, copy segmentEnds, copy arena, copy orphanReplacements)
    @inlinable
    init(source: Span<UInt8>, segments: Span<Segment>, segmentEnds: Span<Int>, virtualLength: Int, arena: Span<UInt8>, orphanReplacements: Span<Range<Int>>) {
        self.span = source
        self.base = 0
        self.inSource = false
        self.arenaRuns = Span<ArenaRun>()
        self.arenaRunEnds = Span<Int>()
        self.segments = segments
        self.segmentEnds = segmentEnds
        self.arena = arena
        self.multiVirtualLength = virtualLength
        self.orphanReplacements = orphanReplacements
    }

    @inlinable
    var isMultiSegment: Bool { segments.count > 0 }

    /// Global/virtual offset of the first content byte.
    @inlinable
    var startOffset: Int { isMultiSegment ? 0 : base }

    /// Global/virtual offset just past the last content byte.
    @inlinable
    var endOffset: Int { isMultiSegment ? multiVirtualLength : base + span.count }

    @inlinable
    var isEmpty: Bool { isMultiSegment ? multiVirtualLength == 0 : span.count == 0 }

    /// The index of the first entry of the non-decreasing running-end table `ends` that is past `offset` - the index of the piece (segment or arena run) covering `offset` (never a zero-length one for an in-range offset) - or `ends.count` when `offset` is at or past the last end.
    @inlinable
    static func firstIndex(endingAfter offset: Int, in ends: Span<Int>) -> Int {
        var lo = 0
        var hi = ends.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if ends[mid] > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
    }

    /// The index of the first range of the ascending, disjoint `ranges` whose `upperBound` is past `offset` - the range containing `offset`, if any contains it - or `ranges.count` when none ends past it.
    @inlinable
    static func firstIndex(endingAfter offset: Int, in ranges: Span<Range<Int>>) -> Int {
        var lo = 0
        var hi = ranges.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if ranges[mid].upperBound > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
    }

    /// Multi-segment only: the index of the segment covering virtual `offset`, or `segments.count` when `offset` is at or past the end.
    @inlinable
    func segmentIndex(covering offset: Int) -> Int {
        Self.firstIndex(endingAfter: offset, in: segmentEnds)
    }

    /// Multi-segment only: the virtual offset of segment `i`'s first byte.
    @inlinable
    func segmentStart(_ i: Int) -> Int {
        i == 0 ? 0 : segmentEnds[i - 1]
    }

    /// Read the byte at `offset` (global for single-segment, virtual for multi-segment).
    @inlinable
    subscript(_ offset: Int) -> UInt8 {
        if isMultiSegment {
            return multiByte(at: offset)
        }
        return span[offset - base]
    }

    /// Multi-segment byte resolution: find the segment covering virtual `offset` and read it. Source segments read `span` (== `sourceBytes`); a non-source segment reads the arena snapshot (`arena[offset]`) when one is present - the interned newline at offset 0 yields `\n`, a synthetic filler run yields its spaces or U+FFFD bytes - or synthesizes `\n` directly when no snapshot is carried (the common case, whose only non-source segment is the interned newline).
    private func multiByte(at offset: Int) -> UInt8 {
        let i = segmentIndex(covering: offset)
        assert(i < segments.count, "inline content is read only at offsets inside the content")
        let seg = segments[i]
        let local = offset - segmentStart(i)
        if seg.inSource {
            return span[Int(seg.offset) + local]
        }
        if arena.count > 0 {
            return arena[Int(seg.offset) + local]
        }
        // No arena snapshot: the only non-source segment is the shared interned `"\n"`.
        return UInt8(ascii: "\n")
    }

    /// If `offset` is within the U+FFFD standing for a byte that cmark's buffer has as an orphaned UTF-8
    /// continuation byte, the number of content bytes from `offset` to the end of that U+FFFD; otherwise `nil`.
    ///
    /// Only a lazy tasklist-retry line whose checkbox advance stopped inside a multi-byte scalar starts with
    /// orphans (`BlockParser.tasklistAdvanceEnd`), and their U+FFFDs are listed in `orphanReplacements`, so a
    /// NUL's own U+FFFD elsewhere in the content is not one.
    func orphanedContinuationByteLength(at offset: Int) -> Int? {
        if orphanReplacements.count == 0 {
            return nil
        }
        let arenaOffset: Int
        if isMultiSegment {
            let i = segmentIndex(covering: offset)
            guard i < segments.count, !segments[i].inSource else {
                return nil
            }
            arenaOffset = Int(segments[i].offset) + (offset - segmentStart(i))
        } else {
            arenaOffset = offset
        }
        let i = Self.firstIndex(endingAfter: arenaOffset, in: orphanReplacements)
        if i < orphanReplacements.count, orphanReplacements[i].lowerBound <= arenaOffset {
            return orphanReplacements[i].upperBound - arenaOffset
        }
        return nil
    }

    /// The original-source byte offsets for the content byte at `offset`, or `nil` if it maps to a synthetic/arena byte: `source` is the offset it is stamped at, and `physical` the offset of the byte as read, which sits on the byte's own source line. They differ only for a re-indented continuation line, whose `source` is moved to its block-content column (and may then lie past the end of its line). Single-segment source content maps identity (the offset already IS a source offset); single-segment arena content resolves through its arena→source run map (`nil` when unmapped); multi-segment resolves through the segment list.
    @inlinable
    func sourceOffsets(ofVirtual offset: Int) -> (source: Int, physical: Int)? {
        if !isMultiSegment {
            if inSource {
                return (offset, offset)
            }
            // Arena content with a source pre-image carries an arena→source run map, content-relative (keyed from the first content byte). Resolve it exactly like the multi-segment segment list below: a run whose `sourceOffset < 0` is a synthetic gap (the interned `\n` line-join) and yields `nil`; arena content with no map (`arenaRuns` empty) has no source image and also yields `nil`. cmark maps a `\|`-unescaped table cell's bytes back to source by a constant shift (it does NOT re-widen for the removed backslash), which the degenerate single-run case reproduces exactly.
            let k = offset - base
            let i = Self.firstIndex(endingAfter: k, in: arenaRunEnds)
            if i < arenaRuns.count {
                let run = arenaRuns[i]
                let v = i == 0 ? 0 : arenaRunEnds[i - 1]
                return run.sourceOffset < 0 ? nil : (Int(run.sourceOffset) + (k - v), Int(run.physicalOffset) + (k - v))
            }
            precondition(arenaRuns.count == 0, "an inline node's source range lies inside its content's arena run map")
            return nil
        }
        let i = segmentIndex(covering: offset)
        precondition(i < segments.count, "an inline node's source range lies inside its multi-segment content")
        let seg = segments[i]
        // Map through `sourceOffset` (re-indents a continuation line to its block-content column); the byte-read `offset` is the physical image. An arena segment's bytes all stand for its one source byte, if it has one.
        if !seg.inSource {
            return seg.sourceOffset < 0 ? nil : (Int(seg.sourceOffset), Int(seg.sourceOffset))
        }
        let local = offset - segmentStart(i)
        return (Int(seg.sourceOffset) + local, Int(seg.offset) + local)
    }

    /// Build a `Chunk` for a sub-range of this content. Single-segment: a direct sub-chunk. Multi-segment: valid only when the range lies within one segment (the common case - most inline nodes don't straddle a line join); callers whose range can straddle (a code span, or a text run that keeps a flag-ON synthetic filler segment) materialize via `InlineParser.materializedChunk` themselves.
    @inlinable
    func chunk(offset: Int, length: Int) -> Chunk {
        if !isMultiSegment {
            return Chunk(offset: offset, length: length, inSource: inSource)
        }
        let i = segmentIndex(covering: offset)
        precondition(i < segments.count, "a content chunk starts on a content byte")
        let seg = segments[i]
        let local = offset - segmentStart(i)
        return Chunk(offset: Int(seg.offset) + local, length: length, inSource: seg.inSource)
    }

    /// A contiguous buffer `Chunk` for forward byte scanning from virtual `offset`, bounded to one readable region and to `limit`.
    ///
    /// The `Scanners` (`matchLinkLabel`, `matchLinkDestination`, `matchLinkTitle`) read a `Chunk` with raw `readByte(at:in:)`, which indexes a single buffer (`sourceBytes` or the arena) by the chunk's own offsets. That is only valid when the virtual offset space coincides with a single buffer's offset space:
    ///
    /// - **Single-segment** content is one buffer region whose global offsets index that buffer directly, so this returns `[offset, limit)` in that buffer unchanged (`readByte` reads stay in bounds, identical to addressing the offsets directly).
    /// - **Multi-segment** content is addressed by *virtual* offsets that don't index any single buffer, so this returns the slice of the one **source** segment containing `offset`, bounded at that segment's end (and at `limit`). Scans therefore stay within a single contiguous source region and never index the wrong buffer or run past its end. A form that would continue past the segment boundary (onto the next line) simply isn't seen, which the caller treats as "no match".
    ///
    /// Returns `nil` when `offset >= limit` or `offset` lands on a synthetic (interned-newline) segment, where no link/reference form can begin. Convert a buffer offset `b` returned by a scanner back to a virtual offset with `offset + (b - chunk.offset)` (the identity for single-segment). Uses `seg.offset` (the byte-read offset) to match `subscript`/`chunk(offset:length:)`.
    @inlinable
    func contiguousChunk(fromVirtual offset: Int, limit: Int) -> Chunk? {
        if offset >= limit {
            return nil
        }
        if !isMultiSegment {
            return Chunk(offset: offset, length: limit - offset, inSource: inSource)
        }
        let i = segmentIndex(covering: offset)
        precondition(i < segments.count, "a scan limit lies within the content, so a scan start below it lies on a content byte")
        let seg = segments[i]
        if !seg.inSource {
            return nil
        }
        let local = offset - segmentStart(i)
        let regionEnd = min(limit, segmentEnds[i])
        return Chunk(offset: Int(seg.offset) + local, length: regionEnd - offset, inSource: true)
    }

    /// Global offset of the next inline-significant byte at or after `globalCursor`, or `endOffset` if none remain. Used to skip plain-text runs in the inline dispatch loop without stepping byte by byte: a `SIMD16` scan compares 16 bytes at once against the significant set, recovering the first matching lane; a sub-16 tail is scanned scalar.
    ///
    /// The significant set must be a superset of the bytes the dispatch switch acts on. `~` and the GFM bare-URL autolink triggers (`:` `w`/`W`) are included only when their option is on - when off, the switch's case for them is a no-op (the byte becomes plain text), so skipping over them is equivalent. `@` is NOT in the set: the GFM email autolink form is detected in a post-pass (`gfmEmailAutolinkPass`), not the forward inline dispatch, so an `@` is always plain text here. The contiguous cluster `[ \ ] ^ _ \``` (91...96) is one range compare.
    func nextSignificant(from globalCursor: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        if isMultiSegment {
            return multiNextSignificant(from: globalCursor, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        }
        let n = span.count
        let startIdx = globalCursor - base
        let found = span.withUnsafeBufferPointer { buf -> Int in
            precondition(buf.baseAddress != nil, "the inline dispatch scans only non-empty content")
            return Self.scanSignificant(buf.baseAddress!, from: startIdx, to: n, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        }
        return base + found
    }

    /// Multi-segment `nextSignificant`: walk the segment list, SIMD-scanning each source segment's contiguous source sub-range via `scanSignificant`. The interned `"\n"` joining two lines is itself in the significant set (the dispatch emits a soft/hard break for it), so a newline segment's first byte is reported immediately without scanning; a synthetic filler run (arena-backed, non-newline: split-tab spaces or orphaned-byte U+FFFDs) carries no significant byte and is skipped. Cost is `SIMD(content bytes)` plus a tiny per-segment fixed cost - the same order as the single-segment fast path, not an O(bytes × segments) scalar walk.
    private func multiNextSignificant(from globalCursor: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        let end = multiVirtualLength
        let count = segments.count
        let si = segmentIndex(covering: globalCursor)
        let segVStart = segmentStart(si)
        return span.withUnsafeBufferPointer { buf -> Int in
            precondition(buf.baseAddress != nil, "multi-segment content borrows a non-empty source")
            let p = buf.baseAddress!
            var i = si
            var vStart = segVStart
            var cursor = globalCursor
            while i < count {
                let seg = segments[i]
                let len = Int(seg.length)
                if seg.inSource {
                    let local = cursor - vStart                 // 0 once we advance past the entry segment
                    let absLo = Int(seg.offset) + local
                    let absHi = Int(seg.offset) + len
                    let foundAbs = Self.scanSignificant(p, from: absLo, to: absHi, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
                    if foundAbs < absHi {
                        return vStart + (foundAbs - Int(seg.offset))
                    }
                } else if arena.count == 0 || arena[Int(seg.offset)] == UInt8(ascii: "\n") {
                    // The interned "\n" join is always inline-significant (soft/hard break) - report its position directly.
                    return cursor
                }
                // else: a synthetic filler run (arena-backed, non-newline) carries no inline-significant byte; fall through to advance past it.
                vStart += len
                cursor = vStart
                i += 1
            }
            return end
        }
    }

    /// SIMD16 scan of `p[lo..<hi]` for the first inline-significant byte; returns that index, or `hi` if none. Shared by the single-segment and per-segment (multi) scan paths so both get the vector fast path. The significant set must stay a superset of the dispatch switch's cases - see `nextSignificant`.
    @inline(__always)
    private static func scanSignificant(_ p: UnsafePointer<UInt8>, from lo: Int, to hi: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        let clusterLo = SIMD16<UInt8>(repeating: 91)    // '['
        let clusterHi = SIMD16<UInt8>(repeating: 96)    // '`'
        let nl = SIMD16<UInt8>(repeating: UInt8(ascii: "\n"))
        let bang = SIMD16<UInt8>(repeating: UInt8(ascii: "!"))
        let amp = SIMD16<UInt8>(repeating: UInt8(ascii: "&"))
        let star = SIMD16<UInt8>(repeating: UInt8(ascii: "*"))
        let lt = SIMD16<UInt8>(repeating: UInt8(ascii: "<"))
        let tilde = SIMD16<UInt8>(repeating: UInt8(ascii: "~"))
        let colon = SIMD16<UInt8>(repeating: UInt8(ascii: ":"))
        let wCanon = SIMD16<UInt8>(repeating: UInt8(ascii: "w"))   // 'w'|0x20 == 'W'|0x20 == 'w'
        let lowerBit = SIMD16<UInt8>(repeating: 0x20)
        // Smart-punctuation triggers: straight quotes (`'` `"`), `-` (dashes), `.` (ellipsis).
        let squote = SIMD16<UInt8>(repeating: UInt8(ascii: "'"))
        let dquote = SIMD16<UInt8>(repeating: UInt8(ascii: "\""))
        let hyphen = SIMD16<UInt8>(repeating: UInt8(ascii: "-"))
        let period = SIMD16<UInt8>(repeating: UInt8(ascii: "."))
        let lanes = SIMD16<UInt8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
        let noMatch = SIMD16<UInt8>(repeating: 16)

        var i = lo
        while i + 16 <= hi {
            let v = UnsafeRawPointer(p + i).loadUnaligned(as: SIMD16<UInt8>.self)
            var m = ((v .>= clusterLo) .& (v .<= clusterHi))
                .| (v .== nl) .| (v .== bang) .| (v .== amp) .| (v .== star) .| (v .== lt)
            if strikethrough {
                m = m .| (v .== tilde)
            }
            if gfmAutolink {
                m = m .| (v .== colon) .| ((v | lowerBit) .== wCanon)
            }
            if smart {
                m = m .| (v .== squote) .| (v .== dquote) .| (v .== hyphen) .| (v .== period)
            }
            if any(m) {
                let lane = lanes.replacing(with: noMatch, where: .!m).min()
                return i + Int(lane)
            }
            i += 16
        }
        while i < hi {
            let b = p[i]
            let significant = (b >= 91 && b <= 96)
                || b == UInt8(ascii: "\n") || b == UInt8(ascii: "!") || b == UInt8(ascii: "&")
                || b == UInt8(ascii: "*") || b == UInt8(ascii: "<")
                || (strikethrough && b == UInt8(ascii: "~"))
                || (gfmAutolink && (b == UInt8(ascii: ":") || (b | 0x20) == UInt8(ascii: "w")))
                || (smart && (b == UInt8(ascii: "'") || b == UInt8(ascii: "\"") || b == UInt8(ascii: "-") || b == UInt8(ascii: ".")))
            if significant {
                return i
            }
            i += 1
        }
        return hi
    }
}

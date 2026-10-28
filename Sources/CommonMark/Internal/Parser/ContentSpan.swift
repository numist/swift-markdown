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
/// - **Multi-segment.** The content is an ordered list of `Segment`s - source-line ranges (zero-copy into `sourceBytes`) joined by the shared interned `"\n"` - addressed by flat *virtual* offsets (`0..<virtualLength`). Used for multi-line paragraph/heading bodies whose lines aren't source-contiguous (block-quote/list continuation, CRLF) so no source bytes are copied. Its only non-source segment is the interned `"\n"` join, read as `\n` without touching the arena.
///
/// `sourceOffset(ofVirtual:)` maps a (virtual) offset back to its original-source byte offset, which is how inline nodes get stamped with source ranges.
internal struct ContentSpan: ~Escapable {
    /// Single-segment: the content bytes (0-based via `base`). Multi-segment: `sourceBytes` (the whole source), indexed directly by a segment's absolute source offset.
    @usableFromInline let span: Span<UInt8>

    /// Single-segment: the global offset of `span[0]` (subtracted from a global offset to index `span`). Multi-segment: unused (0).
    @usableFromInline let base: Int

    /// Single-segment: which buffer `span` is (`true` = source, `false` = arena scratch). Multi-segment: unused.
    @usableFromInline let inSource: Bool

    /// The content's pieces, held in stable storage for the inline loop's duration (the live `storage.segments` pool grows during parsing), empty for source-backed content.
    ///
    /// Multi-segment: the content's segment list, addressed by virtual offset. Single-segment arena content that images a source range: its content-relative arena→source run map, keyed from the first content byte, each source piece imaging a contiguous source range and each non-source piece a synthetic line join whose `offset` is unused. `sourceOffset` resolves through it to recover per-line source columns for reconstructed content - a flattened non-contiguous setext heading, or (as a single constant-shift piece) a `\|`-unescaped table cell. Empty for arena content parsed with positions off and for the email-autolink scan's scratch copy; neither is resolved through it.
    @usableFromInline let pieces: Span<Segment>

    /// `pieceEnds[i]` is the content-relative offset just past piece `i` (the running total of piece lengths), held in stable storage alongside `pieces`. Non-decreasing, so the piece covering an offset is found by binary search (`pieceIndex(covering:)`) rather than a walk from the first piece - content has a piece per line, and the inline pass resolves multi-segment offsets once per byte and run-map offsets once per inline node.
    @usableFromInline let pieceEnds: Span<Int>

    /// `true` when `pieces` is the content's segment list, addressed by virtual offset.
    @usableFromInline let isMultiSegment: Bool

    /// Multi-segment only: total virtual byte length across `pieces`.
    @usableFromInline let multiVirtualLength: Int

    /// Single-segment initializer (zero-copy source slice or arena scratch) with no arena→source mapping. For source-backed content `sourceOffset` is the identity map; for arena content it returns `nil`.
    @_lifetime(copy span)
    @inlinable
    init(span: Span<UInt8>, base: Int, inSource: Bool) {
        self.span = span
        self.base = base
        self.inSource = inSource
        self.pieces = Span<Segment>()
        self.pieceEnds = Span<Int>()
        self.isMultiSegment = false
        self.multiVirtualLength = 0
    }

    /// Single-segment arena initializer carrying an arena→source run map and its running end offsets (see `pieces` and `pieceEnds`) so inline stamping recovers source positions for reconstructed (flattened) content.
    @_lifetime(copy span, copy runs, copy runEnds)
    @inlinable
    init(span: Span<UInt8>, base: Int, runs: Span<Segment>, runEnds: Span<Int>) {
        self.span = span
        self.base = base
        self.inSource = false
        self.pieces = runs
        self.pieceEnds = runEnds
        self.isMultiSegment = false
        self.multiVirtualLength = 0
    }

    /// Multi-segment initializer: `source` is the borrowed source bytes; `segments` is the content's segment list and `segmentEnds` its running virtual end offsets (both held in stable storage); `virtualLength` is their total length. The content's only non-source segment is the interned `"\n"` join, synthesized directly on read.
    @_lifetime(copy source, copy segments, copy segmentEnds)
    @inlinable
    init(source: Span<UInt8>, segments: Span<Segment>, segmentEnds: Span<Int>, virtualLength: Int) {
        self.span = source
        self.base = 0
        self.inSource = false
        self.pieces = segments
        self.pieceEnds = segmentEnds
        self.isMultiSegment = true
        self.multiVirtualLength = virtualLength
    }

    /// Global/virtual offset of the first content byte.
    @inlinable
    var startOffset: Int { isMultiSegment ? 0 : base }

    /// Global/virtual offset just past the last content byte.
    @inlinable
    var endOffset: Int { isMultiSegment ? multiVirtualLength : base + span.count }

    @inlinable
    var isEmpty: Bool { isMultiSegment ? multiVirtualLength == 0 : span.count == 0 }

    /// The index of the first entry of the non-decreasing running-end table `ends` that is past `offset` - the index of the piece covering `offset` (never a zero-length one for an in-range offset) - or `ends.count` when `offset` is at or past the last end.
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

    /// The index of the piece covering content-relative `offset`, or `pieces.count` when `offset` is at or past the end.
    @inlinable
    func pieceIndex(covering offset: Int) -> Int {
        Self.firstIndex(endingAfter: offset, in: pieceEnds)
    }

    /// The content-relative offset of piece `i`'s first byte.
    @inlinable
    func pieceStart(_ i: Int) -> Int {
        i == 0 ? 0 : pieceEnds[i - 1]
    }

    /// Read the byte at `offset` (global for single-segment, virtual for multi-segment).
    @inlinable
    subscript(_ offset: Int) -> UInt8 {
        if isMultiSegment {
            return multiByte(at: offset)
        }
        return span[offset - base]
    }

    /// Multi-segment byte resolution: find the segment covering virtual `offset` and read it. Source segments read `span` (== `sourceBytes`); a non-source segment is the interned `"\n"` join, read as `\n` directly.
    private func multiByte(at offset: Int) -> UInt8 {
        let i = pieceIndex(covering: offset)
        assert(i < pieces.count, "inline content is read only at offsets inside the content")
        let seg = pieces[i]
        let local = offset - pieceStart(i)
        if seg.inSource {
            return span[Int(seg.offset) + local]
        }
        // The only non-source segment is the shared interned `"\n"`.
        return UInt8(ascii: "\n")
    }

    /// The original-source byte offset for the content byte at `offset`. Single-segment source content maps identity (the offset already IS a source offset); single-segment arena content resolves through its arena→source run map; multi-segment resolves through the segment list.
    ///
    /// `offset` always images a source byte: callers resolve only an inline node's first and last bytes, and no inline node starts or ends on a byte without a source image, such as a line join (a soft or hard line break has no source range, and the text before it ends at the join).
    @inlinable
    func sourceOffset(ofVirtual offset: Int) -> Int {
        if !isMultiSegment && inSource {
            return offset
        }
        // Single-segment arena content: inline nodes are stamped only with positions on, and then it carries a content-relative run map that tiles it. A `\|`-unescaped table cell is one run, so its bytes map to source by a constant shift that does not account for removed backslashes.
        let k = offset - base
        let i = pieceIndex(covering: k)
        precondition(i < pieces.count, "an inline node's source range lies inside its content's pieces")
        let piece = pieces[i]
        precondition(piece.inSource, "an inline node's first and last bytes image source bytes")
        return Int(piece.offset) + (k - pieceStart(i))
    }

    /// Build a `Chunk` for a sub-range of this content. Single-segment: a direct sub-chunk. Multi-segment: valid only when the range lies within one segment (the common case - most inline nodes don't straddle a line join); callers whose range can straddle (a code span) materialize via `InlineParser.materializedChunk` themselves.
    @inlinable
    func chunk(offset: Int, length: Int) -> Chunk {
        if !isMultiSegment {
            return Chunk(offset: offset, length: length, inSource: inSource)
        }
        let i = pieceIndex(covering: offset)
        precondition(i < pieces.count, "a content chunk starts on a content byte")
        let seg = pieces[i]
        let local = offset - pieceStart(i)
        return Chunk(offset: Int(seg.offset) + local, length: length, inSource: seg.inSource)
    }

    /// A contiguous buffer `Chunk` for forward byte scanning from virtual `offset`, bounded to one readable region and to `limit`.
    ///
    /// A reader of a `Chunk` (`EntityParser.matchEntity`, `normalizeLabel(chunk:)`) indexes a single buffer (`sourceBytes` or the arena) by the chunk's own offsets. That is only valid when the virtual offset space coincides with a single buffer's offset space:
    ///
    /// - **Single-segment** content is one buffer region whose global offsets index that buffer directly, so this returns `[offset, limit)` in that buffer unchanged (`readByte` reads stay in bounds, identical to addressing the offsets directly).
    /// - **Multi-segment** content is addressed by *virtual* offsets that don't index any single buffer, so this returns the slice of the one **source** segment containing `offset`, bounded at that segment's end (and at `limit`). Scans therefore stay within a single contiguous source region and never index the wrong buffer or run past its end. A form that would continue past the segment boundary (onto the next line) simply isn't seen, which the caller treats as "no match".
    ///
    /// Returns `nil` when `offset >= limit` or `offset` lands on a synthetic segment (a line join), where no link/reference form can begin. Convert a buffer offset `b` returned by a scanner back to a virtual offset with `offset + (b - chunk.offset)` (the identity for single-segment). Uses `seg.offset` (the byte-read offset) to match `subscript`/`chunk(offset:length:)`.
    @inlinable
    func contiguousChunk(fromVirtual offset: Int, limit: Int) -> Chunk? {
        if offset >= limit {
            return nil
        }
        if !isMultiSegment {
            return Chunk(offset: offset, length: limit - offset, inSource: inSource)
        }
        let i = pieceIndex(covering: offset)
        precondition(i < pieces.count, "a scan limit lies within the content, so a scan start below it lies on a content byte")
        let seg = pieces[i]
        if !seg.inSource {
            return nil
        }
        let local = offset - pieceStart(i)
        let regionEnd = min(limit, pieceEnds[i])
        return Chunk(offset: Int(seg.offset) + local, length: regionEnd - offset, inSource: true)
    }

    /// Global offset of the next inline-significant byte at or after `globalCursor`, or `endOffset` if none remain. Lets the inline dispatch loop skip plain-text runs without stepping byte by byte: a `SIMD16` scan compares 16 bytes at once against the significant set, recovering the first matching lane; a sub-16 tail is scanned scalar.
    ///
    /// The significant set must be a superset of the bytes the dispatch switch acts on. `~` and the GFM bare-URL autolink triggers (`:` `w`/`W`) are included only when their option is on - when off, the switch's case for them is a no-op (the byte becomes plain text), so skipping over them is equivalent. `@` is NOT in the set: the GFM email autolink form is detected in a post-pass (`gfmEmailAutolinkPass`), not the forward inline dispatch, so an `@` is always plain text here. The contiguous cluster `[ \ ] ^ _ \``` (91...96) is one range compare.
    func nextSignificant(from globalCursor: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        if isMultiSegment {
            return multiNextSignificant(from: globalCursor, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        }
        let n = span.count
        let startIdx = globalCursor - base
        let found = Self.scanSignificant(span, from: startIdx, to: n, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        return base + found
    }

    /// Multi-segment `nextSignificant`: walk the segment list, SIMD-scanning each source segment's contiguous source sub-range via `scanSignificant`. The interned `"\n"` joining two lines is itself in the significant set (the dispatch emits a soft or hard line break for it), so a join's position is reported immediately without scanning. Cost is `SIMD(content bytes)` plus a tiny per-segment fixed cost - the same order as the single-segment fast path, not an O(bytes × segments) scalar walk.
    private func multiNextSignificant(from globalCursor: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        let end = multiVirtualLength
        let count = pieces.count
        let si = pieceIndex(covering: globalCursor)
        let segVStart = pieceStart(si)
        var i = si
        var vStart = segVStart
        var cursor = globalCursor
        while i < count {
            let seg = pieces[i]
            let len = Int(seg.length)
            if seg.inSource {
                let local = cursor - vStart                 // 0 past the entry segment
                let absLo = Int(seg.offset) + local
                let absHi = Int(seg.offset) + len
                let foundAbs = Self.scanSignificant(span, from: absLo, to: absHi, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
                if foundAbs < absHi {
                    return vStart + (foundAbs - Int(seg.offset))
                }
            } else {
                // The interned "\n" join is always inline-significant (a soft or hard line break) - report its position directly.
                return cursor
            }
            vStart += len
            cursor = vStart
            i += 1
        }
        return end
    }

    /// SIMD16 scan of `span[lo..<hi]` for the first inline-significant byte; returns that index, or `hi` if none. Shared by the single-segment and per-segment (multi) scan paths so both get the vector fast path. The significant set must stay a superset of the dispatch switch's cases - see `nextSignificant`.
    @inline(__always)
    private static func scanSignificant(_ span: Span<UInt8>, from lo: Int, to hi: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
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
        let bytes = span.bytes

        var i = lo
        while i + 16 <= hi {
            let v = bytes.loadSIMD16(fromByteOffset: i)
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
            let b = span[i]
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

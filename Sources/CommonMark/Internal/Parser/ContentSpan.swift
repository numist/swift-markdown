/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A block's inline content.
///
/// Single-segment content is one region of the source or of a copy of the arena, so the arena may grow during inline parsing; it is addressed by that buffer's offsets. Multi-segment content is a list of source line ranges joined by the interned `"\n"`, addressed by virtual offsets from 0, so lines that aren't contiguous in the source are read without copying.
internal struct ContentSpan: ~Escapable {
    /// Single-segment: the content bytes. Multi-segment: the whole source.
    @usableFromInline let span: Span<UInt8>

    /// Single-segment: the offset of `span[0]`. Multi-segment: 0.
    @usableFromInline let base: Int

    /// Single-segment: whether `span` is in the source.
    @usableFromInline let inSource: Bool

    /// Multi-segment: the segment list. Single-segment arena content: its run map to the source, whose non-source pieces are line joins. Empty where no offset is resolved through it.
    ///
    /// Held apart from `storage.segments`, which grows during inline parsing.
    @usableFromInline let pieces: Span<Segment>

    /// `pieceEnds[i]` is the content-relative offset just past piece `i`. An offset's piece is found by binary search, because content has a piece per line and the inline pass resolves multi-segment offsets once per byte.
    @usableFromInline let pieceEnds: Span<Int>

    @usableFromInline let isMultiSegment: Bool

    @usableFromInline let multiVirtualLength: Int

    /// Single-segment content without a run map, so only source content resolves source offsets.
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

    /// Single-segment arena content with its run map (see `pieces`).
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

    /// Multi-segment content: `segmentEnds` holds the running ends of `segments`, and `virtualLength` their total.
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

    @inlinable
    var startOffset: Int { isMultiSegment ? 0 : base }

    @inlinable
    var endOffset: Int { isMultiSegment ? multiVirtualLength : base + span.count }

    @inlinable
    var isEmpty: Bool { isMultiSegment ? multiVirtualLength == 0 : span.count == 0 }

    /// The index of the first entry of non-decreasing `ends` past `offset`: the piece covering `offset`, never a zero-length one, or `ends.count` past the end.
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

    @inlinable
    subscript(_ offset: Int) -> UInt8 {
        if isMultiSegment {
            return multiByte(at: offset)
        }
        return span[offset - base]
    }

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

    /// The source offset of the content byte at `offset`, which must image a source byte. Callers resolve only an inline node's first and last bytes, which are never a line join.
    @inlinable
    func sourceOffset(ofVirtual offset: Int) -> Int {
        if !isMultiSegment && inSource {
            return offset
        }
        // Arena content reaches here only with positions on, when it carries a run map that tiles it. A `\|`-unescaped table cell is one run, a constant shift that ignores removed backslashes.
        let k = offset - base
        let i = pieceIndex(covering: k)
        precondition(i < pieces.count, "an inline node's source range lies inside its content's pieces")
        let piece = pieces[i]
        precondition(piece.inSource, "an inline node's first and last bytes image source bytes")
        return Int(piece.offset) + (k - pieceStart(i))
    }

    /// A `Chunk` for a sub-range, which in multi-segment content must lie within one segment. A caller whose range can cross a line join (a code span) uses `InlineParser.materializedChunk`.
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

    /// A `Chunk` for scanning forward from `offset`, bounded by `limit` and, in multi-segment content, by the end of the segment containing `offset`.
    ///
    /// Chunk readers such as `EntityParser.matchEntity` index one buffer by the chunk's offsets, which virtual offsets don't, so a form that continues onto the next line isn't seen. Returns `nil` when `offset >= limit` or `offset` is a line join, where no form begins. A scanner's buffer offset `b` maps back to `offset + (b - chunk.offset)`.
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

    /// The offset of the next byte at or after `globalCursor` that the inline dispatch acts on, or `endOffset`, so the dispatch skips plain text 16 bytes at a time.
    ///
    /// The set must include every byte the dispatch switch acts on. An option's bytes are included only with that option, since the switch otherwise treats them as text. `@` is never included, because email autolinks are found in a later pass (`gfmEmailAutolinkPass`).
    func nextSignificant(from globalCursor: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        if isMultiSegment {
            return multiNextSignificant(from: globalCursor, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        }
        let n = span.count
        let startIdx = globalCursor - base
        let found = Self.scanSignificant(span, from: startIdx, to: n, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        return base + found
    }

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
                // A line join is always significant: it becomes a soft or hard line break.
                return cursor
            }
            vStart += len
            cursor = vStart
            i += 1
        }
        return end
    }

    /// The index of the first significant byte in `span[lo..<hi]`, or `hi`; see `nextSignificant`.
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

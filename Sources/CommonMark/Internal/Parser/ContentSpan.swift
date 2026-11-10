/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A block's inline content.
///
/// Single-segment content is one region of the source or of the arena, addressed by that buffer's offsets; arena content is read from a copy, since the arena grows during inline parsing. Multi-segment content is a list of source line ranges joined by the interned `"\n"`, addressed by virtual offsets from 0, so lines that aren't contiguous in the source are read without copying.
internal struct ContentSpan: ~Escapable {
    /// Single-segment: the content bytes. Multi-segment: the whole source.
    let span: Span<UInt8>

    /// Single-segment: the offset of `span[0]`. Multi-segment: 0.
    let base: Int

    /// Single-segment: whether `span` is in the source.
    let inSource: Bool

    /// Multi-segment: the segment list. Single-segment arena content: its run map to the source, whose non-source pieces are line joins. Empty where no offset is resolved through it.
    ///
    /// Held apart from `storage.segments`, which grows during inline parsing.
    let pieces: Span<Segment>

    /// `pieceEnds[i]` is the content-relative offset just past piece `i`.
    let pieceEnds: Span<Int>

    /// The parse's shared lookup state (see `PieceHint`), `nil` only where `pieces` is empty.
    ///
    /// Content has a piece per line and is scanned a byte at a time, so most lookups land in the piece the last lookup found or one a few pieces away, where `pieceIndex(covering:)` searches first. Multi-segment content also keeps there the source piece it last read (`sourcePiece(covering:)`).
    let pieceHint: PieceHint?

    let isMultiSegment: Bool

    let multiVirtualLength: Int

    /// Multi-segment: which of the multi-segment contents made with `pieceHint` this is, counting from 1.
    let multiIdentity: Int

    /// Single-segment content without a run map, so only source content resolves source offsets.
    @_lifetime(copy span)
    init(span: Span<UInt8>, base: Int, inSource: Bool) {
        self.span = span
        self.base = base
        self.inSource = inSource
        self.pieces = Span<Segment>()
        self.pieceEnds = Span<Int>()
        self.pieceHint = nil
        self.isMultiSegment = false
        self.multiVirtualLength = 0
        self.multiIdentity = 0
    }

    /// Single-segment arena content with its run map (see `pieces`).
    @_lifetime(copy span, copy runs, copy runEnds)
    init(span: Span<UInt8>, base: Int, runs: Span<Segment>, runEnds: Span<Int>, hint: PieceHint) {
        self.span = span
        self.base = base
        self.inSource = false
        self.pieces = runs
        self.pieceEnds = runEnds
        self.pieceHint = hint
        self.isMultiSegment = false
        self.multiVirtualLength = 0
        self.multiIdentity = 0
    }

    /// Multi-segment content: `segmentEnds` holds the running ends of `segments`, and `virtualLength` their total.
    @_lifetime(copy source, copy segments, copy segmentEnds)
    init(source: Span<UInt8>, segments: Span<Segment>, segmentEnds: Span<Int>, virtualLength: Int, hint: PieceHint) {
        self.span = source
        self.base = 0
        self.inSource = false
        self.pieces = segments
        self.pieceEnds = segmentEnds
        self.pieceHint = hint
        self.isMultiSegment = true
        self.multiVirtualLength = virtualLength
        hint.multiSegmentContentsMade &+= 1
        self.multiIdentity = hint.multiSegmentContentsMade
    }

    var startOffset: Int { isMultiSegment ? 0 : base }
    var endOffset: Int { isMultiSegment ? multiVirtualLength : base + span.count }
    var isEmpty: Bool { isMultiSegment ? multiVirtualLength == 0 : span.count == 0 }

    /// The index of the first entry of `pieceEnds[lo..<hi]` past `offset`, or `hi` if none is: the piece covering `offset`, never a zero-length one, when it lies in that range.
    private func firstIndex(endingAfter offset: Int, from lo: Int, to hi: Int) -> Int {
        var lo = lo
        var hi = hi
        while lo < hi {
            let mid = (lo + hi) / 2
            if pieceEnds[mid] > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
    }

    /// The index of the piece covering content-relative `offset`, or `pieces.count` when `offset` is at or past the end.
    ///
    /// The search widens from `pieceHint`, doubling its step, so a piece `d` pieces away costs O(log d) and a scan costs O(1) per byte.
    private func pieceIndex(covering offset: Int) -> Int {
        var lo = 0
        var hi = pieceEnds.count
        if let hint = pieceHint?.index, pieceEnds.indices.contains(hint) {
            var step = 1
            if pieceEnds[hint] <= offset {
                lo = hint + 1
                while lo + step <= hi {
                    if pieceEnds[lo + step - 1] > offset {
                        hi = lo + step - 1
                        break
                    }
                    lo += step
                    step *= 2
                }
            } else if offset >= pieceStart(hint) {
                return hint
            } else {
                hi = hint
                while hi - step >= 0 {
                    if pieceEnds[hi - step] <= offset {
                        lo = hi - step + 1
                        break
                    }
                    hi -= step
                    step *= 2
                }
            }
        }
        let found = firstIndex(endingAfter: offset, from: lo, to: hi)
        if found < pieceEnds.count {
            pieceHint?.index = found
        }
        return found
    }

    /// The content-relative offset of piece `i`'s first byte.
    private func pieceStart(_ i: Int) -> Int {
        i == 0 ? 0 : pieceEnds[i - 1]
    }

    subscript(_ offset: Int) -> UInt8 {
        if isMultiSegment {
            return multiByte(at: offset)
        }
        return span[offset - base]
    }

    /// Calls `body` with a reader of the content byte at any offset from `offset` on.
    ///
    /// In multi-segment content the reader takes the bytes of the piece covering `offset` straight from the source, without the checks the subscript makes on every byte to find its source piece, and later pieces through the subscript.
    @inline(__always)
    func withForwardReader<Result>(from offset: Int, _ body: ((Int) -> UInt8) -> Result) -> Result {
        guard isMultiSegment else {
            return body { span[$0 - base] }
        }
        // At the end or at a line join no source piece covers `offset`, so every byte is read through the subscript.
        guard offset < multiVirtualLength, let piece = sourcePiece(covering: offset) else {
            return body { multiByte(at: $0) }
        }
        return body { $0 < piece.range.upperBound ? span[$0 + piece.shift] : multiByte(at: $0) }
    }

    private func multiByte(at offset: Int) -> UInt8 {
        guard let piece = sourcePiece(covering: offset) else {
            // The only non-source segment is the shared interned `"\n"`.
            return UInt8(ascii: "\n")
        }
        return span[offset + piece.shift]
    }

    /// The virtual range of the multi-segment content's source piece covering `offset`, and the distance from its offsets to their source offsets, or `nil` where a line join covers `offset`.
    ///
    /// The piece is cached in `pieceHint` with the identity of the content it belongs to, since a scan reads a piece's
    /// bytes one after another; a piece another content cached is never used.
    private func sourcePiece(covering offset: Int) -> (range: Range<Int>, shift: Int)? {
        if let hint = pieceHint, hint.sourcePieceOwner == multiIdentity, hint.sourcePiece.contains(offset) {
            return (hint.sourcePiece, hint.sourcePieceShift)
        }
        let i = pieceIndex(covering: offset)
        precondition(i < pieces.count, "content is read only at offsets inside it")
        let seg = pieces[i]
        if !seg.inSource {
            return nil
        }
        let range = pieceStart(i)..<pieceEnds[i]
        let shift = seg.offset - range.lowerBound
        if let hint = pieceHint {
            hint.sourcePieceOwner = multiIdentity
            hint.sourcePiece = range
            hint.sourcePieceShift = shift
        }
        return (range, shift)
    }

    /// The source offset of the content byte at `offset`, which must image a source byte. Callers resolve only an inline node's first and last bytes, which are never a line join.
    func sourceOffset(ofVirtual offset: Int) -> Int {
        if !isMultiSegment && inSource {
            return offset
        }
        // Multi-segment content resolves through its segments, and arena content, which reaches here only with `.sourcePosition`, through the run map that tiles it.
        let k = offset - base
        let i = pieceIndex(covering: k)
        precondition(i < pieces.count, "an inline node's source range lies inside its content's pieces")
        let piece = pieces[i]
        precondition(piece.inSource, "an inline node's first and last bytes image source bytes")
        return piece.offset + (k - pieceStart(i))
    }

    /// A `Chunk` for a sub-range, which in multi-segment content must lie within one segment. A caller whose range can cross a line join copies it into the arena instead, as `materializedChunk` does.
    func chunk(offset: Int, length: Int) -> Chunk {
        if !isMultiSegment {
            return Chunk(offset: offset, length: length, inSource: inSource)
        }
        let i = pieceIndex(covering: offset)
        precondition(i < pieces.count, "a content chunk starts on a content byte")
        let seg = pieces[i]
        let local = offset - pieceStart(i)
        return Chunk(offset: seg.offset + local, length: length, inSource: seg.inSource)
    }

    /// A `Chunk` for scanning forward from `offset`, bounded by `limit` and, in multi-segment content, by the end of the segment containing `offset`.
    ///
    /// Chunk readers such as `EntityParser.matchEntity` index a single buffer, which virtual offsets don't address, so in multi-segment content they see only the rest of `offset`'s line. Returns `nil` when `offset >= limit` or `offset` is a line join. A scanner's buffer offset `b` maps back to `offset + (b - chunk.offset)`.
    func contiguousChunk(fromVirtual offset: Int, limit: Int) -> Chunk? {
        if offset >= limit {
            return nil
        }
        if !isMultiSegment {
            return Chunk(offset: offset, length: limit - offset, inSource: inSource)
        }
        guard let piece = sourcePiece(covering: offset) else {
            return nil
        }
        return Chunk(offset: offset + piece.shift, length: min(limit, piece.range.upperBound) - offset, inSource: true)
    }

    /// The offset of the next byte at or after `globalCursor` that the inline dispatch acts on, or `endOffset`, so the dispatch skips plain text 16 bytes at a time.
    ///
    /// The set must include every byte the dispatch switch acts on. `~`, `:`, `w` and the smart punctuation bytes are included only with their options, since the switch otherwise treats them as text; `^`, which only `.attributes` acts on, is always included as part of the `[`–`` ` `` range. `@` is never included, because email autolinks are found in a later pass (`gfmEmailAutolinkPass`).
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
            let len = seg.length
            if seg.inSource {
                let local = cursor - vStart
                let absLo = seg.offset + local
                let absHi = seg.offset + len
                let foundAbs = Self.scanSignificant(span, from: absLo, to: absHi, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
                if foundAbs < absHi {
                    return vStart + (foundAbs - seg.offset)
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
        let clusterLo = SIMD16<UInt8>(repeating: UInt8(ascii: "["))
        let clusterHi = SIMD16<UInt8>(repeating: UInt8(ascii: "`"))
        let nl = SIMD16<UInt8>(repeating: UInt8(ascii: "\n"))
        let bang = SIMD16<UInt8>(repeating: UInt8(ascii: "!"))
        let amp = SIMD16<UInt8>(repeating: UInt8(ascii: "&"))
        let star = SIMD16<UInt8>(repeating: UInt8(ascii: "*"))
        let lt = SIMD16<UInt8>(repeating: UInt8(ascii: "<"))
        let tilde = SIMD16<UInt8>(repeating: UInt8(ascii: "~"))
        let colon = SIMD16<UInt8>(repeating: UInt8(ascii: ":"))
        let w = SIMD16<UInt8>(repeating: UInt8(ascii: "w"))
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
                m = m .| (v .== colon) .| (v .== w)
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
            let significant = (b >= UInt8(ascii: "[") && b <= UInt8(ascii: "`"))
                || b == UInt8(ascii: "\n") || b == UInt8(ascii: "!") || b == UInt8(ascii: "&")
                || b == UInt8(ascii: "*") || b == UInt8(ascii: "<")
                || (strikethrough && b == UInt8(ascii: "~"))
                || (gfmAutolink && (b == UInt8(ascii: ":") || b == UInt8(ascii: "w")))
                || (smart && (b == UInt8(ascii: "'") || b == UInt8(ascii: "\"") || b == UInt8(ascii: "-") || b == UInt8(ascii: ".")))
            if significant {
                return i
            }
            i += 1
        }
        return hi
    }
}

/// The piece a `ContentSpan` offset lookup last found, and the source piece a multi-segment content last read, held by reference so that lookups through a borrowed `ContentSpan` update them.
///
/// One is shared by every `ContentSpan` of a parse. An index left by another content is still a valid hint, since a lookup bounds-checks it and only starts its search there.
internal final class PieceHint {
    var index = 0

    /// How many multi-segment contents have been made with this hint.
    var multiSegmentContentsMade = 0

    /// The `multiIdentity` of the multi-segment content whose source piece `sourcePiece` is.
    var sourcePieceOwner = 0

    /// That content's source piece that a lookup last found: its virtual range, and the distance from its offsets to their source offsets.
    var sourcePiece: Range<Int> = 0..<0
    var sourcePieceShift = 0
}

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A read-only view over a single block's inline content.
///
/// Two modes, distinguished by `isMultiSegment`:
///
/// - **Single-segment (the overwhelmingly common case).** The content is one contiguous buffer region - a zero-copy slice of the source (`inSource == true`) or of a scratch copy (`inSource == false`). Bytes are addressed by *global* offsets (`startOffset..<endOffset`) via a branchless `span[offset - base]`, identical in cost to a plain single-buffer read. For source-backed content the global offset IS the original-source byte offset.
///
/// - **Multi-segment.** The content is an ordered list of `Segment`s - source-line ranges (zero-copy into `sourceBytes`) joined by the shared interned `"\n"` - addressed by flat *virtual* offsets (`0..<virtualLength`). Used for multi-line paragraph/heading bodies whose lines aren't source-contiguous (block-quote/list continuation, CRLF) so no source bytes are copied. The input never contains arena-only bytes (decoded entities / synthesized runs are produced *during* inline parsing, not present in the raw block content), so reads come only from `sourceBytes` plus the literal `\n` - `storage.strings` is never held across the inline loop's appends.
///
/// `sourceOffset(ofVirtual:)` maps a (virtual) offset back to its original-source byte offset, which is how inline nodes get stamped with source ranges.
internal struct ContentSpan: ~Escapable {
    /// Single-segment: the content bytes (0-based via `base`). Multi-segment: `sourceBytes` (the whole source), indexed directly by a segment's absolute source offset.
    let span: Span<UInt8>

    /// Single-segment: the global offset of `span[0]` (subtracted from a global offset to index `span`). Multi-segment: unused (0).
    let base: Int

    /// Single-segment: which buffer `span` is (`true` = source, `false` = scratch). Multi-segment: unused.
    let inSource: Bool

    let pieces: Span<Segment>

    let pieceEnds: Span<Int>

    let pieceHint: PieceHint?

    let isMultiSegment: Bool

    let multiVirtualLength: Int

    let multiIdentity: Int

    /// Single-segment initializer (zero-copy source slice or scratch).
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

    // `virtualLength` isn't derived from `segmentEnds`: content trimmed of trailing whitespace ends before its last segment does.
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

    /// Global/virtual offset of the first content byte.
    var startOffset: Int { isMultiSegment ? 0 : base }
    /// Global/virtual offset just past the last content byte.
    var endOffset: Int { isMultiSegment ? multiVirtualLength : base + span.count }
    var isEmpty: Bool { isMultiSegment ? multiVirtualLength == 0 : span.count == 0 }

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

    private func pieceStart(_ i: Int) -> Int {
        i == 0 ? 0 : pieceEnds[i - 1]
    }

    /// Read the byte at `offset` (global for single-segment, virtual for multi-segment).
    subscript(_ offset: Int) -> UInt8 {
        if isMultiSegment {
            return multiByte(at: offset)
        }
        return span[offset - base]
    }

    // Reading the starting piece straight from the source spares each of its bytes the subscript's piece lookup.
    @inline(__always)
    func withForwardReader<Result>(from offset: Int, _ body: ((Int) -> UInt8) -> Result) -> Result {
        guard isMultiSegment else {
            return body { span[$0 - base] }
        }
        guard offset < multiVirtualLength, let piece = sourcePiece(covering: offset) else {
            return body { multiByte(at: $0) }
        }
        return body { $0 < piece.range.upperBound ? span[$0 + piece.shift] : multiByte(at: $0) }
    }

    /// Multi-segment byte resolution: find the segment covering virtual `offset` and read it. Source segments read `span` (== `sourceBytes`); the interned newline segment yields `\n`.
    private func multiByte(at offset: Int) -> UInt8 {
        guard let piece = sourcePiece(covering: offset) else {
            // The only non-source segment in inline content is the shared interned `"\n"`.
            return UInt8(ascii: "\n")
        }
        return span[offset + piece.shift]
    }

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

    func sourceOffset(ofVirtual offset: Int) -> Int {
        if !isMultiSegment && inSource {
            return offset
        }
        let k = offset - base
        let i = pieceIndex(covering: k)
        precondition(i < pieces.count, "an inline node's source range lies inside its content's pieces")
        let piece = pieces[i]
        precondition(piece.inSource, "an inline node's first and last bytes image source bytes")
        return piece.offset + (k - pieceStart(i))
    }

    func sourceOffset(ofMultiSegmentVirtual offset: Int) -> Int? {
        sourcePiece(covering: offset).map { offset + $0.shift }
    }

    /// Build a `Chunk` for a sub-range of this content. Single-segment: a direct sub-chunk. Multi-segment: valid only when the range lies within one segment (the common case - inline nodes don't straddle a line join); callers that can straddle (code spans) handle materialization themselves.
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

    /// Global offset of the next inline-significant byte at or after `globalCursor`, or `endOffset` if none remain. Used to skip plain-text runs in the inline dispatch loop without stepping byte by byte: a `SIMD16` scan compares 16 bytes at once against the significant set, recovering the first matching lane; a sub-16 tail is scanned scalar.
    ///
    /// The significant set must be a superset of the bytes the dispatch switch acts on. `~` and the GFM autolink triggers (`:` `w`) are included only when their option is on - when off, the switch's case for them is a no-op (the byte becomes plain text), so skipping over them is equivalent. The contiguous cluster `[ \ ] ^ _ \``` (91...96) is one range compare.
    func nextSignificant(from globalCursor: Int, strikethrough: Bool, gfmAutolink: Bool, smart: Bool) -> Int {
        if isMultiSegment {
            return multiNextSignificant(from: globalCursor, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        }
        let n = span.count
        let startIdx = globalCursor - base
        let found = Self.scanSignificant(span, from: startIdx, to: n, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
        return base + found
    }

    /// Multi-segment `nextSignificant`: walk the segment list, SIMD-scanning each source segment's contiguous source sub-range via `scanSignificant`. The interned `"\n"` joining two lines is itself in the significant set (the dispatch emits a soft/hard break for it), so a newline segment's first byte is reported immediately without scanning. Cost is `SIMD(content bytes)` plus a tiny per-segment fixed cost - the same order as the single-segment fast path, not an O(bytes × segments) scalar walk.
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
                let local = cursor - vStart                 // 0 once we advance past the entry segment
                let absLo = seg.offset + local
                let absHi = seg.offset + len
                let foundAbs = Self.scanSignificant(span, from: absLo, to: absHi, strikethrough: strikethrough, gfmAutolink: gfmAutolink, smart: smart)
                if foundAbs < absHi {
                    return vStart + (foundAbs - seg.offset)
                }
            } else {
                // The only non-source segment in inline content is the shared interned "\n", which is always inline-significant - report its position directly.
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
        // Smart-punctuation triggers: straight quotes (`'` `"`), `-` (dashes), `.` (ellipsis).
        let squote = SIMD16<UInt8>(repeating: UInt8(ascii: "'"))
        let dquote = SIMD16<UInt8>(repeating: UInt8(ascii: "\""))
        let hyphen = SIMD16<UInt8>(repeating: UInt8(ascii: "-"))
        let period = SIMD16<UInt8>(repeating: UInt8(ascii: "."))
        return span.firstIndex(
            from: lo,
            to: hi,
            matching: { v in
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
                return m
            },
            or: { b in
                (b >= UInt8(ascii: "[") && b <= UInt8(ascii: "`"))
                    || b == UInt8(ascii: "\n") || b == UInt8(ascii: "!") || b == UInt8(ascii: "&")
                    || b == UInt8(ascii: "*") || b == UInt8(ascii: "<")
                    || (strikethrough && b == UInt8(ascii: "~"))
                    || (gfmAutolink && (b == UInt8(ascii: ":") || b == UInt8(ascii: "w")))
                    || (smart && (b == UInt8(ascii: "'") || b == UInt8(ascii: "\"") || b == UInt8(ascii: "-") || b == UInt8(ascii: ".")))
            }
        )
    }
}

// A class, so that a lookup through a borrowed `ContentSpan` can record the piece it found: scans read content a
// byte at a time, so the next lookup usually lands in or near that piece. One hint is shared by every `ContentSpan`
// of a parse that has pieces, so a lookup bounds-checks `index` and uses `sourcePiece` only for the content that
// owns it.
internal final class PieceHint {
    var index = 0

    var multiSegmentContentsMade = 0

    var sourcePieceOwner = 0

    var sourcePiece: Range<Int> = 0..<0
    var sourcePieceShift = 0
}

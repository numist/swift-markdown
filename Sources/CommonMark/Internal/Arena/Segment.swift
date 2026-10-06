/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// One piece of a node's content: a byte range that lives in either the borrowed source `Span` (`inSource == true`) or `DocumentStorage`'s additions arena (`inSource == false`).
///
/// A `Segment` is the N-way generalization of `Chunk`'s `inSource` two-buffer scheme. Nodes reference an ordered run of these (see `ContentRef`) so that content spanning multiple source ranges (a multi-line paragraph) or mixing source with synthetic bytes (a joined newline, a decoded entity) can be represented without copying the source bytes into an intermediate buffer.
///
/// `Int32` fields keep the per-document segment pool compact; markdown sources are far below the 2 GiB limit this implies.
internal struct Segment: Equatable {
    internal var offset: Int32
    internal var length: Int32
    internal var inSource: Bool

    /// The original-source byte offset this segment's content maps to for source-position stamping, when it differs from `offset` (the byte-read offset).
    ///
    /// Equal to `offset` in the overwhelmingly common case - the content is stamped where its bytes physically sit. It diverges only for a re-indented paragraph continuation line: cmark strips a continuation line's leading whitespace but reports the surviving content at the block's content column (`block_offset`; column 1 at the top level), not at its true first-non-space column. Such a segment therefore reads its bytes from `offset` (past the stripped whitespace) while mapping its source positions from `sourceOffset` (the block-content column).
    ///
    /// For an `inSource == false` segment, `sourceOffset` is the one source byte that every byte of the segment stands for - a split tab's leftover columns, emitted as spaces, stand for the tab byte - or `-1` when the segment has no source image (the interned `\n` join and other arena-only content, which no inline node starts or ends on).
    internal var sourceOffset: Int32

    /// `sourceOffset` defaults to `offset` for a source segment (the content is stamped where it sits) and to `-1` (no source image) for an arena segment; pass it explicitly only to re-indent a continuation line's source mapping, or to name the source byte an arena segment stands for.
    internal init(offset: Int32, length: Int32, inSource: Bool, sourceOffset: Int32? = nil) {
        self.offset = offset
        self.length = length
        self.inSource = inSource
        self.sourceOffset = sourceOffset ?? (inSource ? offset : -1)
    }

    internal init(_ chunk: Chunk) {
        self.init(offset: Int32(chunk.offset), length: Int32(chunk.length), inSource: chunk.inSource)
    }

    /// Reconstruct a `Chunk` view of this segment. Used by internal parser code that still works in the single-buffer `Chunk` vocabulary.
    internal var chunk: Chunk {
        Chunk(offset: Int(offset), length: Int(length), inSource: inSource)
    }
}

/// One run of a single-segment arena buffer's arena→source map: `length` consecutive content bytes that image a contiguous source range beginning at `sourceOffset`.
///
/// A `sourceOffset < 0` marks a synthetic gap - the interned `"\n"` line-join between reconstructed lines, or an arena-only line with no source pre-image - which stays position-less (`nil`), matching cmark's position-less soft breaks. Runs are contiguous and ordered (they tile the content from its first byte), so the map walks exactly like the multi-segment `Segment` list, minus the byte reads (bytes come from the flat arena span). This lets inline stamping recover per-line source columns for content that was flattened into one arena chunk (a non-contiguous setext heading), and in the single-run case it expresses the constant shift of a `\|`-unescaped table cell.
///
/// `physicalOffset` is the `Segment.offset` analog: the run's byte-read source offset, which always sits on the run's own physical source line even when `sourceOffset` re-indents a continuation line to its block-content column and thereby overshoots that line. It equals `sourceOffset` for content that images its source where its bytes sit (a top-level line, or the constant-shift table cell). A source-mapped table row uses it to place the row's content end on its true physical line (see `TableParser.rowProjection`); `< 0` marks a synthetic gap with no physical image.
internal struct ArenaRun: Equatable {
    internal var length: Int32
    internal var sourceOffset: Int32
    internal var physicalOffset: Int32

    /// `physicalOffset` defaults to `sourceOffset` (the run images its source where its bytes sit); pass it explicitly only when a re-indented continuation line's byte-read offset differs from its re-indented source mapping.
    internal init(length: Int32, sourceOffset: Int32, physicalOffset: Int32? = nil) {
        self.length = length
        self.sourceOffset = sourceOffset
        self.physicalOffset = physicalOffset ?? sourceOffset
    }
}

/// A single arena chunk's source image: its content-relative run map (`ArenaRun`), keyed from `base`, the chunk's first arena byte.
internal struct ContentImage {
    internal let base: Int
    internal let runs: [ArenaRun]
    /// `runEnds[i]` is the content-relative offset just past run `i`.
    private let runEnds: [Int]

    internal init(base: Int, runs: [ArenaRun]) {
        self.base = base
        self.runs = runs
        var end = 0
        runEnds = runs.map { run in
            end += Int(run.length)
            return end
        }
    }

    /// The source offsets imaged by arena byte `offset` - the offset it is stamped at, and the offset it was read from (see `ArenaRun`) - or `nil` for a byte outside the chunk. Callers resolve only bytes that aren't line joins, the chunk's one kind of synthetic gap.
    internal func sourceOffsets(ofArenaByte offset: Int) -> (source: Int, physical: Int)? {
        let k = offset - base
        guard k >= 0, let total = runEnds.last, k < total else {
            return nil
        }
        var lo = 0
        var hi = runEnds.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if runEnds[mid] > k {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        let run = runs[lo]
        let local = k - (lo == 0 ? 0 : runEnds[lo - 1])
        precondition(run.sourceOffset >= 0, "a resolved byte is not a line join")
        return (Int(run.sourceOffset) + local, Int(run.physicalOffset) + local)
    }
}

/// A node's content, expressed as a contiguous slice `[first, first + count)` of `DocumentStorage.segments`.
///
/// The overwhelmingly common case is `count == 1` (a single source range - most text runs, URLs, and labels), which costs the same as a single inline `Chunk`. `totalLength` caches the total byte length across the segments so length queries don't have to walk the pool.
internal struct ContentRef: Equatable {
    internal var first: Int32
    internal var count: Int32
    internal var totalLength: Int32

    internal init(first: Int32, count: Int32, totalLength: Int32) {
        self.first = first
        self.count = count
        self.totalLength = totalLength
    }

    internal static let empty = ContentRef(first: 0, count: 0, totalLength: 0)
}

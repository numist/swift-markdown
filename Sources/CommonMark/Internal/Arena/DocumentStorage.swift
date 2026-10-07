/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// Owning storage for parser-produced AST data.
///
/// Holds only the values produced by parsing - nodes, materialized strings, table alignments, and parse options. The source bytes are *borrowed* by the owning `MarkdownDocument` (as a `Span`), not owned here.
///
/// `~Copyable` so the storage can never be silently duplicated. `MarkdownDocument` owns one of these and threads it `inout` through the parser.
internal struct DocumentStorage: ~Copyable {
    typealias Index = Int
    
    /// All nodes in DFS order of creation.
    ///
    /// The root document is always index 0. The initial capacity holds the nodes of a typical inline-only document.
    internal var nodes: UniqueArray<NodeRecord> = UniqueArray(minimumCapacity: 16)

    /// Bump-allocated arena for synthetic/materialized bytes (entity-decoded text, normalized link references, autolink scheme prefixes) that don't exist as contiguous regions of the source.
    ///
    /// Source-derived content is never copied here - it is referenced in place via `Segment`s with `inSource == true`.
    internal var strings: UniqueArray<UInt8>

    /// Append-only pool of content segments. A node's content (`NodeData`) is a `ContentRef` slice `[first, first + count)` of this pool. Single-segment refs (the common case) append exactly one entry here.
    internal var segments: UniqueArray<Segment> = UniqueArray(minimumCapacity: 16)

    /// Per-table-node alignment storage.
    ///
    /// `NodeData.table` stores an offset into this array plus a column count.
    internal var tableAlignments: UniqueArray<MarkdownNode.TableAlignment> = UniqueArray()

    /// Link reference definitions discovered while finalizing paragraphs.
    ///
    /// Keys are labels normalized by `normalizeLabel` (spec "Links"). The first definition of a label wins.
    internal var referenceMap: [String: ReferenceDefinition] = [:]

    /// Inline attribute definitions of the form `^[label]: attrs`.
    ///
    /// Keyed by the same normalized label form as `referenceMap` but stored separately so `[foo]` (link) and `^[foo]` (attribute) lookups don't collide. First definition wins.
    internal var attributeReferenceMap: [String: Chunk] = [:]

    /// GFM footnote definitions, registered as each definition block closes.
    ///
    /// Keyed by normalized label, value is the index of the `.footnoteDefinition` node in `nodes`. The first definition to close wins, so a definition nested in a same-label one wins over its encloser.
    internal var footnoteMap: [String: Index] = [:]

    /// Every `.footnoteDefinition` node, in opening (document) order.
    ///
    /// Used by the footnote post-processing pass to enumerate all definitions so unreferenced ones can be dropped.
    internal var footnoteDefinitionOrder: [Index] = []

    /// Number of lines in the document.
    internal var lineCount = 0

    /// Half-open source byte range `[start, end)` for one node, in original-source coordinates.
    ///
    /// `start == -1` marks an unstamped node (a node never assigned a position). Positions are always the byte projection of `start` / `end` via `StorageView.position(ofByte:)`.
    internal struct SourceByteRange: Equatable {
        internal var start: Int
        internal var end: Int

        internal static let unset = SourceByteRange(start: -1, end: -1)
    }

    /// Byte offset (into the original source, post-BOM) at which each line begins.
    ///
    /// Index `i` holds the start of line `i+1`. Built during `parse()` ONLY when `.sourcePosition` is set; empty otherwise. Maps a node's byte range to 1-based (line, column) positions.
    internal var lineStarts: UniqueArray<Int> = UniqueArray()

    /// Per-node source byte range, parallel to `nodes` (index `i` is node `i`'s range).
    ///
    /// Populated ONLY when `.sourcePosition` is set. `appendNode` pushes a default `.unset` entry in lockstep so the array stays index-aligned with `nodes`. `.start == -1` means the node has no recorded start.
    internal var sourceRanges: UniqueArray<SourceByteRange> = UniqueArray()

    /// The options that control parsing of this document.
    internal let options: MarkdownDocument.ParseOptions

    /// `true` when source-position tracking is on.
    internal var positionsEnabled: Bool {
        options.contains(.sourcePosition)
    }

    internal init(options: MarkdownDocument.ParseOptions) {
        self.options = options
        // Reserve byte 0 of the additions arena as a shared `"\n"`. Multi-line code/HTML block bodies reference this single byte via `newlineSegment` for their line endings instead of copying a `\n` into the arena per join.
        strings = UniqueArray(repeating: UInt8(ascii: "\n"), count: 1)
    }

    /// The arena offset of the shared interned `"\n"` byte reserved in `init`.
    internal static let newlineOffset: Int32 = 0

    /// A `Segment` addressing the shared interned `"\n"`.
    ///
    /// Used as the line ending when a node's content is accumulated as a segment list (e.g. multi-line code blocks), so joins cost a pooled `Segment` entry rather than a copied byte.
    internal var newlineSegment: Segment {
        Segment(offset: Self.newlineOffset, length: 1, inSource: false)
    }

    /// Append a new node and return its index. The caller is responsible for wiring sibling/child links.
    internal mutating func appendNode(_ record: NodeRecord) -> Index {
        let idx = Index(nodes.count)
        nodes.append(record)
        if positionsEnabled {
            // Keep `sourceRanges` index-aligned with `nodes`; stamped later via `setSourceStart/End`.
            sourceRanges.append(.unset)
        }
        return idx
    }

    /// Record the source byte offset (into the original source) where `node`'s content begins. No-op when positions are off or `offset` is `nil` (e.g. a tab-expanded line that doesn't map to source).
    internal mutating func setSourceStart(_ node: Index, _ offset: Int?) {
        if let offset, positionsEnabled {
            sourceRanges[node].start = offset
        }
    }

    /// Record the half-open source byte offset just past `node`'s last content byte.
    internal mutating func setSourceEnd(_ node: Index, _ offset: Int?) {
        if let offset, positionsEnabled {
            sourceRanges[node].end = offset
        }
    }

    /// Intern a single `Chunk` as a one-segment `ContentRef`. The bridge used by parser code that produces content in the single-buffer `Chunk` vocabulary. Appends one entry to `segments`.
    internal mutating func intern(_ chunk: Chunk) -> ContentRef {
        if chunk.isEmpty {
            return .empty
        }
        let first = Int32(segments.count)
        segments.append(Segment(chunk))
        return ContentRef(first: first, count: 1, totalLength: Int32(chunk.length))
    }

    /// Append a run of segments as a single `ContentRef`. Used for multi-segment content (multi-line joins, prefixed autolinks).
    internal mutating func intern(_ pieces: consuming UniqueArray<Segment>) -> ContentRef {
        let first = Int32(segments.count)
        var total: Int32 = 0
        for i in 0..<pieces.count {
            let piece = pieces[i]
            segments.append(piece)
            total += piece.length
        }
        let count = Int32(segments.count) - first
        if count == 0 {
            return .empty
        }
        return ContentRef(first: first, count: count, totalLength: total)
    }

    /// Read a single-segment `ContentRef` back as a `Chunk`.
    ///
    /// Used for footnote labels, which are never empty and always one segment.
    internal func chunk(of ref: ContentRef) -> Chunk {
        precondition(ref.count == 1, "a footnote label is a single non-empty segment")
        return segments[Int(ref.first)].chunk
    }

    /// Trim a leaf node's single-segment literal in place.
    ///
    /// Drop `trimStart` bytes off the front and set the byte length to `newLength`. Allocation-free - each leaf owns a unique pooled segment, so mutating it doesn't alias another node. Used by emphasis/strong resolution, which trims delimiter runs off the surrounding text nodes.
    internal mutating func trimLiteral(of node: Index, trimStart: Int, newLength: Int) {
        guard case .literal(let ref) = nodes[node].data, ref.count == 1 else {
            preconditionFailure("a delimiter run's text node is a single-segment literal")
        }
        let i = Int(ref.first)
        segments[i].offset += Int32(trimStart)
        segments[i].length = Int32(newLength)
        nodes[node].data = .literal(ContentRef(first: ref.first, count: 1, totalLength: Int32(newLength)))
    }

    /// Read access to a node by index. Internal helpers only - public access goes through `MarkdownNode`.
    internal subscript(index: Index) -> NodeRecord {
        get { nodes[index] }
        set { nodes[index] = newValue }
    }

    /// Append `childIndex` as a child of `parentIndex`. Maintains the `firstChild` / `lastChild` / `next` / `previous` invariants.
    internal mutating func appendChild(_ childIndex: Index, to parentIndex: Index) {
        nodes[childIndex].parent = parentIndex
        if let existingLast = nodes[parentIndex].lastChild {
            nodes[existingLast].next = childIndex
            nodes[childIndex].previous = existingLast
        } else {
            nodes[parentIndex].firstChild = childIndex
        }
        nodes[parentIndex].lastChild = childIndex
    }

    /// Detach `childIndex` from its current parent's child list.
    ///
    /// The node itself remains in `nodes` (so other indices stay stable) but is orphaned - DFS traversals will not visit it. Used when ref-def parsing consumes an entire paragraph's content.
    ///
    /// The detached node's `parent` pointer is preserved so that paragraph finalization can bubble `state.current` back up via `parent` after dropping the empty paragraph.
    internal mutating func unlinkChild(_ childIndex: Index) {
        precondition(nodes[childIndex].parent != nil, "only the document node has no parent, and it is never unlinked")
        let parent = nodes[childIndex].parent!
        let prev = nodes[childIndex].previous
        let next = nodes[childIndex].next
        assert(prev != nil || nodes[parent].firstChild == childIndex, "unlinkChild on a node that isn't linked into its parent's child list")
        assert(next != nil || nodes[parent].lastChild == childIndex, "unlinkChild on a node that isn't linked into its parent's child list")
        if let prev {
            nodes[prev].next = next
        } else {
            nodes[parent].firstChild = next
        }
        if let next {
            nodes[next].previous = prev
        } else {
            nodes[parent].lastChild = prev
        }
        nodes[childIndex].previous = nil
        nodes[childIndex].next = nil
    }

    /// Insert `newChild` immediately after `referenceChild` in the parent's child list.
    ///
    /// The new child must not already be linked anywhere. Used during emphasis resolution to splice a fresh `.emphasis` / `.strong` node between the opener's and closer's surrounding text.
    internal mutating func insertChildAfter(_ newChild: Index, after referenceChild: Index) {
        let parent = nodes[referenceChild].parent
        let next = nodes[referenceChild].next
        nodes[newChild].parent = parent
        nodes[newChild].previous = referenceChild
        nodes[newChild].next = next
        nodes[referenceChild].next = newChild
        if let next {
            nodes[next].previous = newChild
        } else if let parent {
            nodes[parent].lastChild = newChild
        }
    }

    /// Insert `newChild` immediately before `referenceChild` in the parent's child list.
    ///
    /// Mirror of `insertChildAfter`. Used by link/image resolution to splice the new `.link` / `.image` node into the position of the opening `[` text node before reparenting the inner siblings.
    internal mutating func insertChildBefore(_ newChild: Index, before referenceChild: Index) {
        let parent = nodes[referenceChild].parent
        let prev = nodes[referenceChild].previous
        nodes[newChild].parent = parent
        nodes[newChild].previous = prev
        nodes[newChild].next = referenceChild
        nodes[referenceChild].previous = newChild
        if let prev {
            nodes[prev].next = newChild
        } else if let parent {
            nodes[parent].firstChild = newChild
        }
    }
}

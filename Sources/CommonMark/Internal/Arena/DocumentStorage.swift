/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// The parse result: nodes, materialized bytes, and options. `MarkdownDocument` owns it and borrows the source.
internal struct DocumentStorage: ~Copyable {
    typealias Index = Int
    
    /// All nodes in creation order; the document is index 0. The initial capacity fits a typical inline-only document.
    internal var nodes: UniqueArray<NodeRecord> = UniqueArray(minimumCapacity: 16)

    /// Arena for bytes that aren't a contiguous range of the source, such as decoded entities and autolink scheme prefixes. Source bytes are never copied here.
    internal var strings: UniqueArray<UInt8>

    /// Append-only pool that `ContentRef`s slice.
    internal var segments: UniqueArray<Segment> = UniqueArray(minimumCapacity: 16)

    /// Link reference definitions by normalized label. The first definition of a label wins.
    internal var referenceMap = [String: ReferenceDefinition]()

    /// `^[label]: attrs` definitions, keyed like `referenceMap` but kept apart so `[foo]` and `^[foo]` don't collide. The first definition wins.
    internal var attributeReferenceMap = [String: Chunk]()

    /// Footnote definition nodes by normalized label. The first definition to close wins, so a definition nested in a same-label one wins over its encloser.
    internal var footnoteMap = [String: Index]()

    /// Every `.footnoteDefinition` node in document order, so unreferenced ones can be dropped.
    internal var footnoteDefinitionOrder: [Index] = []

    internal var lineCount = 0

    /// A node's source bytes `[start, end)`; `start == -1` marks a node without a position.
    internal struct SourceByteRange: Equatable {
        internal var start: Int
        internal var end: Int

        internal static let unset = SourceByteRange(start: -1, end: -1)
    }

    /// Byte offset (into the original source, post-BOM) at which each line begins.
    ///
    /// Index `i` holds the start of line `i+1`. Built during `parse()` ONLY when `.sourcePosition` is set; empty otherwise. Used to convert a node's byte range into 1-based (line, column) positions.
    internal var lineStarts: UniqueArray<Int> = UniqueArray()

    /// Each node's source range, index-aligned with `nodes`. Built only with `.sourcePosition`.
    internal var sourceRanges: UniqueArray<SourceByteRange> = UniqueArray()

    /// Parse options used to create this document.
    internal let options: MarkdownDocument.ParseOptions

    /// `true` when source-position tracking is on.
    internal var positionsEnabled: Bool {
        options.contains(.sourcePosition)
    }

    internal init(options: MarkdownDocument.ParseOptions) {
        self.options = options
        // Reserve byte 0 of the additions arena as a shared `"\n"`. Multi-line code/HTML block bodies (and any future multi-segment join) reference this single byte via `newlineSegment` for their line separators instead of copying a `\n` into the arena per join.
        strings = UniqueArray(repeating: UInt8(ascii: "\n"), count: 1)
    }

    /// The arena offset of the shared interned `"\n"` byte reserved in `init`.
    internal static let newlineOffset: Int32 = 0

    /// A `Segment` addressing the shared interned `"\n"`.
    ///
    /// Used as the line separator when a node's content is accumulated as a segment list (e.g. multi-line code blocks), so joins cost a pooled `Segment` entry rather than a copied byte.
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

    /// No-op when positions are off or `offset` is `nil`, as is `setSourceEnd`.
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

    internal mutating func intern(_ chunk: Chunk) -> ContentRef {
        if chunk.isEmpty {
            return .empty
        }
        let first = Int32(segments.count)
        segments.append(Segment(chunk))
        return ContentRef(first: first, count: 1, totalLength: Int32(chunk.length))
    }

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

    /// The chunk of a footnote label, which is always one non-empty segment.
    internal func chunk(of ref: ContentRef) -> Chunk {
        precondition(ref.count == 1, "a footnote label is a single non-empty segment")
        return segments[Int(ref.first)].chunk
    }

    /// Trims a single-segment literal in place, dropping `trimStart` bytes and keeping `newLength`. Each leaf owns its segment, so no other node changes.
    internal mutating func trimLiteral(of node: Index, trimStart: Int, newLength: Int) {
        guard case .literal(let ref) = nodes[node].data, ref.count == 1 else {
            preconditionFailure("a delimiter run's text node is a single-segment literal")
        }
        let i = Int(ref.first)
        segments[i].offset += Int32(trimStart)
        segments[i].length = Int32(newLength)
        nodes[node].data = .literal(ContentRef(first: ref.first, count: 1, totalLength: Int32(newLength)))
    }

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

    /// Steps a pre-order walk of `root`'s subtree out of a finished `parent`: `child` becomes its next sibling and `parent` its parent. Returns `false`, changing nothing, at `root`.
    ///
    /// Tree passes walk links instead of recursing, so any nesting depth runs in constant stack.
    internal func ascend(from parent: inout Index, resumingAt child: inout Index?, within root: Index) -> Bool {
        if parent == root {
            return false
        }
        precondition(nodes[parent].parent != nil, "only the document node has no parent, and a walk never climbs above its root")
        child = nodes[parent].next
        parent = nodes[parent].parent!
        return true
    }

    /// Removes `childIndex` from its parent's children. It keeps its `parent`, so paragraph finalization can climb out of a paragraph it removes.
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

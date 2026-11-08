/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// Reused buffers for the inline pass, owned by its caller so their borrow is independent of the `storage` mutations `parseInline` performs.
///
/// `bytes` holds a copy of arena content. `pieces` holds a copy of a segment list or run map, since `storage.segments` grows during inline parsing, and `pieceEnds` their running ends.
private struct InlineScratch: ~Copyable {
    var bytes = UniqueArray<UInt8>()
    var pieces = UniqueArray<Segment>()
    var pieceEnds = UniqueArray<Int>()

    mutating func removeAllPieces() {
        pieces.removeSubrange(0..<pieces.count)
        pieceEnds.removeSubrange(0..<pieceEnds.count)
    }

    mutating func append(piece: Segment) {
        let start = pieceEnds.count == 0 ? 0 : pieceEnds[pieceEnds.count - 1]
        pieces.append(piece)
        pieceEnds.append(start + Int(piece.length))
    }
}

/// Block-level Markdown parser.
internal struct BlockParser : ~Copyable, ~Escapable {
    internal var storage: DocumentStorage
    
    internal let sourceBytes: Span<UInt8>
    
    /// The document node, index 0.
    let documentIndex: DocumentStorage.Index

    /// The block-start depth on one line at which a list marker stops opening a list, bounding the cost of deep nesting.
    ///
    /// Each block start on a line is one level, counting from 1. A list marker at this depth or deeper is paragraph
    /// text, so 99 `>` followed by `- ` give no list. Nesting across lines and block quotes are uncapped.
    static let maxListNesting = 100

    /// The deepest open block.
    var current: DocumentStorage.Index

    /// Changes whenever a block opens or closes or a paragraph is removed, so whenever the open blocks, or whether an
    /// open list item holds a block, can change.
    var openBlocksVersion = 0

    /// Where a line's walk of the open blocks ends when nothing is left of the line at a given open block, kept while
    /// `version` is `openBlocksVersion` (see `walkPastEmptyRemainder`).
    struct EmptyRemainderWalk {
        var version: Int
        var deepestMatched: DocumentStorage.Index
        var allMatched: Bool
    }
    var emptyRemainderWalks: [DocumentStorage.Index: EmptyRemainderWalk] = [:]

    /// How many list items and footnote definitions a line's walk continues with nothing left of the line before
    /// `walkPastEmptyRemainder` takes over.
    static let emptyRemainderWalkLimit = 8

    /// The open leaf's accumulated content and its node.
    ///
    /// At most one leaf accumulates content at a time, and containers hold no text, so it is threaded by move through the block-parse call chain: functions that begin or extend a leaf consume it and return the updated one.
    struct PendingLeaf : ~Copyable {
        var node: DocumentStorage.Index
        var content: PendingContent
    }

    /// A source range (`.lazy`) or a segment list (`.segments`).
    ///
    /// `joinPending` defers a line's `\n`, so that if the next line is contiguous in the source the run stays one zero-copy source range. Only `appendNewline` sets it and the next `addLine` clears it, so it is never set between lines.
    enum PendingContent : ~Copyable {
        case lazy(range: Range<Int>, joinPending: Bool = false)
        /// Each line is a source segment, or an arena copy for a code or HTML block line that splits a tab, and each line join is `newlineSegment`. Used for code and HTML block bodies and for paragraph lines not contiguous in the source.
        case segments(UniqueArray<Segment>)
    }

    /// Result of `materializePendingContent`. `map` is the content's run map when it is flattened from a segment list.
    struct LeafMaterialization {
        var chunk: Chunk
        var map: [ArenaRun] = []
    }

    /// Result of the code/HTML block continuation handlers: whether the block stays open plus the updated leaf.
    struct LeafContinuation : ~Copyable {
        var stillOpen: Bool
        var pending: PendingLeaf?
    }

    let positionsEnabled: Bool

    /// The current line's source range. `lastLineSourceEnd` is the previous line's content end, where a block that a later line closes ends.
    var currentLineSourceRange: Range<Int> = 0..<0
    var lastLineSourceEnd: Int = 0

    /// The source offset before which the line reader has read every byte.
    var sourceReadEnd: Int = 0

    /// No source byte from here up to `sourceReadEnd` is a NUL, so content there needs no NUL replacement.
    var nulFreeSourceStart: Int = 0

    /// The source offset just past the open indented code block's last line that is not blank, where the block ends:
    /// blank lines following an indented code block are not part of it (Indented code blocks).
    var indentedCodeContentEnd: Int = 0

    /// Whether the current line is a lazy continuation line: an open container's prefix failed to match, so the walk stopped short of the open leaf.
    var currentLineIsLazyContinuation: Bool = false

    /// Inline parsing deferred until all blocks close, so a reference resolves against a definition later in the document.
    var pendingInlines: [(DocumentStorage.Index, ContentRef)] = []

    /// Run maps for content that reaches the inline pass as one arena chunk (flattened, NUL-replaced or pipe-unescaped), keyed by node, so its inlines get source positions.
    var arenaSourceMaps: [DocumentStorage.Index: [ArenaRun]] = [:]

    /// What the table check needs to know about the open paragraph, recorded when the paragraph is first
    /// continued. Only populated with `.tables`.
    struct OpenParagraphTableState {
        let node: DocumentStorage.Index

        /// Whether a line and the next form a table's header and delimiter rows, the delimiter row indented fewer
        /// than four columns and not lazy. The paragraph is then a table, which a lazy continuation line can't
        /// continue, so `processLine` breaks a later line that fails a container's prefix out of the table and that
        /// container.
        var tablePending = false
    }

    /// `nil` until the open paragraph's second line arrives.
    var openParagraphTableState: OpenParagraphTableState?

    /// List items whose last block is a removed paragraph that held only definitions or a task list item marker,
    /// mapped to whether a blank line follows it. An entry is dropped when the item gains another block.
    ///
    /// The removed paragraph still counts as a block for list looseness (Lists) and `endsWithBlankLine`, and keeps
    /// the item from counting as empty, so a blank line after it does not close the item (List items).
    var itemsEndingInRemovedParagraph: [DocumentStorage.Index: Bool] = [:]

    /// List items that directly contain a removed paragraph that held only definitions or a task list item marker,
    /// and another block with a blank line between them, which makes their list loose (Lists). Consulted by `detectLooseList`.
    var itemsWithBlankLineAroundRemovedParagraph: Set<DocumentStorage.Index> = []

    /// Reset per `parseInline` pass.
    var htmlCloserMisses = HTMLCloserMisses()

    /// Reset per `parseInline` pass.
    var backtickRunsSeen = BacktickRunsSeen()

    /// The character references decoded in this `parseInline` pass with positions on, in arena order: each one's
    /// decoded arena range and its source range.
    var characterReferenceSources: [(arena: Range<Int>, source: Range<Int>)] = []

    /// The delimiter stack (see `DelimiterRecord`), topped by `lastDelim` and reused across passes.
    var delimiters = UniqueArray<DelimiterRecord>()
    var lastDelim: Int? = nil

    /// The bracket stack (see `BracketRecord`), topped by `lastBracket` and reused across passes.
    var brackets = UniqueArray<BracketRecord>()
    var lastBracket: Int? = nil

    // MARK: - Init
    
    @_lifetime(copy source)
    init(storage: consuming DocumentStorage, source: Span<UInt8>) {
        self.storage = storage
        self.sourceBytes = source
        self.positionsEnabled = self.storage.options.contains(.sourcePosition)

        // Size the append-only arenas from the input so they don't grow geometrically during the parse. The ratios are
        // generous: over-reserving costs one larger allocation, while under-reserving brings back the realloc chain.
        let byteCount = self.sourceBytes.count
        self.storage.nodes.reserveCapacity(byteCount / 16)
        self.storage.segments.reserveCapacity(byteCount / 16)
        self.storage.strings.reserveCapacity(byteCount / 4)

        documentIndex = self.storage.appendNode(NodeRecord(kind: .document))
        current = documentIndex
    }
    
    // MARK: - Parse
    
    consuming func parse() -> DocumentStorage {
        if storage.options.contains(.inlineOnly) {
            parseInlineOnly()
            return storage
        }

        var reader = LineReader(source: sourceBytes)

        do {
            var pending: PendingLeaf? = nil
            while reader.next() != nil {
                let lineRangeInOriginalSource = reader.lineRange
                if positionsEnabled {
                    storage.lineStarts.append(lineRangeInOriginalSource.lowerBound)
                    lastLineSourceEnd = currentLineSourceRange.upperBound
                }
                currentLineSourceRange = lineRangeInOriginalSource
                noteLineRead(reader)
                pending = processLine(lineRange: lineRangeInOriginalSource, pending: pending)
            }

            // At the end of input, close every open block.
            while current != documentIndex {
                pending = finalize(node: current, pending: pending, endsOnCurrentLine: true)
            }
            
            // The document node is never finalized, so it is stamped here, from the first line's start, after any BOM. An empty document has no source range.
            if positionsEnabled, reader.lineNumber > 0 {
                storage.setSourceStart(documentIndex, storage.lineStarts[0])
                storage.setSourceEnd(documentIndex, currentLineSourceRange.upperBound)
            }
        }

        // With all blocks closed every definition is known, so references resolve forward.
        let pending = pendingInlines
        
        var scratch = InlineScratch()

        for (node, ref) in pending {
            precondition(ref.totalLength > 0, "only non-empty content is queued for inline parsing")
            if ref.count == 1 {
                parseInline(chunk: storage.segments[Int(ref.first)].chunk, scratch: &scratch, into: node)
            } else {
                // Multi-segment content is parsed from the source through a copy of its segment list.
                scratch.removeAllPieces()
                for i in 0..<Int(ref.count) {
                    scratch.append(piece: storage.segments[Int(ref.first) + i])
                }
                parseInline(
                    content: ContentSpan(source: sourceBytes, segments: scratch.pieces.span, segmentEnds: scratch.pieceEnds.span, virtualLength: Int(ref.totalLength)),
                    into: node
                )
            }

            let image: ContentImage?
            if positionsEnabled, ref.count == 1, case let chunk = storage.segments[Int(ref.first)].chunk, !chunk.inSource, let map = arenaSourceMaps[node] {
                image = ContentImage(base: chunk.offset, runs: map)
            } else {
                image = nil
            }
            finishInlines(node, image: image)
        }

        processFootnotes()

        storage.lineCount = reader.lineNumber
        return storage
    }

    /// Numbers the footnote references, drops the definitions no reference resolves to, and moves the referenced
    /// ones, out of any container, to the end of the document in index order.
    private mutating func processFootnotes() {
        guard storage.options.contains(.footnotes) else { return }
        // A footnote reference exists only where its label resolves to a footnote definition.
        guard !storage.footnoteDefinitionOrder.isEmpty else { return }
        let referencedDefs = numberLiveFootnoteReferences()
        let keep = Set(referencedDefs)
        // Drop unreferenced definitions, including duplicate-label ones, whose references resolved to the label's
        // first definition.
        for defIdx in storage.footnoteDefinitionOrder where !keep.contains(defIdx) {
            storage.unlinkChild(defIdx)
        }
        for defIdx in referencedDefs {
            storage.unlinkChild(defIdx)
            storage.appendChild(defIdx, to: documentIndex)
        }
    }

    /// Numbers each footnote reference by the order of its definition's first reference in document order, and
    /// returns the referenced definitions in that order.
    ///
    /// The walk covers footnote definitions too, whose content can reference other footnotes, and keeps an explicit
    /// stack so deep nesting can't overflow the call stack.
    private mutating func numberLiveFootnoteReferences() -> [DocumentStorage.Index] {
        var referencedDefs: [DocumentStorage.Index] = []
        var indices: [DocumentStorage.Index: Int] = [:]
        var pending: [DocumentStorage.Index] = []
        if let first = storage[documentIndex].firstChild {
            pending.append(first)
        }
        while let node = pending.popLast() {
            if case .footnoteReference(let label) = storage[node].data,
               let defIdx = storage.footnoteMap[normalizeLabel(chunk: storage.chunk(of: label))] {
                let index: Int
                if let existing = indices[defIdx] {
                    index = existing
                } else {
                    referencedDefs.append(defIdx)
                    index = referencedDefs.count
                    indices[defIdx] = index
                }
                storage[node].kind = .footnoteReference(index: index)
            }
            if let next = storage[node].next {
                pending.append(next)
            }
            if let child = storage[node].firstChild {
                pending.append(child)
            }
        }
        return referencedDefs
    }

    /// Parses `node`'s inline content in `chunk`. Arena content is parsed from a copy, because `parseInline` appends to the arena, with its run map from `arenaSourceMaps` when it has one.
    private mutating func parseInline(
        chunk: Chunk,
        scratch: inout InlineScratch,
        into node: DocumentStorage.Index,
        preserveWhitespace: Bool = false
    ) {
        if chunk.inSource {
            parseInline(
                content: ContentSpan(span: sourceBytes.extracting(chunk.range), base: chunk.offset, inSource: true),
                into: node,
                preserveWhitespace: preserveWhitespace
            )
            return
        }
        scratch.bytes.removeSubrange(0..<scratch.bytes.count)
        scratch.bytes.append(copying: storage.strings.span.extracting(chunk.range))
        scratch.removeAllPieces()
        for run in arenaSourceMaps[node] ?? [] {
            scratch.append(piece: Segment(offset: run.sourceOffset, length: run.length, inSource: run.sourceOffset >= 0))
        }
        parseInline(
            content: ContentSpan(span: scratch.bytes.span, base: chunk.offset, runs: scratch.pieces.span, runEnds: scratch.pieceEnds.span),
            into: node,
            preserveWhitespace: preserveWhitespace
        )
    }

    /// The `.inlineOnly` and `.preserveWhitespace` parse.
    ///
    /// Any non-empty input, even a lone BOM, becomes one paragraph holding the source after any BOM, with line endings normalized to `\n` and every other byte kept. Only inline syntax is parsed, and line endings stay literal text.
    private mutating func parseInlineOnly() {
        let count = sourceBytes.count

        // Empty input has no lines, so it yields an empty document with no paragraph.
        guard count > 0 else {
            return
        }

        // Skip a leading UTF-8 BOM.
        var start = 0
        if count >= 3, sourceBytes[0] == 0xEF, sourceBytes[1] == 0xBB, sourceBytes[2] == 0xBF {
            start = 3
        }

        // Count lines and note any CR in one pass, so LF-only input stays zero-copy below. A BOM-only input counts as
        // one empty line.
        var hasCR = false
        // Where the last line's content ends: its terminator's first byte, or the end of input for an unterminated last line.
        var contentEnd = count
        var reader = LineReader(source: sourceBytes)
        while reader.next() != nil {
            if positionsEnabled {
                storage.lineStarts.append(reader.lineRange.lowerBound)
            }
            contentEnd = reader.lineRange.upperBound
            hasCR = hasCR || (contentEnd < count && sourceBytes[contentEnd] == UInt8(ascii: "\r"))
            noteLineRead(reader)
        }
        storage.lineCount = reader.lineNumber

        // Link reference definitions leading the content are consumed, and the paragraph is kept even when
        // nothing, or only whitespace, remains.
        let paragraph = addChild(kind: .paragraph, parent: documentIndex, start: start)
        // The paragraph holds the whole input after any BOM, but it and the document end where the last line's content ends, as in block mode.
        storage.setSourceStart(documentIndex, start)
        storage.setSourceEnd(documentIndex, contentEnd)
        storage.setSourceEnd(paragraph, contentEnd)

        // A NUL becomes U+FFFD (Insecure characters), which forces the arena copy below.
        let hasNUL = containsNUL(Chunk(offset: start, length: contentEnd - start, inSource: true))
        // The arena copy's source image, for the email autolink pass.
        var image: ContentImage? = nil
        var scratch = InlineScratch()
        if !hasCR && !hasNUL {
            let rest = parseDefinitions(in: Chunk(offset: start, length: count - start, inSource: true))
            parseInline(chunk: rest, scratch: &scratch, into: paragraph, preserveWhitespace: true)
        } else {
            // Copy the content to the arena with line endings normalized to `\n` and NULs to U+FFFD. With positions on, record
            // its run map: a CRLF's `\n` images its LF, so a node ending at the break covers the CRLF, as for LF input (a node
            // starting there starts after the CR), and each of a U+FFFD's three bytes images its NUL.
            let arenaStart = storage.strings.count
            var runs: [ArenaRun] = []
            var j = start
            while j < count {
                let byte = sourceBytes[j]
                if byte == UInt8(ascii: "\r") {
                    if j + 1 < count, sourceBytes[j + 1] == UInt8(ascii: "\n") {
                        j += 1
                    }
                    storage.strings.append(UInt8(ascii: "\n"))
                    if positionsEnabled {
                        Self.appendContentByte(imaging: j, to: &runs)
                    }
                } else if byte == 0 {
                    appendReplacementCharacter()
                    if positionsEnabled {
                        for _ in 0..<3 {
                            Self.appendContentByte(imaging: j, to: &runs)
                        }
                    }
                } else {
                    storage.strings.append(byte)
                    if positionsEnabled {
                        Self.appendContentByte(imaging: j, to: &runs)
                    }
                }
                j += 1
            }
            let arenaEnd = storage.strings.count
            let rest = parseDefinitions(in: Chunk(offset: arenaStart, length: arenaEnd - arenaStart, inSource: false))
            if positionsEnabled {
                arenaSourceMaps[paragraph] = sliceRuns(runs, from: rest.offset - arenaStart, length: rest.length)
            }
            parseInline(
                chunk: rest,
                scratch: &scratch,
                into: paragraph,
                preserveWhitespace: true
            )
            if positionsEnabled {
                image = ContentImage(base: arenaStart, runs: runs)
            }
        }
        finishInlines(paragraph, image: image)
        if positionsEnabled {
            endInlinesWithinLastLine(after: paragraph, contentEnd: contentEnd)
        }
    }

    /// Ends every node created after `paragraph` no later than `contentEnd`, the end of the input's last line.
    ///
    /// A node holding the final line ending would otherwise end past the last line. One starting inside that line ending gets an empty range at `contentEnd`.
    private mutating func endInlinesWithinLastLine(after paragraph: DocumentStorage.Index, contentEnd: Int) {
        for node in (paragraph + 1)..<storage.nodes.count where storage.sourceRanges[node].end > contentEnd {
            storage.sourceRanges[node].end = contentEnd
            storage.sourceRanges[node].start = min(storage.sourceRanges[node].start, contentEnd)
        }
    }

    /// Extends a run map by one byte imaging `sourceOffset`, or by a line-join byte when `sourceOffset < 0`.
    @inline(__always)
    fileprivate static func appendContentByte(imaging sourceOffset: Int, to runs: inout [ArenaRun]) {
        if let last = runs.last {
            let length = Int(last.length)
            let continuesGap = sourceOffset < 0 && last.sourceOffset < 0
            let continuesRun = sourceOffset >= 0 && last.sourceOffset >= 0
                && Int(last.sourceOffset) + length == sourceOffset
            if continuesGap || continuesRun {
                runs[runs.count - 1].length += 1
                return
            }
        }
        runs.append(ArenaRun(length: 1, sourceOffset: Int32(sourceOffset)))
    }

    /// Merges a leaf's adjacent text nodes, then finds extended email autolinks. `image` maps the leaf's content to the source when it is one arena chunk.
    private mutating func finishInlines(_ leaf: DocumentStorage.Index, image: ContentImage?) {
        consolidateTextNodes(leaf)
        // Email autolinks (Autolinks (extension)) are found in merged text, after emphasis is resolved.
        if storage.options.contains(.gfmAutolink) {
            gfmEmailAutolinkPass(leaf, image: image)
        }
    }

    // MARK: - State
    
    /// Appends a node starting at source offset `start` under `parent`.
    private mutating func addChild(kind: MarkdownNode.Kind, parent: DocumentStorage.Index, data: NodeData? = nil, start: Int) -> DocumentStorage.Index {
        let idx = storage.appendNode(NodeRecord(kind: kind, parent: parent, data: data))
        openBlocksVersion &+= 1
        if itemsEndingInRemovedParagraph.removeValue(forKey: parent) == true {
            itemsWithBlankLineAroundRemovedParagraph.insert(parent)
        }
        storage.appendChild(idx, to: parent)
        storage.setSourceStart(idx, start)
        return idx
    }

    /// Moves out `node`'s pending content, or `nil` if nothing is pending. Another node's pending content is a bug.
    private func take(_ pending: consuming PendingLeaf?, ifNode node: DocumentStorage.Index) -> PendingContent? {
        guard let leaf = pending else {
            return nil
        }
        
        if leaf.node == node {
            return consume leaf.content
        }
        
        fatalError("pending content for node \(leaf.node) must drain before node \(node) accumulates content")
    }

    /// Re-seeds `node`'s content as the segments that `map` images for arena `chunk`, so later lines append as to any segment-list paragraph.
    ///
    /// Used when a setext heading's content loses leading link reference definitions, or a paragraph left holding only definitions continues.
    private mutating func reseedSegments(_ chunk: Chunk, map: [ArenaRun], for node: DocumentStorage.Index) -> PendingLeaf {
        precondition(!chunk.inSource, "source-backed content re-seeds as a `.lazy` range, not as segments")
        precondition(map.reduce(0) { $0 + Int($1.length) } == chunk.length, "a run map tiles its content")
        var segments = UniqueArray<Segment>()
        for run in map {
            if run.sourceOffset < 0 {
                for _ in 0..<run.length {
                    segments.append(storage.newlineSegment)
                }
            } else {
                segments.append(Segment(offset: run.sourceOffset, length: run.length, inSource: true))
            }
        }
        return PendingLeaf(node: node, content: .segments(segments))
    }

    /// Appends `sourceBytes[range]` to `node`'s pending content.
    private mutating func addLine(range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // Code and HTML block bodies, which are never inline-parsed, accumulate as segments.
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            return addLineSegment(range: range, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .none:
            // A first line stays a source range.
            precondition(nodeKind.canAccumulateText, "only paragraphs and headings accumulate text lines")
            return PendingLeaf(node: node, content: .lazy(range: range))
        case .some(let existing):
            // A line directly after the previous range across a lone `\n` extends it, so a top-level LF paragraph stays one
            // zero-copy range. A stripped container prefix or a CR falls through to segments.
            switch consume existing {
            case .lazy(let prev, joinPending: true) where range.lowerBound == prev.upperBound + 1
                    && prev.upperBound < sourceBytes.count
                    && sourceBytes[prev.upperBound] == UInt8(ascii: "\n"):
                return PendingLeaf(node: node, content: .lazy(range: prev.lowerBound..<range.upperBound))
            case .lazy(let prev, joinPending: true):
                // The previous range becomes a source segment, joined to this line by `newlineSegment`.
                var segs = UniqueArray<Segment>()
                segs.append(Segment(offset: Int32(prev.lowerBound), length: Int32(prev.count), inSource: true))
                segs.append(storage.newlineSegment)
                return addLineSegment(range: range, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
            case .segments(let segs):
                return addLineSegment(range: range, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
            case .lazy(_, joinPending: false):
                preconditionFailure("a continuation line follows a deferred line join")
            }
        }
    }

    /// Appends a line join to `node`'s pending content. A `.lazy` range defers it (`joinPending`), so the next `addLine` can keep the run zero-copy.
    private mutating func appendNewline(to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            return appendSegment(storage.newlineSegment, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .lazy(let range, joinPending: false)?:
            return PendingLeaf(node: node, content: .lazy(range: range, joinPending: true))
        case .segments(let segs)?:
            return appendSegment(storage.newlineSegment, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
        case .lazy?:
            preconditionFailure("a deferred line join is requested once per line")
        case nil:
            preconditionFailure("a line join follows the leaf's first line")
        }
    }

    /// Appends a line of a segment-list leaf as a source segment. An empty line appends nothing, since the joins around it carry it.
    private mutating func addLineSegment(range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        guard !range.isEmpty else { return pending }
        return appendSegment(Segment(offset: Int32(range.lowerBound), length: Int32(range.upperBound - range.lowerBound), inSource: true), to: node, pending: pending)
    }

    /// Appends the rest of a code or HTML block line from `bodyStart`, after `leadingSpaces` spaces from a split tab.
    private mutating func appendCodeBodyLine(bodyStart: Int, leadingSpaces: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // The line reader has read the line, so a line not known to be free of NUL holds one.
        if leadingSpaces == 0 && isKnownFreeOfNUL(Chunk(offset: bodyStart, length: lineEnd - bodyStart, inSource: true)) {
            return addLine(range: bodyStart..<lineEnd, to: node, pending: pending)
        }
        return appendCodeLineCopy(spaces: leadingSpaces, sourceStart: bodyStart, lineEnd: lineEnd, to: node, pending: pending)
    }

    /// Append the rest of an HTML block line from `cursor`, where the container prefixes ended at `column`.
    private mutating func appendLineAfterPrefix(lineRange: Range<Int>, cursor: Int, column: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let (bodyStart, leadingSpaces) = htmlLineBody(lineRange: lineRange, cursor: cursor, column: column)
        return appendCodeBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: node, pending: pending)
    }

    /// Where the rest of an HTML block line from `cursor` begins, given the `column` the container prefixes reached,
    /// and how many spaces a split tab contributes.
    ///
    /// `cursor` is mid-tab when a block quote marker's optional space or a list item's indent consumed part of a tab;
    /// the tab's leftover columns become spaces (Tabs).
    private func htmlLineBody(lineRange: Range<Int>, cursor: Int, column: Int) -> (bodyStart: Int, leadingSpaces: Int) {
        let priorColumn = columnWidth(from: lineRange.lowerBound, to: cursor)
        return stripFenceIndent(
            range: cursor..<lineRange.upperBound,
            maxColumns: column - priorColumn,
            startColumn: priorColumn
        )
    }

    /// Appends `spaces` spaces and the source bytes `[sourceStart, lineEnd)`, each NUL replaced with U+FFFD (Insecure
    /// characters), as one arena segment, for a code or HTML block line whose stripped indent split a tab (Tabs) or that
    /// holds a NUL. The finalize normalizers rely on one segment per line.
    private mutating func appendCodeLineCopy(spaces: Int, sourceStart: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        let offset = storage.strings.count
        for _ in 0..<spaces {
            storage.strings.append(UInt8(ascii: " "))
        }
        appendReplacingNUL(sourceBytes.extracting(sourceStart..<lineEnd))
        return appendSegment(
            Segment(offset: Int32(offset), length: Int32(storage.strings.count - offset), inSource: false),
            to: node, pending: pending)
    }

    // MARK: - NUL -> U+FFFD replacement (Insecure characters)

    /// The index of the first NUL in `span`, or `span.count` if there is none.
    private static func firstNUL(in span: Span<UInt8>) -> Int {
        let nul = SIMD16<UInt8>(repeating: 0)
        return span.firstIndex(matching: { $0 .== nul }, or: { $0 == 0 })
    }

    /// Records the line `reader` last read, so content within the lines read since its last NUL needs no NUL scan.
    private mutating func noteLineRead(_ reader: borrowing LineReader) {
        if reader.lineFirstNUL < reader.lineRange.upperBound {
            nulFreeSourceStart = reader.lineRange.upperBound
        }
        sourceReadEnd = reader.lineRange.upperBound
    }

    /// Whether `chunk` is source content the line reader has read and found free of NUL.
    private func isKnownFreeOfNUL(_ chunk: Chunk) -> Bool {
        chunk.inSource && chunk.offset >= nulFreeSourceStart && chunk.offset + chunk.length <= sourceReadEnd
    }

    private func containsNUL(_ chunk: Chunk) -> Bool {
        if isKnownFreeOfNUL(chunk) {
            return false
        }
        let bytes = chunk.inSource ? sourceBytes.extracting(chunk.range) : storage.strings.span.extracting(chunk.range)
        return Self.firstNUL(in: bytes) < bytes.count
    }

    private func segmentsContainNUL(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        for i in 0..<segs.count where containsNUL(segs[i].chunk) {
            return true
        }
        return false
    }

    /// Replaces each NUL in `chunk` with U+FFFD (Insecure characters), copying only if it has one.
    private mutating func replacingNUL(_ chunk: Chunk) -> Chunk {
        containsNUL(chunk) ? copyReplacingNUL(chunk) : chunk
    }

    /// `chunk` copied to the arena with each NUL replaced with U+FFFD.
    private mutating func copyReplacingNUL(_ chunk: Chunk) -> Chunk {
        let offset = storage.strings.count
        if chunk.inSource {
            appendReplacingNUL(sourceBytes.extracting(chunk.range))
        } else {
            // The arena can't be read through a span while it grows, so its bytes are copied one at a time.
            for i in chunk.range {
                let b = storage.strings[i]
                if b == 0 {
                    appendReplacementCharacter()
                } else {
                    storage.strings.append(b)
                }
            }
        }
        return arenaChunk(from: offset)
    }

    /// Appends `bytes` to the arena with each NUL replaced with U+FFFD.
    private mutating func appendReplacingNUL(_ bytes: Span<UInt8>) {
        var rest = bytes
        while !rest.isEmpty {
            let nul = Self.firstNUL(in: rest)
            storage.strings.append(copying: rest.extracting(0..<nul))
            if nul < rest.count {
                appendReplacementCharacter()
            }
            rest = rest.extracting(min(nul + 1, rest.count)..<rest.count)
        }
    }

    private mutating func appendReplacementCharacter() {
        storage.strings.append(0xEF)
        storage.strings.append(0xBF)
        storage.strings.append(0xBD)
    }

    /// `replacingNUL(_:)` that also updates `chunk`'s run map `map`: each of a U+FFFD's three bytes images its NUL. With positions off, `map` is untouched.
    private mutating func replacingNUL(_ chunk: Chunk, map: inout [ArenaRun]) -> Chunk {
        guard containsNUL(chunk) else { return chunk }
        if positionsEnabled {
            map = rewrittenMap(sourceImage(of: chunk, map: map), of: chunk) { readByte(at: $0, in: chunk) == 0 ? 3 : 1 }
        }
        return copyReplacingNUL(chunk)
    }

    /// `chunk`'s run map `map` after a rewrite that turns `chunk`'s byte at each offset into `copies(offset)` bytes,
    /// each imaging what that byte images. An empty `map` stays empty.
    private func rewrittenMap(_ map: [ArenaRun], of chunk: Chunk, copies: (Int) -> Int) -> [ArenaRun] {
        assert(map.isEmpty || map.reduce(0) { $0 + Int($1.length) } == chunk.length, "a run map must tile its chunk")
        var rewritten: [ArenaRun] = []
        var i = chunk.offset
        for run in map {
            for local in 0..<Int(run.length) {
                let sourceOffset = run.sourceOffset < 0 ? -1 : Int(run.sourceOffset) + local
                for _ in 0..<copies(i) {
                    Self.appendContentByte(imaging: sourceOffset, to: &rewritten)
                }
                i += 1
            }
        }
        return rewritten
    }

    /// `chunk`'s run map: `map`, or for source content with an empty `map`, the one run imaging its own range.
    private func sourceImage(of chunk: Chunk, map: [ArenaRun]) -> [ArenaRun] {
        if map.isEmpty, chunk.inSource, chunk.length > 0 {
            return [ArenaRun(length: Int32(chunk.length), sourceOffset: Int32(chunk.offset))]
        }
        return map
    }

    /// `raw`'s run map `map` after `unescapePipes`, without each stripped backslash.
    func unescapedPipesMap(_ map: [ArenaRun], of raw: Chunk) -> [ArenaRun] {
        assert(map.reduce(0) { $0 + Int($1.length) } == raw.length, "a run map must tile its chunk")
        let end = raw.offset + raw.length
        // The same `\|` match as `unescapePipes`: a backslash immediately followed by a pipe.
        return rewrittenMap(map, of: raw) { i in
            readByte(at: i, in: raw) == UInt8(ascii: "\\") && i + 1 < end && readByte(at: i + 1, in: raw) == UInt8(ascii: "|") ? 0 : 1
        }
    }

    /// Appends `segment` to `node`'s pending segment list, starting one if needed.
    private mutating func appendSegment(_ segment: Segment, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        if case .segments(var segs)? = take(pending, ifNode: node) {
            segs.append(segment)
            return PendingLeaf(node: node, content: .segments(segs))
        }
        return PendingLeaf(node: node, content: .segments(UniqueArray(repeating: segment, count: 1)))
    }

    /// Drains `node`'s pending segment list, for code and HTML block finalize.
    private func drainSegments(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> UniqueArray<Segment> {
        switch consume pending {
        case .none:
            return UniqueArray()
        case .some(let leaf):
            precondition(leaf.node == node, "pending content belongs to the one open leaf, which drains when it closes")
            switch consume leaf.content {
            case .segments(let segs):
                return segs
            default:
                // Only code/HTML blocks drain here, and they only ever accumulate segments.
                fatalError("drainSegments called on non-segment content")
            }
        }
    }

    /// Materializes the open paragraph's pending content as a chunk: a `.lazy` range in place, or a segment list flattened into the arena with its run map.
    private mutating func materializePendingContent(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafMaterialization {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        let leaf = pending!
        precondition(leaf.node == node, "the pending leaf is the open paragraph's")
        switch consume leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            return LeafMaterialization(chunk: Chunk(offset: range.lowerBound, length: range.count, inSource: true))
        case .segments(let segs):
            var map: [ArenaRun] = []
            let chunk = flattenSegments(segs, map: &map)
            return LeafMaterialization(chunk: chunk, map: map)
        }
    }

    /// The offset of the last `\n` in the source range, or `nil` if the range is a single line.
    private func lastNewline(in range: Range<Int>) -> Int? {
        var i = range.upperBound - 1
        while i >= range.lowerBound {
            if sourceBytes[i] == UInt8(ascii: "\n") { return i }
            i -= 1
        }
        return nil
    }

    /// The index of the last line join in a multi-line paragraph's segments.
    ///
    /// It is found from the end: a paragraph asks once per delimiter-shaped line, and walking every line for each would
    /// make a long paragraph quadratic.
    private func lastLineJoin(in segs: borrowing UniqueArray<Segment>) -> Int {
        let nl = storage.newlineSegment
        var i = segs.count - 1
        while i >= 0 && segs[i] != nl {
            i -= 1
        }
        precondition(i >= 0, "a paragraph's segment list holds a line join")
        return i
    }

    /// Whether the open paragraph's last line and the delimiter-candidate line `sourceBytes[delimRange]` open a table
    /// (Tables (extension)). The two lines are copied to a scratch region of the arena for `opensTable`, then truncated.
    private mutating func lastLineOpensTable(delimRange: Range<Int>, pending: borrowing PendingLeaf) -> Bool {
        let scratchStart = storage.strings.count
        switch pending.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            for i in (lastNewline(in: range).map { $0 + 1 } ?? range.lowerBound)..<range.upperBound {
                storage.strings.append(sourceBytes[i])
            }
        case .segments(let segs):
            for i in (lastLineJoin(in: segs) + 1)..<segs.count {
                let seg = segs[i]
                for j in 0..<Int(seg.length) {
                    storage.strings.append(segmentByte(seg, j))
                }
            }
        }
        let headerEnd = storage.strings.count
        for i in delimRange {
            storage.strings.append(sourceBytes[i])
        }
        let opens = opensTable(header: scratchStart..<headerEnd, delimiter: headerEnd..<storage.strings.count)
        // Keeping the scratch would leave dead bytes in the arena for the parse's lifetime.
        storage.strings.removeLast(storage.strings.count - scratchStart)
        return opens
    }

    /// Sets `tablePending` when delimiter-candidate line `sourceBytes[delimRange]` opens a table whose header is the open
    /// paragraph's last line, since a table has one header row (Tables (extension)). Otherwise the paragraph continues,
    /// and a later line can still open one.
    ///
    /// Earlier lines are split off into a paragraph before `node`, which is re-seeded with the header line alone.
    private mutating func detectPendingTable(_ node: DocumentStorage.Index, delimRange: Range<Int>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        guard lastLineOpensTable(delimRange: delimRange, pending: pending!) else {
            return pending
        }
        openParagraphTableState!.tablePending = true
        let leaf = pending!
        switch consume leaf.content {
        case .lazy(let range, _):
            guard let lastNewline = lastNewline(in: range) else {
                return PendingLeaf(node: node, content: .lazy(range: range))
            }
            return splitContiguousHeader(node, range: range, lastNewline: lastNewline)
        case .segments(let segs):
            let lineJoin = lastLineJoin(in: segs)
            return splitSegmentHeader(node, segments: segs, lineJoin: lineJoin)
        }
    }

    /// Splits a source-contiguous paragraph before its last line: the earlier lines become a paragraph before `node`,
    /// which keeps the header line.
    private mutating func splitContiguousHeader(_ node: DocumentStorage.Index, range: Range<Int>, lastNewline: Int) -> PendingLeaf? {
        let headerRange = (lastNewline + 1)..<range.upperBound
        // The preceding lines are non-blank paragraph content (a blank line would have closed the
        // paragraph); they trim to empty only when they hold nothing but line tabulations and form feeds.
        let precedingLines = Chunk(offset: range.lowerBound, length: lastNewline - range.lowerBound, inSource: true)
        // The split-off lines are a paragraph that bypasses finalize, so its raw content is formed here.
        if let precedingChunk = tableSplitParagraphContent(precedingLines.trimmingWhitespace(using: self), in: precedingLines, node: node) {
            let preceding = insertTablePrecedingParagraph(before: node)
            let span = precedingChunk.isEmpty ? precedingLines : precedingChunk
            storage.setSourceStart(preceding, span.offset)
            storage.setSourceEnd(preceding, span.offset + span.length)
            enqueueTablePrecedingContent(precedingChunk, map: [], of: preceding)
        }
        storage.setSourceStart(node, headerRange.lowerBound)
        return PendingLeaf(node: node, content: .lazy(range: headerRange))
    }

    /// Queues a table-preceding paragraph's content for inline parsing with NUL replaced, and registers its run map
    /// `map`, which is empty for source content.
    private mutating func enqueueTablePrecedingContent(_ content: Chunk, map: [ArenaRun], of node: DocumentStorage.Index) {
        if content.isEmpty {
            return
        }
        var map = map
        let nulReplaced = replacingNUL(content, map: &map)
        if positionsEnabled, !nulReplaced.inSource {
            let image = sourceImage(of: nulReplaced, map: map)
            if !image.isEmpty {
                arenaSourceMaps[node] = image
            }
        }
        pendingInlines.append((node, storage.intern(nulReplaced)))
    }

    private mutating func insertTablePrecedingParagraph(before node: DocumentStorage.Index) -> DocumentStorage.Index {
        let paragraph = storage.appendNode(NodeRecord(kind: .paragraph, parent: storage[node].parent))
        storage.insertChildBefore(paragraph, before: node)
        return paragraph
    }

    /// Splits a segment-list paragraph before its header, the segments after its last line join: the earlier lines
    /// become a paragraph before `node`.
    private mutating func splitSegmentHeader(_ node: DocumentStorage.Index, segments: consuming UniqueArray<Segment>, lineJoin: Int) -> PendingLeaf? {
        var segs = segments
        var header = UniqueArray<Segment>()
        for i in (lineJoin + 1)..<segs.count {
            header.append(segs[i])
        }
        segs.removeSubrange(lineJoin..<segs.count)
        let untrimmedLastLine = segs[segs.count - 1]
        segs = trimSegments(segs)
        let trimmedLastLength = Int(segs[segs.count - 1].length)
        let preceding = segs
        let trailingSeparator = trimmedLastLength < Int(untrimmedLastLine.length)
            ? segmentByte(untrimmedLastLine, trimmedLastLength)
            : nil
        let precedingNode = insertTablePrecedingParagraph(before: node)
        // Read through a borrow, so `preceding` can then be consumed by `intern`.
        if positionsEnabled {
            let span = segmentsSourceSpan(preceding)
            storage.setSourceStart(precedingNode, span.start)
            storage.setSourceEnd(precedingNode, span.end)
        }
        // These lines bypass `drainLeaf`, so a NUL in them forces a flatten here, since a segment list can't carry
        // the U+FFFD (see `ContentSpan`).
        let substitutes = segmentsContainNUL(preceding)
        let trimsControlWhitespace = segmentsEndInControlWhitespace(preceding)
        let mayHoldMatcher = segmentsCouldMatchMatcher(preceding)
        if substitutes || trimsControlWhitespace || mayHoldMatcher {
            var map: [ArenaRun] = []
            let flat = flattenSegments(preceding, map: &map)
            if let content = tableSplitParagraphContent(flat.trimmingWhitespace(using: self), in: flat, node: precedingNode, fallbackSeparator: trailingSeparator) {
                if positionsEnabled, !content.isEmpty {
                    let span = sourceSpan(of: sliceRuns(map, from: content.offset - flat.offset, length: content.length))
                    storage.setSourceStart(precedingNode, span.start)
                    storage.setSourceEnd(precedingNode, span.end)
                }
                let contentMap = positionsEnabled ? sliceRuns(map, from: content.offset - flat.offset, length: content.length) : []
                enqueueTablePrecedingContent(content, map: contentMap, of: precedingNode)
            } else {
                storage.unlinkChild(precedingNode)
            }
        } else {
            pendingInlines.append((precedingNode, storage.intern(preceding)))
        }
        if positionsEnabled {
            storage.setSourceStart(node, segmentsSourceSpan(header).start)
        }
        return PendingLeaf(node: node, content: .segments(header))
    }

    /// The source span of a paragraph's segments, from the first line's start to the last line's end.
    private func segmentsSourceSpan(_ segs: borrowing UniqueArray<Segment>) -> (start: Int, end: Int) {
        precondition(segs.count > 0, "a paragraph's split-off lines and header line are never empty")
        let first = segs[0]
        let last = segs[segs.count - 1]
        precondition(first.inSource && last.inSource, "a paragraph's lines start and end on a source byte")
        return (Int(first.offset), Int(last.offset) + Int(last.length))
    }

    /// The source extent imaged by the run map of trimmed paragraph content: from its first run's byte to just past
    /// its last run's.
    private func sourceSpan(of map: [ArenaRun]) -> (start: Int, end: Int) {
        precondition(!map.isEmpty && map.first!.sourceOffset >= 0 && map.last!.sourceOffset >= 0, "trimmed paragraph content starts and ends on source bytes")
        return (Int(map.first!.sourceOffset), Int(map.last!.sourceOffset) + Int(map.last!.length))
    }

    // MARK: - Per-line dispatcher

    /// Process the line of Markdown at `lineRange` in the source.
    private mutating func processLine(lineRange: Range<Int>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        // PHASE 1: Strip each open container's continuation prefix. `deepestMatched` is the deepest container that continued.
        let walk = walkOpenContainers(lineRange: lineRange)
        let deepestMatched = walk.deepestMatched
        let cursor = walk.cursor
        let prefixColumns = walk.prefixColumns
        let allMatched = walk.allMatched

        currentLineIsLazyContinuation = !allMatched

        // PHASE 2a: Code-block / HTML-block continuation.
        let openKind = storage[current].kind
        if openKind.isCodeBlock || openKind == .htmlBlock {
            let leaf = continueOrCloseLeafBlock(lineRange: lineRange, cursor: cursor, prefixColumns: prefixColumns, allMatched: allMatched, pending: pending)
            let leafStillOpen = leaf.stillOpen
            pending = leaf.pending
            if leafStillOpen {
                return pending
            }
        }

        let scan = leadingScan(range: cursor..<lineRange.upperBound, baseColumn: prefixColumns)
        var line = LineContext(
            lineRange: lineRange,
            deepestMatched: deepestMatched,
            cursor: cursor,
            allMatched: allMatched,
            firstNonSpace: scan.firstNonSpace,
            firstNonSpaceByte: scan.firstNonSpaceByte,
            indent: scan.indentColumns,
            prefixColumns: prefixColumns,
            openKind: storage[current].kind
        )

        // PHASE 2b: Blank line.
        if scan.isBlank {
            return handleBlankLine(deepestMatched: deepestMatched, allMatched: allMatched, pending: pending)
        }
        // The containers that matched a non-blank line, and their ancestors, no longer end with a blank line. One that failed keeps its flag, since this line closes it.
        var clearUp: DocumentStorage.Index? = deepestMatched
        while let clearUp_ = clearUp {
            storage.nodes[clearUp_].lastLineBlank = false
            clearUp = storage[clearUp_].parent
        }

        // PHASE 2c: Setext heading underline.
        if underlineParagraph(line: &line, pending: &pending) {
            return pending
        }

        // PHASE 2d: Paragraph continuation.
        if absorbParagraphLine(line: line, pending: &pending) {
            return pending
        }

        // PHASE 3: Close stale containers down to deepestMatched.
        while current != deepestMatched {
            pending = finalize(node: current, pending: pending)
        }

        // PHASE 4: Open new blocks. A container loops back, so `> > foo` opens both quotes and then a paragraph.
        return dispatchNewBlocks(
            lineRange: lineRange,
            startCursor: cursor,
            startColumn: prefixColumns,
            pending: pending
        )
    }

    /// What `processLine` knows about a line once its container prefixes are stripped and its leading whitespace scanned.
    private struct LineContext {
        var lineRange: Range<Int>
        /// The deepest open container whose continuation matched the line.
        var deepestMatched: DocumentStorage.Index
        /// The byte offset into the line after the stripped container prefixes.
        var cursor: Int
        /// Whether every open container matched the line.
        var allMatched: Bool
        var firstNonSpace: Int
        var firstNonSpaceByte: UInt8
        /// The indentation, in columns, measured from the container prefix.
        var indent: Int
        /// The column the container prefixes reached (see `walkOpenContainers`).
        var prefixColumns: Int
        /// The kind of the open block, `current`.
        var openKind: MarkdownNode.Kind
    }

    /// An open code block or HTML block takes the line as its content when the prefix walk reached it, unless the line ends the block; then `stillOpen` is `false` and the line dispatches as a fresh block. When the walk failed before the block, the block closes.
    private mutating func continueOrCloseLeafBlock(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, allMatched: Bool, pending: consuming PendingLeaf?) -> LeafContinuation {
        guard allMatched else {
            return LeafContinuation(stillOpen: false, pending: finalize(node: current, pending: pending))
        }
        if storage[current].kind.isCodeBlock {
            return handleCodeBlockContinuation(lineRange: lineRange, cursor: cursor, prefixColumns: prefixColumns, pending: pending)
        }
        return handleHTMLBlockContinuation(lineRange: lineRange, cursor: cursor, prefixColumns: prefixColumns, pending: pending)
    }

    /// A blank line closes the open leaf and any container that failed to continue, and records the line for list tightness (Lists).
    private mutating func handleBlankLine(deepestMatched: DocumentStorage.Index, allMatched: Bool, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let nowOpen = storage[current].kind
        if nowOpen.canAccumulateText {
            pending = finalize(node: current, pending: pending)
        }
        // Close any container in the chain that failed to continue.
        if !allMatched {
            while current != deepestMatched {
                pending = finalize(node: current, pending: pending)
            }
        }
        // For list tightness (Lists), the blank line belongs to the deepest container that matched it, and it follows that container's last block, if any. Neither its ancestors nor a block quote, whose lines all begin with `>`, end with it.
        let container = deepestMatched
        if itemsEndingInRemovedParagraph[container] != nil {
            itemsEndingInRemovedParagraph[container] = true
        } else if let lastChild = storage[container].lastChild {
            storage.nodes[lastChild].lastLineBlank = true
        }
        storage.nodes[container].lastLineBlank = switch storage[container].kind {
        case .blockQuote: false
        default: true
        }
        // Only the deepest open container ends with a blank line: a line that opens a block inside it clears its flag,
        // and a line it does not continue closes it.
        assert(storage[container].parent.map { !storage.nodes[$0].lastLineBlank } ?? true, "only the deepest open container ends with a blank line")
        return pending
    }

    /// Whether a line of the open paragraph and the line after it form a table's header and delimiter rows.
    private var openParagraphIsTablePending: Bool {
        assert(openParagraphTableState == nil || openParagraphTableState!.node == current, "the recorded table state belongs to the open leaf")
        return openParagraphTableState?.tablePending == true
    }

    /// Turns the open paragraph into a setext heading when the line underlines it (Setext headings). Returns whether the line is done: it formed a heading, or continued a paragraph holding only definitions.
    ///
    /// A table-pending paragraph is a table, so a `-` or `=` line can't underline it (`r\n|-\n=` is a table with a `=` body row).
    private mutating func underlineParagraph(line: inout LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        guard line.openKind == .paragraph && line.allMatched && !openParagraphIsTablePending && line.indent < 4,
              let level = matchSetextUnderline(range: line.cursor..<lineRange.upperBound, firstNonSpace: line.firstNonSpace) else {
            return false
        }
        // Leading link reference definitions come out first; if they are the whole paragraph, no heading forms.
        let para = current
        let materialized = materializePendingContent(para, pending: consume pending)
        let raw = materialized.chunk
        // Empty unless the content was flattened from segments.
        let flatMap = materialized.map
        pending = nil
        let trimmedHead = raw.trimmingWhitespace(using: self)
        let stripped = parseDefinitions(in: trimmedHead)
        if !self.isBlank(chunk: stripped) {
            pending = makeHeading(para, level: level, raw: raw, stripped: stripped, flatMap: flatMap)
            return true
        }
        // A paragraph of only definitions forms no heading (Setext headings), but it is open while this line is
        // examined. A line that can't interrupt a paragraph, such as a lone `-` (an empty list item, List items) or
        // a run of `=` or `-` that is no thematic break, continues it and becomes its text once the definitions go.
        let continuesParagraph = !lineStartsNewBlock(
            range: line.cursor..<lineRange.upperBound,
            firstNonSpace: line.firstNonSpace,
            indent: line.indent,
            baseColumn: line.prefixColumns,
            currentKind: .paragraph,
            interruptsParagraph: true
        )
        if continuesParagraph {
            // These leading definitions are registered already; restoring them below lets the
            // paragraph's finalize, or the split of a table that forms first, remove them again.
            pending = raw.inSource
                ? PendingLeaf(node: para, content: .lazy(range: raw.range))
                : reseedSegments(raw, map: flatMap, for: para)
            pending = appendNewline(to: para, pending: consume pending)
            pending = addLine(range: line.firstNonSpace..<lineRange.upperBound, to: para, pending: consume pending)
            return true
        }
        // Only definitions: drop the paragraph and dispatch the line as a new block.
        removeEmptiedParagraph(para)
        openParagraphTableState = nil
        guard let parent = storage[para].parent else {
            fatalError("Invalid internal state - missing parent")
        }
        current = parent
        line.openKind = storage[current].kind
        return false
    }

    /// Turns the open paragraph into a `level` heading holding `stripped`, `raw` without its leading definitions. `flatMap` is `raw`'s run map.
    private mutating func makeHeading(_ para: DocumentStorage.Index, level: UInt8, raw: Chunk, stripped: Chunk, flatMap: [ArenaRun]) -> PendingLeaf {
        // A source range stays `.lazy`; arena content becomes the source segments its run map images, so the heading's inlines keep source positions.
        let pending: PendingLeaf
        if stripped.inSource {
            pending = PendingLeaf(node: para, content: .lazy(range: stripped.range))
        } else {
            pending = reseedSegments(stripped, map: sliceRuns(flatMap, from: stripped.offset - raw.offset, length: stripped.length), for: para)
        }
        let headingContent = stripped.trimmingWhitespace(using: self)
        if positionsEnabled, !headingContent.isEmpty,
           let start = sourceStart(of: headingContent, in: raw, map: flatMap) {
            storage.setSourceStart(para, start)
        }
        storage[para].kind = .heading(level: Int(level))
        openParagraphTableState = nil
        // The heading stays open with its content pending, so the usual close path finalizes it. No line continues a
        // heading.
        return pending
    }

    /// Whether the open paragraph absorbs the line as a continuation; otherwise the line starts a block that closes it. Only here does the interrupt decision matter, so only here does the matcher ladder run.
    ///
    /// A table-pending paragraph is a table, so a line that can't be a row closes it and its container: a lazy continuation
    /// line, a lone `|`, which has no cells, or a line indented four or more columns, which starts an indented code block
    /// because a table is not a paragraph (Indented code blocks).
    private mutating func absorbParagraphLine(line: LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        let tablePending = openParagraphIsTablePending
        let breaksOutOfPendingTable = tablePending
            && (currentLineIsLazyContinuation
                || line.indent >= 4
                || isLonePipeRow(range: line.firstNonSpace..<lineRange.upperBound))
        if line.openKind != .paragraph || breaksOutOfPendingTable {
            return false
        }
        // `mightStartBlock` covers every matcher's first byte, so prose skips the ladder. A list marker interrupts the
        // paragraph only when the paragraph's own container matched; otherwise it starts a sibling item. A table is no
        // paragraph, so the limits on interrupting one (List items, Lists) don't apply: `r\n|-\n-` is a table and a list.
        let interruptsParagraph = !tablePending
            && storage[current].parent == line.deepestMatched
        let canInterrupt = Self.mightStartBlock(line.firstNonSpaceByte)
            && lineStartsNewBlock(
                range: line.cursor..<lineRange.upperBound,
                firstNonSpace: line.firstNonSpace,
                indent: line.indent,
                baseColumn: line.prefixColumns,
                currentKind: line.openKind,
                interruptsParagraph: interruptsParagraph
            )
        if canInterrupt {
            return false
        }
        // A continuation, matched or lazy, closes no containers.
        if storage.options.contains(.tables) {
            recordTableDelimiterCandidate(line: line, pending: &pending)
        }
        pending = appendNewline(to: current, pending: consume pending)
        pending = addLine(range: line.firstNonSpace..<lineRange.upperBound, to: current, pending: consume pending)
        return true
    }

    /// Notes whether a continuation line may open a table with the paragraph's last line as its header.
    ///
    /// Inlined because it runs on every paragraph continuation line.
    @inline(__always)
    private mutating func recordTableDelimiterCandidate(line: LineContext, pending: inout PendingLeaf?) {
        let delimRange = line.firstNonSpace..<line.lineRange.upperBound
        if openParagraphTableState == nil {
            openParagraphTableState = OpenParagraphTableState(node: current)
        }
        assert(openParagraphTableState!.node == current, "the recorded state belongs to the open paragraph")
        // The first such line that opens a table sets `tablePending`, ending the search. `couldBeDelimiterRow` keeps
        // prose from materializing.
        if !openParagraphTableState!.tablePending,
           line.indent < 4, !currentLineIsLazyContinuation,
           couldBeDelimiterRow(range: delimRange) {
            pending = detectPendingTable(current, delimRange: delimRange, pending: consume pending)
        }
    }

    /// Strips each open container's continuation prefix, top-down. Returns the deepest container matched, the cursor past the prefixes, the column they reached, and whether every container matched.
    ///
    /// `prefixColumns` exceeds `cursor`'s column when a prefix ends mid-tab: `cursor` stays at the tab, which the leaf strip splits, its leftover columns becoming spaces (Tabs).
    private mutating func walkOpenContainers(lineRange: Range<Int>) -> (deepestMatched: DocumentStorage.Index, cursor: Int, prefixColumns: Int, allMatched: Bool) {
        var cursor = lineRange.lowerBound
        var deepestMatched = documentIndex
        var prefixColumns = 0
        var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
        // The first non-whitespace byte at or after `cursor`, valid while `cursor` has not passed it. Containers that
        // consume only whitespace leave it unchanged, so a chain of nested items scans the line's indent once.
        var firstNonSpaceAhead = -1

        // Descend from the document to `current` through each open block's last child, which is its open child. A
        // line stops at the first container whose prefix it fails, so it visits no container inside that one.
        var node = documentIndex
        // The list items and footnote definitions a blank rest of the line has continued.
        var blankContinued = 0
        while true {
            let kind = storage[node].kind
            switch kind {
            case .document:
                deepestMatched = node
            case .blockQuote:
                if cursor > firstNonSpaceAhead {
                    firstNonSpaceAhead = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
                }
                let firstNonSpace = firstNonSpaceAhead
                // An outer quote's marker can leave `cursor` mid-tab, so this marker's indent is measured from
                // `prefixColumns`.
                if let advanced = matchBlockQuoteMarker(
                    range: cursor..<lineRange.upperBound,
                    firstNonSpace: firstNonSpace,
                    baseColumn: prefixColumns
                ) {
                    // The marker's optional space consumes only one column of a wider tab, so the tab stays at
                    // `cursor` for the leaf strip to split and `prefixColumns` records the column (Tabs).
                    (cursor, prefixColumns) = blockQuotePrefixEnd(
                        lineColumns: &lineColumns,
                        markerEnd: firstNonSpace + 1,
                        advanced: advanced
                    )
                    deepestMatched = node
                } else {
                    // Without `>`, the block quote's paragraph may continue lazily.
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .list:
                // A list has no continuation prefix of its own; its items do.
                deepestMatched = node
            case .item, .footnoteDefinition:
                // An item continues when the indent past its parent's prefix reaches its content column, or on a
                // blank line once it holds a block (List items). A footnote definition continues likewise at four
                // columns, and on any blank line. Any other line fails, so the open paragraph may continue lazily.
                if cursor > firstNonSpaceAhead {
                    firstNonSpaceAhead = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
                }
                let firstNonSpace = firstNonSpaceAhead
                let isBlank = firstNonSpace == lineRange.upperBound
                let isItem = if case .item = kind { true } else { false }
                let padding = isItem ? itemPadding(of: node) : 4
                // Columns, not bytes, measured from `prefixColumns`, since a tab's width depends on the column it
                // starts at (Tabs). Each whitespace byte spans at least one column, so `padding` bytes decide.
                let availCols = indentColumns(from: cursor, to: min(firstNonSpace, cursor + padding), baseColumn: prefixColumns)
                if availCols >= padding {
                    // This precedes the empty-item check, so a whitespace-only line whose indent covers the content
                    // column extends even an empty item (a tab after a bare `-`).
                    cursor = advanceColumns(
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: padding,
                        baseColumn: prefixColumns
                    )
                    // Record the intended column even when a straddling tab kept `cursor` from passing it (Tabs).
                    prefixColumns += padding
                    deepestMatched = node
                } else if isBlank, !isItem || storage[node].firstChild != nil || itemsEndingInRemovedParagraph[node] != nil {
                    // A deeper item measures from the line end. An empty item closes, since a list item can begin with
                    // at most one blank line (List items); one whose first paragraph held only definitions or a task
                    // list item marker is not empty.
                    cursor = firstNonSpace
                    prefixColumns = lineColumns.column(at: cursor, in: sourceBytes)
                    deepestMatched = node
                    blankContinued += 1
                    if blankContinued > Self.emptyRemainderWalkLimit, node != current, let child = storage[node].lastChild {
                        let rest = walkPastEmptyRemainder(from: child, deepestMatched: node)
                        return (rest.deepestMatched, cursor, prefixColumns, rest.allMatched)
                    }
                } else {
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .paragraph, .heading, .codeBlock, .htmlBlock, .text, .thematicBreak:
                // Leaves have no prefix; the caller handles their continuation.
                return (deepestMatched, cursor, prefixColumns, true)
            default:
                break
            }
            if node == current {
                return (deepestMatched, cursor, prefixColumns, true)
            }
            guard let child = storage[node].lastChild else {
                preconditionFailure("each open block above `current` has its open child as its last child")
            }
            node = child
        }
    }

    /// Continues `walkOpenContainers` from open block `start` once nothing is left of the line.
    ///
    /// With nothing left, a block quote fails (Block quotes), a list item without a block fails (List items), and lists,
    /// items holding a block and footnote definitions continue. Where the walk ends then depends only on the open blocks
    /// from `start` down, so it is recorded per block passed and reused until `openBlocksVersion` changes. Otherwise `n`
    /// blank lines in a chain of `n` open footnote definitions walk `n` squared.
    private mutating func walkPastEmptyRemainder(from start: DocumentStorage.Index, deepestMatched inherited: DocumentStorage.Index) -> (deepestMatched: DocumentStorage.Index, allMatched: Bool) {
        var node = start
        var deepestMatched = inherited
        var allMatched: Bool
        var passed: [DocumentStorage.Index] = []
        walk: while true {
            if let recorded = emptyRemainderWalks[node], recorded.version == openBlocksVersion {
                deepestMatched = recorded.deepestMatched
                allMatched = recorded.allMatched
                break
            }
            passed.append(node)
            switch storage[node].kind {
            case .blockQuote:
                allMatched = false
                break walk
            case .item:
                guard storage[node].firstChild != nil || itemsEndingInRemovedParagraph[node] != nil else {
                    allMatched = false
                    break walk
                }
                deepestMatched = node
            case .list, .footnoteDefinition:
                deepestMatched = node
            case .paragraph, .heading, .codeBlock, .htmlBlock, .text, .thematicBreak:
                allMatched = true
                break walk
            default:
                break
            }
            if node == current {
                allMatched = true
                break
            }
            guard let child = storage[node].lastChild else {
                preconditionFailure("each open block above `current` has its open child as its last child")
            }
            node = child
        }
        let outcome = EmptyRemainderWalk(version: openBlocksVersion, deepestMatched: deepestMatched, allMatched: allMatched)
        for block in passed {
            emptyRemainderWalks[block] = outcome
        }
        return (deepestMatched, allMatched)
    }

    /// Whether the line starts a block that ends the open paragraph.
    ///
    /// `interruptsParagraph` is `false` when only a container shallower than the paragraph's matched, so a list marker starts a sibling item.
    private func lineStartsNewBlock(range: Range<Int>, firstNonSpace: Int, indent: Int, baseColumn: Int, currentKind: MarkdownNode.Kind, interruptsParagraph: Bool) -> Bool {
        // A line indented four or more columns starts no block that interrupts a paragraph.
        if indent >= 4 {
            return false
        }
        if matchThematicBreak(range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        if matchATXHeading(range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        if matchOpeningFence(range: range, firstNonSpace: firstNonSpace, indent: indent) != nil {
            return true
        }
        if matchBlockQuoteMarker(range: range, firstNonSpace: firstNonSpace, baseColumn: baseColumn) != nil {
            return true
        }
        // HTML blocks of types 1–6 interrupt a paragraph; type 7 does not (HTML blocks). When the paragraph's own
        // container failed to match, the line continues nothing, so `>o\n<d>` closes the block quote and opens an
        // HTML block, while `o\n<d>` keeps `<d>` as paragraph text.
        if matchHTMLBlockStart(range: range, firstNonSpace: firstNonSpace, allowType7: !interruptsParagraph) != nil {
            return true
        }
        // A footnote definition opener `[^label]:` interrupts a paragraph, so `[^a]: A\n[^b]: B` opens two
        // definitions rather than folding the second into the first definition's paragraph.
        if storage.options.contains(.footnotes),
           indent < 4,
           matchFootnoteDefinition(range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        // A list marker interrupts a paragraph only if it starts a non-empty item, and an ordered one only from 1 (List items, Lists), at every level: `- a\n  2. b` keeps `2. b` as text, while in `1. a\n2. b` the item didn't match, so `2.` opens a sibling item.
        if let marker = matchListMarker(range: range, firstNonSpace: firstNonSpace, markerColumn: baseColumn + indent, indent: indent) {
            if marker.isEmpty {
                // `- a\n  +` and `a\n+` keep `+` as text; in `> a\n+` the block quote didn't match, so `+` opens a list.
                return !interruptsParagraph
            }
            if interruptsParagraph
                && marker.kind == .ordered
                && marker.start != 1 {
                return false
            }
            return true
        }
        // An indented code block cannot interrupt a paragraph (Indented code blocks).
        return false
    }

    /// Continues an open HTML block. `stillOpen` is `false` when the line is left for new-block dispatch.
    private mutating func handleHTMLBlockContinuation(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        guard case .htmlBlock(let type, _) = storage[current].data else {
            preconditionFailure("an HTML block node always carries its block type")
        }
        // Types 6 and 7 end at a blank line, which is not part of the block.
        if type >= 6, indexOfFirstNonSpace(range: cursor..<lineRange.upperBound) == lineRange.upperBound {
            return LeafContinuation(stillOpen: false, pending: finalize(node: current, pending: pending))
        }
        // Every other line belongs to the block; for types 1–5, the one meeting the end condition closes the block and
        // is consumed.
        pending = appendNewline(to: current, pending: pending)
        pending = appendLineAfterPrefix(lineRange: lineRange, cursor: cursor, column: prefixColumns, to: current, pending: pending)
        if htmlBlockLineMatchesEndCondition(
            type: type,
            range: cursor..<lineRange.upperBound
        ) {
            pending = finalize(node: current, pending: pending, endsOnCurrentLine: true)
        }
        return LeafContinuation(stillOpen: true, pending: pending)
    }

    /// Continues an open code block. `stillOpen` is `false` when the line is left for new-block dispatch; a closing fence is consumed.
    private mutating func handleCodeBlockContinuation(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        let firstNonSpace = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound

        if case .codeBlock(let info) = storage[current].kind, info.isFenced {
            // A closing fence's indent is in columns past the container prefixes, so a tab counts to its tab stop (Tabs).
            let closingFenceIndent =
                columnWidth(from: lineRange.lowerBound, to: firstNonSpace) - prefixColumns
            if matchClosingFence(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indentColumns: closingFenceIndent,
                expectedChar: info.fenceCharacter,
                minimumLength: info.fenceLength
            ) {
                pending = finalize(node: current, pending: pending, endsOnCurrentLine: true)
                return LeafContinuation(stillOpen: true, pending: pending)
            }
            // Strip `prefixColumns` plus `fenceOffset` columns, less the `startColumn` the bytes before `cursor` cover.
            // A tab a container consumed only partly is split here, its leftover columns becoming spaces (Tabs).
            pending = appendNewline(to: current, pending: pending)
            let startColumn = columnWidth(from: lineRange.lowerBound, to: cursor)
            let (bodyStart, leadingSpaces) = stripFenceIndent(
                range: cursor..<lineRange.upperBound,
                maxColumns: prefixColumns + info.fenceOffset - startColumn,
                startColumn: startColumn
            )
            pending = appendCodeBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
            return LeafContinuation(stillOpen: true, pending: pending)
        }
        // Measured from `prefixColumns`, so a tab the prefixes partly consumed counts only its remaining columns (Tabs).
        let indent = indentColumns(from: cursor, to: firstNonSpace, baseColumn: prefixColumns)
        // A blank line keeps its whitespace past four columns as content.
        if indent >= 4 || isBlank {
            // Blank lines that end the block are not part of it, so for list tightness the block ends with a blank line until a further code line follows.
            storage.nodes[current].lastLineBlank = isBlank
            pending = appendNewline(to: current, pending: pending)
            if !isBlank {
                indentedCodeContentEnd = lineRange.upperBound
            }
            if indent > 4 || !isBlank {
                // A tab straddling the fourth column is split: its leftover columns become leading spaces (Tabs).
                let (bodyStart, leadingSpaces) = stripFenceIndent(
                    range: cursor..<lineRange.upperBound,
                    maxColumns: 4,
                    startColumn: prefixColumns
                )
                pending = appendCodeBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
            }
            return LeafContinuation(stillOpen: true, pending: pending)
        }
        pending = finalize(node: current, pending: pending)
        return LeafContinuation(stillOpen: false, pending: pending)
    }

    /// Opens a list item, in the open list when the marker continues it, otherwise in a new list.
    private mutating func openListItem(marker: ListMarkerInfo, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let start = firstNonSpace
        let parentList: DocumentStorage.Index
        if case .list(let info) = storage[current].kind,
           Self.marker(marker, continues: info) {
            parentList = current
        } else {
            // A different marker closes the open list, so `- foo\n+ bar` is two lists (Lists).
            pending = closingOpenList(pending)
            parentList = addChild(
                kind: .list(MarkdownNode.ListInfo(
                    kind: marker.kind,
                    start: marker.start,
                    tight: true,
                    orderedDelimiter: marker.orderedDelimiter,
                    bulletMarker: marker.bulletMarker
                )),
                parent: current,
                data: nil,
                start: start
            )
            current = parentList
        }
        let itemIdx = addChild(
            kind: .item(checked: nil),
            parent: parentList,
            data: .item(padding: marker.contentColumn),
            start: start
        )
        current = itemIdx
        return pending
    }

    /// Whether an item opened by `marker` continues the open list described by `list`: the same list kind, with the same bullet character or ordered delimiter.
    private static func marker(_ marker: ListMarkerInfo, continues list: MarkdownNode.ListInfo) -> Bool {
        if list.kind != marker.kind {
            return false
        }
        switch list.kind {
        case .bullet:
            return list.bulletMarker == marker.bulletMarker
        case .ordered:
            return list.orderedDelimiter == marker.orderedDelimiter
        }
    }

    /// Opens new blocks from `startCursor`, looping after each container so `> - foo` opens both and a paragraph.
    ///
    /// `startColumn` is the walk's `prefixColumns`, past `startCursor`'s column when a prefix consumed part of a tab.
    /// Indents are measured from it, so that tab's consumed columns don't count twice.
    private mutating func dispatchNewBlocks(lineRange: Range<Int>, startCursor: Int, startColumn: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // The matchers and openers this calls on every line that starts a block are `@inline(__always)`: called out of
        // line, they cost about 3% of a prose-heavy parse's instructions.
        var pending = pending
        var cursor = startCursor
        var column = startColumn
        var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
        // The depth of the block start being matched on this line; `maxListNesting` caps list opening by it.
        var depth = 0
        while true {
            depth += 1
            let firstNonSpace = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
            let isBlank = firstNonSpace == lineRange.upperBound
            if isBlank {
                return pending
            }
            let firstNonSpaceColumn = lineColumns.column(at: firstNonSpace, in: sourceBytes)
            let indent = firstNonSpaceColumn - column

            // An earlier marker on this line can leave `cursor` mid-tab, so the indent is measured from `column`.
            if let advanced = matchBlockQuoteMarker(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                baseColumn: column
            ) {
                // A list contains only list items, so an enclosing list closes first.
                pending = closingOpenList(pending)
                let quoteIdx = addChild(
                    kind: .blockQuote,
                    parent: current,
                    start: firstNonSpace
                )
                current = quoteIdx
                // As in `walkOpenContainers`, a tab under the marker's optional space stays at `cursor` for a later
                // leaf to split, and `column` records the column (Tabs).
                (cursor, column) = blockQuotePrefixEnd(
                    lineColumns: &lineColumns,
                    markerEnd: firstNonSpace + 1,
                    advanced: advanced
                )
                continue
            }

            // Before list markers, so `- - -` is a thematic break rather than nested lists.
            if indent < 4, let breakEnd = matchThematicBreak(range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
                pending = closingOpenList(pending)
                return openThematicBreak(firstNonSpace: firstNonSpace, end: breakEnd, pending: pending)
            }

            // A footnote definition is a container that takes the rest of the line.
            if storage.options.contains(.footnotes),
               indent < 4,
               let fn = matchFootnoteDefinition(
                   range: cursor..<lineRange.upperBound,
                   firstNonSpace: firstNonSpace
               ) {
                pending = closingOpenList(pending)
                let fnIdx = openFootnoteDefinition(label: fn.label, firstNonSpace: firstNonSpace)
                current = fnIdx
                cursor = fn.consumedTo
                column = lineColumns.column(at: cursor, in: sourceBytes)
                continue
            }

            // Past `maxListNesting` a marker is paragraph text. Indents are in columns, so a marker a tab pushes four
            // columns in, though fewer bytes, is indented code.
            if indent < 4, depth < Self.maxListNesting, let marker = matchListMarker(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                markerColumn: firstNonSpaceColumn,
                indent: indent
            ) {
                pending = openListItem(marker: marker, firstNonSpace: firstNonSpace, pending: pending)
                cursor = marker.consumedTo
                // Past `cursor`'s column when the marker's padding consumed part of a tab, which stays at `cursor` (Tabs).
                column = marker.contentStartColumn
                continue
            }

            // The line is no list item, so an open list closes before the new block attaches.
            pending = closingOpenList(pending)

            if indent < 4, let heading = matchATXHeading(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                return openATXHeading(heading, firstNonSpace: firstNonSpace, pending: pending)
            }

            // A fence a tab pushes four columns in is indented code: in `>~~~` then `\t~~~`, the second line closes
            // the quote's fence and opens an indented code block holding `~~~`.
            if indent < 4, let fence = matchOpeningFence(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indent: indent
            ) {
                openFencedCode(fence, cursor: cursor, firstNonSpace: firstNonSpace)
                return pending
            }

            // Type 7 can't interrupt a paragraph (HTML blocks).
            let allowType7 = storage[current].kind != .paragraph
            if indent < 4, let htmlType = matchHTMLBlockStart(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                allowType7: allowType7
            ) {
                return openHTMLBlock(htmlType, lineRange: lineRange, cursor: cursor, column: column, firstNonSpace: firstNonSpace, pending: pending)
            }

            // An indented code block can't interrupt a paragraph (Indented code blocks).
            if indent >= 4 && storage[current].kind != .paragraph {
                return openIndentedCode(lineRange: lineRange, cursor: cursor, column: column, pending: pending)
            }

            return openParagraph(lineRange: lineRange, firstNonSpace: firstNonSpace, pending: pending)
        }
    }

    /// Closes an open list at `current`, which holds only list items, before another block opens there.
    private mutating func closingOpenList(_ pending: consuming PendingLeaf?) -> PendingLeaf? {
        if storage[current].kind.isList {
            return finalize(node: current, pending: pending)
        }
        return pending
    }

    /// Opens and closes a thematic break whose line content ends at `end`.
    private mutating func openThematicBreak(firstNonSpace: Int, end: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let breakIdx = addChild(
            kind: .thematicBreak,
            parent: current,
            start: firstNonSpace
        )
        current = breakIdx
        return finalize(node: breakIdx, pending: pending, lineContentEnd: end)
    }

    /// Opens an ATX heading with its content line, and closes it.
    // Inlined for the reason given in `dispatchNewBlocks`.
    @inline(__always)
    private mutating func openATXHeading(_ heading: ATXMatch, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let headingIdx = addChild(
            kind: .heading(level: Int(heading.level)),
            parent: current,
            start: firstNonSpace
        )
        current = headingIdx
        if !heading.contentRange.isEmpty {
            pending = addLine(range: heading.contentRange, to: headingIdx, pending: pending)
        }
        return finalize(node: headingIdx, pending: pending, lineContentEnd: heading.end)
    }

    /// Opens a fenced code block, which stays open.
    private mutating func openFencedCode(_ fence: FenceMatch, cursor: Int, firstNonSpace: Int) {
        // The info string's backslash escapes and character references are decoded (Fenced code blocks).
        let cleanInfo = unescapeURLChunk(fence.infoChunk)
        let infoRef = storage.intern(replacingNUL(cleanInfo))
        // Each content line loses the fence's indent in columns (Fenced code blocks): after a partly consumed tab
        // (`>\t```), the tab's remaining two.
        let fenceOffset = fence.fenceOffset
        let codeIdx = addChild(
            kind: .codeBlock(MarkdownNode.CodeBlockInfo(
                isFenced: true,
                fenceCharacter: fence.character,
                fenceLength: fence.length,
                fenceOffset: fenceOffset
            )),
            parent: current,
            data: .codeBlock(info: infoRef, literal: .empty),
            start: firstNonSpace
        )
        current = codeIdx
    }

    /// Opens an HTML block with the line's content, closing it if the line meets its end condition.
    private mutating func openHTMLBlock(_ htmlType: UInt8, lineRange: Range<Int>, cursor: Int, column: Int, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let (bodyStart, leadingSpaces) = htmlLineBody(lineRange: lineRange, cursor: cursor, column: column)
        // The block keeps its indentation as content (HTML blocks), so it starts where that indentation does: at
        // `bodyStart`, or at the split tab whose leftover columns are the first content (Tabs).
        let htmlIdx = addChild(
            kind: .htmlBlock,
            parent: current,
            data: .htmlBlock(type: htmlType, literal: .empty),
            start: leadingSpaces > 0 ? bodyStart - 1 : bodyStart
        )
        current = htmlIdx
        pending = appendCodeBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: htmlIdx, pending: pending)
        if htmlBlockLineMatchesEndCondition(
            type: htmlType,
            range: firstNonSpace..<lineRange.upperBound
        ) {
            pending = finalize(node: htmlIdx, pending: pending)
        }
        return pending
    }

    /// Opens an indented code block with the line's content.
    private mutating func openIndentedCode(lineRange: Range<Int>, cursor: Int, column: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // The block starts after the four-column indent; further indentation is content (Indented code blocks). A tab
        // straddling the fourth column is split, its leftover columns becoming spaces (Tabs), and the block starts at it.
        let (bodyStart, leadingSpaces) = stripFenceIndent(
            range: cursor..<lineRange.upperBound,
            maxColumns: 4,
            startColumn: column
        )
        let codeIdx = addChild(
            kind: .codeBlock(MarkdownNode.CodeBlockInfo(
                isFenced: false,
                fenceCharacter: nil,
                fenceLength: 0,
                fenceOffset: 0
            )),
            parent: current,
            data: .codeBlock(info: .empty, literal: .empty),
            start: leadingSpaces > 0 ? bodyStart - 1 : bodyStart
        )
        current = codeIdx
        indentedCodeContentEnd = lineRange.upperBound
        return appendCodeBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: codeIdx, pending: pending)
    }

    /// Opens a paragraph with the line's content.
    // Inlined for the reason given in `dispatchNewBlocks`.
    @inline(__always)
    private mutating func openParagraph(lineRange: Range<Int>, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let textRange = firstNonSpace..<lineRange.upperBound
        precondition(storage[current].kind != .paragraph, "dispatch starts below the deepest matched container and opens only containers before a leaf, so `current` is never a paragraph here")
        assert(openParagraphTableState == nil, "the previous paragraph closed before this one opens")
        let paragraphIdx = addChild(kind: .paragraph, parent: current, start: firstNonSpace)
        current = paragraphIdx
        return addLine(range: textRange, to: paragraphIdx, pending: pending)
    }

    // MARK: - Finalize

    // MARK: Segment-content finalize (segment model)

    /// Drained leaf content: one chunk, or a segment list kept zero-copy.
    private enum DrainedLeaf: ~Copyable {
        case chunk(Chunk)
        case segments(UniqueArray<Segment>)
    }

    private struct LeafDrainResult: ~Copyable {
        var content: DrainedLeaf
        /// A `.chunk`'s run map when it is arena content with a source image.
        var map: [ArenaRun] = []
    }

    /// Drains `node`'s pending content, keeping a segment list unless it holds a NUL.
    private mutating func drainLeaf(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafDrainResult {
        switch consume pending {
        case .none:
            return LeafDrainResult(content: .chunk(.empty))
        case .some(let leaf):
            precondition(leaf.node == node, "pending content belongs to the one open leaf, which drains when it closes")
            switch consume leaf.content {
            case .segments(let segs):
                // Inline multi-segment content can hold no arena segment but a line join (`ContentSpan.multiNextSignificant`),
                // so a NUL forces a flatten with U+FFFD substituted.
                if segmentsContainNUL(segs) {
                    var map: [ArenaRun] = []
                    let flat = flattenSegments(segs, map: &map)
                    let replaced = replacingNUL(flat, map: &map)
                    return LeafDrainResult(content: .chunk(replaced), map: map)
                }
                return LeafDrainResult(content: .segments(segs))
            case .lazy(let range, let joinPending):
                precondition(!joinPending, "a deferred line join is always consumed by the next line")
                var map: [ArenaRun] = []
                let replaced = replacingNUL(Chunk(offset: range.lowerBound, length: range.count, inSource: true), map: &map)
                return LeafDrainResult(content: .chunk(replaced), map: map)
            }
        }
    }

    /// Byte `local` of `seg`.
    private func segmentByte(_ seg: Segment, _ local: Int) -> UInt8 {
        if seg.inSource {
            return sourceBytes[Int(seg.offset) + local]
        }
        return storage.strings[Int(seg.offset) + local]
    }

    /// Trims trailing whitespace from the last segment, as `Chunk.trimming(using:)` does. The first segment starts at its first non-space byte.
    private func trimSegments(_ segs: consuming UniqueArray<Segment>) -> UniqueArray<Segment> {
        var segs = segs
        precondition(segs.count > 0, "a paragraph's segment list starts with its opening line")
        precondition(!segmentByte(segs[0], 0).isSpaceTabOrNewline, "a paragraph's opening line starts at its first non-space byte")
        let li = segs.count - 1
        var last = segs[li]
        var len = Int(last.length)
        while len > 0 && segmentByte(last, len - 1).isSpaceTabOrNewline { len -= 1 }
        last.length = Int32(len)
        segs[li] = last
        return segs
    }

    /// Whether a paragraph's segment list begins or ends with a line tabulation or form feed, whitespace that
    /// `trimSegments` leaves for the flat content's trim to remove.
    private func segmentsEndInControlWhitespace(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        let first = segs[0]
        let last = segs[segs.count - 1]
        let isControlWhitespace = { (b: UInt8) in b == 0x0B || b == 0x0C }
        return (first.length > 0 && isControlWhitespace(segmentByte(first, 0)))
            || (last.length > 0 && isControlWhitespace(segmentByte(last, Int(last.length) - 1)))
    }

    /// Whether the content could match a finalize-time matcher: a link reference definition or task list item marker (`[`), an attribute definition (`^[`), or a table.
    ///
    /// A false positive costs only a materialization, so this must cover every matcher's necessary condition. A table's is on its second line, since a single-column header needs no pipe (`a\n:-`).
    private func segmentsCouldMatchMatcher(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        // Raw paragraph content begins at the first non-whitespace byte, line tabulation and form feed included.
        let attributesEnabled = storage.options.contains(.attributes)
        outer: for i in 0..<segs.count {
            let seg = segs[i]
            for j in 0..<Int(seg.length) {
                let b = segmentByte(seg, j)
                if b.isASCIISpace { continue }
                if b == UInt8(ascii: "[") { return true }
                // An attribute definition opens with a `^` immediately followed by `[`, so a `^` split
                // from its `[` by a line join is not admitted (the `[` would fall in the next segment).
                if b == UInt8(ascii: "^"), attributesEnabled, j + 1 < Int(seg.length),
                   segmentByte(seg, j + 1) == UInt8(ascii: "[") {
                    return true
                }
                break outer   // first non-whitespace byte doesn't open a definition
            }
        }
        // A delimiter row holds only `-`, `:`, `|` and delimiter-row padding, with at least one `-`.
        if storage.options.contains(.tables) {
            var line = 0
            var sawDash = false
            var secondLineClean = true
            walk: for i in 0..<segs.count {
                let seg = segs[i]
                for j in 0..<Int(seg.length) {
                    let b = segmentByte(seg, j)
                    if b == UInt8(ascii: "\n") {
                        if line == 1 { break walk }   // reached the end of the second line
                        line += 1
                        continue
                    }
                    if line == 1 {
                        switch b {
                        case UInt8(ascii: "-"):
                            sawDash = true
                        case UInt8(ascii: ":"), UInt8(ascii: "|"), UInt8(ascii: " "), UInt8(ascii: "\t"),
                             0x0B, 0x0C:
                            break
                        default:
                            secondLineClean = false
                            break walk
                        }
                    }
                }
            }
            if secondLineClean && sawDash {
                return true
            }
        }
        return false
    }

    /// Flattens a segment list into one arena chunk, recording its run map in `map`: a source segment images its range, and a line join is a gap. The map tiles the content from its first byte, so it survives a later copy of the content.
    private mutating func flattenSegments(_ segs: borrowing UniqueArray<Segment>, map: inout [ArenaRun]) -> Chunk {
        var total = 0
        for i in 0..<segs.count { total += Int(segs[i].length) }
        var buf = UniqueArray<UInt8>(minimumCapacity: total)
        let offset = storage.strings.count
        for i in 0..<segs.count {
            let seg = segs[i]
            let len = Int(seg.length)
            if seg.inSource {
                buf.append(copying: sourceBytes.extracting(seg.chunk.range))
            } else {
                buf.append(copying: storage.strings.span.extracting(seg.chunk.range))
            }
            if len > 0 {
                if seg.inSource {
                    map.append(ArenaRun(length: Int32(len), sourceOffset: seg.offset))
                } else {
                    map.append(ArenaRun(length: Int32(len), sourceOffset: -1))
                }
            }
        }
        storage.strings.append(copying: buf.span)
        return Chunk(offset: offset, length: total, inSource: false)
    }

    /// Narrows a run map to `[start, start + length)` of its content, rebased to start at 0.
    func sliceRuns(_ runs: [ArenaRun], from start: Int, length: Int) -> [ArenaRun] {
        let end = start + length
        var result: [ArenaRun] = []
        var v = 0
        for run in runs {
            let runStart = v
            let runEnd = v + Int(run.length)
            v = runEnd
            let lo = max(runStart, start)
            let hi = min(runEnd, end)
            if lo >= hi { continue }
            let sourceOffset: Int32 = run.sourceOffset < 0 ? -1 : run.sourceOffset + Int32(lo - runStart)
            result.append(ArenaRun(length: Int32(hi - lo), sourceOffset: sourceOffset))
        }
        return result
    }

    /// The raw content (`paragraphContent`) of the paragraph a table's header row splits off, whose trimmed lines are
    /// `trimmed`, a window of `lines`, or `nil` when its definitions or task list item marker leave nothing.
    /// `node` is that paragraph, or the paragraph it splits from. `fallbackSeparator` is the first byte trimmed off
    /// the lines before `lines` is formed, if any.
    private mutating func tableSplitParagraphContent(_ trimmed: Chunk, in lines: Chunk, node: DocumentStorage.Index, fallbackSeparator: UInt8? = nil) -> Chunk? {
        let content = paragraphContent(of: node, trimmed: trimmed, trailingSeparator: byte(after: trimmed, in: lines) ?? fallbackSeparator)
        return content.isEmpty && content.offset != trimmed.offset ? nil : content
    }

    /// The byte of `outer` just past `content`, a window of it in the same buffer, or `nil` at `outer`'s end.
    private func byte(after content: Chunk, in outer: Chunk) -> UInt8? {
        let end = content.offset + content.length
        return end < outer.offset + outer.length ? readByte(at: end, in: outer) : nil
    }

    /// Where `content`, a window of leaf content `raw` with run map `map` (empty for source content), begins in the
    /// source, or `nil` when it begins on a line join.
    private func sourceStart(of content: Chunk, in raw: Chunk, map: [ArenaRun]) -> Int? {
        if map.isEmpty {
            precondition(content.inSource, "with positions tracked, arena-backed leaf content carries a run map")
            return content.offset
        }
        var remaining = content.offset - raw.offset
        for run in map {
            if remaining < Int(run.length) {
                return run.sourceOffset < 0 ? nil : Int(run.sourceOffset) + remaining
            }
            remaining -= Int(run.length)
        }
        preconditionFailure("leaf content lies within its run map")
    }

    /// Removes `paragraph`, its container's last block, which holds only definitions or a task list item marker.
    ///
    /// In a list item it still counts for looseness as a block of the item (Lists).
    private mutating func removeEmptiedParagraph(_ paragraph: DocumentStorage.Index) {
        if let item = storage[paragraph].parent, case .item = storage[item].kind {
            if let preceding = storage[paragraph].previous, endsWithBlankLine(preceding) {
                itemsWithBlankLineAroundRemovedParagraph.insert(item)
            }
            itemsEndingInRemovedParagraph[item] = false
        }
        storage.unlinkChild(paragraph)
        openBlocksVersion &+= 1
    }

    /// Runs the paragraph matchers on flat content: table detection, then definition and task list item marker extraction. What remains is queued for inline parsing, or the node is dropped.
    ///
    /// `map` is `raw`'s run map, empty for source content.
    private mutating func runParagraphMatchers(node: DocumentStorage.Index, raw: Chunk, map: [ArenaRun]) {
        let trimmed = raw.trimmingWhitespace(using: self)
        if trimmed.isEmpty {
            // A non-blank line can hold only line tabulations and form feeds, which leave the
            // paragraph no raw content (Paragraphs).
            return
        }
        // Tables come before definition extraction: the paragraph is a table from its delimiter row on, and only a
        // paragraph holds definitions, so `[\n|-\n]:/` is a table. A pipe-less `-` or `=` run is a setext underline
        // instead, handled earlier with the definitions extracted: `[o]:o\n-` is a definition and a paragraph,
        // `[o]:o\n|-` a table. A delimiter row indented four or more columns, or lazy, is paragraph text.
        if let table = openParagraphTableState, table.tablePending {
            // The header is the raw paragraph content, before link reference definitions are extracted.
            let tableContent = raw.trimmingTrailing(using: self)
            // Arena content carries a run map, narrowed here to the table's content. Source content has none; the
            // table parser maps it by a constant shift.
            let tableMap = (positionsEnabled && !map.isEmpty)
                ? sliceRuns(map, from: tableContent.offset - raw.offset, length: tableContent.length)
                : []
            parseTable(node: node, chunk: tableContent, sourceMap: tableMap)
            return
        }
        let afterDefinitions = parseDefinitions(in: trimmed).trimmingWhitespace(using: self)
        if afterDefinitions.isEmpty {
            removeEmptiedParagraph(node)
            return
        }
        let contentChunk = taskItemContent(of: node, content: afterDefinitions, trailingSeparator: byte(after: trimmed, in: raw))
        if contentChunk.isEmpty {
            removeEmptiedParagraph(node)
            return
        }
        if positionsEnabled, let start = sourceStart(of: contentChunk, in: raw, map: map) {
            storage.setSourceStart(node, start)
        }
        // Narrow the run map to the content that reaches inline parsing.
        if positionsEnabled, !map.isEmpty {
            let slice = sliceRuns(map, from: contentChunk.offset - raw.offset, length: contentChunk.length)
            if !slice.isEmpty {
                arenaSourceMaps[node] = slice
            }
        }
        pendingInlines.append((node, storage.intern(contentChunk)))
    }

    /// Closes `node`, materializes its content, and makes its parent `current`.
    ///
    /// A block ends on the current line when `endsOnCurrentLine` (the document ends, a closing fence, an HTML block's end condition) or it opened on that line; otherwise it ends on the previous line, which the current line didn't continue. An indented code block ends at its last line that is not blank. `lineContentEnd` is where a one-line ATX heading's or thematic break's content ends.
    private mutating func finalize(node: DocumentStorage.Index, pending: consuming PendingLeaf?, endsOnCurrentLine: Bool = false, lineContentEnd: Int? = nil) -> PendingLeaf? {
        var pending = pending
        let kind = storage[node].kind
        openBlocksVersion &+= 1

        if positionsEnabled {
            let startByte = storage.sourceRanges[node].start
            let startedThisLine = startByte >= Int32(currentLineSourceRange.lowerBound)
            let end: Int
            if let lineContentEnd {
                // An ATX heading or a thematic break ends at its trimmed content extent, not the raw line.
                end = lineContentEnd
                // A block that later ends on this line, such as the document, ends at this content end too.
                currentLineSourceRange = currentLineSourceRange.lowerBound..<end
            } else if case .codeBlock(let info) = kind, !info.isFenced {
                end = indentedCodeContentEnd
            } else {
                end = (endsOnCurrentLine || startedThisLine || kind == .document)
                    ? currentLineSourceRange.upperBound
                    : lastLineSourceEnd
            }
            storage.setSourceEnd(node, end)
        }

        switch kind {
        case .paragraph:
            assert(openParagraphTableState == nil || openParagraphTableState!.node == node, "the recorded table state belongs to the paragraph being closed")
            defer { openParagraphTableState = nil }
            let drained = drainLeaf(node, pending: pending)
            pending = nil
            let map = drained.map
            switch consume drained.content {
            case .chunk(let raw):
                runParagraphMatchers(node: node, raw: raw, map: map)
            case .segments(let segs):
                // Prose stays segments; only content a matcher might match is flattened.
                let trimmed = trimSegments(segs)
                if segmentsCouldMatchMatcher(trimmed) || segmentsEndInControlWhitespace(trimmed) {
                    var map: [ArenaRun] = []
                    let raw = flattenSegments(trimmed, map: &map)
                    runParagraphMatchers(node: node, raw: raw, map: map)
                } else {
                    pendingInlines.append((node, storage.intern(trimmed)))
                }
            }
        case .heading:
            let drained = drainLeaf(node, pending: pending)
            pending = nil
            var map = drained.map
            let raw: Chunk
            switch consume drained.content {
            case .chunk(let chunk):
                raw = chunk
            case .segments(let segs):
                // A re-seeded setext heading's content is a segment list.
                raw = flattenSegments(segs, map: &map)
            }
            // An ATX heading's content range already excludes its surrounding spaces and tabs, and holds no line ending.
            let trimmed = lineContentEnd == nil ? raw.trimmingWhitespace(using: self) : raw
            if !trimmed.isEmpty {
                if positionsEnabled, !map.isEmpty {
                    arenaSourceMaps[node] = sliceRuns(map, from: trimmed.offset - raw.offset, length: trimmed.length)
                }
                pendingInlines.append((node, storage.intern(trimmed)))
            }
        case .codeBlock(let info):
            var segs = drainSegments(node, pending: pending)
            pending = nil
            normalizeCodeBlockSegments(&segs, isFenced: info.isFenced)
            let literalRef = storage.intern(segs)
            if case .codeBlock(let info, _) = storage[node].data {
                storage[node].data = .codeBlock(info: info, literal: literalRef)
            }
        case .htmlBlock:
            var segs = drainSegments(node, pending: pending)
            pending = nil
            normalizeHTMLBlockSegments(&segs)
            let literalRef = storage.intern(segs)
            if case .htmlBlock(let type, _) = storage[node].data {
                storage[node].data = .htmlBlock(type: type, literal: literalRef)
            }
        case .list:
            detectLooseList(node)
        case .footnoteDefinition:
            // A label's first definition to close wins, so one nested in a same-label definition (`[^b]:[^b]:A`) wins
            // over its encloser.
            if case .footnoteDefinition(let labelRef) = storage[node].data {
                let key = normalizeLabel(chunk: storage.chunk(of: labelRef))
                if !key.isEmpty && storage.footnoteMap[key] == nil {
                    storage.footnoteMap[key] = node
                }
            }
        default:
            break
        }
        if let parent = storage[node].parent {
            current = parent
        }
        return pending
    }

    /// Ends every line of an HTML block's body, a final blank one included, with `\n`. Each later line contributes a separator and any content, so one final separator suffices.
    private func normalizeHTMLBlockSegments(_ segs: inout UniqueArray<Segment>) {
        let nl = storage.newlineSegment
        precondition(segs.count > 0 && segs[0] != nl, "an HTML block's body starts with its opening line, which is never empty")
        segs.append(nl)
    }

    /// Normalizes a code block's body segments (Indented code blocks, Fenced code blocks): drops the separator before a fenced block's first line, strips an indented block's trailing blank lines, and ends the last line with `\n`. A fenced block without lines stays empty.
    ///
    /// Content segments hold no `\n`, so the list is lines separated by `newlineSegment`.
    private func normalizeCodeBlockSegments(_ segs: inout UniqueArray<Segment>, isFenced: Bool) {
        let nl = storage.newlineSegment
        var lo = 0
        var hi = segs.count

        // Fenced code emits a separator before its first line; indented code doesn't.
        var strippedLeading = false
        if lo < hi && segs[lo] == nl {
            lo += 1
            strippedLeading = true
        }

        // Indented code strips trailing blank lines; fenced code preserves them.
        if !isFenced {
            while lo < hi {
                let last = segs[hi - 1]
                if last == nl {
                    hi -= 1                       // trailing empty line + its separator
                    continue
                }
                if isAllWhitespace(last) {
                    hi -= 1                       // blank content line
                    if hi > lo && segs[hi - 1] == nl { hi -= 1 }   // and its preceding separator
                    continue
                }
                break
            }
        }

        if lo >= hi {
            precondition(isFenced, "an indented code block's first line holds content, so its body is never empty")
            segs = UniqueArray()
            // A body of one blank line is that line's line ending.
            if strippedLeading { segs.append(nl) }
            return
        }

        segs.removeSubrange(hi..<segs.count)
        segs.removeSubrange(0..<lo)
        // End with one line ending. A fenced block ending on a blank line keeps it, using the separator dropped in front.
        if segs[segs.count - 1] != nl {
            segs.append(nl)
        } else if isFenced && strippedLeading {
            segs.append(nl)
        }
    }

    /// Whether `segment` holds only spaces and tabs. Code block content holds no `\n`.
    private func isAllWhitespace(_ segment: Segment) -> Bool {
        segment.chunk.range.allSatisfy { readByte(at: $0, in: segment.chunk).isSpaceOrTab }
    }

    // MARK: - Helpers

    /// One walk over a line's leading whitespace, combining `indexOfFirstNonSpace` and `indentColumns`.
    private struct LeadingScan {
        var firstNonSpace: Int
        var indentColumns: Int
        var isBlank: Bool
        /// The byte at `firstNonSpace`, or `0` when the line is blank.
        var firstNonSpaceByte: UInt8
    }

    /// Measures `range`'s leading whitespace with tab stops every four columns (Tabs).
    private func leadingScan(range: Range<Int>, baseColumn: Int) -> LeadingScan {
        var i = range.lowerBound
        var col = baseColumn
        while i < range.upperBound {
            let b = sourceBytes[i]
            if b == UInt8(ascii: " ") {
                col += 1
            } else if b == UInt8(ascii: "\t") {
                col += 4 - (col & 3)
            } else {
                return LeadingScan(firstNonSpace: i, indentColumns: col - baseColumn, isBlank: false, firstNonSpaceByte: b)
            }
            i += 1
        }
        return LeadingScan(firstNonSpace: range.upperBound, indentColumns: col - baseColumn, isBlank: true, firstNonSpaceByte: 0)
    }

    /// The first byte in `range` that is not a space or tab, or `range.upperBound`.
    private func indexOfFirstNonSpace(range: Range<Int>) -> Int {
        var i = range.lowerBound
        while i < range.upperBound {
            let b = sourceBytes[i]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return i
            }
            i += 1
        }
        return range.upperBound
    }

    /// The column width of the whitespace `start..<end`, with tab stops every four columns (Tabs).
    ///
    /// `baseColumn` is `start`'s column. It matters when `start` is mid-tab after an outer container consumed part of
    /// the tab, since a tab's width depends on the column it starts at.
    private func indentColumns(from start: Int, to end: Int, baseColumn: Int = 0) -> Int {
        var col = baseColumn
        for i in start..<end {
            let b = sourceBytes[i]
            if b == UInt8(ascii: " ") {
                col += 1
            } else {
                assert(b == UInt8(ascii: "\t"), "an indent run holds only spaces and tabs")
                col += 4 - (col & 3)
            }
        }
        return col - baseColumn
    }

    /// A superset of the bytes a block can start with, so a line starting with any other byte can't interrupt a paragraph.
    @inline(__always)
    private static func mightStartBlock(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "*"), UInt8(ascii: "+"),
            UInt8(ascii: "#"),
            UInt8(ascii: "`"), UInt8(ascii: "~"),
            UInt8(ascii: ">"),
            UInt8(ascii: "<"),
            UInt8(ascii: "["),
            UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return false
        }
    }

    /// The offset past up to `columns` columns of leading whitespace from `start`, at column `baseColumn` (see `indentColumns`).
    ///
    /// A tab that would overshoot `columns` is not split; the result stops before it.
    private func advanceColumns(from start: Int, to end: Int, columns: Int, baseColumn: Int = 0) -> Int {
        var i = start
        var col = baseColumn
        let target = baseColumn + columns
        while i < end && col < target {
            let b = sourceBytes[i]
            if b == UInt8(ascii: " ") {
                col += 1
                i += 1
            } else {
                assert(b == UInt8(ascii: "\t"), "the columns advanced lie within the line's leading spaces and tabs")
                let advance = 4 - (col & 3)
                if col + advance > target {
                    break
                }
                col += advance
                i += 1
            }
        }
        return i
    }

    private struct ATXMatch {
        var level: UInt8
        var contentRange: Range<Int>
        /// Where the heading ends: at its trimmed content, past the opening `#`s when it is empty and a closing sequence was stripped, otherwise at the line end.
        var end: Int
    }

    private struct FenceMatch {
        var character: MarkdownNode.CodeBlockInfo.FenceCharacter
        var length: Int
        var fenceOffset: Int
        var infoChunk: Chunk
    }

    private struct ListMarkerInfo {
        var kind: MarkdownNode.ListInfo.Kind
        var bulletMarker: MarkdownNode.ListInfo.BulletMarker
        var orderedDelimiter: MarkdownNode.ListInfo.OrderedDelimiter
        var start: Int
        var contentColumn: Int    // content's column past the container prefix
        // The content's absolute column, past `consumedTo`'s when the padding consumed part of a tab, which stays at
        // `consumedTo`.
        var contentStartColumn: Int
        var consumedTo: Int       // source offset of first byte of item content
        var isEmpty: Bool         // marker opens an empty item (only whitespace to the line end)
    }

    private func itemPadding(of node: DocumentStorage.Index) -> Int {
        guard case .item(let padding) = storage[node].data else {
            preconditionFailure("an item node always carries its padding")
        }
        return padding
    }

    /// Matches a list marker at `firstNonSpace` (List items).
    ///
    /// `indent` is the marker's indent in columns from the column the enclosing prefixes reached, since a byte count
    /// would under-measure a tab. `markerColumn` is the marker's own column on its line, for the tab stops after it.
    // Inlined for the reason given in `dispatchNewBlocks`.
    @inline(__always)
    private func matchListMarker(range: Range<Int>, firstNonSpace: Int, markerColumn: Int, indent: Int) -> ListMarkerInfo? {
        let markerOffset = indent
        assert(markerOffset <= 3, "block-start matchers run only on a line indented less than four columns")
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let first = sourceBytes[firstNonSpace]

        var kind: MarkdownNode.ListInfo.Kind
        var bulletMarker: MarkdownNode.ListInfo.BulletMarker = .hyphen
        var orderedDelimiter: MarkdownNode.ListInfo.OrderedDelimiter = .period
        var startNumber = 1
        var markerWidth: Int

        switch first {
        case UInt8(ascii: "-"): // -
            kind = .bullet
            bulletMarker = .hyphen
            markerWidth = 1
        case UInt8(ascii: "+"): // +
            kind = .bullet
            bulletMarker = .plus
            markerWidth = 1
        case UInt8(ascii: "*"): // *
            kind = .bullet
            bulletMarker = .asterisk
            markerWidth = 1
        default:
            // Ordered: digits + `.` or `)`.
            if !first.isASCIIDigit {
                return nil
            }
            var i = firstNonSpace
            var digits = 0
            var n = 0
            while i < range.upperBound, sourceBytes[i].isASCIIDigit {
                if digits >= 9 {
                    return nil
                }
                n = n * 10 + Int(sourceBytes[i] - UInt8(ascii: "0"))
                digits += 1
                i += 1
            }
            if digits == 0 || i >= range.upperBound {
                return nil
            }
            let delim = sourceBytes[i]
            switch delim {
            case UInt8(ascii: "."):
                orderedDelimiter = .period
            case UInt8(ascii: ")"):
                orderedDelimiter = .paren
            default:
                return nil
            }
            kind = .ordered
            startNumber = n
            markerWidth = digits + 1
        }

        let afterMarker = firstNonSpace + markerWidth
        // The padding after the marker is measured in columns from the marker's own, so a tab counts to its stop.
        let contentColumnAfterMarker = markerColumn + markerWidth
        // Marker must be followed by a space, tab, or end of line.
        var contentStart: Int
        // The columns from the marker's end to the content.
        var padding = 1
        var isEmpty = false
        if afterMarker >= range.upperBound {
            // Empty item - the line is just `- ` (or end of input after marker).
            contentStart = afterMarker
            isEmpty = true
        } else {
            let next = sourceBytes[afterMarker]
            if next != UInt8(ascii: " ") && next != UInt8(ascii: "\t") {
                return nil
            }
            // The padding is measured in columns (List items): 1–4 are all padding, while 5 or more, or a blank
            // rest, consume one column and leave the rest as content. A tab wider than that column is consumed
            // only in part and stays at the content start (Tabs).
            var col = contentColumnAfterMarker
            var k = afterMarker
            while k < range.upperBound {
                let b = sourceBytes[k]
                if b == UInt8(ascii: " ") {
                    col += 1
                } else if b == UInt8(ascii: "\t") {
                    col += 4 - (col & 3)
                } else {
                    break
                }
                k += 1
            }
            let runColumns = col - contentColumnAfterMarker
            let blankAfter = k >= range.upperBound
            isEmpty = blankAfter
            if blankAfter || runColumns >= 5 {
                if next == UInt8(ascii: "\t") && (4 - (contentColumnAfterMarker & 3)) > 1 {
                    contentStart = afterMarker
                } else {
                    contentStart = afterMarker + 1
                }
            } else {
                // 1–4 columns: the whole run is padding; content begins at the first non-blank byte.
                contentStart = k
                padding = runColumns
            }
        }

        return ListMarkerInfo(
            kind: kind,
            bulletMarker: bulletMarker,
            orderedDelimiter: orderedDelimiter,
            start: startNumber,
            contentColumn: markerOffset + markerWidth + padding,
            contentStartColumn: contentColumnAfterMarker + padding,
            consumedTo: contentStart,
            isEmpty: isEmpty
        )
    }

    /// Type 6 tag names (HTML blocks), as byte arrays because the matchers index them on every candidate line and `String.utf8` is slower.
    private static let htmlBlockType6Tags: [[UInt8]] = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body",
        "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header",
        "hr", "html", "iframe", "legend", "li", "link", "main", "menu",
        "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param",
        "section", "summary", "table", "tbody", "td", "tfoot", "th",
        "thead", "title", "tr", "track", "ul",
    ].map { Array($0.utf8) }

    /// Type 1 tag names, whose closing tags also end the block.
    private static let htmlBlockType1Tags: [[UInt8]] = [
        "pre", "script", "style",
    ].map { Array($0.utf8) }

    /// The end conditions of HTML blocks of types 2 (`-->`), 3 (`?>`) and 5 (`]]>`), as UTF-8 bytes.
    private static let htmlCommentEnd = Array("-->".utf8)
    private static let processingInstructionEnd = Array("?>".utf8)
    private static let cdataEnd = Array("]]>".utf8)
    private static let declarationEnd = Array(">".utf8)

    /// Whether `range` equals lowercase `target`, ignoring ASCII case.
    private func bytesEqualASCIICaseInsensitive(range: Range<Int>, target: [UInt8]) -> Bool {
        let len = range.upperBound - range.lowerBound
        if len != target.count {
            return false
        }
        for i in 0..<len {
            var a = sourceBytes[range.lowerBound + i]
            let b = target[i]
            if a.isUppercaseASCIILetter {
                a += 32
            }
            if a != b {
                return false
            }
        }
        return true
    }

    /// The HTML block start condition (1–7, HTML blocks) the line meets at `firstNonSpace`, if any. Type 7 needs `allowType7`, since it can't interrupt a paragraph.
    private func matchHTMLBlockStart(range: Range<Int>, firstNonSpace: Int, allowType7: Bool) -> UInt8? {
        assert(firstNonSpace - range.lowerBound <= 3, "block-start matchers run only on a line indented less than four columns")
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        if sourceBytes[firstNonSpace] != UInt8(ascii: "<") {
            return nil
        }
        let after = firstNonSpace + 1
        if after >= range.upperBound {
            return nil
        }
        let next = sourceBytes[after]

        // Type 2: `<!--`
        if next == UInt8(ascii: "!"),
           after + 2 < range.upperBound,
           sourceBytes[after + 1] == UInt8(ascii: "-"),
           sourceBytes[after + 2] == UInt8(ascii: "-") {
            return 2
        }
        // Type 5: `<![CDATA[`, case-sensitive.
        if next == UInt8(ascii: "!"),
           after + 7 < range.upperBound,
           sourceBytes[after + 1] == UInt8(ascii: "["),
           sourceBytes[after + 7] == UInt8(ascii: "[") {
            let matched = sourceBytes[after + 2] == UInt8(ascii: "C")
                && sourceBytes[after + 3] == UInt8(ascii: "D")
                && sourceBytes[after + 4] == UInt8(ascii: "A")
                && sourceBytes[after + 5] == UInt8(ascii: "T")
                && sourceBytes[after + 6] == UInt8(ascii: "A")
            if matched {
                return 5
            }
        }
        // Type 4: `<!` followed by an uppercase ASCII letter (start condition 4).
        if next == UInt8(ascii: "!"),
           after + 1 < range.upperBound,
           sourceBytes[after + 1].isUppercaseASCIILetter {
            return 4
        }
        // Type 3: `<?`
        if next == UInt8(ascii: "?") {
            return 3
        }
        // Tags (types 1, 6): `<` or `</` followed by tagname.
        var nameStart = after
        var isClosing = false
        if next == UInt8(ascii: "/") {
            isClosing = true
            nameStart = after + 1
        }
        if nameStart >= range.upperBound || !sourceBytes[nameStart].isASCIILetter {
            return nil
        }
        var nameEnd = nameStart + 1
        while nameEnd < range.upperBound,
              isHTMLTagNameChar(sourceBytes[nameEnd]) {
            nameEnd += 1
        }
        let nameRange = nameStart..<nameEnd

        // Type 1: pre/script/style, open tag only. A closing tag such as `</pre>` doesn't meet start condition 1, but may start a type 7 block.
        if !isClosing {
            for tag in Self.htmlBlockType1Tags {
                if bytesEqualASCIICaseInsensitive(range: nameRange, target: tag) {
                    if nameEnd >= range.upperBound { return 1 }
                    let follow = sourceBytes[nameEnd]
                    if follow.isASCIISpace || follow == UInt8(ascii: ">") {
                        return 1
                    }
                    // Start condition 7 excludes these tag names, so `<script/>` starts no HTML block.
                    return nil
                }
            }
        }

        // Type 6: block-tag-name list.
        for tag in Self.htmlBlockType6Tags {
            if bytesEqualASCIICaseInsensitive(range: nameRange, target: tag) {
                if nameEnd >= range.upperBound { return 6 }
                let follow = sourceBytes[nameEnd]
                if follow.isASCIISpace || follow == UInt8(ascii: ">") {
                    return 6
                }
                if follow == UInt8(ascii: "/"),
                   nameEnd + 1 < range.upperBound,
                   sourceBytes[nameEnd + 1] == UInt8(ascii: ">") {
                    return 6
                }
                return nil
            }
        }

        // Type 7: a complete open or closing tag followed only by whitespace.
        if allowType7, let tagEnd = matchType7Tag(range: range, nameEnd: nameEnd, isClosing: isClosing) {
            if isOnlyWhitespaceToEnd(from: tagEnd, end: range.upperBound) {
                return 7
            }
        }
        return nil
    }

    /// Matches the rest of a type 7 tag after its name (Raw HTML), returning the offset past its `>`.
    private func matchType7Tag(range: Range<Int>, nameEnd: Int, isClosing: Bool) -> Int? {
        var i = nameEnd
        if isClosing {
            i = skipSpacechars(from: i, to: range.upperBound)
            if i >= range.upperBound || sourceBytes[i] != UInt8(ascii: ">") {
                return nil
            }
            return i + 1
        }
        while i < range.upperBound {
            let beforeAttr = i
            i = skipSpacechars(from: i, to: range.upperBound)
            if i == beforeAttr {
                break
            }
            if i >= range.upperBound {
                break
            }
            let first = sourceBytes[i]
            let isFirstChar = first.isASCIILetter
                || first == UInt8(ascii: "_")
                || first == UInt8(ascii: ":")
            if !isFirstChar {
                i = beforeAttr
                break
            }
            i += 1
            while i < range.upperBound {
                let b = sourceBytes[i]
                let ok = b.isASCIILetter
                    || b.isASCIIDigit
                    || b == UInt8(ascii: ":") || b == UInt8(ascii: ".")
                    || b == UInt8(ascii: "_") || b == UInt8(ascii: "-")
                if !ok { break }
                i += 1
            }
            let afterName = i
            i = skipSpacechars(from: i, to: range.upperBound)
            if i < range.upperBound && sourceBytes[i] == UInt8(ascii: "=") {
                i += 1
                i = skipSpacechars(from: i, to: range.upperBound)
                if i >= range.upperBound {
                    return nil
                }
                let opener = sourceBytes[i]
                if opener == UInt8(ascii: "\"") || opener == UInt8(ascii: "'") {
                    i += 1
                    while i < range.upperBound, sourceBytes[i] != opener {
                        i += 1
                    }
                    if i >= range.upperBound { return nil }
                    i += 1
                } else {
                    let valueStart = i
                    while i < range.upperBound {
                        let b = sourceBytes[i]
                        if b.isASCIISpace
                            || b == UInt8(ascii: "\"") || b == UInt8(ascii: "'")
                            || b == UInt8(ascii: "=") || b == UInt8(ascii: "<")
                            || b == UInt8(ascii: ">") || b == UInt8(ascii: "`") {
                            break
                        }
                        i += 1
                    }
                    // An unquoted value is nonempty, so `<a b=>` is no tag (Raw HTML).
                    if i == valueStart {
                        return nil
                    }
                }
            } else {
                i = afterName
            }
        }
        i = skipSpacechars(from: i, to: range.upperBound)
        if i < range.upperBound && sourceBytes[i] == UInt8(ascii: "/") {
            i += 1
        }
        if i >= range.upperBound || sourceBytes[i] != UInt8(ascii: ">") {
            return nil
        }
        return i + 1
    }

    /// Skips whitespace characters, as the inline HTML scanner does, so block and inline HTML agree on what separates tag parts.
    private func skipSpacechars(from start: Int, to end: Int) -> Int {
        var i = start
        while i < end {
            if !sourceBytes[i].isASCIISpace {
                break
            }
            i += 1
        }
        return i
    }

    private func isOnlyWhitespaceToEnd(from start: Int, end: Int) -> Bool {
        skipSpacechars(from: start, to: end) == end
    }

    /// Whether the line meets the end condition of an HTML block of `type` anywhere (HTML blocks).
    private func htmlBlockLineMatchesEndCondition(type: UInt8, range: Range<Int>) -> Bool {
        switch type {
        case 1:
            // `</pre>`, `</script>`, or `</style>` (case-insensitive).
            for tag in Self.htmlBlockType1Tags {
                if findClosingTag(range: range, name: tag) {
                    return true
                }
            }
            return false
        case 2:
            return findSubstring(range: range, needle: Self.htmlCommentEnd)
        case 3:
            return findSubstring(range: range, needle: Self.processingInstructionEnd)
        case 4:
            return findSubstring(range: range, needle: Self.declarationEnd)
        case 5:
            return findSubstring(range: range, needle: Self.cdataEnd)
        default:
            return false
        }
    }

    /// Whether `needle` occurs in `range`.
    private func findSubstring(range: Range<Int>, needle: [UInt8]) -> Bool {
        let len = needle.count
        if len == 0 || range.upperBound - range.lowerBound < len {
            return false
        }
        var i = range.lowerBound
        let limit = range.upperBound - len
        while i <= limit {
            var matched = true
            for k in 0..<len {
                if sourceBytes[i + k] != needle[k] {
                    matched = false
                    break
                }
            }
            if matched {
                return true
            }
            i += 1
        }
        return false
    }

    /// Whether `</name>` occurs in `range`, ignoring ASCII case.
    // Inlined because it scans every byte of a type 1 block's lines once per tag; out of line it costs about 2% of a corpus parse's instructions.
    @inline(__always)
    private func findClosingTag(range: Range<Int>, name: [UInt8]) -> Bool {
        let nameLen = name.count
        // `</` + name + `>` length:
        let totalLen = nameLen + 3
        if range.upperBound - range.lowerBound < totalLen {
            return false
        }
        var i = range.lowerBound
        let limit = range.upperBound - totalLen
        while i <= limit {
            if sourceBytes[i] == UInt8(ascii: "<"),
               sourceBytes[i + 1] == UInt8(ascii: "/") {
                let nameRange = (i + 2)..<(i + 2 + nameLen)
                var matched = true
                for k in 0..<nameLen {
                    var a = sourceBytes[nameRange.lowerBound + k]
                    if a.isUppercaseASCIILetter {
                        a += 32
                    }
                    if a != name[k] {
                        matched = false
                        break
                    }
                }
                if matched, sourceBytes[i + 2 + nameLen] == UInt8(ascii: ">") {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    private func isHTMLTagNameChar(_ b: UInt8) -> Bool {
        b.isASCIILetter
            || b.isASCIIDigit
            || b == UInt8(ascii: "-")
    }

    /// Matches a block quote marker (Block quotes), returning the offset past it and its optional space or tab.
    ///
    /// `baseColumn` is `range.lowerBound`'s column (see `indentColumns`).
    // Inlined for the reason given in `dispatchNewBlocks`.
    @inline(__always)
    private func matchBlockQuoteMarker(range: Range<Int>, firstNonSpace: Int, baseColumn: Int = 0) -> Int? {
        // A byte count would under-measure a tab: `\t>` is no block quote marker.
        if indentColumns(from: range.lowerBound, to: firstNonSpace, baseColumn: baseColumn) > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
        if sourceBytes[firstNonSpace] != UInt8(ascii: ">") { // >
            return nil
        }
        var i = firstNonSpace + 1
        if i < range.upperBound && (sourceBytes[i] == UInt8(ascii: " ") || sourceBytes[i] == UInt8(ascii: "\t")) {
            i += 1
        }
        return i
    }

    /// Where a matched block quote marker leaves the line: the cursor and the column reached.
    ///
    /// The optional character after `>` is one column (Tabs), so a wider tab is consumed only in part: the cursor stays
    /// on it, at a column strictly inside it. Measuring from the tab's stop instead would recount it as four columns.
    private func blockQuotePrefixEnd(lineColumns: inout LineColumns, markerEnd: Int, advanced: Int) -> (cursor: Int, column: Int) {
        let markerEndColumn = lineColumns.column(at: markerEnd, in: sourceBytes)
        if advanced == markerEnd + 1, sourceBytes[markerEnd] == UInt8(ascii: "\t"), 4 - (markerEndColumn & 3) > 1 {
            return (markerEnd, markerEndColumn + 1)
        }
        return (advanced, lineColumns.column(at: advanced, in: sourceBytes))
    }

    /// Matches an opening code fence (Fenced code blocks). `indent` is in columns from the column the enclosing prefixes reached.
    // Inlined for the reason given in `dispatchNewBlocks`.
    @inline(__always)
    private func matchOpeningFence(range: Range<Int>, firstNonSpace: Int, indent: Int) -> FenceMatch? {
        assert(indent <= 3, "block-start matchers run only on a line indented less than four columns")
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let markerCharacter = sourceBytes[firstNonSpace]
        guard let marker = MarkdownNode.CodeBlockInfo.FenceCharacter(character: markerCharacter) else {
            return nil
        }
        var i = firstNonSpace
        while i < range.upperBound && sourceBytes[i] == marker.character {
            i += 1
        }
        let runLength = i - firstNonSpace
        if runLength < 3 {
            return nil
        }
        var infoStart = i
        while infoStart < range.upperBound && sourceBytes[infoStart].isASCIISpace {
            infoStart += 1
        }
        var infoEnd = range.upperBound
        while infoEnd > infoStart && sourceBytes[infoEnd - 1].isASCIISpace {
            infoEnd -= 1
        }
        if marker == .backtick {
            for j in infoStart..<infoEnd where sourceBytes[j] == UInt8(ascii: "`") {
                return nil
            }
        }
        return FenceMatch(
            character: marker,
            length: runLength,
            fenceOffset: indent,
            infoChunk: Chunk(
                offset: infoStart,
                length: infoEnd - infoStart,
                inSource: true
            )
        )
    }

    /// Whether the line closes a fence of `expectedChar` at least `minimumLength` long (Fenced code blocks). The indent is
    /// in columns, so a tab-led line is content.
    private func matchClosingFence(range: Range<Int>, firstNonSpace: Int, indentColumns: Int, expectedChar: MarkdownNode.CodeBlockInfo.FenceCharacter?, minimumLength: Int) -> Bool {
        precondition(expectedChar != nil, "a fenced code block always records its fence character")
        let fenceByte = expectedChar!.character
        if indentColumns > 3 {
            return false
        }
        guard firstNonSpace < range.upperBound else {
            return false
        }
        if sourceBytes[firstNonSpace] != fenceByte {
            return false
        }
        var i = firstNonSpace
        while i < range.upperBound && sourceBytes[i] == fenceByte {
            i += 1
        }
        return i - firstNonSpace >= minimumLength && isSpaceOrTabOnly(i..<range.upperBound)
    }

    /// Whether `sourceBytes[range]` holds only spaces and tabs.
    // Inlined because out of line it costs about 0.5% of the spec text's parse instructions.
    @inline(__always)
    private func isSpaceOrTabOnly(_ range: Range<Int>) -> Bool {
        range.allSatisfy { sourceBytes[$0].isSpaceOrTab }
    }

    /// Strips up to `maxColumns` columns of leading whitespace from a code or HTML block line at column `startColumn`.
    ///
    /// A tab straddling the boundary is dropped and its leftover columns returned as `leadingSpaces` (Tabs).
    private func stripFenceIndent(range: Range<Int>, maxColumns: Int, startColumn: Int) -> (bodyStart: Int, leadingSpaces: Int) {
        var i = range.lowerBound
        var column = startColumn
        var consumed = 0
        while i < range.upperBound && consumed < maxColumns {
            let b = sourceBytes[i]
            if b == UInt8(ascii: " ") {
                column += 1
                consumed += 1
                i += 1
            } else if b == UInt8(ascii: "\t") {
                let width = 4 - (column & 3)
                if consumed + width <= maxColumns {
                    column += width
                    consumed += width
                    i += 1
                } else {
                    return (i + 1, width - (maxColumns - consumed))
                }
            } else {
                break
            }
        }
        return (i, 0)
    }

    /// The column reached after `sourceBytes[from..<to]` (Tabs). Unlike `indentColumns`, it counts every byte, container
    /// markers included.
    private func columnWidth(from: Int, to: Int) -> Int {
        var column = 0
        for i in from..<to {
            column += sourceBytes[i] == UInt8(ascii: "\t") ? 4 - (column & 3) : 1
        }
        return column
    }

    /// `columnWidth` from a line's start, advancing from the previous answer; queries never move back.
    ///
    /// The prefix walk and block dispatch place each container marker by its column, and measuring each from the line
    /// start would make a line of `n` nested markers cost `n` squared.
    private struct LineColumns {
        private var offset: Int
        private var column = 0

        init(lineStart: Int) {
            offset = lineStart
        }

        /// The absolute column reached after the line's bytes before `target`.
        mutating func column(at target: Int, in source: Span<UInt8>) -> Int {
            precondition(target >= offset, "a line's column queries never move back")
            while offset < target {
                column += source[offset] == UInt8(ascii: "\t") ? 4 - (column & 3) : 1
                offset += 1
            }
            return column
        }
    }

    /// Matches a setext heading underline (Setext headings).
    private func matchSetextUnderline(range: Range<Int>, firstNonSpace: Int) -> UInt8? {
        assert(firstNonSpace - range.lowerBound <= 3, "block-start matchers run only on a line indented less than four columns")
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let marker = sourceBytes[firstNonSpace]
        let level: UInt8
        switch marker {
        case UInt8(ascii: "="):
            level = 1
        case UInt8(ascii: "-"):
            level = 2
        default:
            return nil
        }
        var i = firstNonSpace
        while i < range.upperBound && sourceBytes[i] == marker {
            i += 1
        }
        return isSpaceOrTabOnly(i..<range.upperBound) ? level : nil
    }

    /// Matches a thematic break (Thematic breaks), returning the offset past its last marker character.
    private func matchThematicBreak(range: Range<Int>, firstNonSpace: Int) -> Int? {
        assert(firstNonSpace - range.lowerBound <= 3, "block-start matchers run only on a line indented less than four columns")
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let marker = sourceBytes[firstNonSpace]
        if marker != UInt8(ascii: "-") && marker != UInt8(ascii: "_") && marker != UInt8(ascii: "*") {
            return nil
        }
        var count = 0
        var end = firstNonSpace
        var i = firstNonSpace
        while i < range.upperBound {
            let b = sourceBytes[i]
            if b == marker {
                count += 1
                end = i + 1
            } else if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return nil
            }
            i += 1
        }
        return count >= 3 ? end : nil
    }

    /// Matches an ATX heading (ATX headings).
    private func matchATXHeading(range: Range<Int>, firstNonSpace: Int) -> ATXMatch? {
        assert(firstNonSpace - range.lowerBound <= 3, "block-start matchers run only on a line indented less than four columns")
        var i = firstNonSpace
        var level: Int = 0
        while i < range.upperBound && sourceBytes[i] == UInt8(ascii: "#") { // #
            level += 1
            i += 1
        }
        if level < 1 || level > 6 {
            return nil
        }
        if i < range.upperBound {
            let b = sourceBytes[i]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return nil
            }
        }
        var contentStart = i
        while contentStart < range.upperBound
            && (sourceBytes[contentStart] == UInt8(ascii: " ") || sourceBytes[contentStart] == UInt8(ascii: "\t")) {
            contentStart += 1
        }
        var contentEnd = range.upperBound
        while contentEnd > contentStart
            && (sourceBytes[contentEnd - 1] == UInt8(ascii: " ") || sourceBytes[contentEnd - 1] == UInt8(ascii: "\t")) {
            contentEnd -= 1
        }
        let beforeHashes = contentEnd
        while contentEnd > contentStart && sourceBytes[contentEnd - 1] == UInt8(ascii: "#") {
            contentEnd -= 1
        }
        let removedHashes = beforeHashes - contentEnd
        if removedHashes > 0 {
            if contentEnd > contentStart {
                let preceding = sourceBytes[contentEnd - 1]
                if preceding == UInt8(ascii: " ") || preceding == UInt8(ascii: "\t") {
                    while contentEnd > contentStart
                        && (sourceBytes[contentEnd - 1] == UInt8(ascii: " ") || sourceBytes[contentEnd - 1] == UInt8(ascii: "\t")) {
                        contentEnd -= 1
                    }
                } else {
                    contentEnd = beforeHashes
                }
            }
        }

        let end: Int
        if contentStart != contentEnd {
            end = contentEnd
        } else if removedHashes > 0 {
            end = i
        } else {
            end = range.upperBound
        }

        return ATXMatch(level: UInt8(level), contentRange: contentStart..<contentEnd, end: end)
    }

    /// Marks the list loose (Lists) when a blank line separates two of its items, or two blocks an item directly contains. A removed paragraph that held only definitions or a task list item marker counts as a block.
    private mutating func detectLooseList(_ list: DocumentStorage.Index) {
        var loose = false
        var item = storage[list].firstChild
        outer: while let item_ = item {
            let nextItem = storage[item_].next
            if itemsWithBlankLineAroundRemovedParagraph.contains(item_) {
                loose = true
                break outer
            }
            // (a) Item ends with a blank line and has a next sibling.
            if nextItem != nil && storage.nodes[item_].lastLineBlank {
                loose = true
                break outer
            }
            // (b) Any subitem ends with a blank line, AND either the item has a next sibling OR the subitem itself does.
            var sub = storage[item_].firstChild
            while let sub_ = sub {
                let nextSub = storage[sub_].next
                if (nextItem != nil || nextSub != nil)
                    && endsWithBlankLine(sub_) {
                    loose = true
                    break outer
                }
                sub = nextSub
            }
            item = nextItem
        }
        if loose {
            if case .list(var info) = storage[list].kind {
                info.tight = false
                storage[list].kind = .list(info)
            }
        }
    }

    /// Whether the last block down `node`'s spine of lists and items ends with a blank line. An item ending in a removed paragraph does when a blank line follows that paragraph.
    private func endsWithBlankLine(_ node: DocumentStorage.Index) -> Bool {
        var cur = node
        while true {
            let kind = storage[cur].kind
            let isListOrItem = switch kind {
            case .list, .item: true
            default: false
            }
            if let blankLineAfterRemovedParagraph = itemsEndingInRemovedParagraph[cur] {
                return blankLineAfterRemovedParagraph
            }
            if isListOrItem, let lastChild = storage[cur].lastChild {
                cur = lastChild
                continue
            }
            return storage.nodes[cur].lastLineBlank
        }
    }

    /// The byte at `offset` in `chunk`'s buffer.
    func readByte(at offset: Int, in chunk: Chunk) -> UInt8 {
        chunk.inSource ? sourceBytes[offset] : storage.strings[offset]
    }

    /// The raw content of the paragraph `node` whose trimmed lines are `trimmed`: what follows its leading link
    /// reference definitions, from its first non-whitespace byte, less any task list item marker. `trailingSeparator` is
    /// the byte after `trimmed` on its line.
    private mutating func paragraphContent(of node: DocumentStorage.Index, trimmed: Chunk, trailingSeparator: UInt8?) -> Chunk {
        taskItemContent(of: node, content: parseDefinitions(in: trimmed).trimmingWhitespace(using: self), trailingSeparator: trailingSeparator)
    }

    /// The paragraph `node`'s `content` less any task list item marker (Task list items (extension)), which makes its
    /// item a task list item when `node` is the item's first block.
    ///
    /// `trailingSeparator` is the byte after `content` on its line, which follows a marker that fills the content.
    private mutating func taskItemContent(of node: DocumentStorage.Index, content: Chunk, trailingSeparator: UInt8?) -> Chunk {
        guard storage.options.contains(.tasklist),
              let item = storage[node].parent,
              case .item = storage[item].kind,
              storage[item].firstChild == node,
              content.length >= 3,
              readByte(at: content.offset, in: content) == UInt8(ascii: "["),
              readByte(at: content.offset + 2, in: content) == UInt8(ascii: "]"),
              let separator = content.length > 3 ? readByte(at: content.offset + 3, in: content) : trailingSeparator,
              separator.isExtensionScannerSpace else {
            return content
        }
        switch readByte(at: content.offset + 1, in: content) {
        case UInt8(ascii: " "):
            storage[item].kind = .item(checked: false)
        case UInt8(ascii: "x"), UInt8(ascii: "X"):
            storage[item].kind = .item(checked: true)
        default:
            return content
        }
        return content.extracting(min(4, content.length)..<content.length).trimmingWhitespace(using: self)
    }

    /// Matches a footnote definition opener `[^label]:`, whose label holds no whitespace or unescaped bracket, returning
    /// the label and where the definition's content begins, past any spaces and tabs.
    private func matchFootnoteDefinition(range: Range<Int>, firstNonSpace: Int) -> (label: Chunk, consumedTo: Int)? {
        let end = range.upperBound
        guard firstNonSpace + 1 < end,
              sourceBytes[firstNonSpace] == UInt8(ascii: "["),
              sourceBytes[firstNonSpace + 1] == UInt8(ascii: "^") else {
            return nil
        }
        let labelStart = firstNonSpace + 2
        var i = labelStart
        while i < end {
            let b = sourceBytes[i]
            if b == UInt8(ascii: "]") {
                break
            }
            // As in a link label (Links), a square bracket inside the label must be escaped.
            if b == UInt8(ascii: "[") {
                return nil
            }
            if b == UInt8(ascii: "\\"), i + 1 < end, !sourceBytes[i + 1].isASCIISpace {
                i += 2
                continue
            }
            // A NUL is allowed: it stands for U+FFFD (Insecure characters), which it becomes wherever
            // the label is materialized.
            if b.isASCIISpace {
                return nil
            }
            i += 1
        }
        let labelLen = i - labelStart
        guard labelLen > 0,
              i < end, sourceBytes[i] == UInt8(ascii: "]"),
              i + 1 < end, sourceBytes[i + 1] == UInt8(ascii: ":") else {
            return nil
        }
        var contentStart = i + 2
        while contentStart < end {
            let b = sourceBytes[contentStart]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                break
            }
            contentStart += 1
        }
        return (
            label: Chunk(offset: labelStart, length: labelLen, inSource: true),
            consumedTo: contentStart
        )
    }

    /// Opens a footnote definition under `current`; `finalize` registers it when it closes.
    private mutating func openFootnoteDefinition(label rawLabel: Chunk, firstNonSpace: Int) -> DocumentStorage.Index {
        // A NUL becomes U+FFFD (Insecure characters), as in a reference's paragraph, so the keys match.
        let label = replacingNUL(rawLabel)
        let labelRef = storage.intern(label)
        let fnIdx = addChild(
            kind: .footnoteDefinition,
            parent: current,
            data: .footnoteDefinition(label: labelRef),
            start: firstNonSpace
        )
        storage.footnoteDefinitionOrder.append(fnIdx)
        return fnIdx
    }

    // MARK: Reference Parser
    
    /// Consumes link reference definitions, and with `.attributes` `^[label]: attrs` definitions, from the start of `chunk`, returning the rest. The first definition of a label wins (Link reference definitions).
    private mutating func parseDefinitions(in chunk: Chunk) -> Chunk {
        let endOffset = chunk.offset + chunk.length
        var i = chunk.offset
        while i < endOffset {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "[") {
                guard let after = parseOneLinkDefinition(
                    Chunk(offset: i, length: endOffset - i, inSource: chunk.inSource)
                ) else {
                    break
                }
                i = after
            } else if b == UInt8(ascii: "^"),
                      storage.options.contains(.attributes),
                      i + 1 < endOffset,
                      readByte(at: i + 1, in: chunk) == UInt8(ascii: "[") {
                guard let after = parseOneAttributeDefinition(
                    Chunk(offset: i, length: endOffset - i, inSource: chunk.inSource)
                ) else {
                    break
                }
                i = after
            } else {
                break
            }
        }
        return Chunk(offset: i, length: endOffset - i, inSource: chunk.inSource)
    }

    private func isBlank(chunk: Chunk) -> Bool {
        chunk.trimmingWhitespace(using: self).isEmpty
    }

    // MARK: - Link definition

    /// Parses one link reference definition, returning the offset past it and its line ending.
    private mutating func parseOneLinkDefinition(_ chunk: Chunk) -> Int? {
        let end = chunk.range.upperBound
        let inSource = chunk.inSource
        guard let (label, i) = matchDefinitionLabel(chunk) else {
            return nil
        }
        guard let dest = matchLinkDestination(
            Chunk(offset: i, length: end - i, inSource: inSource)
        ) else {
            return nil
        }
        // In inline-only mode a destination that runs to the end of the content forms no definition, so a
        // lone `[a]: /u` stays literal text while `[a]: /u "t"` is consumed.
        if storage.options.contains(.inlineOnly), dest.afterEnd >= end {
            return nil
        }
        // When the line doesn't end after a title, the definition ends at the destination instead.
        let beforeTitle = dest.afterEnd
        let afterTitleSpnl = skipSpacesAndOneLineEnd(from: beforeTitle, in: chunk)
        var titleChunk: Chunk = .empty
        var afterAll = -1
        if afterTitleSpnl > beforeTitle,
           let title = matchLinkTitle(
               Chunk(offset: afterTitleSpnl, length: end - afterTitleSpnl, inSource: inSource)
           ) {
            let afterSpaces = skipLineWhitespace(from: title.afterEnd, in: chunk)
            if let lineEnd = skipLineEndOrEOF(from: afterSpaces, in: chunk) {
                titleChunk = title.chunk
                afterAll = lineEnd
            }
        }
        if afterAll < 0 {
            let afterSpaces = skipLineWhitespace(from: dest.afterEnd, in: chunk)
            guard let lineEnd = skipLineEndOrEOF(from: afterSpaces, in: chunk) else {
                return nil
            }
            afterAll = lineEnd
        }
        // `normalizeLabel` replaces a NUL itself (Insecure characters), so the key matches a reference's even
        // in content `drainLeaf` hasn't NUL-replaced yet (the setext underline path).
        let key = normalizeLabel(chunk: label)
        if key.isEmpty {
            return nil
        }
        if storage.referenceMap[key] == nil {
            // A NUL becomes U+FFFD (Insecure characters). The content may not be NUL-replaced yet, so it is done
            // here, where every stored definition passes.
            let destination = replacingNUL(cleanURLChunk(dest.chunk))
            let title = replacingNUL(unescapeURLChunk(titleChunk))
            storage.referenceMap[key] = ReferenceDefinition(
                destination: destination,
                title: title
            )
        }
        return afterAll
    }

    /// Matches a definition's label and `:` at the start of `chunk`, returning the label's interior and where the
    /// definition's content begins, past whitespace including at most one line ending.
    private mutating func matchDefinitionLabel(_ chunk: Chunk) -> (label: Chunk, contentStart: Int)? {
        guard let label = matchLinkLabel(chunk) else {
            return nil
        }
        let colon = label.afterEnd
        guard colon < chunk.range.upperBound, readByte(at: colon, in: chunk) == UInt8(ascii: ":") else {
            return nil
        }
        return (label.interior, skipSpacesAndOneLineEnd(from: colon + 1, in: chunk))
    }

    // MARK: - Attribute definition

    /// Parses one `^[label]: attrs` definition, returning the offset past it and its line ending.
    private mutating func parseOneAttributeDefinition(_ chunk: Chunk) -> Int? {
        let start = chunk.offset
        let end = chunk.range.upperBound
        let inSource = chunk.inSource
        precondition(start < end && readByte(at: start, in: chunk) == UInt8(ascii: "^"), "an attribute definition is parsed only from a `^`")
        guard let (label, attrsStart) = matchDefinitionLabel(chunk.extracting(1..<chunk.length)) else {
            return nil
        }
        var i = attrsStart
        while i < end {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "\n") {
                break
            }
            i += 1
        }
        let attrsLen = i - attrsStart
        if attrsLen == 0 {
            return nil
        }
        let lineEnd = skipLineEndOrEOF(from: i, in: chunk)
        precondition(lineEnd != nil, "an attribute definition's attributes run to a line end or the content end")
        let afterAll = lineEnd!
        let key = normalizeLabel(chunk: label)
        if key.isEmpty {
            return nil
        }
        if storage.attributeReferenceMap[key] == nil {
            // Trimmed and unescaped like a link destination, with NULs replaced as above.
            let attrs = replacingNUL(cleanURLChunk(Chunk(
                offset: attrsStart,
                length: attrsLen,
                inSource: inSource
            )))
            storage.attributeReferenceMap[key] = attrs
        }
        return afterAll
    }

    /// `chunk` with backslash escapes removed and character references decoded, copied to the arena only if it holds either.
    ///
    /// With `backslashEscapes: false` backslashes stay literal, as in autolinks (Autolinks).
    mutating func unescapeURLChunk(_ chunk: Chunk, backslashEscapes: Bool = true) -> Chunk {
        guard !chunk.isEmpty else {
            return chunk
        }
        
        let endOff = chunk.offset + chunk.length
        var hasEscape = false
        for i in chunk.offset..<endOff {
            let b = readByte(at: i, in: chunk)
            if backslashEscapes, b == UInt8(ascii: "\\"), i + 1 < endOff,
               readByte(at: i + 1, in: chunk).isASCIIPunct {
                hasEscape = true
                break
            }
            if b == UInt8(ascii: "&") {
                hasEscape = true
                break
            }
        }
        if !hasEscape {
            return chunk
        }
        let outOffset = storage.strings.count
        var j = chunk.offset
        while j < endOff {
            let b = readByte(at: j, in: chunk)
            if backslashEscapes, b == UInt8(ascii: "\\"), j + 1 < endOff {
                let next = readByte(at: j + 1, in: chunk)
                if next.isASCIIPunct {
                    storage.strings.append(next)
                    j += 2
                    continue
                }
            }
            if b == UInt8(ascii: "&") {
                let entity = if chunk.inSource {
                    EntityParser.matchEntity(start: j, end: endOff, source: sourceBytes)
                } else {
                    EntityParser.matchEntity(start: j, end: endOff, source: storage.strings.span)
                }
                if let entity {
                    for k in 0..<entity.count {
                        storage.strings.append(entity.bytes[k])
                    }
                    j = entity.afterSemi
                    continue
                }
            }
            storage.strings.append(b)
            j += 1
        }
        return arenaChunk(from: outOffset)
    }

    /// The arena bytes from `offset` to the arena's end, as just appended.
    mutating func arenaChunk(from offset: Int) -> Chunk {
        Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
    }

    /// Trims a link destination's spaces, tabs and line endings, keeping line tabulation and form feed, then unescapes it.
    /// A title is not trimmed, so it uses `unescapeURLChunk`.
    mutating func cleanURLChunk(_ chunk: Chunk) -> Chunk {
        let trimmed = chunk.trimming(using: self)
        return unescapeURLChunk(trimmed)
    }
}

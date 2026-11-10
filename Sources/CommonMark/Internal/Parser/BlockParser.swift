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
        pieceEnds.append(start + piece.length)
    }
}

/// The Markdown parser: the block structure line by line, then each leaf's inline content.
///
/// A method that only reads the parser but calls its other methods is still `mutating`, since a non-mutating method
/// copies the whole parser before each such call.
internal struct BlockParser : ~Copyable, ~Escapable {
    internal var storage: DocumentStorage
    
    internal let sourceBytes: Span<UInt8>
    
    /// The document node, index 0.
    let documentIndex: DocumentStorage.Index

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
        /// Each non-empty line is a source segment, or an arena copy for a code or HTML block line that splits a tab or holds a NUL, and each line join is `newlineSegment`. Used for code and HTML block bodies and for paragraph lines not contiguous in the source.
        case segments(UniqueArray<Segment>)
    }

    /// Result of the code/HTML block continuation handlers: whether the block consumed the line, plus the updated leaf.
    struct LeafContinuation : ~Copyable {
        var consumedLine: Bool
        var pending: PendingLeaf?
    }

    let positionsEnabled: Bool

    /// The source offset before which the line reader has read every byte.
    var sourceReadEnd: Int = 0

    /// No source byte from here up to `sourceReadEnd` is a NUL, so content there needs no NUL replacement.
    var nulFreeSourceStart: Int = 0

    /// Where the open code or HTML block ends unless a closing fence follows: past its last line's content (see
    /// `contentEnd(ofLine:bodyStart:leadingSpaces:)`); for an indented code block, past its last non-blank line
    /// (Indented code blocks); for a fenced code block with only its opening line, past its info string or opening
    /// fence.
    var blockContentEnd: Int = 0

    /// Inline parsing deferred until all blocks close, so a reference resolves against a definition later in the document.
    var pendingInlines: [(DocumentStorage.Index, ContentRef)] = []

    /// Run maps for content that reaches the inline pass as one arena chunk (flattened, NUL-replaced or pipe-unescaped), keyed by node, so its inlines get source positions.
    var arenaSourceMaps: [DocumentStorage.Index: [ArenaRun]] = [:]

    /// What the table check needs to know about the open paragraph, recorded at the first continuation line the
    /// check sees. Only populated with `.tables`.
    struct OpenParagraphTableState {
        let node: DocumentStorage.Index

        /// Whether a line and the next form a table's header and delimiter rows, the delimiter row indented fewer
        /// than four columns and not lazy. The paragraph is then a table, which a lazy continuation line can't
        /// continue, so `processLine` breaks a later line that fails a container's prefix out of the table and that
        /// container.
        var tablePending = false
    }

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

    /// List items whose first block is a removed paragraph that held only definitions or a task list item marker, so
    /// no later paragraph is their first block (Task list items (extension)).
    var itemsWithRemovedFirstParagraph: Set<DocumentStorage.Index> = []

    /// Reset per `parseInline` pass.
    var htmlCloserMisses = HTMLCloserMisses()

    /// Reset per `parseInline` pass.
    var backtickRunsSeen = BacktickRunsSeen()

    /// Reset per `parseInline` pass and per `definitionsEnd` call.
    var destinationParentheses = BalancedParenthesesScan()

    /// Reset per `parseInline` pass.
    var attributeParentheses = BalancedParenthesesScan()

    /// The character references decoded in this `parseInline` pass with `.sourcePosition`, in arena order: each
    /// one's decoded arena range and its source range.
    var characterReferenceSources: [(arena: Range<Int>, source: Range<Int>)] = []

    /// The delimiter stack (see `DelimiterRecord`), topped by `lastDelim` and reused across passes.
    var delimiters = UniqueArray<DelimiterRecord>()
    var lastDelim: Int? = nil

    /// The bracket stack (see `BracketRecord`), topped by `lastBracket` and reused across passes.
    var brackets = UniqueArray<BracketRecord>()
    var lastBracket: Int? = nil

    /// The number of links and autolinks formed in this `parseInline` pass.
    var linksFormed = 0

    /// The `ContentSpan.pieceHint` of every content this parse reads through a segment list or run map.
    let pieceHint = PieceHint()

    // MARK: - Init
    
    @_lifetime(copy source)
    init(storage: consuming DocumentStorage, source: Span<UInt8>) {
        self.storage = storage
        self.sourceBytes = source
        self.positionsEnabled = self.storage.options.contains(.sourcePosition)

        // Reserve the append-only arenas in proportion to the input, so they regrow only for dense input.
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
                let lineRange = reader.lineRange
                if positionsEnabled {
                    storage.lineStarts.append(reader.lineStart)
                }
                noteLineRead(reader)
                pending = processLine(lineRange: lineRange, pending: pending)
            }

            while current != documentIndex {
                pending = finalize(node: current, pending: pending)
            }
            
            // The document node is never finalized, so it is stamped here. An empty document has no source range.
            if positionsEnabled, reader.lineNumber > 0 {
                stampDocument()
            }
        }

        let pending = pendingInlines
        
        var scratch = InlineScratch()

        for (node, ref) in pending {
            precondition(ref.totalLength > 0, "only non-empty content is queued for inline parsing")
            if ref.count == 1 {
                parseInline(chunk: storage.segments[ref.first].chunk, scratch: &scratch, into: node)
            } else {
                // Multi-segment content is parsed from the source through a copy of its segment list.
                scratch.removeAllPieces()
                for i in 0..<ref.count {
                    scratch.append(piece: storage.segments[ref.first + i])
                }
                parseInline(
                    content: ContentSpan(source: sourceBytes, segments: scratch.pieces.span, segmentEnds: scratch.pieceEnds.span, virtualLength: ref.totalLength, hint: pieceHint),
                    into: node
                )
            }

            let image: ContentImage?
            if positionsEnabled, ref.count == 1, case let chunk = storage.segments[ref.first].chunk, !chunk.inSource, let map = arenaSourceMaps[node] {
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
    /// ones, out of any container, to the end of the document in the order of their numbers.
    ///
    /// A reference inside a dropped definition counts, so the definition it resolves to is kept, though the reference
    /// is dropped with the definition holding it.
    private mutating func processFootnotes() {
        guard storage.options.contains(.footnotes) else { return }
        // A footnote reference exists only where its label resolves to a footnote definition.
        guard !storage.footnoteDefinitionOrder.isEmpty else { return }
        let referencedDefs = numberFootnoteReferences()
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
    private mutating func numberFootnoteReferences() -> [DocumentStorage.Index] {
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

    /// Parses `node`'s inline content in `chunk`. Arena content, with its run map from `arenaSourceMaps` when it has one, is parsed from a copy, since `parseInline` appends to the arena.
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
            content: ContentSpan(span: scratch.bytes.span, base: chunk.offset, runs: scratch.pieces.span, runEnds: scratch.pieceEnds.span, hint: pieceHint),
            into: node,
            preserveWhitespace: preserveWhitespace
        )
    }

    /// The `.inlineOnly` and `.preserveWhitespace` parse.
    ///
    /// Any non-empty input, even a lone BOM, becomes one paragraph holding the source after any BOM and any leading
    /// definitions, with line endings normalized to `\n` and each NUL replaced with U+FFFD (Insecure characters). The
    /// rest is parsed as inline content only: a line ending is text, except after a backslash, where it is a hard line
    /// break.
    private mutating func parseInlineOnly() {
        let count = sourceBytes.count
        guard count > 0 else {
            return
        }

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
                storage.lineStarts.append(reader.lineStart)
            }
            contentEnd = reader.lineRange.upperBound
            hasCR = hasCR || (contentEnd < count && sourceBytes[contentEnd] == UInt8(ascii: "\r"))
            noteLineRead(reader)
        }
        storage.lineCount = reader.lineNumber

        // Link reference definitions leading the content are consumed, and the paragraph is kept even when
        // nothing, or only whitespace, remains. It starts at its first content byte and ends where the last line's
        // content ends, so with no content before that its range is empty there.
        let paragraph = addChild(kind: .paragraph, parent: documentIndex, start: start)
        storage.setSourceEnd(paragraph, contentEnd)
        var contentStart = contentEnd
        if positionsEnabled {
            stampDocument()
        }

        // A NUL becomes U+FFFD (Insecure characters), which forces the arena copy below.
        let hasNUL = containsNUL(Chunk(offset: start, length: contentEnd - start, inSource: true))
        // The arena copy's source image, for the email autolink pass.
        var image: ContentImage? = nil
        var scratch = InlineScratch()
        if !hasCR && !hasNUL {
            let rest = parseDefinitions(in: Chunk(offset: start, length: count - start, inSource: true))
            contentStart = rest.offset
            parseInline(chunk: rest, scratch: &scratch, into: paragraph, preserveWhitespace: true)
        } else {
            // Copy the content to the arena with line endings normalized to `\n` and NULs to U+FFFD. With `.sourcePosition`,
            // record its run map: a CRLF's `\n` images its LF, so a node ending at the break covers the CRLF, as for LF input (a
            // node starting there is moved to the CR when stamped), and each of a U+FFFD's three bytes images its NUL.
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
                arenaSourceMaps[paragraph] = Self.sliceRuns(runs, from: rest.offset - arenaStart, length: rest.length)
            }
            parseInline(
                chunk: rest,
                scratch: &scratch,
                into: paragraph,
                preserveWhitespace: true
            )
            if positionsEnabled {
                let arenaImage = ContentImage(base: arenaStart, runs: runs)
                if let restStart = arenaImage.sourceOffset(ofArenaByte: rest.offset) {
                    contentStart = lineEndingStart(restStart)
                }
                image = arenaImage
            }
        }
        storage.setSourceStart(paragraph, min(contentStart, contentEnd))
        finishInlines(paragraph, image: image)
        if positionsEnabled {
            endInlinesWithinLastLine(after: paragraph, contentEnd: contentEnd)
        }
    }

    /// Stamps the document with the whole input, any BOM included, and records the start of the line after the last
    /// when the input ends in a line ending, since the end of such input is column 1 of that line.
    private mutating func stampDocument() {
        let end = sourceBytes.count
        storage.setSourceStart(documentIndex, 0)
        storage.setSourceEnd(documentIndex, end)
        if sourceBytes[end - 1] == UInt8(ascii: "\n") || sourceBytes[end - 1] == UInt8(ascii: "\r") {
            storage.lineStarts.append(end)
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

    /// Where a node whose first byte images source byte `offset` starts: at `offset`, or at the CR before it when it is
    /// a CRLF's LF, which the `\n` standing for that CRLF images.
    func lineEndingStart(_ offset: Int) -> Int {
        offset > 0 && sourceBytes[offset] == UInt8(ascii: "\n") && sourceBytes[offset - 1] == UInt8(ascii: "\r") ? offset - 1 : offset
    }

    /// Extends a run map by one byte imaging `sourceOffset`, or by a line-join byte when `sourceOffset < 0`.
    @inline(__always)
    fileprivate static func appendContentByte(imaging sourceOffset: Int, to runs: inout [ArenaRun]) {
        if let last = runs.last {
            let length = last.length
            let continuesGap = sourceOffset < 0 && last.sourceOffset < 0
            let continuesRun = sourceOffset >= 0 && last.sourceOffset >= 0
                && last.sourceOffset + length == sourceOffset
            if continuesGap || continuesRun {
                runs[runs.count - 1].length += 1
                return
            }
        }
        runs.append(ArenaRun(length: 1, sourceOffset: sourceOffset))
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
            // A line directly after the previous range across a lone `\n` extends it, so a paragraph of unindented LF
            // lines stays one zero-copy range. Anything stripped between the lines, such as a container prefix or
            // indentation, or a CR, falls through to segments.
            switch consume existing {
            case .lazy(let prev, joinPending: true) where range.lowerBound == prev.upperBound + 1
                    && prev.upperBound < sourceBytes.count
                    && sourceBytes[prev.upperBound] == UInt8(ascii: "\n"):
                return PendingLeaf(node: node, content: .lazy(range: prev.lowerBound..<range.upperBound))
            case .lazy(let prev, joinPending: true):
                // The previous range becomes a source segment, joined to this line by `newlineSegment`.
                var segs = UniqueArray<Segment>()
                segs.append(Segment(offset: prev.lowerBound, length: prev.count, inSource: true))
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
        return appendSegment(Segment(offset: range.lowerBound, length: range.upperBound - range.lowerBound, inSource: true), to: node, pending: pending)
    }

    /// Appends the rest of a code or HTML block line from `bodyStart`, after `leadingSpaces` spaces from a split tab.
    private mutating func appendLiteralBodyLine(bodyStart: Int, leadingSpaces: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // The line reader has read the line, so a line not known to be free of NUL holds one.
        if leadingSpaces == 0 && isKnownFreeOfNUL(Chunk(offset: bodyStart, length: lineEnd - bodyStart, inSource: true)) {
            return addLine(range: bodyStart..<lineEnd, to: node, pending: pending)
        }
        return appendLiteralLineCopy(spaces: leadingSpaces, sourceStart: bodyStart, lineEnd: lineEnd, to: node, pending: pending)
    }

    /// Where a code or HTML block line's content ends: at the line's end, or at its start when stripping the container
    /// prefixes and indentation left no content, so a block ending with that line ends just past the line before.
    private func contentEnd(ofLine lineRange: Range<Int>, bodyStart: Int, leadingSpaces: Int) -> Int {
        bodyStart < lineRange.upperBound || leadingSpaces > 0 ? lineRange.upperBound : lineRange.lowerBound
    }

    /// Where the rest of an HTML block line from `cursor` begins, given the `column` the container prefixes reached,
    /// and how many spaces a split tab contributes.
    ///
    /// `cursor` is mid-tab when a block quote marker's optional space or a list item's indent consumed part of a tab;
    /// the tab's leftover columns become spaces (Tabs).
    private func htmlLineBody(lineRange: Range<Int>, cursor: Int, column: Int) -> (bodyStart: Int, leadingSpaces: Int) {
        let priorColumn = columnWidth(from: lineRange.lowerBound, to: cursor)
        return stripIndent(
            range: cursor..<lineRange.upperBound,
            maxColumns: column - priorColumn,
            startColumn: priorColumn
        )
    }

    /// Appends `spaces` spaces and the source bytes `[sourceStart, lineEnd)`, each NUL replaced with U+FFFD (Insecure
    /// characters), as one arena segment, for a code or HTML block line whose stripped indent split a tab (Tabs) or that
    /// holds a NUL. The finalize normalizers rely on one segment per line.
    private mutating func appendLiteralLineCopy(spaces: Int, sourceStart: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        let offset = storage.strings.count
        for _ in 0..<spaces {
            storage.strings.append(UInt8(ascii: " "))
        }
        appendReplacingNUL(sourceBytes.extracting(sourceStart..<lineEnd))
        return appendSegment(
            Segment(offset: offset, length: storage.strings.count - offset, inSource: false),
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
        // A line join is the interned `"\n"`, so only lines are scanned.
        let lineJoin = storage.newlineSegment
        for i in 0..<segs.count where segs[i] != lineJoin && containsNUL(segs[i].chunk) {
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

    mutating func appendReplacementCharacter() {
        storage.strings.append(0xEF)
        storage.strings.append(0xBF)
        storage.strings.append(0xBD)
    }

    /// `replacingNUL(_:)` that also updates `chunk`'s run map `map`: each of a U+FFFD's three bytes images its NUL. Without `.sourcePosition`, `map` is untouched.
    private mutating func replacingNUL(_ chunk: Chunk, map: inout [ArenaRun]) -> Chunk {
        guard containsNUL(chunk) else { return chunk }
        if positionsEnabled {
            map = rewrittenMap(sourceImage(of: chunk, map: map), of: chunk) { readByte(at: $0, in: chunk) == 0 ? 3 : 1 }
        }
        return copyReplacingNUL(chunk)
    }

    /// `chunk`'s run map `map` after a rewrite that turns `chunk`'s byte at each offset into `copies(offset)` bytes,
    /// each imaging what that byte images. An empty `map` stays empty.
    func rewrittenMap(_ map: [ArenaRun], of chunk: Chunk, copies: (Int) -> Int) -> [ArenaRun] {
        assert(map.isEmpty || map.reduce(0) { $0 + $1.length } == chunk.length, "a run map must tile its chunk")
        var rewritten: [ArenaRun] = []
        var i = chunk.offset
        for run in map {
            for local in 0..<run.length {
                let sourceOffset = run.sourceOffset < 0 ? -1 : run.sourceOffset + local
                for _ in 0..<copies(i) {
                    Self.appendContentByte(imaging: sourceOffset, to: &rewritten)
                }
                i += 1
            }
        }
        return rewritten
    }

    /// `chunk`'s run map: `map`, or for source content with an empty `map`, the one run imaging its own range.
    func sourceImage(of chunk: Chunk, map: [ArenaRun]) -> [ArenaRun] {
        if map.isEmpty, chunk.inSource, chunk.length > 0 {
            return [ArenaRun(length: chunk.length, sourceOffset: chunk.offset)]
        }
        return map
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

    /// Where the open paragraph's last line begins in its pending `leaf`: the source offset in a `.lazy` range, or the
    /// index of the line's first segment in a segment list.
    private func lastLineStart(of leaf: borrowing PendingLeaf) -> Int {
        switch leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            return lastNewline(in: range).map { $0 + 1 } ?? range.lowerBound
        case .segments(let segs):
            return lastLineJoin(in: segs) + 1
        }
    }

    /// Whether the open paragraph's last line, from `lastLineStart` (see `lastLineStart(of:)`), and the
    /// delimiter-candidate line `sourceBytes[delimRange]` open a table (Tables (extension)).
    private mutating func lastLineOpensTable(delimRange: Range<Int>, pending: borrowing PendingLeaf, lastLineStart: Int) -> Bool {
        let header: Range<Int>
        switch pending.content {
        case .lazy(let range, _):
            header = lastLineStart..<range.upperBound
        case .segments(let segs):
            let lastLine = segs[segs.count - 1]
            precondition(lastLineStart == segs.count - 1 && lastLine.inSource, "a paragraph's last line is the source segment after its last line join")
            header = lastLine.chunk.range
        }
        return opensTable(header: header, delimiter: delimRange)
    }

    /// Sets `tablePending` when delimiter-candidate line `sourceBytes[delimRange]` opens a table whose header is the open
    /// paragraph's last line, since a table has one header row (Tables (extension)). Otherwise the paragraph continues,
    /// and a later line can still open one.
    ///
    /// Earlier lines are split off into a paragraph before `node`, which is re-seeded with the header line alone.
    private mutating func detectPendingTable(_ node: DocumentStorage.Index, delimRange: Range<Int>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        let headerStart = lastLineStart(of: pending!)
        guard lastLineOpensTable(delimRange: delimRange, pending: pending!, lastLineStart: headerStart) else {
            return pending
        }
        openParagraphTableState!.tablePending = true
        let leaf = pending!
        switch consume leaf.content {
        case .lazy(let range, _):
            guard headerStart > range.lowerBound else {
                return PendingLeaf(node: node, content: .lazy(range: range))
            }
            return splitContiguousHeader(node, range: range, lastNewline: headerStart - 1)
        case .segments(let segs):
            return splitSegmentHeader(node, segments: segs, lineJoin: headerStart - 1)
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
        if let precedingChunk = tableSplitParagraphContent(precedingLines.trimmingWhitespace(using: self), node: node) {
            let preceding = insertTablePrecedingParagraph(before: node)
            // With no raw content, the paragraph's range is empty at its start.
            let span = precedingChunk.isEmpty ? Chunk(offset: precedingLines.offset, length: 0, inSource: true) : precedingChunk
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
    /// become a paragraph before `node`, unless their definitions or task list item marker leave nothing.
    private mutating func splitSegmentHeader(_ node: DocumentStorage.Index, segments: consuming UniqueArray<Segment>, lineJoin: Int) -> PendingLeaf? {
        var segs = segments
        var header = UniqueArray<Segment>()
        for i in (lineJoin + 1)..<segs.count {
            header.append(segs[i])
        }
        segs.removeSubrange(lineJoin..<segs.count)
        let precedingNode = insertTablePrecedingParagraph(before: node)
        if positionsEnabled {
            let span = segmentsSourceSpan(segs)
            storage.setSourceStart(precedingNode, span.start)
            storage.setSourceEnd(precedingNode, span.end)
        }
        // These lines bypass `drainLeaf`, so a NUL in them forces a flatten here, since a segment list can't carry
        // the U+FFFD (see `ContentSpan`).
        if segmentsContainNUL(segs) {
            var map: [ArenaRun] = []
            let flat = flattenSegments(segs, map: &map)
            if let content = tableSplitParagraphContent(flat.trimmingWhitespace(using: self), node: precedingNode) {
                let contentMap = positionsEnabled ? Self.sliceRuns(map, from: content.offset - flat.offset, length: content.length) : []
                if positionsEnabled, !content.isEmpty {
                    let span = sourceSpan(of: contentMap)
                    storage.setSourceStart(precedingNode, span.start)
                    storage.setSourceEnd(precedingNode, span.end)
                } else {
                    emptySourceRangeAtStart(precedingNode)
                }
                enqueueTablePrecedingContent(content, map: contentMap, of: precedingNode)
            } else {
                storage.unlinkChild(precedingNode)
            }
        } else if case let total = totalLength(of: segs), let content = rawContentRange(in: segs, total: total, taskItemParagraph: precedingNode) {
            if content.isEmpty {
                storage.unlinkChild(precedingNode)
            } else {
                enqueueRawContent(of: precedingNode, self.segments(segs, in: content, total: total))
            }
        } else {
            emptySourceRangeAtStart(precedingNode)
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
        return (first.offset, last.offset + last.length)
    }

    /// The source offset just past virtual offset `end - 1` of a paragraph's segments, `total` bytes long, a byte that
    /// is not whitespace.
    private func sourceEnd(ofVirtual end: Int, in segs: borrowing UniqueArray<Segment>, total: Int) -> Int {
        precondition(end > 0, "a paragraph's content that is not whitespace is not empty")
        let (i, segmentStart) = segment(endingAtOrAfter: end, in: segs, total: total)
        precondition(segs[i].inSource, "a paragraph's lines start and end on a source byte")
        return segs[i].offset + end - segmentStart
    }

    /// The index and virtual start of the segment of `segs`, `total` bytes long, that holds the byte before virtual
    /// offset `end`.
    ///
    /// It is searched for from the end, since the end of a leaf's trimmed lines lies in or near its last line.
    private func segment(endingAtOrAfter end: Int, in segs: borrowing UniqueArray<Segment>, total: Int) -> (index: Int, start: Int) {
        var i = segs.count - 1
        var start = total - segs[i].length
        while start >= end {
            i -= 1
            start -= segs[i].length
        }
        return (i, start)
    }

    /// The source span imaged by the run map of trimmed paragraph content: from its first run's byte to just past
    /// its last run's.
    private func sourceSpan(of map: [ArenaRun]) -> (start: Int, end: Int) {
        guard let first = map.first, let last = map.last, first.sourceOffset >= 0, last.sourceOffset >= 0 else {
            preconditionFailure("trimmed paragraph content starts and ends on source bytes")
        }
        return (first.sourceOffset, last.sourceOffset + last.length)
    }

    // MARK: - Per-line dispatcher

    /// Processes the line at `lineRange`.
    private mutating func processLine(lineRange: Range<Int>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let walk = walkOpenContainers(lineRange: lineRange)
        let deepestMatched = walk.deepestMatched
        let cursor = walk.cursor
        let prefixColumns = walk.prefixColumns
        let allMatched = walk.allMatched

        let openKind = storage[current].kind
        if openKind.isCodeBlock || openKind == .htmlBlock {
            let leaf = continueOrCloseLeafBlock(lineRange: lineRange, cursor: cursor, prefixColumns: prefixColumns, allMatched: allMatched, pending: pending)
            let consumedLine = leaf.consumedLine
            pending = leaf.pending
            if consumedLine {
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

        if scan.isBlank {
            return handleBlankLine(deepestMatched: deepestMatched, allMatched: allMatched, pending: pending)
        }
        // The containers that matched a non-blank line, and their ancestors, no longer end with a blank line. One that failed keeps its flag, since this line closes it.
        var clearUp: DocumentStorage.Index? = deepestMatched
        while let clearUp_ = clearUp {
            storage.nodes[clearUp_].lastLineBlank = false
            clearUp = storage[clearUp_].parent
        }

        if underlineParagraph(line: &line, pending: &pending) {
            return pending
        }

        if absorbParagraphLine(line: line, pending: &pending) {
            return pending
        }

        while current != deepestMatched {
            pending = finalize(node: current, pending: pending)
        }

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
        /// The source offset past the stripped container prefixes.
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

    /// An open code block or HTML block consumes the line when the prefix walk reached it: as content, which closes an HTML block when it meets the block's end condition, or as a closing fence. A line that the block can't take, or that the walk failed before reaching the block, closes it, and `consumedLine` is `false` so `processLine` treats the line as it would with no such block open.
    private mutating func continueOrCloseLeafBlock(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, allMatched: Bool, pending: consuming PendingLeaf?) -> LeafContinuation {
        guard allMatched else {
            return LeafContinuation(consumedLine: false, pending: finalize(node: current, pending: pending))
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
        assert(openParagraphTableState.map { $0.node == current } ?? true, "the recorded table state belongs to the open leaf")
        return openParagraphTableState?.tablePending == true
    }

    /// Turns the open paragraph into a setext heading when the line underlines it (Setext headings). Returns whether the line is done: it formed a heading, or continued a paragraph holding only definitions.
    ///
    /// A table-pending paragraph is a table, so a `-` or `=` line can't underline it (`r\n|-\n=` is a table with a `=` body row).
    private mutating func underlineParagraph(line: inout LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        guard line.openKind == .paragraph && line.allMatched && !openParagraphIsTablePending && line.indent < 4,
              let underline = matchSetextUnderline(range: line.cursor..<lineRange.upperBound, firstNonSpace: line.firstNonSpace) else {
            return false
        }
        let para = current
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        // Leading link reference definitions come out first; if they are the whole paragraph, no heading forms.
        let content = headingContentRange(of: pending!)
        if !content.isEmpty {
            makeHeading(para, level: underline.level, content: narrowedContent(pending.take()!, to: content), underlineEnd: underline.end)
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
            interruptsParagraph: true
        )
        if continuesParagraph {
            // The leading definitions are registered already; the paragraph's finalize, or the split of a table that
            // forms first, strips them from its content.
            pending = appendNewline(to: para, pending: consume pending)
            pending = addLine(range: line.firstNonSpace..<lineRange.upperBound, to: para, pending: consume pending)
            return true
        }
        // Only definitions: drop the paragraph and dispatch the line as a new block. That block opens in the same
        // container, past the definitions, so they need not extend the container's range.
        pending = nil
        removeEmptiedParagraph(para, contentEnd: nil)
        openParagraphTableState = nil
        guard let parent = storage[para].parent else {
            fatalError("a paragraph always has a parent")
        }
        current = parent
        line.openKind = storage[current].kind
        return false
    }

    /// Where a setext heading's raw content (Setext headings) lies in the open paragraph's pending `leaf`: past its
    /// leading definitions and the whitespace after them, up to its trailing whitespace. The offsets are source offsets
    /// for a `.lazy` range and virtual offsets for a segment list.
    private mutating func headingContentRange(of leaf: borrowing PendingLeaf) -> Range<Int> {
        switch leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            let trimmed = Chunk(offset: range.lowerBound, length: range.count, inSource: true).trimmingWhitespace(using: self)
            return parseDefinitions(in: trimmed).trimmingWhitespace(using: self).range
        case .segments(let segs):
            return rawContentRange(in: segs, total: totalLength(of: segs), taskItemParagraph: nil) ?? 0..<0
        }
    }

    /// `leaf`'s content narrowed to `range`, in the offsets `headingContentRange` returns.
    private func narrowedContent(_ leaf: consuming PendingLeaf, to range: Range<Int>) -> PendingContent {
        switch consume leaf.content {
        case .lazy:
            return .lazy(range: range)
        case .segments(let segs):
            let total = totalLength(of: segs)
            return .segments(segments(segs, in: range, total: total))
        }
    }

    /// Turns the open paragraph into a `level` heading holding `content` and closes it, since no line continues a
    /// heading. The heading ends at `underlineEnd`, past its underline's last marker character.
    private mutating func makeHeading(_ para: DocumentStorage.Index, level: UInt8, content: consuming PendingContent, underlineEnd: Int) {
        storage[para].kind = .heading(level: Int(level))
        openParagraphTableState = nil
        if positionsEnabled {
            switch content {
            case .lazy(let range, _):
                storage.setSourceStart(para, range.lowerBound)
            case .segments(let segs):
                storage.setSourceStart(para, segmentsSourceSpan(segs).start)
            }
        }
        _ = finalize(node: para, pending: PendingLeaf(node: para, content: content))
        if positionsEnabled {
            storage.setSourceEnd(para, underlineEnd)
        }
    }

    /// Whether the open paragraph absorbs the line as a continuation; otherwise the line starts a block that closes it.
    ///
    /// A table-pending paragraph is a table, so a line that can't be a row closes it and its container: a lazy continuation
    /// line, a lone `|`, which has no cells, or a line indented four or more columns, which starts an indented code block
    /// because a table is not a paragraph (Indented code blocks).
    private mutating func absorbParagraphLine(line: LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        let tablePending = openParagraphIsTablePending
        let breaksOutOfPendingTable = tablePending
            && (!line.allMatched
                || line.indent >= 4
                || isLonePipeRow(range: line.firstNonSpace..<lineRange.upperBound))
        if line.openKind != .paragraph || breaksOutOfPendingTable {
            return false
        }
        // `mightStartBlock` covers the first byte of every block start `lineStartsNewBlock` matches, so a line starting
        // with any other byte skips the matchers. The limits on a list marker interrupting a paragraph (List items)
        // apply only when the paragraph's own container matched: in `1. a\n2. b` the item didn't, so `2.` opens an
        // item. A table is no paragraph, so the limits on interrupting one (List items, Lists) don't apply: `r\n|-\n-`
        // is a table and a list.
        let interruptsParagraph = !tablePending
            && storage[current].parent == line.deepestMatched
        let canInterrupt = Self.mightStartBlock(line.firstNonSpaceByte)
            && lineStartsNewBlock(
                range: line.cursor..<lineRange.upperBound,
                firstNonSpace: line.firstNonSpace,
                indent: line.indent,
                baseColumn: line.prefixColumns,
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

    /// Checks whether a continuation line opens a table with the paragraph's last line as its header (see
    /// `detectPendingTable`).
    ///
    /// Inlined because it runs on every paragraph continuation line: out of line, it costs about 0.3% of the spec
    /// text's parse instructions with tables enabled.
    @inline(__always)
    private mutating func recordTableDelimiterCandidate(line: LineContext, pending: inout PendingLeaf?) {
        let delimRange = line.firstNonSpace..<line.lineRange.upperBound
        if openParagraphTableState == nil {
            openParagraphTableState = OpenParagraphTableState(node: current)
        }
        assert(openParagraphTableState!.node == current, "the recorded state belongs to the open paragraph")
        // The first such line that opens a table sets `tablePending`, ending the search. `couldBeDelimiterRow` keeps
        // ordinary prose out of the table check.
        if !openParagraphTableState!.tablePending,
           line.indent < 4, line.allMatched,
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
        // The offset of the first byte at or after `cursor` that is not a space or tab, valid while `cursor` has not
        // passed it. Containers that consume only spaces and tabs leave it unchanged, so a chain of nested items scans
        // the line's indent once.
        var firstNonSpaceAhead = -1

        // Descend from the document to `current` through each open block's last child, which is its open child. A
        // line stops at the first container whose prefix it fails, so it visits no container inside that one.
        var node = documentIndex
        // The list items and footnote definitions continued with nothing left of the line.
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
                    (cursor, prefixColumns) = blockQuotePrefixEnd(
                        lineColumns: &lineColumns,
                        markerEnd: firstNonSpace + 1,
                        advanced: advanced
                    )
                    storage.setSourceEnd(node, firstNonSpace + 1)
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
                // A list item can begin with at most one blank line (List items), so a blank line closes an item
                // that holds no block yet, however far the line is indented. A removed paragraph that held only
                // definitions or a task list item marker counts as a block.
                if isBlank, isItem, storage[node].firstChild == nil, itemsEndingInRemovedParagraph[node] == nil {
                    return (deepestMatched, cursor, prefixColumns, false)
                }
                let padding = isItem ? itemPadding(of: node) : 4
                // Columns, not bytes, measured from `prefixColumns`, since a tab's width depends on the column it
                // starts at (Tabs). Each whitespace byte spans at least one column, so `padding` bytes decide.
                let availCols = indentColumns(from: cursor, to: min(firstNonSpace, cursor + padding), baseColumn: prefixColumns)
                if availCols >= padding {
                    cursor = advanceColumns(
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: padding,
                        baseColumn: prefixColumns
                    )
                    // Record the intended column even when a straddling tab kept `cursor` from passing it (Tabs).
                    prefixColumns += padding
                    deepestMatched = node
                } else if isBlank {
                    // The rest of the line is blank, so deeper containers see nothing left of it.
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
    /// `interruptsParagraph` is `false` when the paragraph's own container failed to match or the paragraph is a table,
    /// so the limits on interrupting a paragraph don't apply.
    private mutating func lineStartsNewBlock(range: Range<Int>, firstNonSpace: Int, indent: Int, baseColumn: Int, interruptsParagraph: Bool) -> Bool {
        // A line indented four or more columns starts no block that interrupts a paragraph.
        if indent >= 4 {
            return false
        }
        var noBreakBefore = 0
        if matchThematicBreak(range: range, firstNonSpace: firstNonSpace, noBreakBefore: &noBreakBefore) != nil {
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
        return false
    }

    /// Continues an open HTML block. `consumedLine` is `false` for the blank line that ends a type 6 or 7 block, which
    /// is left to blank-line handling.
    private mutating func handleHTMLBlockContinuation(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        guard case .htmlBlock(let type, _) = storage[current].data else {
            preconditionFailure("an HTML block node always carries its block type")
        }
        // Types 6 and 7 end at a blank line, which is not part of the block.
        if type >= 6, indexOfFirstNonSpace(range: cursor..<lineRange.upperBound) == lineRange.upperBound {
            return LeafContinuation(consumedLine: false, pending: finalize(node: current, pending: pending))
        }
        // Every other line belongs to the block; for types 1–5, the one meeting the end condition closes the block and
        // is consumed.
        pending = appendNewline(to: current, pending: pending)
        let (bodyStart, leadingSpaces) = htmlLineBody(lineRange: lineRange, cursor: cursor, column: prefixColumns)
        blockContentEnd = contentEnd(ofLine: lineRange, bodyStart: bodyStart, leadingSpaces: leadingSpaces)
        pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
        if htmlBlockLineMatchesEndCondition(
            type: type,
            range: cursor..<lineRange.upperBound
        ) {
            pending = finalize(node: current, pending: pending)
        }
        return LeafContinuation(consumedLine: true, pending: pending)
    }

    /// Continues an open code block. `consumedLine` is `false` when the line is left for new-block dispatch; a closing fence is consumed.
    private mutating func handleCodeBlockContinuation(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        let firstNonSpace = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound

        if case .codeBlock(let info) = storage[current].kind, info.isFenced {
            // A closing fence's indent is in columns past the container prefixes, so a tab counts to its tab stop (Tabs).
            let closingFenceIndent =
                columnWidth(from: lineRange.lowerBound, to: firstNonSpace) - prefixColumns
            if let fenceEnd = matchClosingFence(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indentColumns: closingFenceIndent,
                expectedChar: info.fenceCharacter,
                minimumLength: info.fenceLength
            ) {
                pending = finalize(node: current, pending: pending, lineContentEnd: fenceEnd)
                return LeafContinuation(consumedLine: true, pending: pending)
            }
            // A tab a container consumed only partly is split here, its leftover columns becoming spaces (Tabs).
            pending = appendNewline(to: current, pending: pending)
            let startColumn = columnWidth(from: lineRange.lowerBound, to: cursor)
            let (bodyStart, leadingSpaces) = stripIndent(
                range: cursor..<lineRange.upperBound,
                maxColumns: prefixColumns + info.fenceOffset - startColumn,
                startColumn: startColumn
            )
            blockContentEnd = contentEnd(ofLine: lineRange, bodyStart: bodyStart, leadingSpaces: leadingSpaces)
            pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
            return LeafContinuation(consumedLine: true, pending: pending)
        }
        // Measured from `prefixColumns`, so a tab the prefixes partly consumed counts only its remaining columns (Tabs).
        let indent = indentColumns(from: cursor, to: firstNonSpace, baseColumn: prefixColumns)
        // A blank line keeps its whitespace past four columns as content.
        if indent >= 4 || isBlank {
            // Blank lines that end the block are not part of it, so for list tightness the block ends with a blank line until a further code line follows.
            storage.nodes[current].lastLineBlank = isBlank
            pending = appendNewline(to: current, pending: pending)
            if !isBlank {
                blockContentEnd = lineRange.upperBound
            }
            if indent > 4 || !isBlank {
                // A tab straddling the fourth column is split: its leftover columns become leading spaces (Tabs).
                let (bodyStart, leadingSpaces) = stripIndent(
                    range: cursor..<lineRange.upperBound,
                    maxColumns: 4,
                    startColumn: prefixColumns
                )
                pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
            }
            return LeafContinuation(consumedLine: true, pending: pending)
        }
        pending = finalize(node: current, pending: pending)
        return LeafContinuation(consumedLine: false, pending: pending)
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
        storage.setSourceEnd(itemIdx, marker.markerEnd)
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
        // The matchers and openers this calls that are marked `@inline(__always)` cost 0.8% to 1.9% of the instructions
        // of a parse of `Benchmarks/100kb-test-content.md` out of line.
        var pending = pending
        var cursor = startCursor
        var column = startColumn
        var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
        var noThematicBreakBefore = startCursor
        while true {
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
                pending = closingOpenList(pending)
                let quoteIdx = addChild(
                    kind: .blockQuote,
                    parent: current,
                    start: firstNonSpace
                )
                storage.setSourceEnd(quoteIdx, firstNonSpace + 1)
                current = quoteIdx
                (cursor, column) = blockQuotePrefixEnd(
                    lineColumns: &lineColumns,
                    markerEnd: firstNonSpace + 1,
                    advanced: advanced
                )
                continue
            }

            // Before list markers, so `- - -` is a thematic break rather than nested lists. A marker before
            // `noThematicBreakBefore` skips the scan, so the nested markers of `- - - … x` scan the line once.
            if indent < 4, firstNonSpace >= noThematicBreakBefore, let breakEnd = matchThematicBreak(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                noBreakBefore: &noThematicBreakBefore
            ) {
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

            // Indents are in columns, so a marker a tab pushes four columns in, though fewer bytes, is indented code.
            if indent < 4, let marker = matchListMarker(
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

            pending = closingOpenList(pending)

            // An indented line continues an open paragraph, so here, where none is open, it starts an indented code
            // block (Indented code blocks). A fence a tab pushes four columns in is indented code: in `>~~~` then
            // `\t~~~`, the second line closes the block quote and its fenced code block, and opens an indented code
            // block holding `~~~`.
            if indent >= 4 {
                return openIndentedCode(lineRange: lineRange, cursor: cursor, column: column, pending: pending)
            }

            if let heading = matchATXHeading(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                return openATXHeading(heading, firstNonSpace: firstNonSpace, pending: pending)
            }

            if let fence = matchOpeningFence(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indent: indent
            ) {
                openFencedCode(fence, cursor: cursor, firstNonSpace: firstNonSpace)
                return pending
            }

            // No open paragraph remains here for a type 7 start to interrupt (HTML blocks).
            if let htmlType = matchHTMLBlockStart(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                allowType7: true
            ) {
                return openHTMLBlock(htmlType, lineRange: lineRange, cursor: cursor, column: column, firstNonSpace: firstNonSpace, pending: pending)
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
        let cleanInfo = unescapedChunk(fence.infoChunk)
        let infoRef = storage.intern(replacingNUL(cleanInfo))
        // Each content line loses up to the fence's indent in columns (Fenced code blocks): after a partly consumed
        // tab (`>\t```), the tab's remaining two.
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
        blockContentEnd = fence.infoChunk.length > 0 ? fence.infoChunk.offset + fence.infoChunk.length : firstNonSpace + fence.length
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
        blockContentEnd = lineRange.upperBound
        pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: htmlIdx, pending: pending)
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
        let (bodyStart, leadingSpaces) = stripIndent(
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
        blockContentEnd = lineRange.upperBound
        return appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: codeIdx, pending: pending)
    }

    /// Opens a paragraph with the line's content.
    // Inlined for the reason given in `dispatchNewBlocks`.
    @inline(__always)
    private mutating func openParagraph(lineRange: Range<Int>, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let textRange = firstNonSpace..<lineRange.upperBound
        precondition(storage[current].kind != .paragraph, "dispatch starts at the deepest matched container, which is never a leaf, and opens only containers before a leaf, so `current` is never a paragraph here")
        assert(openParagraphTableState == nil, "the previous paragraph closed before this one opens")
        let paragraphIdx = addChild(kind: .paragraph, parent: current, start: firstNonSpace)
        current = paragraphIdx
        return addLine(range: textRange, to: paragraphIdx, pending: pending)
    }

    // MARK: - Finalize

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

    /// Drains `node`'s pending content with each NUL replaced with U+FFFD (Insecure characters), keeping a segment list
    /// unless it holds a NUL.
    private mutating func drainLeaf(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafDrainResult {
        switch consume pending {
        case .none:
            return LeafDrainResult(content: .chunk(.empty))
        case .some(let leaf):
            precondition(leaf.node == node, "pending content belongs to the one open leaf, which drains when it closes")
            switch consume leaf.content {
            case .segments(let segs):
                // Inline multi-segment content can hold no arena segment but a line join (`ContentSpan.multiNextSignificant`),
                // so a NUL forces a flatten with each NUL replaced with U+FFFD.
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
            return sourceBytes[seg.offset + local]
        }
        return storage.strings[seg.offset + local]
    }

    /// The total length of a leaf's lines `segs`, line joins included.
    private func totalLength(of segs: borrowing UniqueArray<Segment>) -> Int {
        var total = 0
        for i in 0..<segs.count {
            total += segs[i].length
        }
        return total
    }

    /// The virtual range of a leaf's lines `segs`, `total` bytes long, without leading and trailing whitespace
    /// (Paragraphs, Setext headings).
    private func trimmedRange(of segs: borrowing UniqueArray<Segment>, total: Int) -> Range<Int> {
        var lower = 0
        leading: for i in 0..<segs.count {
            let seg = segs[i]
            for j in 0..<seg.length {
                if !segmentByte(seg, j).isWhitespaceCharacter {
                    break leading
                }
                lower += 1
            }
        }
        var upper = total
        trailing: for i in stride(from: segs.count - 1, through: 0, by: -1) {
            let seg = segs[i]
            for j in stride(from: seg.length - 1, through: 0, by: -1) {
                if upper == lower || !segmentByte(seg, j).isWhitespaceCharacter {
                    break trailing
                }
                upper -= 1
            }
        }
        return lower..<upper
    }

    /// `segs`, `total` bytes long, narrowed to the virtual `range`, whose bounds lie on source bytes.
    private func segments(_ segs: consuming UniqueArray<Segment>, in range: Range<Int>, total: Int) -> UniqueArray<Segment> {
        precondition(!range.isEmpty, "a leaf's narrowed content is not empty")
        var segs = segs
        let (last, lastStart) = segment(endingAtOrAfter: range.upperBound, in: segs, total: total)
        // The first segment is searched for from whichever is nearer in bytes, the lines' start or the last segment's,
        // which takes fewer steps when leading definitions fill most of the lines.
        var first = last
        var firstStart = lastStart
        if range.lowerBound < lastStart - range.lowerBound {
            first = 0
            firstStart = 0
            while firstStart + segs[first].length <= range.lowerBound {
                firstStart += segs[first].length
                first += 1
            }
        } else {
            while firstStart > range.lowerBound {
                first -= 1
                firstStart -= segs[first].length
            }
        }
        segs[last].length = range.upperBound - lastStart
        segs[first].offset += range.lowerBound - firstStart
        segs[first].length -= range.lowerBound - firstStart
        segs.removeSubrange((last + 1)..<segs.count)
        segs.removeSubrange(0..<first)
        return segs
    }

    /// Queues the raw content of the paragraph `node` whose lines are `segs` for inline parsing, as segments of the
    /// source, or removes the paragraph when its definitions or task list item marker leave nothing.
    private mutating func finishParagraph(_ node: DocumentStorage.Index, segments segs: consuming UniqueArray<Segment>) {
        let total = totalLength(of: segs)
        guard let content = rawContentRange(in: segs, total: total, taskItemParagraph: node) else {
            // Lines of whitespace that include a line tabulation or form feed are not blank (Characters and lines),
            // yet leave the paragraph no raw content (Paragraphs).
            emptySourceRangeAtStart(node)
            return
        }
        if content.isEmpty {
            removeEmptiedParagraph(node, contentEnd: positionsEnabled ? sourceEnd(ofVirtual: content.upperBound, in: segs, total: total) : nil)
            return
        }
        enqueueRawContent(of: node, segments(segs, in: content, total: total))
    }

    /// The virtual range of the raw content of the paragraph `node`, or with `node` nil of a setext heading, whose
    /// lines are `segs`, `total` bytes long (see `rawContentStart(in:trimmed:taskItemParagraph:)`), or `nil` when its
    /// lines are all whitespace. The range is empty, at the end of the lines' trimmed range, when the paragraph's
    /// definitions or task list item marker leave nothing.
    private mutating func rawContentRange(in segs: borrowing UniqueArray<Segment>, total: Int, taskItemParagraph node: DocumentStorage.Index?) -> Range<Int>? {
        let trimmed = trimmedRange(of: segs, total: total)
        if trimmed.isEmpty {
            return nil
        }
        return rawContentStart(in: segs, trimmed: trimmed, taskItemParagraph: node)..<trimmed.upperBound
    }

    /// Stamps the paragraph `node` with the source span of its raw content `content`, the segments of its lines it
    /// keeps, and queues them for inline parsing.
    private mutating func enqueueRawContent(of node: DocumentStorage.Index, _ content: consuming UniqueArray<Segment>) {
        if positionsEnabled {
            let span = segmentsSourceSpan(content)
            storage.setSourceStart(node, span.start)
            storage.setSourceEnd(node, span.end)
        }
        pendingInlines.append((node, storage.intern(content)))
    }

    /// Flattens a segment list into one arena chunk, recording its run map in `map`: a source segment images its range, and a line join is a gap. The map tiles the content from its first byte, so it survives a later copy of the content.
    private mutating func flattenSegments(_ segs: borrowing UniqueArray<Segment>, map: inout [ArenaRun]) -> Chunk {
        let total = totalLength(of: segs)
        // Arena segments are read through a span of the arena, which can't be borrowed while the arena grows, so the
        // content is assembled apart and then appended.
        var buf = UniqueArray<UInt8>(minimumCapacity: total)
        let offset = storage.strings.count
        for i in 0..<segs.count {
            let seg = segs[i]
            let len = seg.length
            if seg.inSource {
                buf.append(copying: sourceBytes.extracting(seg.chunk.range))
            } else {
                buf.append(copying: storage.strings.span.extracting(seg.chunk.range))
            }
            if len > 0 {
                if seg.inSource {
                    map.append(ArenaRun(length: len, sourceOffset: seg.offset))
                } else {
                    map.append(ArenaRun(length: len, sourceOffset: -1))
                }
            }
        }
        storage.strings.append(copying: buf.span)
        return Chunk(offset: offset, length: total, inSource: false)
    }

    /// Narrows a run map to `[start, start + length)` of its content, rebased to start at 0.
    static func sliceRuns(_ runs: [ArenaRun], from start: Int, length: Int) -> [ArenaRun] {
        let end = start + length
        var result: [ArenaRun] = []
        var v = 0
        for run in runs {
            let runStart = v
            let runEnd = v + run.length
            v = runEnd
            let lo = max(runStart, start)
            let hi = min(runEnd, end)
            if lo >= hi { continue }
            let sourceOffset = run.sourceOffset < 0 ? -1 : run.sourceOffset + (lo - runStart)
            result.append(ArenaRun(length: hi - lo, sourceOffset: sourceOffset))
        }
        return result
    }

    /// The raw content (`paragraphContent`) of the paragraph a table's header row splits off, whose trimmed lines are
    /// `trimmed`, or `nil` when its definitions or task list item marker leave nothing. `node` is checked for being its
    /// list item's first block: the split-off paragraph, or before that is inserted, the paragraph it splits from.
    private mutating func tableSplitParagraphContent(_ trimmed: Chunk, node: DocumentStorage.Index) -> Chunk? {
        let content = paragraphContent(of: node, trimmed: trimmed)
        return content.isEmpty && !trimmed.isEmpty ? nil : content
    }

    /// The source span of `content`, a non-empty window of leaf content `raw` with run map `map` (empty for source
    /// content) that begins and ends on a content byte: from the source byte its first byte images to just past the
    /// one its last byte images.
    private func sourceSpan(of content: Chunk, in raw: Chunk, map: [ArenaRun]) -> (start: Int, end: Int) {
        precondition(!content.isEmpty, "only non-empty content has a source span")
        if map.isEmpty {
            precondition(content.inSource, "with `.sourcePosition`, arena-backed leaf content carries a run map")
            return (content.offset, content.offset + content.length)
        }
        let image = ContentImage(base: raw.offset, runs: map)
        guard let start = image.sourceOffset(ofArenaByte: content.offset),
              let last = image.sourceOffset(ofArenaByte: content.offset + content.length - 1) else {
            preconditionFailure("leaf content lies within its run map")
        }
        return (start, last + 1)
    }

    /// Gives `paragraph`, which has no raw content, an empty source range at its start.
    private mutating func emptySourceRangeAtStart(_ paragraph: DocumentStorage.Index) {
        if positionsEnabled {
            storage.sourceRanges[paragraph].end = storage.sourceRanges[paragraph].start
        }
    }

    /// Removes `paragraph`, its container's last block, which holds only definitions or a task list item marker.
    ///
    /// In a list item it still counts for looseness as a block of the item (Lists). Its content still counts for its
    /// container's range, which ends no earlier than `contentEnd`, just past the paragraph's last content byte, if given.
    private mutating func removeEmptiedParagraph(_ paragraph: DocumentStorage.Index, contentEnd: Int?) {
        if let contentEnd, let container = storage[paragraph].parent {
            storage.sourceRanges[container].end = max(storage.sourceRanges[container].end, contentEnd)
        }
        if let item = storage[paragraph].parent, case .item = storage[item].kind {
            if let preceding = storage[paragraph].previous {
                if endsWithBlankLine(preceding) {
                    itemsWithBlankLineAroundRemovedParagraph.insert(item)
                }
            } else {
                itemsWithRemovedFirstParagraph.insert(item)
            }
            itemsEndingInRemovedParagraph[item] = false
        }
        storage.unlinkChild(paragraph)
        openBlocksVersion &+= 1
    }

    /// Queues the raw content of the paragraph `node`, whose lines are the one chunk `raw` with run map `map` (empty for
    /// source content), for inline parsing, or removes the paragraph when its definitions or task list item marker leave
    /// nothing.
    private mutating func finishParagraph(_ node: DocumentStorage.Index, chunk raw: Chunk, map: [ArenaRun]) {
        let trimmed = raw.trimmingWhitespace(using: self)
        if trimmed.isEmpty {
            // Lines of whitespace that include a line tabulation or form feed are not blank (Characters and lines),
            // yet leave the paragraph no raw content (Paragraphs).
            emptySourceRangeAtStart(node)
            return
        }
        let contentChunk = paragraphContent(of: node, trimmed: trimmed)
        if contentChunk.isEmpty {
            removeEmptiedParagraph(node, contentEnd: positionsEnabled ? sourceSpan(of: trimmed, in: raw, map: map).end : nil)
            return
        }
        if positionsEnabled {
            let span = sourceSpan(of: contentChunk, in: raw, map: map)
            storage.setSourceStart(node, span.start)
            storage.setSourceEnd(node, span.end)
        }
        if positionsEnabled, !map.isEmpty {
            let slice = Self.sliceRuns(map, from: contentChunk.offset - raw.offset, length: contentChunk.length)
            if !slice.isEmpty {
                arenaSourceMaps[node] = slice
            }
        }
        pendingInlines.append((node, storage.intern(contentChunk)))
    }

    /// Whether `kind` is a container block (Container blocks).
    private static func isContainer(_ kind: MarkdownNode.Kind) -> Bool {
        switch kind {
        case .blockQuote, .list, .item, .footnoteDefinition: true
        default: false
        }
    }

    /// Closes `node`, materializes its content, and makes its parent `current`.
    ///
    /// A code block or HTML block ends at `blockContentEnd`, unless a closing fence ends it. A container block ends just past its last content byte: where its last child ends, or where its own marker does if that is later (a block quote's `>` on the last line that has one, a list item's list marker, a footnote definition's `[^label]:`), so blank lines and trailing whitespace after its content are not part of it. A paragraph that held only link reference definitions or a task list item marker leaves no child but still counts as content, while a fenced code block's or HTML block's blank lines are its content, so a container ending in one ends on its last line. A paragraph's end is set once its raw content is known, and a setext heading's past its underline. `lineContentEnd` is where an ATX heading (see `ATXMatch.end`), a thematic break or a closing fence ends on its line.
    private mutating func finalize(node: DocumentStorage.Index, pending: consuming PendingLeaf?, lineContentEnd: Int? = nil) -> PendingLeaf? {
        var pending = pending
        let kind = storage[node].kind
        openBlocksVersion &+= 1

        if positionsEnabled {
            if let lineContentEnd {
                storage.setSourceEnd(node, lineContentEnd)
            } else if kind.isCodeBlock || kind == .htmlBlock {
                storage.setSourceEnd(node, blockContentEnd)
            } else if Self.isContainer(kind) {
                let ownEnd = storage.sourceRanges[node].end
                storage.setSourceEnd(node, storage[node].lastChild.map { max(ownEnd, storage.sourceRanges[$0].end) } ?? ownEnd)
            }
        }

        switch kind {
        case .paragraph:
            assert(openParagraphTableState.map { $0.node == node } ?? true, "the recorded table state belongs to the paragraph being closed")
            defer { openParagraphTableState = nil }
            // Tables come before definition extraction: the paragraph is a table from its delimiter row on, and only a
            // paragraph holds definitions, so `[\n|-\n]:/` is a table. A pipe-less `-` or `=` run is a setext underline
            // instead, handled earlier with the definitions extracted: `[o]:o\n-` is a definition and a paragraph,
            // `[o]:o\n|-` a table.
            if openParagraphTableState?.tablePending == true {
                parseTable(node: node, pending: pending)
                pending = nil
                break
            }
            let drained = drainLeaf(node, pending: pending)
            pending = nil
            let map = drained.map
            switch consume drained.content {
            case .chunk(let raw):
                finishParagraph(node, chunk: raw, map: map)
            case .segments(let segs):
                finishParagraph(node, segments: segs)
            }
        case .heading:
            // The content is already trimmed: an ATX heading's to its line's content, a setext heading's to its raw
            // content.
            let drained = drainLeaf(node, pending: pending)
            pending = nil
            let map = drained.map
            switch consume drained.content {
            case .chunk(let content):
                if !content.isEmpty {
                    if positionsEnabled, !map.isEmpty {
                        arenaSourceMaps[node] = map
                    }
                    pendingInlines.append((node, storage.intern(content)))
                }
            case .segments(let segs):
                pendingInlines.append((node, storage.intern(segs)))
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

        // A fenced block's first line follows a separator, so the separator is there exactly when the block has a
        // line; an indented block's first line follows none.
        var strippedLeading = false
        if lo < hi && segs[lo] == nl {
            lo += 1
            strippedLeading = true
        }

        if !isFenced {
            // A trailing blank line is its separator, followed by its spaces and tabs past the four-column indent if it
            // keeps any.
            while lo < hi {
                let last = segs[hi - 1]
                if last == nl {
                    hi -= 1
                    continue
                }
                if isSpaceOrTabOnly(last) {
                    hi -= 1
                    if hi > lo && segs[hi - 1] == nl { hi -= 1 }
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
        // The separators end every line but the last, which is a content line or a fenced block's final blank line.
        segs.append(nl)
    }

    /// Whether `segment`, a code block line, holds only spaces and tabs.
    private func isSpaceOrTabOnly(_ segment: Segment) -> Bool {
        segment.chunk.range.allSatisfy { readByte(at: $0, in: segment.chunk).isSpaceOrTab }
    }

    // MARK: - Helpers

    /// One walk over a line's leading spaces and tabs, combining `indexOfFirstNonSpace` and `indentColumns`.
    private struct LeadingScan {
        var firstNonSpace: Int
        var indentColumns: Int
        var isBlank: Bool
        /// The byte at `firstNonSpace`, or `0` when the line is blank.
        var firstNonSpaceByte: UInt8
    }

    /// Measures `range`'s leading spaces and tabs, with tab stops every four columns (Tabs).
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

    /// The column width of the spaces and tabs `start..<end`, with tab stops every four columns (Tabs).
    ///
    /// `baseColumn` is `start`'s column, which places the tab stops: a tab's width depends on the column it starts at.
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

    /// A superset of the bytes that can begin a block interrupting a paragraph, so a line beginning with any other byte
    /// can't interrupt one.
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

    /// The offset past up to `columns` columns of leading spaces and tabs from `start`, at column `baseColumn` (see
    /// `indentColumns`).
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
        /// Where the heading ends: past its closing sequence or trimmed content, or past the opening `#`s when it has
        /// neither.
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
        var markerEnd: Int        // source offset just past the marker
        var consumedTo: Int       // source offset of first byte of item content
        var isEmpty: Bool         // marker opens an empty item (only spaces and tabs to the line end)
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
        case UInt8(ascii: "-"):
            kind = .bullet
            bulletMarker = .hyphen
            markerWidth = 1
        case UInt8(ascii: "+"):
            kind = .bullet
            bulletMarker = .plus
            markerWidth = 1
        case UInt8(ascii: "*"):
            kind = .bullet
            bulletMarker = .asterisk
            markerWidth = 1
        default:
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
        let columnAfterMarker = markerColumn + markerWidth
        var contentStart: Int
        // The columns from the marker's end to the content.
        var padding = 1
        var isEmpty = false
        if afterMarker >= range.upperBound {
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
            var col = columnAfterMarker
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
            let runColumns = col - columnAfterMarker
            let blankAfter = k >= range.upperBound
            isEmpty = blankAfter
            if blankAfter || runColumns >= 5 {
                if next == UInt8(ascii: "\t") && (4 - (columnAfterMarker & 3)) > 1 {
                    contentStart = afterMarker
                } else {
                    contentStart = afterMarker + 1
                }
            } else {
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
            contentStartColumn: columnAfterMarker + padding,
            markerEnd: afterMarker,
            consumedTo: contentStart,
            isEmpty: isEmpty
        )
    }

    /// Type 6 tag names (HTML blocks).
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
        if next == UInt8(ascii: "!"),
           after + 1 < range.upperBound,
           sourceBytes[after + 1].isUppercaseASCIILetter {
            return 4
        }
        if next == UInt8(ascii: "?") {
            return 3
        }
        var nameStart = after
        var isClosing = false
        if next == UInt8(ascii: "/") {
            isClosing = true
            nameStart = after + 1
        }
        // The tag scanners read this copy, not `sourceBytes`: capturing the parser costs 2% to 3.5% of the instructions
        // of a parse of `Benchmarks/100kb-test-content.md`.
        let bytes = sourceBytes
        guard let nameEnd = htmlTagNameEnd(from: nameStart, end: range.upperBound, byte: { bytes[$0] }) else {
            return nil
        }
        let nameRange = nameStart..<nameEnd

        // Type 1: pre/script/style, open tag only. A closing tag such as `</pre>` doesn't meet start condition 1, but may start a type 7 block.
        if !isClosing {
            for tag in Self.htmlBlockType1Tags {
                if bytesEqualASCIICaseInsensitive(range: nameRange, target: tag) {
                    if nameEnd >= range.upperBound { return 1 }
                    let follow = sourceBytes[nameEnd]
                    if follow.isWhitespaceCharacter || follow == UInt8(ascii: ">") {
                        return 1
                    }
                    // Start condition 7 excludes these tag names, so `<script/>` starts no HTML block.
                    return nil
                }
            }
        }

        for tag in Self.htmlBlockType6Tags {
            if bytesEqualASCIICaseInsensitive(range: nameRange, target: tag) {
                if nameEnd >= range.upperBound { return 6 }
                let follow = sourceBytes[nameEnd]
                if follow.isWhitespaceCharacter || follow == UInt8(ascii: ">") {
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

        if allowType7, let tagEnd = htmlTagEnd(afterName: nameEnd, isClosing: isClosing, end: range.upperBound, byte: { bytes[$0] }) {
            if isOnlyWhitespaceToEnd(from: tagEnd, end: range.upperBound) {
                return 7
            }
        }
        return nil
    }

    private func isOnlyWhitespaceToEnd(from start: Int, end: Int) -> Bool {
        var i = start
        while i < end, sourceBytes[i].isWhitespaceCharacter {
            i += 1
        }
        return i == end
    }

    /// Whether the line meets the end condition of an HTML block of `type` anywhere (HTML blocks).
    private func htmlBlockLineMatchesEndCondition(type: UInt8, range: Range<Int>) -> Bool {
        switch type {
        case 1:
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
    // Inlined because it scans every byte of a type 1 block's lines once per tag: out of line it costs about 5% of the
    // instructions of a parse of `Benchmarks/100kb-test-content.md` after a `<pre>` line.
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
        if sourceBytes[firstNonSpace] != UInt8(ascii: ">") {
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
    /// on the tab, and the column reached lies inside it.
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
        while infoStart < range.upperBound && sourceBytes[infoStart].isWhitespaceCharacter {
            infoStart += 1
        }
        var infoEnd = range.upperBound
        while infoEnd > infoStart && sourceBytes[infoEnd - 1].isWhitespaceCharacter {
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

    /// Where the line's closing fence ends, if the line closes a fence of `expectedChar` at least `minimumLength` long
    /// (Fenced code blocks). `indentColumns` is the fence's indent in columns past the container prefixes (Tabs).
    private func matchClosingFence(range: Range<Int>, firstNonSpace: Int, indentColumns: Int, expectedChar: MarkdownNode.CodeBlockInfo.FenceCharacter?, minimumLength: Int) -> Int? {
        guard let fenceByte = expectedChar?.character else {
            preconditionFailure("a fenced code block always records its fence character")
        }
        if indentColumns > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
        if sourceBytes[firstNonSpace] != fenceByte {
            return nil
        }
        var i = firstNonSpace
        while i < range.upperBound && sourceBytes[i] == fenceByte {
            i += 1
        }
        return i - firstNonSpace >= minimumLength && isSpaceOrTabOnly(i..<range.upperBound) ? i : nil
    }

    /// Whether `sourceBytes[range]` holds only spaces and tabs.
    // Inlined because out of line it costs about 1% of the spec text's parse instructions.
    @inline(__always)
    private func isSpaceOrTabOnly(_ range: Range<Int>) -> Bool {
        range.allSatisfy { sourceBytes[$0].isSpaceOrTab }
    }

    /// Strips up to `maxColumns` columns of leading spaces and tabs from a code or HTML block line at column
    /// `startColumn`.
    ///
    /// A tab straddling the boundary is dropped and its leftover columns returned as `leadingSpaces` (Tabs).
    private func stripIndent(range: Range<Int>, maxColumns: Int, startColumn: Int) -> (bodyStart: Int, leadingSpaces: Int) {
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

    /// Matches a setext heading underline (Setext headings), returning the heading level and the offset past the
    /// underline's last `=` or `-`.
    private func matchSetextUnderline(range: Range<Int>, firstNonSpace: Int) -> (level: UInt8, end: Int)? {
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
        return isSpaceOrTabOnly(i..<range.upperBound) ? (level, i) : nil
    }

    /// Matches a thematic break (Thematic breaks), returning the offset past its last marker character.
    ///
    /// Without a match, `noBreakBefore` becomes the offset where the match failed: the first byte that is neither the
    /// marker character nor a space or tab, or the line's end when the markers are too few. The line from any
    /// non-whitespace byte between `firstNonSpace` and that offset is no thematic break either, since it holds the same
    /// marker character, and fewer of them, before that offset.
    private func matchThematicBreak(range: Range<Int>, firstNonSpace: Int, noBreakBefore: inout Int) -> Int? {
        assert(firstNonSpace - range.lowerBound <= 3, "block-start matchers run only on a line indented less than four columns")
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let marker = sourceBytes[firstNonSpace]
        if marker != UInt8(ascii: "-") && marker != UInt8(ascii: "_") && marker != UInt8(ascii: "*") {
            noBreakBefore = firstNonSpace
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
                noBreakBefore = i
                return nil
            }
            i += 1
        }
        if count < 3 {
            noBreakBefore = range.upperBound
            return nil
        }
        return end
    }

    /// Matches an ATX heading (ATX headings).
    private func matchATXHeading(range: Range<Int>, firstNonSpace: Int) -> ATXMatch? {
        assert(firstNonSpace - range.lowerBound <= 3, "block-start matchers run only on a line indented less than four columns")
        var i = firstNonSpace
        var level: Int = 0
        while i < range.upperBound && sourceBytes[i] == UInt8(ascii: "#") {
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

        // The closing sequence is the heading's own syntax, so the heading ends past it, as past any content.
        let end = contentStart != beforeHashes ? beforeHashes : i
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
            // A blank line separates the item from the next.
            if nextItem != nil && storage.nodes[item_].lastLineBlank {
                loose = true
                break outer
            }
            // A blank line separates a block the item directly contains from a block after it, in the item or the next.
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

    /// The raw content of the paragraph `node` whose trimmed lines are `trimmed`: what follows its leading definitions,
    /// from its first non-whitespace byte, or without definitions, `trimmed` less any task list item marker. A marker
    /// makes `node`'s list item a task list item.
    private mutating func paragraphContent(of node: DocumentStorage.Index, trimmed: Chunk) -> Chunk {
        let afterDefinitions = parseDefinitions(in: trimmed)
        // A definition counts as a block of its list item (Lists), so a marker after one doesn't begin the item's
        // first block.
        guard afterDefinitions.offset == trimmed.offset else {
            return afterDefinitions.trimmingWhitespace(using: self)
        }
        guard let item = taskListItem(firstBlock: node),
              let checked = Self.taskItemMarker(length: trimmed.length, byte: { readByte(at: trimmed.offset + $0, in: trimmed) }) else {
            return trimmed
        }
        storage[item].kind = .item(checked: checked)
        return trimmed.extracting(3..<trimmed.length).trimmingWhitespace(using: self)
    }

    /// Where the raw content of the paragraph `node` whose lines are `segs` begins (see `paragraphContent(of:trimmed:)`),
    /// as a virtual offset of the lines within `trimmed`, their virtual range without leading and trailing whitespace.
    /// With `node` nil, a setext heading's content, which has no task list item marker. A task list item marker makes
    /// `node`'s list item a task list item.
    ///
    /// The lines are read in place, so content that isn't contiguous in the source is not copied.
    private mutating func rawContentStart(in segs: borrowing UniqueArray<Segment>, trimmed: Range<Int>, taskItemParagraph node: DocumentStorage.Index?) -> Int {
        precondition(!trimmed.isEmpty, "only non-blank content begins past definitions or a marker")
        var first = 0
        var offset = 0
        while offset + segs[first].length <= trimmed.lowerBound {
            offset += segs[first].length
            first += 1
        }
        // A definition begins with `[` or `^`, and a task list item marker with `[`.
        guard Self.mayBeginDefinition(segmentByte(segs[first], trimmed.lowerBound - offset)) else {
            return trimmed.lowerBound
        }
        var segmentEnds = UniqueArray<Int>(minimumCapacity: segs.count)
        var end = 0
        for i in 0..<segs.count {
            end += segs[i].length
            segmentEnds.append(end)
        }
        let content = ContentSpan(source: sourceBytes, segments: segs.span, segmentEnds: segmentEnds.span, virtualLength: trimmed.upperBound, hint: pieceHint)
        let afterDefinitions = definitionsEnd(in: content, from: trimmed.lowerBound)
        // As in `paragraphContent(of:trimmed:)`, a marker after a definition doesn't begin the item's first block.
        if afterDefinitions != trimmed.lowerBound {
            return skipWhitespace(from: afterDefinitions, in: content)
        }
        guard let node,
              let item = taskListItem(firstBlock: node),
              let checked = Self.taskItemMarker(length: trimmed.count, byte: { content[trimmed.lowerBound + $0] }) else {
            return trimmed.lowerBound
        }
        storage[item].kind = .item(checked: checked)
        return skipWhitespace(from: trimmed.lowerBound + 3, in: content)
    }

    /// The list item whose first block is the paragraph `node`, which may make it a task list item (Task list items
    /// (extension)).
    private func taskListItem(firstBlock node: DocumentStorage.Index) -> DocumentStorage.Index? {
        guard storage.options.contains(.tasklist),
              let item = storage[node].parent,
              case .item = storage[item].kind,
              storage[item].firstChild == node,
              !itemsWithRemovedFirstParagraph.contains(item) else {
            return nil
        }
        return item
    }

    /// The checked state of a task list item marker (Task list items (extension)) beginning `length` content bytes read
    /// through `byte`, or `nil` when they don't begin with one followed by whitespace.
    private static func taskItemMarker(length: Int, byte: (Int) -> UInt8) -> Bool? {
        // A marker that ends the content is followed by a line ending or the end of input.
        guard length >= 3,
              byte(0) == UInt8(ascii: "["),
              byte(2) == UInt8(ascii: "]"),
              length == 3 || byte(3).isWhitespaceCharacter else {
            return nil
        }
        let between = byte(1)
        if between == UInt8(ascii: "x") || between == UInt8(ascii: "X") {
            return true
        }
        return between.isLineWhitespace ? false : nil
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
            if b == UInt8(ascii: "\\"), i + 1 < end, !sourceBytes[i + 1].isWhitespaceCharacter {
                i += 2
                continue
            }
            if b.isWhitespaceCharacter {
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

    /// Opens a footnote definition under `current`, registering it unless its label already has a definition: as for
    /// link reference definitions, the first in the document wins.
    private mutating func openFootnoteDefinition(label rawLabel: Chunk, firstNonSpace: Int) -> DocumentStorage.Index {
        // The stored label has each NUL replaced with U+FFFD (Insecure characters).
        let label = replacingNUL(rawLabel)
        let labelRef = storage.intern(label)
        let fnIdx = addChild(
            kind: .footnoteDefinition,
            parent: current,
            data: .footnoteDefinition(label: labelRef),
            start: firstNonSpace
        )
        // Past the label's `]:`.
        storage.setSourceEnd(fnIdx, rawLabel.offset + rawLabel.length + 2)
        storage.footnoteDefinitionOrder.append(fnIdx)
        let key = normalizeLabel(chunk: label)
        if !key.isEmpty && storage.footnoteMap[key] == nil {
            storage.footnoteMap[key] = fnIdx
        }
        return fnIdx
    }

    // MARK: - Definitions
    
    /// Consumes link reference definitions, and with `.attributes` `^[label]: attrs` definitions, from the start of `chunk`, returning the rest. The first definition of a label wins (Link reference definitions).
    private mutating func parseDefinitions(in chunk: Chunk) -> Chunk {
        let end = chunk.offset + chunk.length
        let rest: Int
        if chunk.inSource {
            rest = definitionsEnd(in: ContentSpan(span: sourceBytes.extracting(chunk.range), base: chunk.offset, inSource: true), from: chunk.offset)
        } else if !chunk.isEmpty && Self.mayBeginDefinition(readByte(at: chunk.offset, in: chunk)) {
            // Arena content is read from a copy, since registering a definition can grow the arena.
            var bytes = UniqueArray<UInt8>()
            bytes.append(copying: storage.strings.span.extracting(chunk.range))
            rest = definitionsEnd(in: ContentSpan(span: bytes.span, base: chunk.offset, inSource: false), from: chunk.offset)
        } else {
            rest = chunk.offset
        }
        return Chunk(offset: rest, length: end - rest, inSource: chunk.inSource)
    }

    /// Whether a definition can begin with `byte`: `[`, or `^` for an attribute definition.
    private static func mayBeginDefinition(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "[") || byte == UInt8(ascii: "^")
    }

    /// The offset past the link reference definitions, and with `.attributes` `^[label]: attrs` definitions, that
    /// `content` holds from `start`, each registered unless its label already has a definition (Link reference
    /// definitions).
    private mutating func definitionsEnd(in content: borrowing ContentSpan, from start: Int) -> Int {
        // Every bare destination scanned below is read from this content up to its end.
        destinationParentheses.reset()
        let end = content.endOffset
        var i = start
        while i < end {
            let after: Int?
            if content[i] == UInt8(ascii: "[") {
                after = parseOneLinkDefinition(from: i, in: content)
            } else if content[i] == UInt8(ascii: "^"),
                      storage.options.contains(.attributes),
                      i + 1 < end,
                      content[i + 1] == UInt8(ascii: "[") {
                after = parseOneAttributeDefinition(from: i, in: content)
            } else {
                after = nil
            }
            guard let after else {
                break
            }
            i = after
        }
        return i
    }

    /// `content`'s bytes at `range` as a chunk with backslash escapes and character references resolved, copied into
    /// the arena once if `range` holds either or, as a link title can, spans a line join.
    // Inlined because it resolves every inline link's destination and title: out of line it costs about 0.5% of the
    // instructions of a parse of 20,000 paragraphs each holding an inline link.
    @inline(__always)
    mutating func unescapedChunk(_ range: Range<Int>, in content: borrowing ContentSpan) -> Chunk {
        if range.isEmpty {
            return .empty
        }
        if let contiguous = content.contiguousChunk(fromVirtual: range.lowerBound, limit: range.upperBound),
           contiguous.length == range.count {
            return unescapedChunk(contiguous)
        }
        // A backslash escape or character reference never continues past a line ending, so each line resolves alone.
        let offset = storage.strings.count
        var i = range.lowerBound
        while i < range.upperBound {
            if let line = content.contiguousChunk(fromVirtual: i, limit: range.upperBound) {
                appendUnescaped(line)
                i += line.length
            } else {
                storage.strings.append(content[i])
                i += 1
            }
        }
        return arenaChunk(from: offset)
    }

    /// Skips whitespace characters (Characters and lines).
    func skipWhitespace(from cursor: Int, in content: borrowing ContentSpan) -> Int {
        var i = cursor
        while i < content.endOffset, content[i].isWhitespaceCharacter {
            i += 1
        }
        return i
    }

    // The scanners below, `parseOneLinkDefinition` and `matchDefinitionLabel` are `@inline(__always)`: out of line,
    // they cost about 2% of the instructions of a parse of 200,000 one-line definitions `[aN]: /uN "tN"`.

    /// Skips spaces, tabs, line tabulations and form feeds.
    @inline(__always)
    private func skipLineWhitespace(from cursor: Int, in content: borrowing ContentSpan) -> Int {
        var i = cursor
        while i < content.endOffset, content[i].isLineWhitespace {
            i += 1
        }
        return i
    }

    /// Skips line whitespace, at most one line ending, and more line whitespace.
    @inline(__always)
    private func skipSpacesAndOneLineEnd(from cursor: Int, in content: borrowing ContentSpan) -> Int {
        let i = skipLineWhitespace(from: cursor, in: content)
        guard i < content.endOffset, content[i] == UInt8(ascii: "\n") else {
            return i
        }
        return skipLineWhitespace(from: i + 1, in: content)
    }

    /// The offset past a line ending at `cursor`, `cursor` at the end of `content`, or `nil`.
    @inline(__always)
    private func skipLineEndOrEOF(from cursor: Int, in content: borrowing ContentSpan) -> Int? {
        if cursor >= content.endOffset {
            return cursor
        }
        return content[cursor] == UInt8(ascii: "\n") ? cursor + 1 : nil
    }

    // MARK: - Link definition

    /// Parses one link reference definition at `start`, returning the offset past it and its line ending.
    // Inlined for the reason given before `skipLineWhitespace`.
    @inline(__always)
    private mutating func parseOneLinkDefinition(from start: Int, in content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        guard let (label, destinationStart) = matchDefinitionLabel(from: start, in: content),
              let destination = matchLinkDestination(from: destinationStart, end: end, in: content) else {
            return nil
        }
        // When the line doesn't end after a title, the definition ends at the destination instead.
        var title: Range<Int> = destination.afterEnd..<destination.afterEnd
        var afterAll: Int? = nil
        let titleStart = skipSpacesAndOneLineEnd(from: destination.afterEnd, in: content)
        if titleStart > destination.afterEnd,
           let match = matchLinkTitle(from: titleStart, end: end, in: content),
           let lineEnd = skipLineEndOrEOF(from: skipLineWhitespace(from: match.afterEnd, in: content), in: content) {
            title = match.interior
            afterAll = lineEnd
        }
        if afterAll == nil {
            afterAll = skipLineEndOrEOF(from: skipLineWhitespace(from: destination.afterEnd, in: content), in: content)
        }
        guard let afterAll else {
            return nil
        }
        // `normalizeLabel` replaces a NUL itself (Insecure characters), so the key matches a reference's even
        // in content `drainLeaf` hasn't NUL-replaced yet (the setext underline path).
        let key = normalizeLabel(virtualRange: label, in: content)
        if key.isEmpty {
            return nil
        }
        if storage.referenceMap[key] == nil {
            // A NUL becomes U+FFFD (Insecure characters). The content may not be NUL-replaced yet, so it is done
            // here, where every stored definition passes.
            storage.referenceMap[key] = ReferenceDefinition(
                destination: replacingNUL(unescapedChunk(destination.destination, in: content)),
                title: replacingNUL(unescapedChunk(title, in: content))
            )
        }
        return afterAll
    }

    /// Matches a definition's label and `:` at `start`, returning the label's interior and where the definition's
    /// content begins, past whitespace including at most one line ending.
    // Inlined for the reason given before `skipLineWhitespace`.
    @inline(__always)
    private mutating func matchDefinitionLabel(from start: Int, in content: borrowing ContentSpan) -> (label: Range<Int>, contentStart: Int)? {
        guard let label = matchLinkLabel(from: start, end: content.endOffset, in: content),
              label.afterEnd < content.endOffset,
              content[label.afterEnd] == UInt8(ascii: ":") else {
            return nil
        }
        return (label.interior, skipSpacesAndOneLineEnd(from: label.afterEnd + 1, in: content))
    }

    // MARK: - Attribute definition

    /// Parses one `^[label]: attrs` definition at `start`, returning the offset past it and its line ending.
    private mutating func parseOneAttributeDefinition(from start: Int, in content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        precondition(start < end && content[start] == UInt8(ascii: "^"), "an attribute definition is parsed only from a `^`")
        guard let (label, attributesStart) = matchDefinitionLabel(from: start + 1, in: content) else {
            return nil
        }
        var attributesEnd = attributesStart
        while attributesEnd < end, content[attributesEnd] != UInt8(ascii: "\n") {
            attributesEnd += 1
        }
        if attributesEnd == attributesStart {
            return nil
        }
        let key = normalizeLabel(virtualRange: label, in: content)
        if key.isEmpty {
            return nil
        }
        if storage.attributeReferenceMap[key] == nil {
            let attributesChunk = materializedChunk(start: attributesStart, end: attributesEnd, content: content)
            storage.attributeReferenceMap[key] = replacingNUL(unescapedChunk(attributesChunk.trimming(using: self)))
        }
        return attributesEnd < end ? attributesEnd + 1 : attributesEnd
    }

    /// `chunk` with backslash escapes removed and character references decoded, copied to the arena only if it holds either.
    ///
    /// With `backslashEscapes: false` backslashes stay literal, as in autolinks (Autolinks).
    mutating func unescapedChunk(_ chunk: Chunk, backslashEscapes: Bool = true) -> Chunk {
        guard holdsEscapeOrReference(chunk, backslashEscapes: backslashEscapes) else {
            return chunk
        }
        let outOffset = storage.strings.count
        appendUnescaped(chunk, backslashEscapes: backslashEscapes)
        return arenaChunk(from: outOffset)
    }

    /// Whether `chunk` holds a backslash escape, when `backslashEscapes`, or a character reference.
    private func holdsEscapeOrReference(_ chunk: Chunk, backslashEscapes: Bool) -> Bool {
        let endOff = chunk.range.upperBound
        for i in chunk.range {
            let b = readByte(at: i, in: chunk)
            if backslashEscapes, b == UInt8(ascii: "\\"), i + 1 < endOff,
               readByte(at: i + 1, in: chunk).isASCIIPunct {
                return true
            }
            if b == UInt8(ascii: "&"), characterReference(at: i, in: chunk) != nil {
                return true
            }
        }
        return false
    }

    /// Appends `chunk`'s bytes to the arena with backslash escapes removed, when `backslashEscapes`, and character
    /// references decoded.
    mutating func appendUnescaped(_ chunk: Chunk, backslashEscapes: Bool = true) {
        let endOff = chunk.range.upperBound
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
            if b == UInt8(ascii: "&"), let entity = characterReference(at: j, in: chunk) {
                for k in 0..<entity.count {
                    storage.strings.append(entity.bytes[k])
                }
                j = entity.afterSemi
                continue
            }
            storage.strings.append(b)
            j += 1
        }
    }

    /// The character reference at the `&` at `offset` in `chunk`, or `nil` if none starts there.
    func characterReference(at offset: Int, in chunk: Chunk) -> EntityParser.EntityMatch? {
        if chunk.inSource {
            EntityParser.matchEntity(start: offset, end: chunk.range.upperBound, source: sourceBytes)
        } else {
            EntityParser.matchEntity(start: offset, end: chunk.range.upperBound, source: storage.strings.span)
        }
    }

    /// The arena bytes from `offset` to the arena's end, as just appended.
    func arenaChunk(from offset: Int) -> Chunk {
        Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
    }
}

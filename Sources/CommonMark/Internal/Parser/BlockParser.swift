/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

// Owned by the inline pass's caller, so a borrow of these buffers is independent of the `storage` mutations `parseInline`
// performs.
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

// A method that only reads the parser may still be `mutating`, since a non-mutating method can copy the whole parser
// before each call it makes to another parser method.
/// Block-level Markdown parser.
internal struct BlockParser : ~Copyable, ~Escapable {
    /// The storage we are parsing from.
    internal var storage: DocumentStorage
    
    /// The source bytes as a `Span<UInt8>`.
    ///
    /// The parser is byte-oriented; the borrowed source is held directly as a span (UTF-8 validity is only re-established at the `UTF8Span`-vending public API).
    internal let sourceBytes: Span<UInt8>

    internal let limits: MarkdownDocument.ParseLimits
    
    /// The root document node - always index 0.
    let documentIndex: DocumentStorage.Index

    /// The deepest currently-open block.
    ///
    /// New text is appended here (or to a new child of an ancestor) and finalization unwinds outward toward the root.
    var current: DocumentStorage.Index

    // Bumped whenever a block opens or closes or a paragraph is removed, since each can change where a walk recorded in
    // `emptyRemainderWalks` ends.
    var openBlocksVersion = 0

    struct EmptyRemainderWalk {
        var version: Int
        var deepestMatched: DocumentStorage.Index
        var allMatched: Bool
    }
    var emptyRemainderWalks = [DocumentStorage.Index: EmptyRemainderWalk]()

    static let emptyRemainderWalkLimit = 8

    /// The single open leaf's accumulated content together with the node it belongs to.
    ///
    /// At most one leaf (paragraph / heading / code / HTML block) accumulates content at any moment, and container blocks (block quote / list / item) never hold text. This state is threaded through the block-parse call chain - functions that begin or extend a leaf's content `consume` the current `PendingLeaf?` and return the updated one, and `parse()` owns the root binding.
    struct PendingLeaf : ~Copyable {
        /// The node this content is accumulating into.
        var node: DocumentStorage.Index
        /// The accumulated content.
        var content: PendingContent
    }

    enum PendingContent : ~Copyable {
        case lazy(range: Range<Int>, joinPending: Bool = false)
        // A paragraph's first segment can hold several source-contiguous lines; only its last segment is always one line.
        /// An ordered segment list.
        case segments(UniqueArray<Segment>)
    }

    struct LeafContinuation : ~Copyable {
        var consumedLine: Bool
        var pending: PendingLeaf?
    }

    /// `true` when `.sourcePosition` tracking is on.
    ///
    /// Hoisted so the per-node stamping in `addChild` and `finalize` is a single bool test on the hot path when positions are off.
    let positionsEnabled: Bool

    // Only content parsed in place holds a CR, so a range into that content indexes `sourceBytes` directly.
    var contentHoldsCR = false

    var sourceReadEnd: Int = 0

    var nulFreeSourceStart: Int = 0

    var blockContentEnd: Int = 0

    /// Inline-parsing tasks deferred until after all block parsing completes.
    ///
    /// This delay is what lets a `[foo]` shortcut reference resolve against a `[foo]: url` ref-def that appears later in the document.
    var pendingInlines: [(DocumentStorage.Index, ContentRef)] = []

    var arenaSourceMaps = [DocumentStorage.Index: [ArenaRun]]()

    // A lazy continuation line's leading whitespace counts toward a link label's byte limits, though its paragraph's
    // content omits it.
    final class LazyLineWhitespace {
        var bySourceOffset: [Int: Int] = [:]
        var byArenaOffset: [Int: Int] = [:]
    }
    var lazyLineWhitespace: LazyLineWhitespace?

    struct OpenParagraphState {
        let node: DocumentStorage.Index

        var tablePending = false

        var tableColumns = 0

        var tableAutocompletedCells = 0

        var holdsLineOverRowCellLimit = false

        var definitionsCommitted = false

        var whitespaceOnlyLineBeforeDefinitions = false

        var holdsWhitespaceOnlyLine = false

        var incompleteDefinition: IncompleteDefinition?

        var headingHoldsWhitespaceOnlyLine: Bool {
            whitespaceOnlyLineBeforeDefinitions || holdsWhitespaceOnlyLine
        }
    }

    enum IncompleteDefinition {
        case cannotComplete
        case openLabel(readEnd: Int)
        case openTitle(LinkTitleScan, readEnd: Int)
    }

    var openParagraphState: OpenParagraphState?

    // A paragraph removed for holding only definitions or a task list item marker still counts as a block of its list
    // item: for looseness (Lists), for whether the item is empty (List items), and as its first block (Task list items
    // (extension)).
    var itemsEndingInRemovedParagraph = [DocumentStorage.Index: Bool]()

    var itemsWithBlankLineAroundRemovedParagraph = Set<DocumentStorage.Index>()

    var itemsWithRemovedFirstParagraph = Set<DocumentStorage.Index>()

    var htmlCloserMisses = HTMLCloserMisses()

    var backtickRunsSeen = BacktickRunsSeen()

    var destinationParentheses = BalancedParenthesesScan()

    var attributeParentheses = BalancedParenthesesScan()

    var characterReferenceSources: [(arena: Range<Int>, source: Range<Int>)] = []

    var delimiters = UniqueArray<DelimiterRecord>()
    var lastDelim: Int? = nil

    var brackets = UniqueArray<BracketRecord>()
    var lastBracket: Int? = nil

    var linksFormed = 0

    var referenceExpansionRemaining: Int

    // Made on first use, so a parse that reads no segment list or run map allocates none.
    var pieceHint: PieceHint {
        mutating get {
            if let hint = lazyPieceHint {
                return hint
            }
            let hint = PieceHint()
            lazyPieceHint = hint
            return hint
        }
    }
    private var lazyPieceHint: PieceHint?

    // MARK: - Init
    
    @_lifetime(copy source)
    init(storage: consuming DocumentStorage, source: Span<UInt8>, limits: MarkdownDocument.ParseLimits) {
        self.storage = storage
        self.sourceBytes = source
        self.limits = limits
        self.positionsEnabled = self.storage.options.contains(.sourcePosition)
        self.referenceExpansionRemaining = max(limits.referenceExpansionBudget, source.count)

        // Pre-size the append-only arenas from the input length so they don't grow geometrically during the parse (each growth is a malloc + a memmove of everything appended so far - a measurable share of parse time and the bulk of the remaining allocations on large inputs).
        // Ratios are deliberately generous: over-reserving costs one larger malloc with no zero-fill, while under-reserving brings the realloc chain back.
        let byteCount = self.sourceBytes.count
        self.storage.nodes.reserveCapacity(byteCount / 16)
        self.storage.segments.reserveCapacity(byteCount / 8)
        self.storage.strings.reserveCapacity(byteCount / 4)

        documentIndex = self.storage.appendNode(NodeRecord(kind: .document))
        current = documentIndex
    }
    
    // MARK: - Parse
    
    consuming func parse() -> DocumentStorage {
        // Inline-only modes (`.inlineOnly` / `.preserveWhitespace`) bypass block structure entirely.
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

            // EOF: finalize all open blocks back up to the document root.
            while current != documentIndex {
                pending = finalize(node: current, pending: pending)
            }
            
            // The document root is never passed to `finalize`; stamp its end (whole-source span) here. A truly-empty document (no lines) is left unstamped so it reports no source range.
            if positionsEnabled, reader.lineNumber > 0 {
                stampDocument()
            }
        }

        // Inline-parsing pass: with all blocks closed (and `storage`'s `referenceMap` / `attributeReferenceMap` / `footnoteMap` fully populated), run inline parsing for every paragraph and heading queued during finalize. Forward references like `[foo]\n\n[foo]: url` resolve correctly because the def is in the map by the time the ref's paragraph is parsed.
        let pending = pendingInlines
        
        var scratch = InlineScratch()

        for (node, ref) in pending {
            precondition(ref.totalLength > 0, "only non-empty content is queued for inline parsing")
            if ref.count == 1 {
                parseInline(chunk: storage.segments[ref.first].chunk, scratch: &scratch, into: node)
            } else {
                // Multi-segment content (multi-line non-contiguous paragraph/heading): copy the segment list into stable storage and parse it directly from the source - no flattening into the arena.
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

    // A reference inside a dropped definition still counts, so the definition it resolves to is kept, though the
    // reference is dropped with the definition holding it.
    private mutating func processFootnotes() {
        guard storage.options.contains(.footnotes) else { return }
        guard !storage.footnoteDefinitionOrder.isEmpty else { return }
        let referencedDefs = numberFootnoteReferences()
        let keep = Set(referencedDefs)
        for defIdx in storage.footnoteDefinitionOrder where !keep.contains(defIdx) {
            storage.unlinkChild(defIdx)
        }
        for defIdx in referencedDefs {
            storage.unlinkChild(defIdx)
            storage.appendChild(defIdx, to: documentIndex)
        }
    }

    private mutating func numberFootnoteReferences() -> [DocumentStorage.Index] {
        var referencedDefs: [DocumentStorage.Index] = []
        var indices: [DocumentStorage.Index: Int] = [:]
        var parent = documentIndex
        var child = storage[documentIndex].firstChild
        while true {
            guard let node = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: documentIndex) else {
                    return referencedDefs
                }
                continue
            }
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
            if let first = storage[node].firstChild {
                parent = node
                child = first
            } else {
                child = storage[node].next
            }
        }
    }

    private mutating func parseInline(
        chunk: Chunk,
        scratch: inout InlineScratch,
        into node: DocumentStorage.Index,
        preserveWhitespace: Bool = false
    ) {
        if chunk.inSource {
            // Source-backed: zero-copy slice of the source span.
            parseInline(
                content: ContentSpan(span: sourceBytes.extracting(chunk.range), base: chunk.offset, inSource: true),
                into: node,
                preserveWhitespace: preserveWhitespace
            )
            return
        }
        // Arena-backed: copy the content region out of `storage.strings` so the read view is independent of the appends `parseInline` makes to that same array.
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

    /// Inline-only parse path for `.inlineOnly` / `.preserveWhitespace`.
    private mutating func parseInlineOnly() {
        let count = sourceBytes.count
        guard count > 0 else {
            return
        }

        // Skip a leading UTF-8 BOM.
        var start = 0
        if count >= 3, sourceBytes[0] == 0xEF, sourceBytes[1] == 0xBB, sourceBytes[2] == 0xBF {
            start = 3
        }

        var hasCR = false
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

        let paragraph = addChild(kind: .paragraph, parent: documentIndex, start: start)
        storage.setSourceEnd(paragraph, contentEnd)
        var contentStart = contentEnd
        if positionsEnabled {
            stampDocument()
        }

        let hasNUL = containsNUL(Chunk(offset: start, length: contentEnd - start, inSource: true))
        var image: ContentImage? = nil
        var scratch = InlineScratch()
        if !hasNUL {
            contentHoldsCR = hasCR
            let rest = parseDefinitions(in: Chunk(offset: start, length: count - start, inSource: true))
            contentStart = rest.offset
            parseInline(chunk: rest, scratch: &scratch, into: paragraph, preserveWhitespace: true)
        } else {
            // Normalize `\r\n` and lone `\r` to `\n` into the string arena, then read from an independent scratch copy (the inline parser appends to `storage.strings` as it runs).
            // A CRLF's `\n` images its LF, so a node ending with that line ending covers the CRLF; `lineEndingStart`
            // moves a node starting there to the CR.
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
                        Self.appendContentBytes(1, imaging: j, to: &runs)
                    }
                } else if byte == 0 {
                    appendReplacementCharacter()
                    if positionsEnabled {
                        for _ in 0..<3 {
                            Self.appendContentBytes(1, imaging: j, to: &runs)
                        }
                    }
                } else {
                    storage.strings.append(byte)
                    if positionsEnabled {
                        Self.appendContentBytes(1, imaging: j, to: &runs)
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
        if contentHoldsCR {
            writeLineEndingsAsLineFeeds(inTextOf: paragraph)
        }
        if positionsEnabled {
            endInlinesWithinLastLine(after: paragraph, contentEnd: contentEnd)
        }
    }

    // Input that ends in a line ending ends at column 1 of the line after it, so that line's start is recorded.
    private mutating func stampDocument() {
        let end = sourceBytes.count
        storage.setSourceStart(documentIndex, 0)
        storage.setSourceEnd(documentIndex, end)
        if sourceBytes[end - 1] == UInt8(ascii: "\n") || sourceBytes[end - 1] == UInt8(ascii: "\r") {
            storage.lineStarts.append(end)
        }
    }

    // A node holding the input's final line ending would otherwise end past the last line.
    private mutating func endInlinesWithinLastLine(after paragraph: DocumentStorage.Index, contentEnd: Int) {
        for node in (paragraph + 1)..<storage.nodes.count where storage.sourceRanges[node].end > contentEnd {
            storage.sourceRanges[node].end = contentEnd
            storage.sourceRanges[node].start = min(storage.sourceRanges[node].start, contentEnd)
        }
    }

    func lineEndingStart(_ offset: Int) -> Int {
        offset > 0 && sourceBytes[offset] == UInt8(ascii: "\n") && sourceBytes[offset - 1] == UInt8(ascii: "\r") ? offset - 1 : offset
    }

    @inline(__always)
    fileprivate static func appendContentBytes(_ count: Int, imaging sourceOffset: Int, to runs: inout [ArenaRun]) {
        if let last = runs.last {
            let length = last.length
            let continuesGap = sourceOffset < 0 && last.sourceOffset < 0
            let continuesRun = sourceOffset >= 0 && last.sourceOffset >= 0
                && last.sourceOffset + length == sourceOffset
            if continuesGap || continuesRun {
                runs[runs.count - 1].length += count
                return
            }
        }
        runs.append(ArenaRun(length: count, sourceOffset: sourceOffset))
    }

    private mutating func finishInlines(_ leaf: DocumentStorage.Index, image: ContentImage?) {
        // Coalesce adjacent text nodes so smart-punct / entity substitutions don't leave the content split across sibling text nodes.
        consolidateTextNodes(leaf)
        // Email autolinks (Autolinks (extension)) are found in merged text, after emphasis is resolved.
        if storage.options.contains(.gfmAutolink) {
            gfmEmailAutolinkPass(leaf, image: image)
        }
    }

    // MARK: - State
    
    /// Append a node as a child of the given parent. Returns the new node's index.
    private mutating func addChild(kind: MarkdownNode.Kind, parent: DocumentStorage.Index, data: NodeData? = nil, start: Int) -> DocumentStorage.Index {
        let idx = storage.appendNode(NodeRecord(kind: kind, parent: parent, data: data))
        openBlocksVersion &+= 1
        if !itemsEndingInRemovedParagraph.isEmpty, itemsEndingInRemovedParagraph.removeValue(forKey: parent) == true {
            itemsWithBlankLineAroundRemovedParagraph.insert(parent)
        }
        storage.appendChild(idx, to: parent)
        storage.setSourceStart(idx, start)
        return idx
    }

    /// Consume `pending` and return `node`'s accumulated content, or `nil` if `node` has none (either nothing was pending, or a *different* node's leaf was - which the single-open-leaf invariant forbids).
    ///
    /// Moves the content out; the leaf is destroyed. Used by the append helpers, which always either find their own node's content or none.
    private func take(_ pending: consuming PendingLeaf?, ifNode node: DocumentStorage.Index) -> PendingContent? {
        guard let leaf = pending else {
            return nil
        }
        
        if leaf.node == node {
            return consume leaf.content
        }
        
        fatalError("pending content for node \(leaf.node) must drain before node \(node) accumulates content")
    }

    private mutating func addLine(range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // Code/HTML block bodies accumulate as a zero-copy segment list rather than a materialized byte buffer (they're never inline-parsed). See `addLineSegment`.
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind.isHTMLBlock {
            return addLineSegment(range: range, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .none:
            precondition(nodeKind.canAccumulateText, "only paragraphs and headings accumulate text lines")
            return PendingLeaf(node: node, content: .lazy(range: range))
        case .some(let existing):
            // If this line is also source-backed and immediately follows the previous span in the source - i.e. it starts one byte past the previous span and that byte is a single `\n` - then the join needs no synthesized separator: the embedded `\n` already lives in the source, so we keep the whole run as one zero-copy `.lazy` range.
            switch consume existing {
            case .lazy(let prev, joinPending: true) where range.lowerBound == prev.upperBound + 1
                    && prev.upperBound < sourceBytes.count
                    && sourceBytes[prev.upperBound] == UInt8(ascii: "\n"):
                return PendingLeaf(node: node, content: .lazy(range: prev.lowerBound..<range.upperBound))
            case .lazy(let prev, joinPending: true):
                // Non-contiguous continuation (block-quote/list prefix stripped, CRLF, tab): switch to a source-segment list rather than copying bytes - the previous span becomes a zero-copy source segment, joined to this line by the shared interned `\n`.
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

    /// Append a single `\n` to `pending` for `node`, returning the updated leaf.
    ///
    /// Used to rejoin lines during paragraph continuation, since `LineReader` returns ranges without their line terminators.
    private mutating func appendNewline(to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind.isHTMLBlock {
            return appendSegment(storage.newlineSegment, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .lazy(let range, joinPending: false)?:
            return PendingLeaf(node: node, content: .lazy(range: range, joinPending: true))
        case .segments(let segs)?:
            // A multi-line paragraph already accumulating as segments: the line join is the shared interned `\n` segment (zero-copy), not a byte appended to a materialized buffer.
            return appendSegment(storage.newlineSegment, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
        case .lazy?:
            preconditionFailure("a deferred line join is requested once per line")
        case nil:
            preconditionFailure("a line join follows the leaf's first line")
        }
    }

    /// Empty ranges append nothing (the surrounding `\n` separators carry blank lines), leaving `pending` unchanged.
    private mutating func addLineSegment(range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        guard !range.isEmpty else { return pending }
        return appendSegment(Segment(offset: range.lowerBound, length: range.upperBound - range.lowerBound, inSource: true), to: node, pending: pending)
    }

    private mutating func appendLiteralBodyLine(bodyStart: Int, leadingSpaces: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        if leadingSpaces == 0 && isKnownFreeOfNUL(Chunk(offset: bodyStart, length: lineEnd - bodyStart, inSource: true)) {
            return addLine(range: bodyStart..<lineEnd, to: node, pending: pending)
        }
        return appendLiteralLinePieces(spaces: leadingSpaces, sourceStart: bodyStart, lineEnd: lineEnd, to: node, pending: pending)
    }

    private func contentEnd(ofLine lineRange: Range<Int>, bodyStart: Int, leadingSpaces: Int) -> Int {
        bodyStart < lineRange.upperBound || leadingSpaces > 0 ? lineRange.upperBound : lineRange.lowerBound
    }

    // A block quote marker's optional space or a list item's indent can consume part of a tab, leaving `cursor`
    // mid-tab; the tab's remaining columns become spaces (Tabs).
    private mutating func htmlLineBody(lineRange: Range<Int>, cursor: Int, column: Int) -> (bodyStart: Int, leadingSpaces: Int) {
        var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
        let priorColumn = lineColumns.column(at: cursor, in: sourceBytes)
        return stripIndent(
            range: cursor..<lineRange.upperBound,
            maxColumns: column - priorColumn,
            startColumn: priorColumn
        )
    }

    private mutating func appendLiteralLinePieces(spaces: Int, sourceStart: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        var arenaPieceStart = storage.strings.count
        for _ in 0..<spaces {
            storage.strings.append(UInt8(ascii: " "))
        }
        var start = sourceStart
        while true {
            let nul = start + Self.firstNUL(in: sourceBytes.extracting(start..<lineEnd))
            if nul > start {
                if storage.strings.count > arenaPieceStart {
                    pending = appendSegment(Segment(offset: arenaPieceStart, length: storage.strings.count - arenaPieceStart, inSource: false), to: node, pending: pending)
                }
                pending = appendSegment(Segment(offset: start, length: nul - start, inSource: true), to: node, pending: pending)
                arenaPieceStart = storage.strings.count
            }
            guard nul < lineEnd else {
                break
            }
            appendReplacementCharacter()
            start = nul + 1
        }
        if storage.strings.count > arenaPieceStart {
            pending = appendSegment(Segment(offset: arenaPieceStart, length: storage.strings.count - arenaPieceStart, inSource: false), to: node, pending: pending)
        }
        return pending
    }

    private static func firstNUL(in span: Span<UInt8>) -> Int {
        let nul = SIMD16<UInt8>(repeating: 0)
        return span.firstIndex(matching: { $0 .== nul }, or: { $0 == 0 })
    }

    private mutating func noteLineRead(_ reader: borrowing LineReader) {
        if reader.lineFirstNUL < reader.lineRange.upperBound {
            nulFreeSourceStart = reader.lineRange.upperBound
        }
        sourceReadEnd = reader.lineRange.upperBound
    }

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
        let lineJoin = storage.newlineSegment
        for i in 0..<segs.count where segs[i] != lineJoin && containsNUL(segs[i].chunk) {
            return true
        }
        return false
    }

    private mutating func replacingNUL(_ chunk: Chunk) -> Chunk {
        containsNUL(chunk) ? copyReplacingNUL(chunk) : chunk
    }

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

    private mutating func replacingNUL(_ chunk: Chunk, map: inout [ArenaRun]) -> Chunk {
        guard containsNUL(chunk) else { return chunk }
        if positionsEnabled {
            map = rewrittenMap(sourceImage(of: chunk, map: map), of: chunk) { readByte(at: $0, in: chunk) == 0 ? 3 : 1 }
        }
        return copyReplacingNUL(chunk)
    }

    func rewrittenMap(_ map: [ArenaRun], of chunk: Chunk, copies: (Int) -> Int) -> [ArenaRun] {
        assert(map.isEmpty || map.reduce(0) { $0 + $1.length } == chunk.length, "a run map must tile its chunk")
        var rewritten: [ArenaRun] = []
        var i = chunk.offset
        for run in map {
            for local in 0..<run.length {
                let sourceOffset = run.sourceOffset < 0 ? -1 : run.sourceOffset + local
                for _ in 0..<copies(i) {
                    Self.appendContentBytes(1, imaging: sourceOffset, to: &rewritten)
                }
                i += 1
            }
        }
        return rewritten
    }

    func sourceImage(of chunk: Chunk, map: [ArenaRun]) -> [ArenaRun] {
        if map.isEmpty, chunk.inSource, chunk.length > 0 {
            return [ArenaRun(length: chunk.length, sourceOffset: chunk.offset)]
        }
        return map
    }

    /// Append a single `Segment` to `node`'s pending segment list, starting one if needed; returns the updated leaf.
    ///
    /// The existing list is *moved* out of `pending` and extended in place.
    private mutating func appendSegment(_ segment: Segment, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        if case .segments(var segs)? = take(pending, ifNode: node) {
            segs.append(segment)
            return PendingLeaf(node: node, content: .segments(segs))
        }
        return PendingLeaf(node: node, content: .segments(UniqueArray(repeating: segment, count: 1)))
    }

    /// Drain `node`'s pending segment list (for code/HTML block finalize).
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

    private func lastNewline(in range: Range<Int>) -> Int? {
        var i = range.upperBound - 1
        while i >= range.lowerBound {
            if sourceBytes[i] == UInt8(ascii: "\n") { return i }
            i -= 1
        }
        return nil
    }

    private func lastLineJoin(in segs: borrowing UniqueArray<Segment>) -> Int {
        let nl = storage.newlineSegment
        var i = segs.count - 1
        while i >= 0 && segs[i] != nl {
            i -= 1
        }
        precondition(i >= 0, "a paragraph's segment list holds a line join")
        return i
    }

    private func lastLineStart(of leaf: borrowing PendingLeaf) -> Int {
        switch leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            return lastNewline(in: range).map { $0 + 1 } ?? range.lowerBound
        case .segments(let segs):
            return lastLineJoin(in: segs) + 1
        }
    }

    private mutating func lastLineOpensTable(delimRange: Range<Int>, pending: borrowing PendingLeaf, lastLineStart: Int) -> Int? {
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

    private mutating func detectPendingTable(_ node: DocumentStorage.Index, delimRange: Range<Int>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        let headerStart = lastLineStart(of: pending!)
        guard let columns = lastLineOpensTable(delimRange: delimRange, pending: pending!, lastLineStart: headerStart),
              !lineBeforeLastExceedsRowCellLimit(pending: pending!, lastLineStart: headerStart) else {
            return pending
        }
        openParagraphState!.tablePending = true
        openParagraphState!.tableColumns = columns
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

    private mutating func lineBeforeLastExceedsRowCellLimit(pending: borrowing PendingLeaf, lastLineStart: Int) -> Bool {
        if openParagraphState!.holdsLineOverRowCellLimit {
            return true
        }
        // A line has no more cells than bytes, so no line exceeds a limit of at least the source's length.
        guard limits.maxTableRowCells < sourceBytes.count else {
            return false
        }
        var found = false
        switch pending.content {
        case .lazy(let range, _):
            found = lastLineStart > range.lowerBound && holdsLineOverRowCellLimit(range.lowerBound..<(lastLineStart - 1))
        case .segments(let segs):
            let nl = storage.newlineSegment
            for i in 0..<lastLineStart where segs[i] != nl {
                precondition(segs[i].inSource, "a paragraph's lines are source segments joined by line joins")
                if holdsLineOverRowCellLimit(segs[i].chunk.range) {
                    found = true
                    break
                }
            }
        }
        openParagraphState!.holdsLineOverRowCellLimit = found
        return found
    }

    private mutating func splitContiguousHeader(_ node: DocumentStorage.Index, range: Range<Int>, lastNewline: Int) -> PendingLeaf? {
        let headerRange = (lastNewline + 1)..<range.upperBound
        // The preceding lines are non-blank, but trim to empty when they hold only spaces, tabs, line tabulations and
        // form feeds.
        let precedingLines = Chunk(offset: range.lowerBound, length: lastNewline - range.lowerBound, inSource: true)
        // The split-off lines are a paragraph that bypasses finalize, so its raw content is formed here.
        if let precedingChunk = tableSplitParagraphContent(precedingLines.trimmingWhitespace(using: self), node: node, linesStart: precedingLines.offset) {
            let preceding = insertTablePrecedingParagraph(before: node)
            let span = precedingChunk.isEmpty ? Chunk(offset: precedingLines.offset, length: 0, inSource: true) : precedingChunk
            storage.setSourceStart(preceding, span.offset)
            storage.setSourceEnd(preceding, span.offset + span.length)
            var map: [ArenaRun] = []
            let nulReplaced = replacingNUL(precedingChunk, map: &map)
            enqueueTablePrecedingContent(nulReplaced, map: map, of: preceding)
        }
        storage.setSourceStart(node, headerRange.lowerBound)
        return PendingLeaf(node: node, content: .lazy(range: headerRange))
    }

    private mutating func enqueueTablePrecedingContent(_ content: Chunk, map: [ArenaRun], of node: DocumentStorage.Index) {
        if content.isEmpty {
            return
        }
        if positionsEnabled, !content.inSource {
            arenaSourceMaps[node] = map
        }
        pendingInlines.append((node, storage.intern(content)))
    }

    private mutating func insertTablePrecedingParagraph(before node: DocumentStorage.Index) -> DocumentStorage.Index {
        let paragraph = storage.appendNode(NodeRecord(kind: .paragraph, parent: storage[node].parent))
        storage.insertChildBefore(paragraph, before: node)
        return paragraph
    }

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
        // These lines bypass finalize, so a NUL in them forces a flatten here, since inline content read through a
        // segment list can't carry the U+FFFD (see `ContentSpan`).
        if segmentsContainNUL(segs) {
            var map: [ArenaRun] = []
            let flat = flattenReplacingNUL(segs, map: &map)
            if let content = tableSplitParagraphContent(flat.trimmingWhitespace(using: self), node: precedingNode, linesStart: flat.offset) {
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
        } else if openParagraphState?.definitionsCommitted == true {
            storage.unlinkChild(precedingNode)
        } else {
            emptySourceRangeAtStart(precedingNode)
        }
        if positionsEnabled {
            storage.setSourceStart(node, segmentsSourceSpan(header).start)
        }
        return PendingLeaf(node: node, content: .segments(header))
    }

    private func segmentsSourceSpan(_ segs: borrowing UniqueArray<Segment>) -> (start: Int, end: Int) {
        precondition(segs.count > 0, "a paragraph's split-off lines and header line are never empty")
        let first = segs[0]
        let last = segs[segs.count - 1]
        precondition(first.inSource && last.inSource, "a paragraph's lines start and end on a source byte")
        return (first.offset, last.offset + last.length)
    }

    private mutating func sourceEnd(ofVirtual end: Int, in segs: borrowing UniqueArray<Segment>, total: Int) -> Int {
        precondition(end > 0, "a paragraph's content that is not whitespace is not empty")
        let (i, segmentStart) = segment(endingAtOrAfter: end, in: segs, total: total)
        precondition(segs[i].inSource, "a paragraph's lines start and end on a source byte")
        return segs[i].offset + end - segmentStart
    }

    // Searched from the end, since the end of a leaf's trimmed lines lies in or near its last line.
    private func segment(endingAtOrAfter end: Int, in segs: borrowing UniqueArray<Segment>, total: Int) -> (index: Int, start: Int) {
        var i = segs.count - 1
        var start = total - segs[i].length
        while start >= end {
            i -= 1
            start -= segs[i].length
        }
        return (i, start)
    }

    private func sourceSpan(of map: [ArenaRun]) -> (start: Int, end: Int) {
        guard let first = map.first, let last = map.last, first.sourceOffset >= 0, last.sourceOffset >= 0 else {
            preconditionFailure("trimmed paragraph content starts and ends on source bytes")
        }
        return (first.sourceOffset, last.sourceOffset + last.length)
    }

    // MARK: - Per-line dispatcher

    /// Process a line of Markdown.
    ///  - lineRange: The range of the line in the original source, in order to lazily reference it.
    private mutating func processLine(lineRange: Range<Int>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        // PHASE 1: Walk the open-container chain, stripping each container's continuation prefix. `deepestMatched` is the deepest container whose continuation succeeded (always a container, never a leaf). `cursor` is the byte offset into the line after stripped prefixes.
        let walk = walkOpenContainers(lineRange: lineRange)
        let deepestMatched = walk.deepestMatched
        let cursor = walk.cursor
        let prefixColumns = walk.prefixColumns
        let allMatched = walk.allMatched

        let openKind = storage[current].kind
        // PHASE 2a: Code-block / HTML-block continuation - only when the prefix walk reached the leaf. If the walk failed before that, the block must close.
        if openKind.isCodeBlock || openKind.isHTMLBlock {
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

        // PHASE 2b: Blank line.
        if scan.isBlank {
            return handleBlankLine(deepestMatched: deepestMatched, allMatched: allMatched, pending: pending)
        }
        // A container the line fails keeps its flag: the line closes it, or continues lazily a paragraph it holds, which a blank line would have closed, so its flag is already clear.
        var clearUp: DocumentStorage.Index? = deepestMatched
        while let clearUp_ = clearUp {
            storage.nodes[clearUp_].lastLineBlank = false
            clearUp = storage[clearUp_].parent
        }

        // PHASE 2c: Setext heading underline transforms an open paragraph that's a direct descendant of the deepest matched container. See spec examples 64, 69, 27, 30.
        if underlineParagraph(line: &line, pending: &pending) {
            return pending
        }

        // PHASE 2d: When a paragraph is open, decide whether this line starts a new block (which closes the paragraph) or is absorbed as lazy/matched continuation.
        if !allMatched && scan.firstNonSpace > cursor {
            recordLazyLineWhitespace(lineStart: lineRange.lowerBound, cursor: cursor, firstNonSpace: scan.firstNonSpace, prefixColumns: prefixColumns)
        }
        if absorbParagraphLine(line: line, pending: &pending) {
            return pending
        }

        // PHASE 3: Close stale containers down to deepestMatched.
        while current != deepestMatched {
            pending = finalize(node: current, pending: pending)
        }

        // PHASE 4: New-block dispatch. Containers (block quote) loop back so a single line like `> > foo` opens both quotes and then a paragraph.
        return dispatchNewBlocks(
            lineRange: lineRange,
            startCursor: cursor,
            startColumn: prefixColumns,
            pending: pending
        )
    }

    private struct LineContext {
        var lineRange: Range<Int>
        var deepestMatched: DocumentStorage.Index
        var cursor: Int
        var allMatched: Bool
        var firstNonSpace: Int
        var firstNonSpaceByte: UInt8
        var indent: Int
        var prefixColumns: Int
        var openKind: MarkdownNode.Kind
    }

    private mutating func continueOrCloseLeafBlock(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, allMatched: Bool, pending: consuming PendingLeaf?) -> LeafContinuation {
        guard allMatched else {
            return LeafContinuation(consumedLine: false, pending: finalize(node: current, pending: pending))
        }
        if storage[current].kind.isCodeBlock {
            return handleCodeBlockContinuation(lineRange: lineRange, cursor: cursor, prefixColumns: prefixColumns, pending: pending)
        }
        return handleHTMLBlockContinuation(lineRange: lineRange, cursor: cursor, prefixColumns: prefixColumns, pending: pending)
    }

    private mutating func handleBlankLine(deepestMatched: DocumentStorage.Index, allMatched: Bool, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let nowOpen = storage[current].kind
        if nowOpen.canAccumulateText {
            pending = finalize(node: current, pending: pending)
        }
        // If a container in the chain failed to continue, close it now.
        if !allMatched {
            while current != deepestMatched {
                pending = finalize(node: current, pending: pending)
            }
        }
        // For list tightness (Lists), the blank line belongs to the deepest container that matched it and follows that container's last block, if any. A block quote, whose lines all begin with `>`, doesn't end with it.
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
        assert(storage[container].parent.map { !storage.nodes[$0].lastLineBlank } ?? true, "only the deepest open container ends with a blank line")
        return pending
    }

    private var openParagraphIsTablePending: Bool {
        assert(openParagraphState.map { $0.node == current } ?? true, "the recorded state belongs to the open leaf")
        return openParagraphState?.tablePending == true
    }

    private mutating func underlineParagraph(line: inout LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        // A table-pending paragraph is a table, which no underline turns into a heading: `r\n|-\n=` is a table with a `=` body row.
        guard line.openKind.isParagraph && line.allMatched && !openParagraphIsTablePending && line.indent < 4,
              let underline = matchSetextUnderline(range: line.cursor..<lineRange.upperBound, firstNonSpace: line.firstNonSpace) else {
            return false
        }
        return handleSetextUnderline(underline, line: &line, pending: &pending)
    }

    @inline(never)
    private mutating func handleSetextUnderline(_ underline: (level: UInt8, end: Int), line: inout LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        let para = current
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        if openParagraphState == nil {
            openParagraphState = OpenParagraphState(node: para)
        }
        assert(openParagraphState!.node == para, "the recorded state belongs to the open paragraph")
        // Each line of a setext heading holds a non-whitespace character (Setext headings). Once a line of only
        // whitespace keeps an underline from forming the heading, a later one can form it only by ending a definition
        // that takes the line in.
        if openParagraphState!.headingHoldsWhitespaceOnlyLine && !incompleteDefinitionMayComplete(pending!) {
            return false
        }
        // Strip any leading reference-link definitions from the paragraph's accumulated content first.
        if let content = commitLeadingDefinitions(&pending) {
            if !openParagraphState!.holdsWhitespaceOnlyLine && holdsWhitespaceOnlyLine(pending!) {
                openParagraphState!.holdsWhitespaceOnlyLine = true
            }
            if openParagraphState!.headingHoldsWhitespaceOnlyLine {
                return false
            }
            precondition(!content.isEmpty, "a paragraph without a line of only whitespace holds a non-whitespace character")
            makeHeading(para, level: underline.level, content: narrowedContent(pending.take()!, to: content), underlineEnd: underline.end)
            return true
        }
        // The paragraph of only definitions is open while this line is examined, so a line that can't interrupt a
        // paragraph, such as `===` or a lone `-`, continues it and becomes its text once the definitions go.
        let continuesParagraph = !lineStartsNewBlock(
            range: line.cursor..<lineRange.upperBound,
            firstNonSpace: line.firstNonSpace,
            indent: line.indent,
            baseColumn: line.prefixColumns,
            interruptsParagraph: true
        )
        if continuesParagraph {
            pending = addLine(range: line.firstNonSpace..<lineRange.upperBound, to: para, pending: nil)
            openParagraphState!.holdsWhitespaceOnlyLine = false
            openParagraphState!.incompleteDefinition = nil
            return true
        }
        // The new block opens in the same container, past the definitions, so they need not extend the container's
        // range.
        pending = nil
        removeEmptiedParagraph(para, contentEnd: nil)
        openParagraphState = nil
        guard let parent = storage[para].parent else {
            fatalError("a paragraph always has a parent")
        }
        current = parent
        line.openKind = storage[current].kind
        return false
    }

    // A line of only whitespace that includes a line tabulation or form feed is not blank (Characters and lines), so
    // a paragraph can hold one.
    private func holdsWhitespaceOnlyLine(_ leaf: borrowing PendingLeaf) -> Bool {
        var lineHoldsNonWhitespace = false
        switch leaf.content {
        case .lazy(let range, _):
            if Self.endsWhitespaceOnlyLine(sourceBytes.extracting(range), lineHoldsNonWhitespace: &lineHoldsNonWhitespace) {
                return true
            }
        case .segments(let segs):
            for i in 0..<segs.count {
                let chunk = segs[i].chunk
                let bytes = chunk.inSource ? sourceBytes.extracting(chunk.range) : storage.strings.span.extracting(chunk.range)
                if Self.endsWhitespaceOnlyLine(bytes, lineHoldsNonWhitespace: &lineHoldsNonWhitespace) {
                    return true
                }
            }
        }
        return !lineHoldsNonWhitespace
    }

    private static func endsWhitespaceOnlyLine(_ bytes: Span<UInt8>, lineHoldsNonWhitespace: inout Bool) -> Bool {
        for i in bytes.indices {
            let b = bytes[i]
            if b == UInt8(ascii: "\n") {
                if !lineHoldsNonWhitespace {
                    return true
                }
                lineHoldsNonWhitespace = false
            } else if !b.isLineWhitespace {
                lineHoldsNonWhitespace = true
            }
        }
        return false
    }

    // The lines before an underline are read as the paragraph they would be without it (Setext headings), so the
    // definitions that paragraph begins with end there for good.
    private mutating func commitLeadingDefinitions(_ pending: inout PendingLeaf?) -> Range<Int>? {
        let lines = leadingDefinitions(of: pending!)
        guard let definitions = lines.definitions else {
            openParagraphState!.incompleteDefinition = .cannotComplete
            return lines.trimmed
        }
        guard definitions.end > lines.trimmed.lowerBound else {
            return lines.trimmed
        }
        openParagraphState!.definitionsCommitted = true
        openParagraphState!.holdsWhitespaceOnlyLine = false
        openParagraphState!.holdsLineOverRowCellLimit = false
        var rest = definitions.end
        var content = definitions.contentStart..<lines.trimmed.upperBound
        if content.isEmpty {
            // Each line of only whitespace after the definitions' last line is a heading line, and the last stands for
            // them all.
            guard lines.lastLineStart >= lines.trimmed.upperBound else {
                return nil
            }
            rest = lines.lastLineStart
            content = rest..<rest
        }
        pending = PendingLeaf(node: openParagraphState!.node, content: trailingLines(pending.take()!, from: rest))
        let start = leafStart(pending!)
        return (start + content.lowerBound - rest)..<(start + content.upperBound - rest)
    }

    private mutating func trailingLines(_ leaf: consuming PendingLeaf, from start: Int) -> PendingContent {
        switch consume leaf.content {
        case .lazy(let range, _):
            return .lazy(range: start..<range.upperBound)
        case .segments(let segs):
            let total = totalLength(of: segs)
            let rest = segments(segs, in: start..<total, total: total)
            // A segment list holds a line join, so a lone segment left becomes a source range.
            if let range = Self.onlySegmentRange(rest) {
                return .lazy(range: range)
            }
            return .segments(rest)
        }
    }

    private static func onlySegmentRange(_ segs: borrowing UniqueArray<Segment>) -> Range<Int>? {
        segs.count == 1 ? segs[0].chunk.range : nil
    }

    private func leafStart(_ leaf: borrowing PendingLeaf) -> Int {
        switch leaf.content {
        case .lazy(let range, _):
            return range.lowerBound
        case .segments:
            return 0
        }
    }

    private struct LeadingDefinitionLines {
        let lastLineStart: Int
        let trimmed: Range<Int>
        let definitions: (end: Int, contentStart: Int)?
    }

    private mutating func leadingDefinitions(of leaf: borrowing PendingLeaf) -> LeadingDefinitionLines {
        switch leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            let trimmed = Chunk(offset: range.lowerBound, length: range.count, inSource: true).trimmingWhitespace(using: self).range
            var definitions: (end: Int, contentStart: Int)? = nil
            if !trimmed.isEmpty, Self.mayBeginDefinition(sourceBytes[trimmed.lowerBound]), definitionMayBegin(at: trimmed.lowerBound, linesStart: range.lowerBound) {
                let content = ContentSpan(span: sourceBytes.extracting(range.lowerBound..<trimmed.upperBound), base: range.lowerBound, inSource: true)
                definitions = readLeadingDefinitions(in: content, linesStart: range.lowerBound, from: trimmed.lowerBound, readEnd: trimmed.upperBound)
            }
            let lastLineStart = lastNewline(in: range).map { $0 + 1 } ?? range.lowerBound
            return LeadingDefinitionLines(lastLineStart: lastLineStart, trimmed: trimmed, definitions: definitions)
        case .segments(let segs):
            let total = totalLength(of: segs)
            let trimmed = trimmedRange(of: segs, total: total)
            var definitions: (end: Int, contentStart: Int)? = nil
            if !trimmed.isEmpty, Self.mayBeginDefinition(byte(at: trimmed.lowerBound, in: segs)), definitionMayBegin(at: trimmed.lowerBound, linesStart: 0) {
                let readEnd = sourceEnd(ofVirtual: trimmed.upperBound, in: segs, total: total)
                let segmentEnds = Self.segmentEnds(of: segs)
                let content = ContentSpan(source: sourceBytes, segments: segs.span, segmentEnds: segmentEnds.span, virtualLength: trimmed.upperBound, hint: pieceHint)
                definitions = readLeadingDefinitions(in: content, linesStart: 0, from: trimmed.lowerBound, readEnd: readEnd)
            }
            let lastLineStart = total - segs[segs.count - 1].length
            return LeadingDefinitionLines(lastLineStart: lastLineStart, trimmed: trimmed, definitions: definitions)
        }
    }

    private mutating func readLeadingDefinitions(in content: borrowing ContentSpan, linesStart: Int, from start: Int, readEnd: Int) -> (end: Int, contentStart: Int) {
        let end = definitionsEnd(in: content, from: start)
        openParagraphState!.incompleteDefinition = incompleteDefinition(at: end, in: content, readEnd: readEnd)
        if end > start {
            var i = linesStart
            while i < start, content[i] != UInt8(ascii: "\n") {
                i += 1
            }
            if i < start {
                openParagraphState!.whitespaceOnlyLineBeforeDefinitions = true
            }
        }
        return (end, skipWhitespace(from: end, in: content))
    }

    // A later line can only close a label still open at the end, begin the destination or attributes after a label at
    // the end, or close a title still open on its destination's line (Link reference definitions).
    private mutating func incompleteDefinition(at start: Int, in content: borrowing ContentSpan, readEnd: Int) -> IncompleteDefinition? {
        let end = content.endOffset
        guard start < end else {
            return .cannotComplete
        }
        let isAttributeDefinition = content[start] == UInt8(ascii: "^")
        var labelStart = start
        if isAttributeDefinition {
            guard storage.options.contains(.attributes), start + 1 < end, content[start + 1] == UInt8(ascii: "[") else {
                return .cannotComplete
            }
            labelStart = start + 1
        } else if content[start] != UInt8(ascii: "[") {
            return .cannotComplete
        }
        guard let (label, contentStart) = matchDefinitionLabel(from: labelStart, in: content) else {
            return linkLabelIsOpen(from: labelStart, end: end, in: content) ? .openLabel(readEnd: readEnd) : .cannotComplete
        }
        if normalizeLabel(virtualRange: label, in: content).isEmpty {
            return .cannotComplete
        }
        if contentStart == end {
            return nil
        }
        // Attributes complete the definition on whatever line they begin.
        if isAttributeDefinition {
            return .cannotComplete
        }
        destinationParentheses.reset()
        guard let destination = matchLinkDestination(from: contentStart, end: end, in: content) else {
            return .cannotComplete
        }
        let titleStart = skipLineWhitespace(from: destination.afterEnd, in: content)
        guard titleStart > destination.afterEnd, titleStart < end, var title = LinkTitleScan(opener: content[titleStart]) else {
            return .cannotComplete
        }
        var i = titleStart + 1
        while i < end, title.canContinue {
            _ = title.read(content[i])
            i += 1
        }
        return title.canContinue ? .openTitle(title, readEnd: readEnd) : .cannotComplete
    }

    private mutating func incompleteDefinitionMayComplete(_ leaf: borrowing PendingLeaf) -> Bool {
        let recorded = openParagraphState!.incompleteDefinition
        switch recorded {
        case nil:
            return true
        case .cannotComplete?:
            return false
        case .openLabel(let readEnd)?:
            guard let end = linesEndBeforeLabelCloser(from: readEnd, in: leaf) else {
                return true
            }
            openParagraphState!.incompleteDefinition = .openLabel(readEnd: end)
            return false
        case .openTitle(var title, let readEnd)?:
            let read = readTitle(&title, from: readEnd, in: leaf)
            if read.closes {
                return true
            }
            openParagraphState!.incompleteDefinition = title.canContinue ? .openTitle(title, readEnd: read.end) : .cannotComplete
            return false
        }
    }

    private func readTitle(_ title: inout LinkTitleScan, from start: Int, in leaf: borrowing PendingLeaf) -> (closes: Bool, end: Int) {
        var closer: (end: Int, lineEnd: Int)? = nil
        let end = forEachLineRun(from: start, in: leaf) { run in
            if let run {
                readTitle(&title, sourceBytes: run, lastCloser: &closer)
            } else if title.canContinue {
                _ = title.read(UInt8(ascii: "\n"))
            }
        }
        guard let closer else {
            return (false, end)
        }
        var i = closer.end
        while i < closer.lineEnd, sourceBytes[i] != UInt8(ascii: "\n") {
            if !sourceBytes[i].isLineWhitespace {
                return (false, end)
            }
            i += 1
        }
        return (true, end)
    }

    private func linesEndBeforeLabelCloser(from start: Int, in leaf: borrowing PendingLeaf) -> Int? {
        var closerFound = false
        var escaped = false
        let end = forEachLineRun(from: start, in: leaf) { run in
            // A backslash escapes nothing across a line ending (Backslash escapes).
            guard let run else {
                escaped = false
                return
            }
            var i = run.lowerBound
            while i < run.upperBound, !closerFound {
                let b = sourceBytes[i]
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "]") {
                    closerFound = true
                }
                i += 1
            }
        }
        return closerFound ? nil : end
    }

    private func forEachLineRun(from start: Int, in leaf: borrowing PendingLeaf, _ body: (Range<Int>?) -> Void) -> Int {
        switch leaf.content {
        case .lazy(let range, _):
            body(start..<range.upperBound)
            return range.upperBound
        case .segments(let segs):
            var first = segs.count - 1
            while !(segs[first].inSource && segs[first].offset < start) {
                first -= 1
            }
            body(start..<(segs[first].offset + segs[first].length))
            for i in (first + 1)..<segs.count {
                body(segs[i].inSource ? segs[i].chunk.range : nil)
            }
            return segmentsSourceSpan(segs).end
        }
    }

    private func readTitle(_ title: inout LinkTitleScan, sourceBytes range: Range<Int>, lastCloser: inout (end: Int, lineEnd: Int)?) {
        var i = range.lowerBound
        while i < range.upperBound, title.canContinue {
            if title.read(sourceBytes[i]) {
                lastCloser = (i + 1, range.upperBound)
            }
            i += 1
        }
    }

    private mutating func narrowedContent(_ leaf: consuming PendingLeaf, to range: Range<Int>) -> PendingContent {
        switch consume leaf.content {
        case .lazy:
            return .lazy(range: range)
        case .segments(let segs):
            let total = totalLength(of: segs)
            return .segments(segments(segs, in: range, total: total))
        }
    }

    private mutating func makeHeading(_ para: DocumentStorage.Index, level: UInt8, content: consuming PendingContent, underlineEnd: Int) {
        storage[para].kind = .heading(level: Int(level))
        openParagraphState = nil
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

    private mutating func absorbParagraphLine(line: LineContext, pending: inout PendingLeaf?) -> Bool {
        let lineRange = line.lineRange
        let tablePending = openParagraphIsTablePending
        let rowRange = line.firstNonSpace..<lineRange.upperBound
        // A table-pending paragraph is a table, and only a paragraph takes a lazy continuation line or a line indented
        // four or more columns (Block quotes, Indented code blocks).
        let breaksOutOfPendingTable = tablePending
            && (!line.allMatched
                || line.indent >= 4
                || isLonePipeRow(range: rowRange)
                || !tableLimitsAdmitRow(rowRange, autocompletedCells: openParagraphState!.tableAutocompletedCells))
        if !line.openKind.isParagraph || breaksOutOfPendingTable {
            return false
        }
        // The limits on interrupting a paragraph (List items) never apply to a table, and apply to a paragraph only
        // when its own container matched, so `2.` in `1. a\n2. b` opens an item.
        let interruptsParagraph = !tablePending
            && storage[current].parent == line.deepestMatched
        // The matcher ladder can only return true if the first content byte is one that some block construct starts with; for ordinary prose continuation lines it isn't, so we skip the whole ladder. `mightStartBlock` is a superset of every matcher's trigger byte, so a `false` here is exactly what `lineStartsNewBlock` would have returned.
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
        // Continue paragraph (matched or lazy). Don't close stale containers - the paragraph absorbs without breaking the chain.
        if tablePending {
            openParagraphState!.tableAutocompletedCells = autocompletedCells(
                openParagraphState!.tableAutocompletedCells, afterRow: rowRange, columns: openParagraphState!.tableColumns)
        } else if storage.options.contains(.tables) {
            recordTableDelimiterCandidate(line: line, pending: &pending)
        }
        pending = appendNewline(to: current, pending: consume pending)
        pending = addLine(range: line.firstNonSpace..<lineRange.upperBound, to: current, pending: consume pending)
        return true
    }

    @inline(never)
    private mutating func recordLazyLineWhitespace(lineStart: Int, cursor: Int, firstNonSpace: Int, prefixColumns: Int) {
        var lineColumns = LineColumns(lineStart: lineStart)
        var whitespace = firstNonSpace - cursor
        let cursorColumn = lineColumns.column(at: cursor, in: sourceBytes)
        // A partly consumed tab counts only the columns it has left (Tabs).
        if prefixColumns > cursorColumn {
            whitespace += 3 - (prefixColumns & 3)
        }
        let recorded = lazyLineWhitespace ?? LazyLineWhitespace()
        recorded.bySourceOffset[firstNonSpace] = whitespace
        lazyLineWhitespace = recorded
    }

    @inline(__always)
    private mutating func recordTableDelimiterCandidate(line: LineContext, pending: inout PendingLeaf?) {
        let delimRange = line.firstNonSpace..<line.lineRange.upperBound
        if openParagraphState == nil {
            openParagraphState = OpenParagraphState(node: current)
        }
        assert(openParagraphState!.node == current, "the recorded state belongs to the open paragraph")
        if !openParagraphState!.tablePending,
           line.indent < 4, line.allMatched,
           couldBeDelimiterRow(range: delimRange) {
            pending = detectPendingTable(current, delimRange: delimRange, pending: consume pending)
        }
    }

    /// Walk the open-container chain top-down, stripping each container's continuation prefix.
    ///
    /// Returns the deepest container whose prefix matched (always a container, never a leaf), the cursor into the line after stripped prefixes, and whether every container in the chain matched.
    private mutating func walkOpenContainers(lineRange: Range<Int>) -> (deepestMatched: DocumentStorage.Index, cursor: Int, prefixColumns: Int, allMatched: Bool) {
        var cursor = lineRange.lowerBound
        var deepestMatched = documentIndex
        var prefixColumns = 0
        var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
        // Containers that consume only spaces and tabs leave this unchanged, so a chain of nested items scans the
        // line's indent once.
        var firstNonSpaceAhead = -1

        var node = documentIndex
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
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .list:
                // Lists themselves don't have a per-line continuation rule; their items do. The list as a container "matches" trivially as long as we get to one of its items.
                deepestMatched = node
            case .item, .footnoteDefinition:
                // Item continuation: line indent must be ≥ the item's content padding.
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
                // Compare in COLUMNS, not bytes, so a leading tab counts as up to 4 cols of indent.
                // Each whitespace byte spans at least one column, so `padding` bytes decide.
                let availCols = indentColumns(from: cursor, to: min(firstNonSpace, cursor + padding), baseColumn: prefixColumns)
                if availCols >= padding {
                    cursor = advanceColumns(
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: padding,
                        baseColumn: prefixColumns
                    )
                    // Record the intended column even when a partly consumed tab kept `cursor` from passing it (Tabs).
                    prefixColumns += padding
                    deepestMatched = node
                } else if isBlank {
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
            case .paragraph, .codeBlock, .htmlBlock:
                // Leaves; they don't have container-level prefix matching. The chain effectively ends here. Caller decides leaf-specific continuation (e.g. code-block fence detection).
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

    // Where the walk ends with nothing left of the line depends only on the open blocks from `start` down, so it is
    // recorded per block passed and reused until `openBlocksVersion` changes. Otherwise `n` blank lines in a chain of
    // `n` open footnote definitions walk `n` squared.
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
            case .paragraph, .codeBlock, .htmlBlock:
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

    /// Returns `true` if the line's content (starting at `firstNonSpace`) begins a new block that would interrupt an open paragraph.
    private mutating func lineStartsNewBlock(range: Range<Int>, firstNonSpace: Int, indent: Int, baseColumn: Int, interruptsParagraph: Bool) -> Bool {
        // Indented code does not interrupt a paragraph (CommonMark 0.31 §4.4).
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
        // Type 7 can't interrupt a paragraph (HTML blocks), but a line the paragraph's own container fails continues
        // nothing, so `>o\n<d>` opens an HTML block.
        if matchHTMLBlockStart(range: range, firstNonSpace: firstNonSpace, allowType7: !interruptsParagraph) != nil {
            return true
        }
        // The line has opened no container yet, so a list marker or a footnote definition is recognized here unless the
        // limit on containers opened before one is negative.
        if limits.maxContainersOpenedOnLineBeforeListMarker < 0 {
            return false
        }
        // A footnote definition interrupts a paragraph, so `[^a]: A\n[^b]: B` is two definitions.
        if storage.options.contains(.footnotes),
           matchFootnoteDefinition(range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        if let marker = matchListMarker(range: range, firstNonSpace: firstNonSpace, markerColumn: baseColumn + indent, indent: indent) {
            if marker.isEmpty {
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

    /// Continue an open HTML block.
    private mutating func handleHTMLBlockContinuation(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        guard case .htmlBlock(let type, _) = storage[current].data else {
            preconditionFailure("an HTML block node always carries its block type")
        }
        // Types 6 and 7 end on a blank line; the blank line is *not* part of the block content.
        // The line is left unconsumed so blank-line handling records it for list tightness.
        if type >= 6, indexOfFirstNonSpace(range: cursor..<lineRange.upperBound) == lineRange.upperBound {
            return LeafContinuation(consumedLine: false, pending: finalize(node: current, pending: pending))
        }
        // The line that contains the end pattern is appended *and* closes the block - it's fully consumed, so we return `true` to suppress new-block redispatch on the closing line.
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

    /// Continue an open code block.
    private mutating func handleCodeBlockContinuation(lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        let firstNonSpace = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound

        if case .codeBlock(let info) = storage[current].kind, info.isFenced {
            // Fenced.
            var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
            let startColumn = lineColumns.column(at: cursor, in: sourceBytes)
            let closingFenceIndent = lineColumns.column(at: firstNonSpace, in: sourceBytes) - prefixColumns
            if let fenceEnd = matchClosingFence(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indentColumns: closingFenceIndent,
                expectedChar: info.fenceCharacter,
                openingLength: info.fenceLength
            ) {
                pending = finalize(node: current, pending: pending, lineContentEnd: fenceEnd)
                return LeafContinuation(consumedLine: true, pending: pending)
            }
            // Continuation: strip up to `fenceOffset` columns of leading whitespace and append.
            pending = appendNewline(to: current, pending: pending)
            let (bodyStart, leadingSpaces) = stripIndent(
                range: cursor..<lineRange.upperBound,
                maxColumns: prefixColumns + info.fenceOffset - startColumn,
                startColumn: startColumn
            )
            blockContentEnd = contentEnd(ofLine: lineRange, bodyStart: bodyStart, leadingSpaces: leadingSpaces)
            pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
            return LeafContinuation(consumedLine: true, pending: pending)
        }
        // Indented.
        let indent = indentColumns(from: cursor, to: firstNonSpace, baseColumn: prefixColumns)
        if indent >= 4 || isBlank {
            // Blank lines that end the block are not part of it, so for list tightness the block ends with a blank line until a further code line follows.
            storage.nodes[current].lastLineBlank = isBlank
            pending = appendNewline(to: current, pending: pending)
            if !isBlank {
                blockContentEnd = lineRange.upperBound
            }
            // For an open indented code block, a "blank" line that actually contains 5+ columns of whitespace preserves the EXTRA columns as content (per spec example 82 - `      ` between two code lines becomes `  ` in the rendered code block).
            if indent > 4 || !isBlank {
                let (bodyStart, leadingSpaces) = stripIndent(
                    range: cursor..<lineRange.upperBound,
                    maxColumns: 4,
                    startColumn: prefixColumns
                )
                pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: current, pending: pending)
            }
            return LeafContinuation(consumedLine: true, pending: pending)
        }
        // Non-indented, non-blank line ends the block.
        pending = finalize(node: current, pending: pending)
        return LeafContinuation(consumedLine: false, pending: pending)
    }

    /// Open a list item under `current`. If `current` is already a list of compatible kind/marker, the item is added as another child of that list. Otherwise a new list is opened first.
    ///
    /// On exit, `current` points at the newly-opened item.
    private mutating func openListItem(marker: ListMarkerInfo, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let start = firstNonSpace
        let parentList: DocumentStorage.Index
        if case .list(let info) = storage[current].kind,
           Self.marker(marker, continues: info) {
            parentList = current
            // Tight/loose detection runs at list-finalize time via `detectLooseList` + the `endsWithBlankLine` recursion, which catches the "blank between sibling items" case at finalize.
        } else {
            // Either there's no open list, or the marker style differs from the open list. In the latter case, finalize the open list so the new list opens as a sibling - `- foo\n+ bar` becomes two top-level lists, not a nested one (CommonMark §5.3).
            pending = closingOpenList(pending)
            // Open a new list.
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

    /// Open new blocks at `current` based on the line's content from `startCursor`. Loops when a container (block quote, list item) opens so that `> > foo` or `- - foo` correctly opens nested containers plus a paragraph in one pass.
    private mutating func dispatchNewBlocks(lineRange: Range<Int>, startCursor: Int, startColumn: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        var cursor = startCursor
        var column = startColumn
        var lineColumns = LineColumns(lineStart: lineRange.lowerBound)
        var noThematicBreakBefore = startCursor
        var containersOpened = 0
        let maxContainersBeforeListMarker = limits.maxContainersOpenedOnLineBeforeListMarker
        while true {
            let firstNonSpace = indexOfFirstNonSpace(range: cursor..<lineRange.upperBound)
            let isBlank = firstNonSpace == lineRange.upperBound
            if isBlank {
                return pending
            }
            let firstNonSpaceColumn = lineColumns.column(at: firstNonSpace, in: sourceBytes)
            let indent = firstNonSpaceColumn - column

            // Block quote opens a container; loop to keep dispatching the rest.
            if let advanced = matchBlockQuoteMarker(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                baseColumn: column
            ) {
                // A block quote can't be a direct child of a list (lists only contain items), so an enclosing list closes first - e.g. a `>` line after list items ends the list and starts a top-level quote.
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
                containersOpened += 1
                continue
            }

            // Thematic break (must be before ATX so `---` etc. wins over content matchers, and before list-marker so `- - -` etc. wins over nested lists).
            // A marker before `noThematicBreakBefore` skips the scan, so the nested markers of `- - - … x` scan the
            // line once.
            if indent < 4, firstNonSpace >= noThematicBreakBefore, let breakEnd = matchThematicBreak(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                noBreakBefore: &noThematicBreakBefore
            ) {
                // Thematic breaks close any enclosing list - they don't become children of a list (lists can only contain items).
                pending = closingOpenList(pending)
                return openThematicBreak(firstNonSpace: firstNonSpace, end: breakEnd, pending: pending)
            }

            if storage.options.contains(.footnotes),
               indent < 4,
               containersOpened <= maxContainersBeforeListMarker,
               let fn = matchFootnoteDefinition(
                   range: cursor..<lineRange.upperBound,
                   firstNonSpace: firstNonSpace
               ) {
                pending = closingOpenList(pending)
                let fnIdx = openFootnoteDefinition(label: fn.label, firstNonSpace: firstNonSpace)
                current = fnIdx
                cursor = fn.consumedTo
                column = lineColumns.column(at: cursor, in: sourceBytes)
                containersOpened += 1
                continue
            }

            // List marker - opens a list (or extends an existing one) and an item. Both are containers; loop so we keep dispatching the rest of the line as content within the new item.
            if indent < 4, containersOpened <= maxContainersBeforeListMarker, let marker = matchListMarker(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                markerColumn: firstNonSpaceColumn,
                indent: indent
            ) {
                pending = openListItem(marker: marker, firstNonSpace: firstNonSpace, pending: pending)
                cursor = marker.consumedTo
                // `column` can pass `cursor`'s column: when the marker's padding partly consumes a tab, `cursor` stays at that tab (Tabs).
                column = marker.contentStartColumn
                containersOpened += 1
                continue
            }

            // From this point on the line isn't a list item, so any open list at `current` must close before we attach the new block (lists can't have direct non-item children).
            pending = closingOpenList(pending)

            // Indented code block (only when current container can't continue a paragraph).
            if indent >= 4 {
                return openIndentedCode(lineRange: lineRange, cursor: cursor, column: column, pending: pending)
            }

            // ATX heading.
            if let heading = matchATXHeading(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                return openATXHeading(heading, firstNonSpace: firstNonSpace, pending: pending)
            }

            // Fenced code block.
            if let fence = matchOpeningFence(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indent: indent
            ) {
                openFencedCode(fence, cursor: cursor, firstNonSpace: firstNonSpace)
                return pending
            }

            // HTML block (types 1–7). Leading 0–3 spaces of indent are preserved verbatim in the block's content. Type 7 is detected only when the current container isn't a paragraph, since it can't interrupt one (per CommonMark 0.31 §4.6).
            if let htmlType = matchHTMLBlockStart(
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                allowType7: true
            ) {
                return openHTMLBlock(htmlType, lineRange: lineRange, cursor: cursor, column: column, firstNonSpace: firstNonSpace, pending: pending)
            }

            // Paragraph fallback. By this point the list-close-if-needed step above has already ensured `current` isn't a list.
            return openParagraph(lineRange: lineRange, firstNonSpace: firstNonSpace, pending: pending)
        }
    }

    private mutating func closingOpenList(_ pending: consuming PendingLeaf?) -> PendingLeaf? {
        if storage[current].kind.isList {
            return finalize(node: current, pending: pending)
        }
        return pending
    }

    private mutating func openThematicBreak(firstNonSpace: Int, end: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let breakIdx = addChild(
            kind: .thematicBreak,
            parent: current,
            start: firstNonSpace
        )
        current = breakIdx
        return finalize(node: breakIdx, pending: pending, lineContentEnd: end)
    }

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

    private mutating func openFencedCode(_ fence: FenceMatch, cursor: Int, firstNonSpace: Int) {
        // Decode backslash escapes and HTML entities in the info string so consumers see the canonical language tag (e.g. `foo\+bar` → `foo+bar`, `f&ouml;&ouml;` → `föö`).
        let cleanInfo = unescapedChunk(fence.infoChunk)
        let infoRef = storage.intern(replacingNUL(cleanInfo))
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

    private mutating func openHTMLBlock(_ htmlType: UInt8, lineRange: Range<Int>, cursor: Int, column: Int, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let (bodyStart, leadingSpaces) = htmlLineBody(lineRange: lineRange, cursor: cursor, column: column)
        // The block keeps its indentation as content (HTML blocks), so when a partly consumed tab's leftover columns
        // are its first content, it starts at that tab (Tabs).
        let htmlIdx = addChild(
            kind: .htmlBlock,
            parent: current,
            data: .htmlBlock(type: htmlType, literal: .empty),
            start: leadingSpaces > 0 ? bodyStart - 1 : bodyStart
        )
        current = htmlIdx
        blockContentEnd = lineRange.upperBound
        pending = appendLiteralBodyLine(bodyStart: bodyStart, leadingSpaces: leadingSpaces, lineEnd: lineRange.upperBound, to: htmlIdx, pending: pending)
        // Check whether this same line also satisfies the end condition.
        if htmlBlockLineMatchesEndCondition(
            type: htmlType,
            range: firstNonSpace..<lineRange.upperBound
        ) {
            pending = finalize(node: htmlIdx, pending: pending)
        }
        return pending
    }

    private mutating func openIndentedCode(lineRange: Range<Int>, cursor: Int, column: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // The block starts where content begins *after* the 4-space code indent is consumed (the extra indentation beyond 4 is preserved as content, and the start column is that post-indent position - not the first non-space char).
        // When the four-column indent partly consumes a tab, its leftover columns become spaces (Tabs) and the block starts at that tab.
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

    @inline(__always)
    private mutating func openParagraph(lineRange: Range<Int>, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let textRange = firstNonSpace..<lineRange.upperBound
        precondition(!storage[current].kind.isParagraph, "dispatch starts at the deepest matched container, which is never a leaf, and opens only containers before a leaf, so `current` is never a paragraph here")
        assert(openParagraphState == nil, "the previous paragraph closed before this one opens")
        let paragraphIdx = addChild(kind: .paragraph, parent: current, start: firstNonSpace)
        current = paragraphIdx
        return addLine(range: textRange, to: paragraphIdx, pending: pending)
    }

    // MARK: - Finalize

    // MARK: Segment-content finalize (segment model)

    /// Drained leaf content: either one contiguous `Chunk` or a multi-line segment list (`.segments`, kept zero-copy).
    ///
    /// Lets paragraph/heading finalize decide whether to keep segments or run the chunk-based matchers without consuming `pending` twice.
    private enum DrainedLeaf: ~Copyable {
        case chunk(Chunk)
        case segments(UniqueArray<Segment>)
    }

    private struct LeafDrainResult: ~Copyable {
        var content: DrainedLeaf
        var map: [ArenaRun] = []
    }

    /// Drain `node`'s pending content, tagging it as a flat chunk or a segment list.
    private mutating func drainLeaf(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafDrainResult {
        switch consume pending {
        case .none:
            return LeafDrainResult(content: .chunk(.empty))
        case .some(let leaf):
            precondition(leaf.node == node, "pending content belongs to the one open leaf, which drains when it closes")
            switch consume leaf.content {
            case .segments(let segs):
                // Inline parsing reads every arena segment of multi-segment content as a line join
                // (`ContentSpan.multiNextSignificant`), so a NUL's U+FFFD can't be spliced in as a segment.
                if segmentsContainNUL(segs) {
                    var map: [ArenaRun] = []
                    let flat = flattenReplacingNUL(segs, map: &map)
                    return LeafDrainResult(content: .chunk(flat), map: map)
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

    private func totalLength(of segs: borrowing UniqueArray<Segment>) -> Int {
        var total = 0
        for i in 0..<segs.count {
            total += segs[i].length
        }
        return total
    }

    private func trimmedRange(of segs: borrowing UniqueArray<Segment>, total: Int) -> Range<Int> {
        var lower = 0
        leading: for i in 0..<segs.count {
            let seg = segs[i]
            for j in 0..<seg.length {
                if !readByte(at: seg.offset + j, in: seg.chunk).isWhitespaceCharacter {
                    break leading
                }
                lower += 1
            }
        }
        var upper = total
        trailing: for i in stride(from: segs.count - 1, through: 0, by: -1) {
            let seg = segs[i]
            for j in stride(from: seg.length - 1, through: 0, by: -1) {
                if upper == lower || !readByte(at: seg.offset + j, in: seg.chunk).isWhitespaceCharacter {
                    break trailing
                }
                upper -= 1
            }
        }
        return lower..<upper
    }

    private mutating func segments(_ segs: consuming UniqueArray<Segment>, in range: Range<Int>, total: Int) -> UniqueArray<Segment> {
        precondition(!range.isEmpty, "a leaf's narrowed content is not empty")
        var segs = segs
        let (last, lastStart) = segment(endingAtOrAfter: range.upperBound, in: segs, total: total)
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

    private mutating func finishParagraph(_ node: DocumentStorage.Index, segments segs: consuming UniqueArray<Segment>) {
        let total = totalLength(of: segs)
        guard let content = rawContentRange(in: segs, total: total, taskItemParagraph: node) else {
            finishWhitespaceOnlyParagraph(node)
            return
        }
        if content.isEmpty {
            removeEmptiedParagraph(node, contentEnd: positionsEnabled ? sourceEnd(ofVirtual: content.upperBound, in: segs, total: total) : nil)
            return
        }
        enqueueRawContent(of: node, segments(segs, in: content, total: total))
    }

    private mutating func rawContentRange(in segs: borrowing UniqueArray<Segment>, total: Int, taskItemParagraph node: DocumentStorage.Index) -> Range<Int>? {
        let trimmed = trimmedRange(of: segs, total: total)
        if trimmed.isEmpty {
            return nil
        }
        return rawContentStart(in: segs, trimmed: trimmed, taskItemParagraph: node)..<trimmed.upperBound
    }

    private mutating func enqueueRawContent(of node: DocumentStorage.Index, _ content: consuming UniqueArray<Segment>) {
        if positionsEnabled {
            let span = segmentsSourceSpan(content)
            storage.setSourceStart(node, span.start)
            storage.setSourceEnd(node, span.end)
        }
        pendingInlines.append((node, storage.intern(content)))
    }

    private mutating func flattenReplacingNUL(_ segs: borrowing UniqueArray<Segment>, map: inout [ArenaRun]) -> Chunk {
        let offset = storage.strings.count
        for i in 0..<segs.count {
            let seg = segs[i]
            guard seg.inSource else {
                // Byte at a time, since the arena can't be read through a span while it grows.
                for k in seg.chunk.range {
                    storage.strings.append(storage.strings[k])
                }
                if positionsEnabled {
                    Self.appendContentBytes(seg.length, imaging: -1, to: &map)
                }
                continue
            }
            var start = seg.offset
            let end = seg.offset + seg.length
            if let recorded = lazyLineWhitespace, let whitespace = recorded.bySourceOffset[start] {
                recorded.byArenaOffset[storage.strings.count] = whitespace
            }
            while start < end {
                let nul = start + Self.firstNUL(in: sourceBytes.extracting(start..<end))
                storage.strings.append(copying: sourceBytes.extracting(start..<nul))
                if positionsEnabled, nul > start {
                    Self.appendContentBytes(nul - start, imaging: start, to: &map)
                }
                guard nul < end else {
                    break
                }
                appendReplacementCharacter()
                if positionsEnabled {
                    // Each byte of the U+FFFD images the NUL, so content ending on the U+FFFD ends just past the NUL.
                    for _ in 0..<3 {
                        Self.appendContentBytes(1, imaging: nul, to: &map)
                    }
                }
                start = nul + 1
            }
        }
        return arenaChunk(from: offset)
    }

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

    private mutating func tableSplitParagraphContent(_ trimmed: Chunk, node: DocumentStorage.Index, linesStart: Int) -> Chunk? {
        let content = paragraphContent(of: node, trimmed: trimmed, linesStart: linesStart)
        return content.isEmpty && (!trimmed.isEmpty || openParagraphState?.definitionsCommitted == true) ? nil : content
    }

    private func sourceEnd(of content: Chunk, in raw: Chunk, map: [ArenaRun]) -> Int {
        precondition(!content.isEmpty, "only non-empty content has a source span")
        if map.isEmpty {
            precondition(content.inSource, "with `.sourcePosition`, arena-backed leaf content carries a run map")
            return content.offset + content.length
        }
        return sourceSpan(of: Self.sliceRuns(map, from: content.offset - raw.offset, length: content.length)).end
    }

    // A line of whitespace that includes a line tabulation or form feed is not blank (Characters and lines), so it can
    // make a paragraph that has no raw content (Paragraphs). With definitions committed, only a thematic break closes
    // such a paragraph, and it opens in the same container past the definitions, so they need not extend the
    // container's range.
    private mutating func finishWhitespaceOnlyParagraph(_ node: DocumentStorage.Index) {
        if openParagraphState?.definitionsCommitted == true {
            removeEmptiedParagraph(node, contentEnd: nil)
        } else {
            emptySourceRangeAtStart(node)
        }
    }

    private mutating func emptySourceRangeAtStart(_ paragraph: DocumentStorage.Index) {
        if positionsEnabled {
            storage.sourceRanges[paragraph].end = storage.sourceRanges[paragraph].start
        }
    }

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

    private mutating func finishParagraph(_ node: DocumentStorage.Index, chunk raw: Chunk, map: [ArenaRun]) {
        let trimmed = raw.trimmingWhitespace(using: self)
        if trimmed.isEmpty {
            finishWhitespaceOnlyParagraph(node)
            return
        }
        let contentChunk = paragraphContent(of: node, trimmed: trimmed, linesStart: raw.offset)
        if contentChunk.isEmpty {
            removeEmptiedParagraph(node, contentEnd: positionsEnabled ? sourceEnd(of: trimmed, in: raw, map: map) : nil)
            return
        }
        if positionsEnabled {
            if map.isEmpty {
                precondition(contentChunk.inSource, "with `.sourcePosition`, arena-backed leaf content carries a run map")
                storage.setSourceStart(node, contentChunk.offset)
                storage.setSourceEnd(node, contentChunk.offset + contentChunk.length)
            } else {
                let contentMap = Self.sliceRuns(map, from: contentChunk.offset - raw.offset, length: contentChunk.length)
                let span = sourceSpan(of: contentMap)
                storage.setSourceStart(node, span.start)
                storage.setSourceEnd(node, span.end)
                arenaSourceMaps[node] = contentMap
            }
        }
        pendingInlines.append((node, storage.intern(contentChunk)))
    }

    private static func isContainer(_ kind: MarkdownNode.Kind) -> Bool {
        switch kind {
        case .blockQuote, .list, .item, .footnoteDefinition: true
        default: false
        }
    }

    /// Close `node`, materialize its accumulated content, and back the parser's `current` pointer up to `node`'s parent.
    private mutating func finalize(node: DocumentStorage.Index, pending: consuming PendingLeaf?, lineContentEnd: Int? = nil) -> PendingLeaf? {
        var pending = pending
        let kind = storage[node].kind
        openBlocksVersion &+= 1

        if positionsEnabled {
            if let lineContentEnd {
                storage.setSourceEnd(node, lineContentEnd)
            } else if kind.isCodeBlock || kind.isHTMLBlock {
                storage.setSourceEnd(node, blockContentEnd)
            } else if Self.isContainer(kind) {
                let ownEnd = storage.sourceRanges[node].end
                storage.setSourceEnd(node, storage[node].lastChild.map { max(ownEnd, storage.sourceRanges[$0].end) } ?? ownEnd)
            }
        }

        switch kind {
        case .paragraph:
            assert(openParagraphState.map { $0.node == node } ?? true, "the recorded state belongs to the paragraph being closed")
            defer { openParagraphState = nil }
            // Tables are found before definitions are extracted: a paragraph becomes a table once its delimiter row
            // arrives, and only a paragraph holds definitions, so `[\n|-\n]:/` and `[o]:o\n|-` are tables.
            if openParagraphState?.tablePending == true {
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
            // Body lines were accumulated as zero-copy source segments; normalize the segment list (drop the leading separator, strip trailing blank lines for indented code, ensure one trailing `\n`) without copying the bodies into the arena.
            var segs = drainSegments(node, pending: pending)
            pending = nil
            normalizeCodeBlockSegments(&segs, isFenced: info.isFenced)
            let literalRef = storage.intern(segs)
            if case .codeBlock(let info, _) = storage[node].data {
                storage[node].data = .codeBlock(info: info, literal: literalRef)
            }
        case .htmlBlock:
            // Body lines accumulate as zero-copy source segments (same as code blocks).
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

    // Each line after the first adds a separator before its content, so only the last line lacks its `\n`, even when
    // it is blank and the list already ends in a separator.
    private func normalizeHTMLBlockSegments(_ segs: inout UniqueArray<Segment>) {
        let nl = storage.newlineSegment
        precondition(segs.count > 0 && segs[0] != nl, "an HTML block's body starts with its opening line, which is never empty")
        segs.append(nl)
    }

    /// Normalize a code block's accumulated body segments (CommonMark 0.31 §4.4) without copying the line bodies.
    ///
    /// Drops the leading separator our accumulator inserts before the first fenced line, strips trailing blank lines for indented code, and ensures the body ends with exactly one `\n` (an empty fenced body stays empty).
    ///
    /// Content segments never contain a `\n` (lines are split on newlines), so `\n` occurs only at separator positions - the list is isomorphic to "lines separated by `\n`".
    private func normalizeCodeBlockSegments(_ segs: inout UniqueArray<Segment>, isFenced: Bool) {
        let nl = storage.newlineSegment
        var lo = 0
        var hi = segs.count

        // Drop a leading separator (fenced code's "appendNewline then addLine" emits one before the first body line; indented code's first line has none).
        var strippedLeading = false
        if lo < hi && segs[lo] == nl {
            lo += 1
            strippedLeading = true
        }

        // Indented code strips trailing blank lines; fenced code preserves them.
        if !isFenced {
            trailing: while lo < hi {
                if segs[hi - 1] == nl {
                    hi -= 1                       // trailing empty line + its separator
                    continue
                }
                var lineStart = hi
                while lineStart > lo && segs[lineStart - 1] != nl {
                    lineStart -= 1
                    if !isSpaceOrTabOnly(segs[lineStart]) {
                        break trailing
                    }
                }
                hi = lineStart
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

    /// `true` if `segment`'s bytes are entirely ASCII spaces/tabs. Code-block content segments never contain `\n`, so only space/tab are checked.
    private func isSpaceOrTabOnly(_ segment: Segment) -> Bool {
        segment.chunk.range.allSatisfy { readByte(at: $0, in: segment.chunk).isSpaceOrTab }
    }

    // MARK: - Helpers

    /// The result of one combined walk over a line's leading whitespace: where the content starts, how many columns of indentation precede it, whether the line is blank, and the first content byte.
    ///
    /// Combines what `indexOfFirstNonSpace` + `indentColumns` compute in separate walks over the same bytes.
    private struct LeadingScan {
        var firstNonSpace: Int
        var indentColumns: Int
        var isBlank: Bool
        /// The byte at `firstNonSpace`, or `0` when the line is blank.
        var firstNonSpaceByte: UInt8
    }

    /// Walk the leading whitespace of `range` once, computing the first-non-space offset, the indent column width (CommonMark's 4-column tab rule), the blank-line flag, and the first content byte.
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

    /// Find the first non-space, non-tab byte in `range`. Returns `range.upperBound` if the range is all whitespace.
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

    /// Count the column-width of the leading whitespace `start..<end` per CommonMark's 4-column tab rule: a tab advances the column to the next multiple of 4.
    // A tab's width depends on the column it starts at, so `baseColumn` is `start`'s column on its line.
    private func indentColumns(from start: Int, to end: Int, baseColumn: Int) -> Int {
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

    /// A superset of the first-content bytes that any block construct can start with.
    ///
    /// If a line's first non-space byte isn't one of these, no block matcher can match it, so it can't interrupt an open paragraph.
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

    /// Walk leading whitespace from `start` toward `end`, consuming up to `columns` columns of indentation (with tab = next 4-col boundary).
    ///
    /// Returns the byte position past the consumed indentation. If a tab would over-shoot `columns`, it isn't split - the function returns the byte before the tab, leaving callers to handle the partial case (rare for indented-code purposes).
    private func advanceColumns(from start: Int, to end: Int, columns: Int, baseColumn: Int) -> Int {
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
        var contentColumn: Int    // column at which item content begins (after marker + space)
        // The content's column on its line, past `consumedTo`'s when the padding consumes only part of a tab.
        var contentStartColumn: Int
        var markerEnd: Int
        var consumedTo: Int       // source offset of first byte of item content
        var isEmpty: Bool
    }

    /// Read the padding stored on an `.item` node.
    private func itemPadding(of node: DocumentStorage.Index) -> Int {
        guard case .item(let padding) = storage[node].data else {
            preconditionFailure("an item node always carries its padding")
        }
        return padding
    }

    /// Try to match a list marker at `firstNonSpace` within `range`. CommonMark 0.31 §5.2:
    /// - Bullet: one of `-`, `+`, `*` followed by a space, tab, or end of line.
    /// - Ordered: 1-9 ASCII digits, then `.` or `)`, then space/tab/end.
    /// `≤3` leading spaces; markers immediately at end-of-line are valid (empty item).
    @inline(__always)
    private func matchListMarker(range: Range<Int>, firstNonSpace: Int, markerColumn: Int, indent: Int) -> ListMarkerInfo? {
        assert(indent <= 3, "block-start matchers run only on a line indented less than four columns")
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
            if i >= range.upperBound {
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
        let columnAfterMarker = markerColumn + markerWidth
        // Marker must be followed by a space, tab, or end of line.
        var contentStart: Int
        var padding = 1
        var isEmpty = false
        if afterMarker >= range.upperBound {
            // Empty item - the line is just `-` (or end of input after marker).
            contentStart = afterMarker
            isEmpty = true
        } else {
            let next = sourceBytes[afterMarker]
            if next != UInt8(ascii: " ") && next != UInt8(ascii: "\t") {
                return nil
            }
            // Per CommonMark §5.2, count the run of spaces / tabs after the marker. With 1–4 spaces of padding, the content column is the column of the first non-blank char. With 5+ spaces, the extra beyond 1 are part of the content (indented code block within the item) and the content column is `marker + 1 space`.
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
            // Treat a fully-blank line after the marker as an empty item (e.g. `-     \n` or `-` followed by EOF after the optional space).
            let blankAfter = k >= range.upperBound
            isEmpty = blankAfter
            if blankAfter || runColumns >= 5 {
                // A tab wider than the one column of padding is consumed only in part, so the content starts at it (Tabs).
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
            contentColumn: indent + markerWidth + padding,
            contentStartColumn: columnAfterMarker + padding,
            markerEnd: afterMarker,
            consumedTo: contentStart,
            isEmpty: isEmpty
        )
    }

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

    /// Tag names that trigger an HTML block of type 1 (their *closing* tag also ends the block).
    private static let htmlBlockType1Tags: [[UInt8]] = [
        "pre", "script", "style",
    ].map { Array($0.utf8) }

    private static let htmlCommentEnd = Array("-->".utf8)
    private static let processingInstructionEnd = Array("?>".utf8)
    private static let cdataEnd = Array("]]>".utf8)
    private static let declarationEnd = Array(">".utf8)

    // Only `range` is case-folded, so `target` must be lowercase.
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

    /// Try to match the start of an HTML block at `firstNonSpace` and return the type number (1–7), or `nil` if no HTML block starts here.
    private mutating func matchHTMLBlockStart(range: Range<Int>, firstNonSpace: Int, allowType7: Bool) -> UInt8? {
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
        // Type 5: `<![CDATA[`
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
        let bytes = sourceBytes
        guard let nameEnd = htmlTagNameEnd(from: nameStart, end: range.upperBound, byte: { bytes[$0] }) else {
            return nil
        }
        let nameRange = nameStart..<nameEnd

        if !isClosing {
            for tag in Self.htmlBlockType1Tags {
                if bytesEqualASCIICaseInsensitive(range: nameRange, target: tag) {
                    // Must be followed by whitespace, `>`, or EOL.
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

        // Type 6: block-tag-name list.
        for tag in Self.htmlBlockType6Tags {
            if bytesEqualASCIICaseInsensitive(range: nameRange, target: tag) {
                // Must be followed by whitespace, `>`, `/>`, or EOL.
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

        // Type 7: any complete open or close tag (with optional attributes for opens) followed only by whitespace until end of line.
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

    /// Check whether a line satisfies the end condition for an HTML block of the given type. The check looks for the closing pattern *anywhere* on the line (per CommonMark 0.31 §4.6).
    private mutating func htmlBlockLineMatchesEndCondition(type: UInt8, range: Range<Int>) -> Bool {
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

    /// Caller must ensure the needle is non-empty.
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

    /// Search for `</tagname>` (case-insensitive) anywhere within `range`.
    @inline(__always)
    private mutating func findClosingTag(range: Range<Int>, name: [UInt8]) -> Bool {
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
               sourceBytes[i + 1] == UInt8(ascii: "/"),
               bytesEqualASCIICaseInsensitive(range: (i + 2)..<(i + 2 + nameLen), target: name),
               sourceBytes[i + 2 + nameLen] == UInt8(ascii: ">") {
                return true
            }
            i += 1
        }
        return false
    }

    /// Try to match a block-quote marker at `firstNonSpace`. CommonMark 0.31 §5.1: up to 3 leading spaces, then `>`, then optionally one space or tab. Returns the offset just past the consumed marker, or `nil` if no match.
    @inline(__always)
    private func matchBlockQuoteMarker(range: Range<Int>, firstNonSpace: Int, baseColumn: Int) -> Int? {
        // A byte count would under-measure a tab, which spans up to four columns.
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

    // The optional space after `>` is one column (Tabs), so a wider tab is consumed only in part and the cursor
    // stays on it.
    private func blockQuotePrefixEnd(lineColumns: inout LineColumns, markerEnd: Int, advanced: Int) -> (cursor: Int, column: Int) {
        let markerEndColumn = lineColumns.column(at: markerEnd, in: sourceBytes)
        if advanced == markerEnd + 1, sourceBytes[markerEnd] == UInt8(ascii: "\t"), 4 - (markerEndColumn & 3) > 1 {
            return (markerEnd, markerEndColumn + 1)
        }
        return (advanced, lineColumns.column(at: advanced, in: sourceBytes))
    }

    /// Try to match an opening fenced code-block line. CommonMark 0.31 §4.5.
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

    /// CommonMark 0.31 §4.5.
    private mutating func matchClosingFence(range: Range<Int>, firstNonSpace: Int, indentColumns: Int, expectedChar: MarkdownNode.CodeBlockInfo.FenceCharacter?, openingLength: Int) -> Int? {
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
        // A closing fence is a code fence, so it is at least 3 long whatever the clamp (Fenced code blocks).
        let minimumLength = min(openingLength, max(limits.fenceLengthClampForClosing, 3))
        return i - firstNonSpace >= minimumLength && isSpaceOrTabOnly(i..<range.upperBound) ? i : nil
    }

    @inline(__always)
    private func isSpaceOrTabOnly(_ range: Range<Int>) -> Bool {
        range.allSatisfy { sourceBytes[$0].isSpaceOrTab }
    }

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

    // Each query resumes from the previous one, since measuring each container marker from the line start would make a
    // line of `n` nested markers cost `n` squared.
    private struct LineColumns {
        private var offset: Int
        private var column = 0

        init(lineStart: Int) {
            offset = lineStart
        }

        mutating func column(at target: Int, in source: Span<UInt8>) -> Int {
            precondition(target >= offset, "a line's column queries never move back")
            while offset < target {
                let byte = source[offset]
                if byte == UInt8(ascii: "\t") {
                    column += 4 - (column & 3)
                } else if byte & 0xC0 != 0x80 {
                    // Tab stops count characters (Tabs), so a UTF-8 continuation byte adds no column.
                    column += 1
                }
                offset += 1
            }
            return column
        }
    }

    /// Try to match a setext heading underline at `firstNonSpace` within `range`. CommonMark 0.31 §4.3.
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

    /// Try to match a thematic break starting at `firstNonSpace` within `range`. CommonMark 0.31 §4.1.
    // On failure `noBreakBefore` is where matching failed, and a line starting at a marker before it fails there too.
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

    /// Try to match an ATX heading. CommonMark 0.31 §4.2.
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

        // The closing sequence is the heading's own syntax, so the heading ends past it, as past any content.
        let end = contentStart != beforeHashes ? beforeHashes : i
        return ATXMatch(level: UInt8(level), contentRange: contentStart..<contentEnd, end: end)
    }

    /// At list finalize, decide whether the list is loose.
    ///
    /// A list is loose per CommonMark §5.3 if any item directly contains two block-level children separated by a blank line - i.e., the item has more than one block child AND a blank line was observed inside it.
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

    /// Read the byte at `offset` from whichever buffer `chunk` lives in - `sourceBytes` when `chunk.inSource`, else the `storage.strings` arena. Encapsulates the `inSource ? sourceBytes[i] : storage.strings[i]` buffer-selection idiom used throughout block and inline parsing.
    func readByte(at offset: Int, in chunk: Chunk) -> UInt8 {
        chunk.inSource ? sourceBytes[offset] : storage.strings[offset]
    }

    private mutating func paragraphContent(of node: DocumentStorage.Index, trimmed: Chunk, linesStart: Int) -> Chunk {
        let afterDefinitions = definitionMayBegin(at: trimmed.offset, linesStart: linesStart) ? parseDefinitions(in: trimmed) : trimmed
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

    private mutating func rawContentStart(in segs: borrowing UniqueArray<Segment>, trimmed: Range<Int>, taskItemParagraph node: DocumentStorage.Index) -> Int {
        precondition(!trimmed.isEmpty, "only non-blank content begins past definitions or a marker")
        // A definition begins with `[` or `^`, and a task list item marker with `[`.
        guard Self.mayBeginDefinition(byte(at: trimmed.lowerBound, in: segs)), definitionMayBegin(at: trimmed.lowerBound, linesStart: 0) else {
            return trimmed.lowerBound
        }
        let segmentEnds = Self.segmentEnds(of: segs)
        let content = ContentSpan(source: sourceBytes, segments: segs.span, segmentEnds: segmentEnds.span, virtualLength: trimmed.upperBound, hint: pieceHint)
        let afterDefinitions = definitionsEnd(in: content, from: trimmed.lowerBound)
        // As in `paragraphContent(of:trimmed:linesStart:)`, a marker after a definition doesn't begin the item's first
        // block.
        if afterDefinitions != trimmed.lowerBound {
            return skipWhitespace(from: afterDefinitions, in: content)
        }
        guard let item = taskListItem(firstBlock: node),
              let checked = Self.taskItemMarker(length: trimmed.count, byte: { content[trimmed.lowerBound + $0] }) else {
            return trimmed.lowerBound
        }
        storage[item].kind = .item(checked: checked)
        return skipWhitespace(from: trimmed.lowerBound + 3, in: content)
    }

    private func byte(at offset: Int, in segs: borrowing UniqueArray<Segment>) -> UInt8 {
        var first = 0
        var segmentStart = 0
        while segmentStart + segs[first].length <= offset {
            segmentStart += segs[first].length
            first += 1
        }
        return readByte(at: segs[first].offset + offset - segmentStart, in: segs[first].chunk)
    }

    private static func segmentEnds(of segs: borrowing UniqueArray<Segment>) -> UniqueArray<Int> {
        var segmentEnds = UniqueArray<Int>(minimumCapacity: segs.count)
        var end = 0
        for i in 0..<segs.count {
            end += segs[i].length
            segmentEnds.append(end)
        }
        return segmentEnds
    }

    // Definitions an underline committed from the start of the open paragraph's lines are the item's first block, not
    // `node`.
    private func taskListItem(firstBlock node: DocumentStorage.Index) -> DocumentStorage.Index? {
        guard storage.options.contains(.tasklist),
              let item = storage[node].parent,
              case .item = storage[item].kind,
              storage[item].firstChild == node,
              !itemsWithRemovedFirstParagraph.contains(item),
              openParagraphState?.definitionsCommitted != true else {
            return nil
        }
        return item
    }

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

    private mutating func matchFootnoteDefinition(range: Range<Int>, firstNonSpace: Int) -> (label: Chunk, consumedTo: Int)? {
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

    private mutating func openFootnoteDefinition(label rawLabel: Chunk, firstNonSpace: Int) -> DocumentStorage.Index {
        let label = replacingNUL(rawLabel)
        let labelRef = storage.intern(label)
        let fnIdx = addChild(
            kind: .footnoteDefinition,
            parent: current,
            data: .footnoteDefinition(label: labelRef),
            start: firstNonSpace
        )
        storage.setSourceEnd(fnIdx, rawLabel.offset + rawLabel.length + 2)
        storage.footnoteDefinitionOrder.append(fnIdx)
        let key = normalizeLabel(chunk: label)
        if !key.isEmpty {
            storage.footnoteMap.storeIfAbsent(fnIdx, forKey: key)
        }
        return fnIdx
    }

    // MARK: Reference Parser
    
    // CommonMark 0.31 §4.7. A definition has the form:
    //
    // ``` [label]: destination optional-title ```
    //
    // The extended-attribute reference form `^[label]: attrs` is recognized in the same loop and stored separately on `DocumentStorage.attributeReferenceMap`.
    //
    // Multiple definitions may stack consecutively at the start of a paragraph. After consuming all that match, the remaining (possibly blank) content is returned for the inline parser to handle. If everything was consumed, the caller is expected to detach the paragraph node from its parent.

    /// Repeatedly consume `[label]: dest "title"` and `^[label]: attrs` definitions from the start of `chunk`.
    ///
    /// Each successful match registers the entry in the appropriate refmap on `storage` (first definition wins per spec) and advances the cursor. Returns the remaining chunk after the last consumed def.
    private mutating func parseDefinitions(in chunk: Chunk) -> Chunk {
        let end = chunk.offset + chunk.length
        let rest: Int
        if chunk.isEmpty || !Self.mayBeginDefinition(readByte(at: chunk.offset, in: chunk)) {
            rest = chunk.offset
        } else if chunk.inSource {
            rest = definitionsEnd(in: ContentSpan(span: sourceBytes.extracting(chunk.range), base: chunk.offset, inSource: true), from: chunk.offset)
        } else {
            // Arena content is read from a copy, since registering a definition can grow the arena.
            var bytes = UniqueArray<UInt8>()
            bytes.append(copying: storage.strings.span.extracting(chunk.range))
            rest = definitionsEnd(in: ContentSpan(span: bytes.span, base: chunk.offset, inSource: false), from: chunk.offset)
        }
        return Chunk(offset: rest, length: end - rest, inSource: chunk.inSource)
    }

    // Past definitions an underline committed, the lines continue from them, so a definition begins only at a line's
    // first byte, as one following another does (Link reference definitions).
    private func definitionMayBegin(at start: Int, linesStart: Int) -> Bool {
        openParagraphState?.definitionsCommitted != true || start == linesStart
    }

    private static func mayBeginDefinition(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "[") || byte == UInt8(ascii: "^")
    }

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

    @inline(__always)
    mutating func unescapedChunk(_ range: Range<Int>, in content: borrowing ContentSpan) -> Chunk {
        if range.isEmpty {
            return .empty
        }
        if let contiguous = content.contiguousChunk(fromVirtual: range.lowerBound, limit: range.upperBound),
           contiguous.length == range.count {
            return unescapedChunk(contiguous)
        }
        // A backslash escape or character reference never continues past a line ending, so each line unescapes alone.
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

    func skipWhitespace(from cursor: Int, in content: borrowing ContentSpan) -> Int {
        var i = cursor
        while i < content.endOffset, content[i].isWhitespaceCharacter {
            i += 1
        }
        return i
    }

    @inline(__always)
    private func skipLineWhitespace(from cursor: Int, in content: borrowing ContentSpan) -> Int {
        var i = cursor
        while i < content.endOffset, content[i].isLineWhitespace {
            i += 1
        }
        return i
    }

    @inline(__always)
    private func skipLineWhitespaceAndOneLineEnd(from cursor: Int, in content: borrowing ContentSpan) -> Int {
        let i = skipLineWhitespace(from: cursor, in: content)
        guard i < content.endOffset else {
            return i
        }
        if content[i] == UInt8(ascii: "\n") {
            return skipLineWhitespace(from: i + 1, in: content)
        }
        guard contentHoldsCR, let afterLineEnding = lineEndingEnd(at: i, in: content) else {
            return i
        }
        return skipLineWhitespace(from: afterLineEnding, in: content)
    }

    @inline(__always)
    private func skipLineEndOrEOF(from cursor: Int, in content: borrowing ContentSpan) -> Int? {
        if cursor >= content.endOffset {
            return cursor
        }
        if content[cursor] == UInt8(ascii: "\n") {
            return cursor + 1
        }
        return contentHoldsCR ? lineEndingEnd(at: cursor, in: content) : nil
    }

    @inline(never)
    func lineEndingEnd(at cursor: Int, in content: borrowing ContentSpan) -> Int? {
        let byte = content[cursor]
        if byte == UInt8(ascii: "\n") {
            return cursor + 1
        }
        guard byte == UInt8(ascii: "\r") else {
            return nil
        }
        return cursor + 1 < content.endOffset && content[cursor + 1] == UInt8(ascii: "\n") ? cursor + 2 : cursor + 1
    }

    // MARK: - Link definition

    /// Try to parse exactly one `[label]: dest title?` form.
    ///
    /// Returns the offset just past the consumed bytes (including the trailing line end), or `nil` if no valid definition starts at `start`.
    @inline(__always)
    private mutating func parseOneLinkDefinition(from start: Int, in content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        guard let (label, destinationStart) = matchDefinitionLabel(from: start, in: content),
              let destination = matchLinkDestination(from: destinationStart, end: end, in: content) else {
            return nil
        }
        // Optional title (after spnl). If we find one but the line then doesn't end cleanly, rewind and try a no-title commit instead.
        var title: Range<Int> = destination.afterEnd..<destination.afterEnd
        var afterAll: Int? = nil
        let titleStart = skipLineWhitespaceAndOneLineEnd(from: destination.afterEnd, in: content)
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
        // `normalizeLabel` replaces a NUL itself (Insecure characters), since this content may not be NUL-replaced yet.
        let key = normalizeLabel(virtualRange: label, in: content)
        if key.isEmpty {
            return nil
        }
        let definition = ReferenceDefinition(
            destination: replacingNUL(unescapedChunk(destination.destination, in: content)),
            title: replacingNUL(unescapedTitle(title, in: content))
        )
        storage.referenceMap.storeIfAbsent(definition, forKey: key)
        return afterAll
    }

    @inline(__always)
    private mutating func matchDefinitionLabel(from start: Int, in content: borrowing ContentSpan) -> (label: Range<Int>, contentStart: Int)? {
        guard let label = matchLinkLabel(from: start, end: content.endOffset, in: content),
              label.afterEnd < content.endOffset,
              content[label.afterEnd] == UInt8(ascii: ":") else {
            return nil
        }
        return (label.interior, skipLineWhitespaceAndOneLineEnd(from: label.afterEnd + 1, in: content))
    }

    // MARK: - Attribute definition

    /// Try to parse exactly one `^[label]: attrs` form (extended-attribute definition).
    ///
    /// Returns the offset just past the consumed bytes (including the trailing line end), or `nil` if no valid definition starts at `start`.
    private mutating func parseOneAttributeDefinition(from start: Int, in content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        precondition(start < end && content[start] == UInt8(ascii: "^"), "an attribute definition is parsed only from a `^`")
        guard let (label, attributesStart) = matchDefinitionLabel(from: start + 1, in: content) else {
            return nil
        }
        var attributesEnd = attributesStart
        while attributesEnd < end, content[attributesEnd] != UInt8(ascii: "\n"), content[attributesEnd] != UInt8(ascii: "\r") {
            attributesEnd += 1
        }
        if attributesEnd == attributesStart {
            return nil
        }
        let key = normalizeLabel(virtualRange: label, in: content)
        if key.isEmpty {
            return nil
        }
        let attributesChunk = materializedChunk(start: attributesStart, end: attributesEnd, content: content)
        let attributes = replacingNUL(unescapedChunk(attributesChunk.trimming(using: self)))
        storage.attributeReferenceMap.storeIfAbsent(attributes, forKey: key)
        return skipLineEndOrEOF(from: attributesEnd, in: content)
    }

    @inline(__always)
    mutating func unescapedTitle(_ range: Range<Int>, in content: borrowing ContentSpan) -> Chunk {
        guard contentHoldsCR, firstCR(in: range) < range.upperBound else {
            return unescapedChunk(range, in: content)
        }
        let offset = storage.strings.count
        appendWritingLineEndingsAsLineFeeds(range, unescaping: true)
        return arenaChunk(from: offset)
    }

    mutating func unescapedChunk(_ chunk: Chunk, backslashEscapes: Bool = true) -> Chunk {
        guard holdsEscapeOrReference(chunk, backslashEscapes: backslashEscapes) else {
            return chunk
        }
        let outOffset = storage.strings.count
        appendUnescaped(chunk, backslashEscapes: backslashEscapes)
        return arenaChunk(from: outOffset)
    }

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

    @inline(__always)
    func characterReference(at offset: Int, in chunk: Chunk) -> EntityParser.EntityMatch? {
        let maxDecimalDigits = limits.maxDecimalCharacterReferenceDigits
        let maxHexadecimalDigits = limits.maxHexadecimalCharacterReferenceDigits
        return if chunk.inSource {
            EntityParser.matchEntity(start: offset, end: chunk.range.upperBound, source: sourceBytes, maxDecimalDigits: maxDecimalDigits, maxHexadecimalDigits: maxHexadecimalDigits)
        } else {
            EntityParser.matchEntity(start: offset, end: chunk.range.upperBound, source: storage.strings.span, maxDecimalDigits: maxDecimalDigits, maxHexadecimalDigits: maxHexadecimalDigits)
        }
    }

    func arenaChunk(from offset: Int) -> Chunk {
        Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
    }

    func firstCR(in range: Range<Int>) -> Int {
        let cr = SIMD16<UInt8>(repeating: UInt8(ascii: "\r"))
        return range.lowerBound + sourceBytes.extracting(range).firstIndex(matching: { $0 .== cr }, or: { $0 == UInt8(ascii: "\r") })
    }

    @inline(never)
    mutating func lineFeedCopy(of chunk: Chunk) -> Chunk? {
        guard firstCR(in: chunk.range) < chunk.range.upperBound else {
            return nil
        }
        let offset = storage.strings.count
        appendWritingLineEndingsAsLineFeeds(chunk.range)
        return arenaChunk(from: offset)
    }

    // A backslash escape or character reference never continues past a line ending, so each line unescapes alone.
    mutating func appendWritingLineEndingsAsLineFeeds(_ range: Range<Int>, unescaping: Bool = false) {
        var i = range.lowerBound
        while i < range.upperBound {
            let cr = firstCR(in: i..<range.upperBound)
            if unescaping {
                appendUnescaped(Chunk(offset: i, length: cr - i, inSource: true))
            } else {
                storage.strings.append(copying: sourceBytes.extracting(i..<cr))
            }
            if cr == range.upperBound {
                return
            }
            storage.strings.append(UInt8(ascii: "\n"))
            i = cr + 1 < range.upperBound && sourceBytes[cr + 1] == UInt8(ascii: "\n") ? cr + 2 : cr + 1
        }
    }
}

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// Block-level Markdown parser.
internal struct BlockParser : ~Copyable, ~Escapable {
    /// The storage we are parsing from.
    internal var storage: DocumentStorage
    
    /// The source bytes as a `Span<UInt8>`.
    ///
    /// The parser is byte-oriented; the borrowed source is held directly as a span (UTF-8 validity is only re-established at the `UTF8Span`-vending public API).
    internal let sourceBytes: Span<UInt8>
    
    /// The root document node - always index 0.
    let documentIndex: DocumentStorage.Index

    /// The capacity initially reserved for the reused open-container chain buffer.
    ///
    /// `walkOpenContainers` rebuilds the open block-quote/list ancestor chain into this buffer each line.
    /// The buffer grows on demand for deeper nesting, so this reservation only avoids reallocation for
    /// typical documents.
    static let initialOpenContainerCapacity = 256

    /// The block-start depth on one line at which a list marker stops opening a list.
    ///
    /// Each block start matched on a line, such as a block quote marker or a list marker, is one level of
    /// depth, counting from 1. A bullet or ordered list marker at depth `maxListNesting` or deeper opens
    /// no list and its text becomes paragraph content, so 99 block quote markers followed by `- ` give no
    /// list. The cap bounds the cost of deeply nested lists. It counts only the current line, so nesting
    /// spread across lines is unaffected, and block quotes are uncapped.
    static let maxListNesting = 100

    /// The deepest currently-open block.
    ///
    /// New text is appended here (or to a new child of an ancestor) and finalization unwinds outward toward the root.
    var current: DocumentStorage.Index

    /// The single open leaf's accumulated content together with the node it belongs to.
    ///
    /// At most one leaf (paragraph / heading / code / HTML block) accumulates content at any moment: the parser drains a leaf via `materializePendingContent` before the next one opens, and container blocks (block quote / list / item) never hold text. This state is threaded through the block-parse call chain - functions that begin or extend a leaf's content `consume` the current `PendingLeaf?` and return the updated one, and `parse()` owns the root binding.
    struct PendingLeaf : ~Copyable {
        /// The node this content is accumulating into.
        var node: DocumentStorage.Index
        /// The accumulated content.
        var content: PendingContent
    }

    /// A single source-range slice (`.lazy`, addressable directly into `BlockParser.source` with no copy), a materialized byte buffer (`.materialized`: arena content re-seeded when an underline line is examined, plus the lines appended to it), or a segment list (`.segments`).
    ///
    /// Single-line paragraphs/headings parsed from the original source stay `.lazy` until `materializePendingContent` emits them as a `Chunk(inSource: true)`.
    ///
    /// A `.lazy` span with `joinPending` set holds a deferred separator: a continuation `\n` is requested after the span but not committed, so that if the *next* line turns out to be contiguous in source (single-LF terminated, no stripped prefix) the whole multi-line run can stay a single zero-copy source range - the embedded `\n` comes from the source itself rather than a synthesized copy. Only `appendNewline` sets it, and the next `addLine` always clears it, so content that is drained or inspected between lines never has it set.
    enum PendingContent : ~Copyable {
        case lazy(range: Range<Int>, joinPending: Bool = false)
        case materialized(MaterializedText)
        /// An ordered segment list.
        ///
        /// Each line is a zero-copy source `Segment` (or, for a code/HTML block body line that splits a tab, an arena copy) and each line join is the shared `newlineSegment`. Used for code/HTML block bodies, and for paragraph lines that are not contiguous in the source. Drained at finalize into a multi-segment `ContentRef` with no source bytes copied.
        case segments(UniqueArray<Segment>)
    }

    /// A paragraph or heading's content copied into a byte buffer, with the content-relative arena→source run map (`ArenaRun`s tiling `bytes` from its first byte) that images each byte: a copied source byte its own offset, a synthetic byte the source byte it stands for, and a line join a gap.
    ///
    /// The map is kept whether or not positions are tracked: it costs one run per contiguous source stretch, and the content it re-seeds must arrive with a map that tiles it (`addChunk`).
    struct MaterializedText : ~Copyable {
        private(set) var bytes = UniqueArray<UInt8>()
        private(set) var map: [ArenaRun] = []

        init() {}

        /// The bytes `bytes` imaged by the content-relative run map `map`, which tiles them.
        init(bytes: consuming UniqueArray<UInt8>, map: [ArenaRun]) {
            precondition(map.reduce(0) { $0 + Int($1.length) } == bytes.count, "a run map tiles its content")
            self.bytes = bytes
            self.map = map
        }

        var count: Int { bytes.count }

        subscript(_ index: Int) -> UInt8 { bytes[index] }

        /// Append `byte`, imaging source byte `sourceOffset` (see `ArenaRun`), or a synthetic gap when `sourceOffset < 0`.
        mutating func append(_ byte: UInt8, imaging sourceOffset: Int) {
            bytes.append(byte)
            BlockParser.appendContentByte(imaging: sourceOffset, to: &map)
        }

        /// Append the source bytes `source[range]`, each imaging itself.
        mutating func append(_ range: Range<Int>, of source: Span<UInt8>) {
            bytes.reserveCapacity(bytes.count + range.count)
            for i in range {
                append(source[i], imaging: i)
            }
        }
    }

    /// Result of `materializePendingContent`: the materialized `Chunk` plus the drained leaf. `map` carries a content-relative arena→source run map when the content is flattened from a source-mapped segment list (empty otherwise).
    struct LeafMaterialization : ~Copyable {
        var chunk: Chunk
        var pending: PendingLeaf?
        var map: [ArenaRun] = []
    }

    /// Result of `drainSegments`: the drained segment list plus the cleared leaf.
    struct LeafSegments : ~Copyable {
        var segments: UniqueArray<Segment>
        var pending: PendingLeaf?
    }

    /// Result of the code/HTML block continuation handlers: whether the block stays open plus the updated leaf.
    struct LeafContinuation : ~Copyable {
        var stillOpen: Bool
        var pending: PendingLeaf?
    }

    /// `true` when the line currently being processed is passed to `processLine` as a slice of `self.source` (i.e. no per-line tab expansion applies).
    ///
    /// Used by `addLine` to decide whether the bytes can be addressed lazily by source-range, deferring materialization until the paragraph spans multiple lines or otherwise transforms the content.
    var currentLineMapsToSource: Bool = false

    /// For a tab-expanded (materialized) line, the buffer offset where `expandPrefixTabs`'s verbatim tail begins, and the corresponding original-line byte offset. Since the tail is copied byte-for-byte, every content offset in it maps back to source by the constant delta `currentLineSourceRange.lowerBound + materializedRestStart - materializedTailBufferStart`; offsets inside the expanded prefix are recovered by a column walk on the original line. Only meaningful while `!currentLineMapsToSource` (see `sourceOffset` for the positions path, and `materializedSourceOffset` / `materializedSourceStart` for the positions-independent content paths).
    var materializedTailBufferStart: Int = 0
    var materializedRestStart: Int = 0

    /// `true` when `.sourcePosition` tracking is on.
    ///
    /// Hoisted so the per-node stamping in `addChild` and `finalize` is a single bool test on the hot path when positions are off.
    let positionsEnabled: Bool

    /// Original-source byte range of the line currently being processed, tracked for every line (positions on or off). Stamps block end positions at finalize time and to recover a materialized code/HTML body line's literal source bytes. `lastLineSourceEnd` keeps the previous line's content end so a block closed by a *later* line can attribute its end to the line it actually ended on.
    var currentLineSourceRange: Range<Int> = 0..<0
    var lastLineSourceEnd: Int = 0

    /// `true` when the line currently being processed is a *lazy* paragraph continuation: at least one open container's continuation prefix failed to match on this line (a block quote with no `>`, or a list item indented less than its content column), so the container-prefix walk stopped short of the open leaf. Set per line in `processLine` from the walk's `allMatched`.
    var currentLineIsLazyContinuation: Bool = false

    /// Inline-parsing tasks deferred until after all block parsing completes.
    ///
    /// This delay is what lets a `[foo]` shortcut reference resolve against a `[foo]: url` link reference definition that appears later in the document. Each entry is a `(node, content chunk)` pair: when the parse pass finishes, `BlockParser.parse` drains this list and invokes `InlineParser.parse` on each.
    var pendingInlines: [(DocumentStorage.Index, ContentRef)] = []

    /// Arena→source run maps for flattened inline content that has a source pre-image, keyed by the content's node.
    ///
    /// Registered at finalize for paragraph, heading, table-cell and table-preceding-paragraph content that reaches inline parsing as one arena `Chunk` (flattened from segments, materialized, NUL-replaced or pipe-unescaped), which loses the per-line source mapping the content had. The content-relative run map lets the inline pass stamp the node's inlines with real source positions. Consulted in the inline pass when building an arena single-segment `ContentSpan`.
    var arenaSourceMaps: [DocumentStorage.Index: [ArenaRun]] = [:]

    /// The indent, in columns, of each paragraph's second line, keyed by the paragraph node and recorded
    /// the first time the paragraph is continued.
    ///
    /// A table's delimiter row is its paragraph's second line (Tables (extension)), and a delimiter row
    /// indented four or more columns past its container's content column is paragraph text. Tables are
    /// detected when the paragraph closes, after each continuation line's leading whitespace is stripped,
    /// so `runParagraphMatchers` reads the indentation recorded here. Only populated when `.tables` is
    /// enabled.
    var paragraphSecondLineIndent: [DocumentStorage.Index: Int] = [:]

    /// `true` when a paragraph's second line, its table delimiter-row candidate, is a lazy continuation
    /// line. Keyed by the paragraph node, recorded once alongside `paragraphSecondLineIndent`.
    ///
    /// A table opens only from a delimiter row that matches every open container's continuation prefix;
    /// a lazy continuation line (Block quotes) continues the paragraph as text, so `>o\n--` and `>o\n|-`
    /// form no table. Tables are detected when the paragraph closes, where laziness is not
    /// observable, so it is recorded here.
    var paragraphSecondLineLazy: [DocumentStorage.Index: Bool] = [:]

    /// `true` when a paragraph's first two lines form a table's header and delimiter rows, keyed by the
    /// paragraph node and recorded once alongside `paragraphSecondLineIndent`.
    ///
    /// Such a paragraph is a table from its delimiter row onward, and a lazy continuation line continues
    /// only a paragraph, so a later line that fails an open container's prefix closes the table and that
    /// container instead of becoming a body row. Tables are detected when the paragraph closes, so
    /// `processLine` consults this flag to break the first such line, and everything after it, out of the
    /// table and its container. Only populated when `.tables` is enabled and the delimiter row is a
    /// non-indented, non-lazy continuation line.
    var paragraphTablePending: [DocumentStorage.Index: Bool] = [:]

    /// Per-kind stretches of scan starts from which a first-closer raw-HTML scan is known to fail in the current `parseInline` pass (`HTMLCloserMisses`). Reset per pass.
    var htmlCloserMisses = HTMLCloserMisses()

    /// The character references decoded in the current `parseInline` pass, with positions tracked, in arena order:
    /// each pair is the decoded bytes' arena range and the reference's source range, `&` through `;`. Reset per pass.
    var characterReferenceSources: [(arena: Range<Int>, source: Range<Int>)] = []

    // MARK: - Init
    
    @_lifetime(copy source)
    init(storage: consuming DocumentStorage, source: Span<UInt8>) {
        self.storage = storage
        self.sourceBytes = source
        self.positionsEnabled = self.storage.options.contains(.sourcePosition)

        // Pre-size the append-only arenas from the input length so they don't grow geometrically during the parse (each growth is a malloc + a memmove of everything appended so far - a measurable share of parse time and the bulk of the remaining allocations on large inputs).
        // Ratios are deliberately generous: over-reserving costs one larger malloc with no zero-fill, while under-reserving brings the realloc chain back. `NodeRecord` is ~100 B so its ratio is the most conservative; `Segment` (12 B) and the `strings` byte arena are cheap.
        let byteCount = self.sourceBytes.count
        self.storage.nodes.reserveCapacity(byteCount / 16)
        self.storage.segments.reserveCapacity(byteCount / 16)
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

        // One reused buffer for the open-container ancestor chain that `walkOpenContainers` rebuilds per line. Heap-backed and reserved once to `initialOpenContainerCapacity` (growing on demand for deeper nesting); reset (keeping capacity) per line. The single open leaf's accumulated content (`pending`) is `~Copyable`, threaded by move through the per-line dispatch and drained to `nil` by the EOF-finalize loop below.
        var chain = UniqueArray<DocumentStorage.Index>(minimumCapacity: Self.initialOpenContainerCapacity)
        do {
            var pending: PendingLeaf? = nil
            while let line = reader.next() {

                // Pre-expand leading tabs (and tabs after container markers like `>` or list markers) into spaces. This sidesteps the partial-tab consumption problem for cases like `>\t\tfoo` and `-\t\tfoo`, where a marker would consume only part of a tab byte and the leftover columns need to remain visible to the next inner block. Skipped for lines inside an open fenced code block.
                let inFencedCode = if case .codeBlock(let info) = storage[current].kind, info.isFenced {
                    true
                } else {
                    false
                }

                let lineRangeInOriginalSource = reader.lineRange
                if positionsEnabled {
                    // Record this line's start (for byte→line/col conversion) and remember the previous line's content end before advancing `currentLineSourceRange`.
                    storage.lineStarts.append(lineRangeInOriginalSource.lowerBound)
                    lastLineSourceEnd = currentLineSourceRange.upperBound
                }
                // Tracked unconditionally: recovering a materialized line's literal source bytes - a code/HTML body line (`appendMaterializedCodeContent`) or paragraph/heading text (`addLine`, `addLineSegment`) - needs the current line's source range even when positions are off, since content must preserve tabs regardless of `.sourcePosition`.
                currentLineSourceRange = lineRangeInOriginalSource
                
                // Per-line materialized buffer used when a line's leading tabs need to be expanded into spaces so partial-tab consumption by container markers works correctly.
                if !inFencedCode, let materialized = expandPrefixTabs(line: line) {
                    currentLineMapsToSource = false
                    materializedTailBufferStart = materialized.tailBufferStart
                    materializedRestStart = materialized.restStart
                    let span = materialized.buffer.span
                    pending = processLine(source: span, lineRange: 0..<span.count, chain: &chain, pending: pending)
                } else {
                    currentLineMapsToSource = true
                    pending = processLine(source: sourceBytes, lineRange: lineRangeInOriginalSource, chain: &chain, pending: pending)
                }
            }

            // EOF: finalize all open blocks back up to the document root. Runs inside this closure (it doesn't touch `chain`) so `pending` stays local - by the end every leaf is drained and `pending` is `nil`.
            while current != documentIndex {
                pending = finalize(node: current, pending: pending, atEOF: true)
            }
            
            // The document root is never passed to `finalize`; stamp its whole-source span here, from the first line's start (after any leading BOM, so it projects to 1:1) to the last line's content end. An empty document has no lines and no source range.
            if positionsEnabled, reader.lineNumber > 0 {
                storage.setSourceStart(documentIndex, storage.lineStarts[0])
                storage.setSourceEnd(documentIndex, currentLineSourceRange.upperBound)
            } else if positionsEnabled, reader.nextStart > 0 {
                // A document consisting only of a BOM is one empty line, so the document spans that empty line after the BOM.
                storage.lineStarts.append(reader.nextStart)
                storage.setSourceStart(documentIndex, reader.nextStart)
                storage.setSourceEnd(documentIndex, reader.nextStart)
            }
        }

        // Inline-parsing pass: with all blocks closed (and `storage`'s `referenceMap` / `attributeReferenceMap` / `footnoteMap` fully populated), run inline parsing for every paragraph and heading queued during finalize. Forward references like `[foo]\n\n[foo]: url` resolve correctly because the def is in the map by the time the ref's paragraph is parsed.
        let pending = pendingInlines
        
        var delimiters = UniqueArray<DelimiterRecord>()
        var brackets = UniqueArray<BracketRecord>()
        
        // Reused scratch buffers: `scratch` holds an arena-content copy while it is parsed; `segScratch` holds a stable copy of a multi-segment content's segment list (the live `storage.segments` pool grows as `parseInline` interns node content) and `segEndScratch` its running virtual end offsets; `runScratch` holds a stable copy of a flattened block's arena→source run map and `runEndScratch` its running end offsets. All owned here so their borrow is independent of the `storage` mutations `parseInline` performs.
        var scratch = UniqueArray<UInt8>()
        var segScratch = UniqueArray<Segment>()
        var segEndScratch = UniqueArray<Int>()
        var runScratch = UniqueArray<ArenaRun>()
        var runEndScratch = UniqueArray<Int>()
        
        for (node, ref) in pending {
            precondition(ref.totalLength > 0, "only non-empty content is queued for inline parsing")
            if ref.count == 1 {
                let chunk = storage.segments[Int(ref.first)].chunk
                if chunk.inSource {
                    // Source-backed: zero-copy slice of the source span.
                    parseInline(
                        content: ContentSpan(span: sourceBytes.extracting(chunk.range), base: chunk.offset, inSource: true),
                        into: node,
                        delimiters: &delimiters,
                        brackets: &brackets
                    )
                } else {
                    // Arena-backed: copy the content region out of `storage.strings` so the read view is independent of the appends `parseInline` makes to that same array.
                    scratch.removeSubrange(0..<scratch.count)
                    scratch.append(copying: storage.strings.span.extracting(chunk.range))
                    // Arena content with a source image carries an arena→source run map so its inlines get source positions; arena content without one (positions off) parses unmapped.
                    runScratch.removeSubrange(0..<runScratch.count)
                    runEndScratch.removeSubrange(0..<runEndScratch.count)
                    if let map = arenaSourceMaps[node] {
                        var runEnd = 0
                        for run in map {
                            runScratch.append(run)
                            runEnd += Int(run.length)
                            runEndScratch.append(runEnd)
                        }
                    }
                    parseInline(
                        content: ContentSpan(span: scratch.span, base: chunk.offset, inSource: false, arenaRuns: runScratch.span, arenaRunEnds: runEndScratch.span),
                        into: node,
                        delimiters: &delimiters,
                        brackets: &brackets
                    )
                }
            } else {
                // Multi-segment content (multi-line non-contiguous paragraph/heading): copy the segment list into stable storage and parse it directly from the source - no flattening into the arena.
                segScratch.removeSubrange(0..<segScratch.count)
                segEndScratch.removeSubrange(0..<segEndScratch.count)
                var virtualEnd = 0
                for i in 0..<Int(ref.count) {
                    let seg = storage.segments[Int(ref.first) + i]
                    segScratch.append(seg)
                    virtualEnd += Int(seg.length)
                    segEndScratch.append(virtualEnd)
                }
                parseInline(
                    content: ContentSpan(source: sourceBytes, segments: segScratch.span, segmentEnds: segEndScratch.span, virtualLength: Int(ref.totalLength)),
                    into: node,
                    delimiters: &delimiters,
                    brackets: &brackets
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

    /// Number the footnote references in document order, drop footnote definitions that no reference
    /// resolves to, and move the referenced ones to the end of the document root in index order.
    ///
    /// Definitions nested in a block quote or list item move to the document root too, leaving any
    /// emptied container behind. Numbering comes from the references present in the finished tree.
    private mutating func processFootnotes() {
        guard storage.options.contains(.footnotes) else { return }
        // A footnote reference exists only where its label resolves to a footnote definition.
        guard !storage.footnoteDefinitionOrder.isEmpty else { return }
        let referencedDefs = numberLiveFootnoteReferences()
        let keep = Set(referencedDefs)
        // Drop definitions with no surviving reference (including duplicate-label definitions, whose
        // references all resolved to the label's winning definition).
        for defIdx in storage.footnoteDefinitionOrder where !keep.contains(defIdx) {
            storage.unlinkChild(defIdx)
        }
        for defIdx in referencedDefs {
            storage.unlinkChild(defIdx)
            storage.appendChild(defIdx, to: documentIndex)
        }
    }

    /// Assign each footnote reference in the finalized tree its 1-based index, and each referenced
    /// definition its reference count. Returns the referenced definitions in index order (the order of
    /// their first reference).
    ///
    /// A definition's index is fixed by its first reference in document pre-order; later references to
    /// the same definition reuse it. The walk covers every container, including footnote definitions,
    /// whose content can reference other footnotes. It keeps an explicit stack rather than recursing so
    /// that deeply nested trees, such as thousands of nested block quotes, do not overflow the call
    /// stack.
    private mutating func numberLiveFootnoteReferences() -> [DocumentStorage.Index] {
        var referencedDefs: [DocumentStorage.Index] = []
        var indices: [DocumentStorage.Index: Int] = [:]
        var referenceCounts: [DocumentStorage.Index: Int] = [:]
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
                referenceCounts[defIdx, default: 0] += 1
            }
            if let next = storage[node].next {
                pending.append(next)
            }
            if let child = storage[node].firstChild {
                pending.append(child)
            }
        }
        for (defIdx, count) in referenceCounts {
            if case .footnoteDefinition(let label, _) = storage[defIdx].data {
                storage[defIdx].data = .footnoteDefinition(label: label, referenceCount: count)
            }
        }
        return referencedDefs
    }

    /// Inline-only parse path for `.inlineOnly` / `.preserveWhitespace`.
    ///
    /// Bypasses block structure completely: any non-empty input (even a BOM-only one) becomes a single `.paragraph`, and empty input yields no paragraph. The paragraph's content is the source with a leading UTF-8 BOM skipped and line endings normalized to `\n`, but with every other byte preserved verbatim - leading indentation, interior space runs, trailing spaces, and all line endings (including a trailing one). Markers like `#`, `* `, `> `, fences and 4-space indents stay literal text; only *inline* syntax (emphasis, code spans, links, autolinks, …) is parsed, and line endings remain literal text rather than becoming soft or hard line breaks.
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

        // Count lines and detect whether any CR needs normalizing to LF, in a single pass that SIMD-skips the runs of content bytes between line breaks (`nextLineBreak`) rather than stepping one byte at a time. Each line ending (`\r\n`, lone `\r`, or `\n`) ends one line, and a final line without a line ending counts as a line. Detecting CR in the same scan is what lets the common LF-only / break-free case stay zero-copy below, addressing the source directly - so line-counting costs no extra pass.
        var hasCR = false
        var lines = 0
        // Where the last line's content ends: its terminator's first byte, or the end of input for an unterminated last line.
        var contentEnd = count
        var i = start
        // A BOM-only input is one empty line, and that line opens the paragraph.
        repeat {
            // Record each line's start for byte→line/col conversion (`StorageView.position(ofByte:)`), exactly as the block path does per `LineReader` line.
            if positionsEnabled {
                storage.lineStarts.append(i)
            }
            let brk = i + LineReader.firstLineTerminator(in: sourceBytes.extracting(i..<count))
            if brk == count {
                // Trailing content with no terminator → one final unterminated line.
                lines += 1
                contentEnd = count
                break
            }
            lines += 1
            contentEnd = brk
            if sourceBytes[brk] == UInt8(ascii: "\r") {
                hasCR = true
                // A `\r` immediately followed by `\n` is a single CRLF terminator.
                i = (brk + 1 < count && sourceBytes[brk + 1] == UInt8(ascii: "\n")) ? brk + 2 : brk + 1
            } else {
                i = brk + 1
            }
        } while i < count
        storage.lineCount = lines

        // Link reference definitions leading the content are consumed, and the paragraph is kept even when
        // nothing, or only whitespace, remains.
        let paragraph = addChild(kind: .paragraph, parent: documentIndex, start: start)
        // The paragraph's content is the whole post-BOM input, trailing line ending included (it is literal text here), and the document spans exactly its one paragraph. Both end where the last line's content ends, as in block mode, so a final line ending doesn't carry the range past the last line.
        storage.setSourceStart(documentIndex, start)
        storage.setSourceEnd(documentIndex, contentEnd)
        storage.setSourceEnd(paragraph, contentEnd)

        var delimiters = UniqueArray<DelimiterRecord>()
        var brackets = UniqueArray<BracketRecord>()
        // A NUL forces the arena-copy path below (per Insecure characters, NUL becomes U+FFFD); scanned here so a
        // NUL-free, LF-only document stays zero-copy.
        var hasNUL = false
        for k in start..<count where sourceBytes[k] == 0 {
            hasNUL = true
            break
        }
        // The arena copy's source image, for the email autolink pass.
        var image: ContentImage? = nil
        if !hasCR && !hasNUL {
            // Zero-copy: the paragraph content is a source slice; emitted text references the source in place.
            let rest = parseDefinitions(in: Chunk(offset: start, length: count - start, inSource: true))
            let content = ContentSpan(span: sourceBytes.extracting(rest.range), base: rest.offset, inSource: true)
            parseInline(
                content: content,
                into: paragraph,
                preserveWhitespace: true,
                delimiters: &delimiters,
                brackets: &brackets
            )
        } else {
            // Normalize `\r\n` and lone `\r` to `\n` and each NUL to U+FFFD into the string arena, then read from an independent scratch copy (the inline parser appends to `storage.strings` as it runs).
            // With positions on, also record the arena→source run map (inline stamping resolves a node's first byte for its start and its last byte, plus one, for its end). Every byte copied as-is, or a lone `\r` → `\n`, images its own source byte. A CRLF's `\n` images its LF, so a node ending at the line break covers the whole CRLF and projects to the next line's start, as it does for LF input (a node ending at the final line ending is pulled back to the end of the last line by `endInlinesWithinLastLine`); the cost is that a node *starting* at that `\n` starts one byte late, after the CR. Each of a U+FFFD's three bytes images its one NUL byte, so a node starting or ending at it covers exactly that byte.
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
                    storage.strings.append(0xEF)
                    storage.strings.append(0xBF)
                    storage.strings.append(0xBD)
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
            var scratch = UniqueArray<UInt8>()
            scratch.append(copying: storage.strings.span.extracting(rest.range))
            var runScratch = UniqueArray<ArenaRun>()
            var runEndScratch = UniqueArray<Int>()
            if positionsEnabled {
                var runEnd = 0
                for run in sliceRuns(runs, from: rest.offset - arenaStart, length: rest.length) {
                    runScratch.append(run)
                    runEnd += Int(run.length)
                    runEndScratch.append(runEnd)
                }
            }
            let content = ContentSpan(span: scratch.span, base: rest.offset, inSource: false, arenaRuns: runScratch.span, arenaRunEnds: runEndScratch.span)
            parseInline(
                content: content,
                into: paragraph,
                preserveWhitespace: true,
                delimiters: &delimiters,
                brackets: &brackets
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

    /// Pull back the range of every node created after `paragraph` that runs past `contentEnd`, the end of the inline-only input's last line content, to end there.
    ///
    /// Inline stamping ends a node one past the source byte its last content byte stands for. For a node holding the final line ending, that end lies past the last line, because no line follows it. A node that starts inside that line ending (a CRLF's `\n` stands for its LF) starts at `contentEnd` too, so it keeps an empty range where the line ending starts.
    private mutating func endInlinesWithinLastLine(after paragraph: DocumentStorage.Index, contentEnd: Int) {
        for node in (paragraph + 1)..<storage.nodes.count where storage.sourceRanges[node].end > contentEnd {
            storage.sourceRanges[node].end = contentEnd
            storage.sourceRanges[node].start = min(storage.sourceRanges[node].start, contentEnd)
        }
    }

    /// Extend an arena→source run map by one content byte that images source byte `sourceOffset` (see `ArenaRun`), or by one synthetic gap byte when `sourceOffset < 0`: the last run grows when the byte continues it, otherwise a new run starts.
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

    /// Post-process a leaf's freshly parsed inline children: merge adjacent text nodes, then detect extended email autolinks.
    ///
    /// Merging runs in every parse mode, including inline-only, so unmatched delimiters, entity and numeric character references, and backslash escapes merge with their neighbouring text.
    ///
    /// `image` maps the leaf's content back to source when it is one arena chunk with a source image.
    private mutating func finishInlines(_ leaf: DocumentStorage.Index, image: ContentImage?) {
        consolidateTextNodes(leaf)
        // Email autolinks (Autolinks (extension)) are found in merged text, after emphasis is resolved.
        if storage.options.contains(.gfmAutolink) {
            gfmEmailAutolinkPass(leaf, image: image)
        }
    }

    // MARK: - State
    
    /// Append a node as a child of the given parent. Returns the new node's index.
    private mutating func addChild(kind: MarkdownNode.Kind, parent: DocumentStorage.Index, data: NodeData? = nil, start: Int? = nil) -> DocumentStorage.Index {
        let idx = storage.appendNode(NodeRecord(kind: kind, parent: parent, data: data))
        storage.appendChild(idx, to: parent)
        storage.setSourceStart(idx, start)
        return idx
    }

    /// The global original-source byte offset for a within-current-line offset.
    ///
    /// When the line maps to source the passed offset is a global source offset (the line is processed as a slice of `sourceBytes`). For a tab-expanded (materialized) line, the offset is a transient-buffer offset: `expandPrefixTabs` only expands the leading whitespace/marker prefix and copies the rest of the line verbatim, so a tail offset maps back by a constant delta and a prefix offset is recovered by re-walking the original line's prefix (see `originalPrefixSourceOffset`). Returns `nil` for a materialized line when positions are off, since its callers only stamp positions; content that must be read back from source uses `materializedSourceOffset`, which doesn't depend on `.sourcePosition`.
    private func sourceOffset(_ lineOffset: Int) -> Int? {
        if currentLineMapsToSource {
            return lineOffset
        }
        guard positionsEnabled else { return nil }
        return materializedSourceOffset(lineOffset)
    }

    /// Map a materialized-buffer offset back to its original-source byte offset, independent of
    /// `positionsEnabled` (unlike `sourceOffset`, which gates on positions). A tail offset maps by a
    /// constant delta; an offset inside the expanded prefix resolves to the byte whose expansion covers
    /// it (a mid-tab offset resolves to that tab's byte). Callers must hold `!currentLineMapsToSource`.
    private func materializedSourceOffset(_ bufferOffset: Int) -> Int {
        if bufferOffset >= materializedTailBufferStart {
            // Verbatim tail: a single constant delta covers every content offset.
            return currentLineSourceRange.lowerBound + materializedRestStart + (bufferOffset - materializedTailBufferStart)
        }
        // Inside the expanded prefix (e.g. an indented-code `bodyStart` landing mid-prefix, or a container marker): re-walk the original prefix to find the byte covering this buffer offset.
        return originalPrefixSourceOffset(bufferOffset: bufferOffset)
    }

    /// Map a buffer offset lying inside a materialized line's expanded prefix back to an original-source byte offset.
    ///
    /// Re-walks the original line's prefix (`[lineStart, lineStart + materializedRestStart)`) with the same tab-expansion rule `expandPrefixTabs` used, tracking each byte's span in the expanded buffer, and returns the source offset of the byte whose expansion covers `bufferOffset`. A tab covers its whole `4 - (col & 3)` run, so a buffer offset landing mid-tab resolves to that tab's byte. O(prefix).
    private func originalPrefixSourceOffset(bufferOffset: Int) -> Int {
        let lineStart = currentLineSourceRange.lowerBound
        let prefixEnd = lineStart + materializedRestStart
        var col = 0
        var i = lineStart
        while i < prefixEnd {
            let width = sourceBytes[i] == UInt8(ascii: "\t") ? 4 - (col & 3) : 1
            if bufferOffset < col + width {
                break
            }
            col += width
            i += 1
        }
        precondition(i < prefixEnd, "a buffer offset inside the expanded prefix is covered by the prefix walk")
        return i
    }

    /// Consume `pending` and return `node`'s accumulated content, or `nil` if `node` has none (either nothing is pending, or a *different* node's leaf is - which the single-open-leaf invariant forbids).
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

    /// Consume `content` and materialize it into a `MaterializedText` ready for further appends.
    ///
    /// A `.materialized` entry's buffer is *moved* out (no copy). `nil` yields an empty buffer.
    private func unwrap(_ content: consuming PendingContent?) -> MaterializedText {
        switch consume content {
        case .none:
            return MaterializedText()
        case .lazy?:
            preconditionFailure("source-backed content is extended in place, never copied into a buffer")
        case .materialized(let existing)?:
            return existing
        case .segments?:
            // Segment lists are only produced for code/HTML blocks, which never re-seed via this path.
            fatalError("unwrap called on segment-list content")
        }
    }

    /// Append the bytes of the arena `chunk`, imaged by its content-relative run map `map`, to `pending` for `node`, returning the updated leaf.
    ///
    /// Used when re-seeding a node's content after a transformation step (e.g. setext heading content trimmed of leading link reference definitions).
    private mutating func addChunk(_ chunk: Chunk, map: [ArenaRun], to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        precondition(!chunk.inSource, "source-backed content re-seeds as a `.lazy` range, not through addChunk")
        precondition(map.reduce(0) { $0 + Int($1.length) } == chunk.length, "a run map tiles its content")
        var text = unwrap(take(pending, ifNode: node))
        var i = chunk.offset
        for run in map {
            for j in 0..<Int(run.length) {
                let sourceOffset = run.sourceOffset < 0 ? -1 : Int(run.sourceOffset) + j
                text.append(storage.strings[i], imaging: sourceOffset)
                i += 1
            }
        }
        return PendingLeaf(node: node, content: .materialized(text))
    }

    /// Append the bytes from `span[range]` to `pending` for `node`, returning the updated leaf.
    private mutating func addLine(span: Span<UInt8>, range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        // Code/HTML block bodies accumulate as a zero-copy segment list rather than a materialized byte buffer (they're never inline-parsed). See `addLineSegment`.
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            return addLineSegment(span: span, range: range, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .none:
            // Fast path: first content for this node and the current line maps directly into `self.source` - store the range lazily and skip the byte copy.
            precondition(nodeKind.canAccumulateText, "only paragraphs and headings accumulate text lines")
            if currentLineMapsToSource {
                return PendingLeaf(node: node, content: .lazy(range: range))
            }
            // Tab-expanded line: per Tabs, tabs behave as spaces only where they define block structure and stay literal in content, so the content is the literal source range rather than the expanded buffer. `expandPrefixTabs` expands only the consumed indentation and copies the rest verbatim, so the first content byte maps to a genuine source byte (never inside an expanded tab's spaces) and the content end maps to the source line end. This covers content that maps 1:1 (the `*` of `*5*` after `*\t` or `>\t`) and content straddling an expanded tab (`**\tx`, where no block marker consumes the tab, so it lands inside the paragraph). The mapping reads only unconditionally tracked line state, so the content is the same whether or not `.sourcePosition` is set.
            return PendingLeaf(node: node, content: .lazy(range: materializedSourceOffset(range.lowerBound)..<materializedSourceOffset(range.upperBound)))
        case .some(let existing):
            // Contiguity fast path: a `\n` separator is deferred after a `.lazy` span (`appendNewline` set its `joinPending`). If this line is also source-backed and immediately follows the previous span in the source - i.e. it starts one byte past the previous span and that byte is a single `\n` - then the join needs no synthesized separator: the embedded `\n` already lives in the source, so we keep the whole run as one zero-copy `.lazy` range. This holds for top-level paragraphs with LF line endings and no stripped container prefix; block quote/list continuation (prefix stripped → non-adjacent range), CRLF/CR (separator isn't a lone `\n` at `prev.upperBound`), and tab-expanded lines (`!currentLineMapsToSource`) all fall through to the segment-list arm below.
            switch consume existing {
            case .lazy(let prev, joinPending: true) where currentLineMapsToSource
                    && range.lowerBound == prev.upperBound + 1
                    && prev.upperBound < sourceBytes.count
                    && sourceBytes[prev.upperBound] == UInt8(ascii: "\n"):
                return PendingLeaf(node: node, content: .lazy(range: prev.lowerBound..<range.upperBound))
            case .lazy(let prev, joinPending: true):
                // Non-contiguous continuation (block-quote/list prefix stripped, CRLF, tab): switch to a source-segment list rather than copying bytes - the previous span becomes a zero-copy source segment, joined to this line by the shared interned `\n`.
                var segs = UniqueArray<Segment>()
                segs.append(Segment(offset: Int32(prev.lowerBound), length: Int32(prev.count), inSource: true))
                segs.append(storage.newlineSegment)
                return addLineSegment(span: span, range: range, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
            case .segments(let segs):
                return addLineSegment(span: span, range: range, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
            case let other:
                var text = unwrap(other)
                // A tab-expanded current line (`!currentLineMapsToSource`) has `span` pointing at the per-line expanded buffer, not source - appending `span[range]` directly would bake the expanded-tab spaces into the arena as if they were literal content. Map back to the literal source range instead, as in the `.none` case above: per Tabs, tabs stay literal in content.
                if !currentLineMapsToSource {
                    text.append(materializedSourceOffset(range.lowerBound)..<materializedSourceOffset(range.upperBound), of: sourceBytes)
                } else {
                    // A source-mapped line's `span` is the source itself.
                    text.append(range.lowerBound..<range.upperBound, of: span)
                }
                return PendingLeaf(node: node, content: .materialized(text))
            }
        }
    }

    /// Append a single `\n` to `pending` for `node`, returning the updated leaf.
    ///
    /// Rejoins lines during paragraph continuation, since `LineReader` returns ranges without their line endings. When the current content is a `.lazy` source span, the separator is *deferred* by setting its `joinPending` so the next `addLine` can keep the run zero-copy if it's source-contiguous; otherwise the `\n` is committed into a materialized buffer immediately.
    private mutating func appendNewline(to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            return appendSegment(storage.newlineSegment, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .lazy(let range, joinPending: false)?:
            return PendingLeaf(node: node, content: .lazy(range: range, joinPending: true))
        case .segments(let segs)?:
            // A multi-line paragraph already accumulating as segments: the line join is the shared interned `\n` segment (zero-copy), not a byte appended to a materialized buffer.
            return appendSegment(storage.newlineSegment, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
        case let existing:
            var text = unwrap(existing)
            text.append(UInt8(ascii: "\n"), imaging: -1)
            return PendingLeaf(node: node, content: .materialized(text))
        }
    }

    /// Append one body line of a code/HTML block as a `Segment`, without copying source bytes, returning the updated leaf.
    ///
    /// A source-mapped line (`currentLineMapsToSource`) becomes a zero-copy `inSource` segment; a line that doesn't map to source (e.g. a tab-expanded line whose `span` is a transient per-line buffer) is copied into the additions arena and referenced by an `inSource: false` segment. Empty ranges append nothing (the surrounding `\n` separators carry blank lines), leaving `pending` unchanged.
    private mutating func addLineSegment(span: Span<UInt8>, range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        guard !range.isEmpty else { return pending }
        if currentLineMapsToSource {
            return appendSegment(Segment(offset: Int32(range.lowerBound), length: Int32(range.upperBound - range.lowerBound), inSource: true), to: node, pending: pending)
        }
        // Materialized (tab-expanded) line. `expandPrefixTabs` turned leading whitespace and container markers into spaces so column matching works on byte offsets, but per Tabs a tab in a code or HTML block body stays literal; only a tab split by the consumed indentation becomes spaces. Recover the literal source bytes instead of copying the expanded buffer.
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            // `appendMaterializedCodeContent` maps the content end to the source line end, so every code/HTML body add must run to the buffer's line end (`span.count`). Every caller does: fenced code, the one construct that trims content, never materializes.
            assert(range.upperBound == span.count, "materialized code/HTML body must extend to the line end")
            return appendMaterializedCodeContent(bufferStart: range.lowerBound, to: node, pending: pending)
        }
        // A tab-expanded paragraph continuation. Its surviving content - the first non-space byte to the line end - is byte-identical to source: `expandPrefixTabs` only expands the prefix and copies the tail verbatim, and the content begins at the first non-space byte, so no expanded-tab space reaches it. Map it back to a zero-copy source segment rather than copying the expanded bytes into the arena. Keeping the content in-source also keeps it readable: a multi-segment inline `ContentSpan` resolves source segments plus the interned `\n` directly (see `ContentSpan.multiByte`).
        assert(range.upperBound == span.count, "materialized paragraph continuation must extend to the line end")
        let sourceStart = materializedSourceOffset(range.lowerBound)
        let lineEnd = currentLineSourceRange.upperBound
        return appendSegment(Segment(offset: Int32(sourceStart), length: Int32(lineEnd - sourceStart), inSource: true), to: node, pending: pending)
    }

    /// Append one body line of a materialized (tab-expanded) code/HTML block as its literal source content, preserving content tabs that `expandPrefixTabs` expanded into spaces.
    ///
    /// `bufferStart` is the body's start offset in the per-line materialized buffer (past the consumed indentation). The line's remaining source bytes - tabs and all - become the content, preceded by synthetic spaces for a tab that the consumed indentation split: per Tabs, the split tab's remaining columns become spaces and the tab byte itself is dropped. Callers always add the whole rest of the line, so the content runs to the source line end. The common no-split case stays a zero-copy `inSource` segment; a split tab copies the spaces plus the literal tail into the arena as one segment (the code/HTML segment list is one content segment per line, which the finalize normalizers rely on).
    private mutating func appendMaterializedCodeContent(bufferStart: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        let lineEnd = currentLineSourceRange.upperBound
        let (sourceStart, splitTabSpaces) = materializedSourceStart(bufferStart: bufferStart)

        if splitTabSpaces == 0 {
            return appendSegment(
                Segment(offset: Int32(sourceStart), length: Int32(lineEnd - sourceStart), inSource: true),
                to: node, pending: pending)
        }
        return appendSplitTabCodeContent(spaces: splitTabSpaces, sourceStart: sourceStart, lineEnd: lineEnd, to: node, pending: pending)
    }

    /// Append `spaces` synthetic leading spaces followed by the verbatim source bytes `[sourceStart, lineEnd)`
    /// as a single arena-backed (`inSource: false`) content segment.
    ///
    /// Used for a code/HTML block body line whose consumed indentation split a tab: per Tabs, the tab's
    /// leftover columns become spaces and any later content tab stays literal. The result is one segment,
    /// which the finalize normalizers rely on (one content segment per body line).
    private mutating func appendSplitTabCodeContent(spaces: Int, sourceStart: Int, lineEnd: Int, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        let offset = storage.strings.count
        storage.strings.reserveCapacity(offset + spaces + (lineEnd - sourceStart))
        for _ in 0..<spaces {
            storage.strings.append(UInt8(ascii: " "))
        }
        for i in sourceStart..<lineEnd {
            storage.strings.append(sourceBytes[i])
        }
        return appendSegment(
            Segment(offset: Int32(offset), length: Int32(spaces + (lineEnd - sourceStart)), inSource: false),
            to: node, pending: pending)
    }

    /// Map a materialized-buffer offset back to the original source for a code/HTML body line: the source byte where the literal content begins, plus the count of synthetic spaces that must precede it.
    ///
    /// A non-zero space count arises only when `bufferStart` lands inside an expanded tab - the consumed indentation split that tab, so its remaining columns become spaces and the split tab byte itself is dropped (the source start advances past it). Re-walks the original prefix like `originalPrefixSourceOffset`; reads `sourceBytes` directly so it is independent of `positionsEnabled`.
    private func materializedSourceStart(bufferStart: Int) -> (sourceStart: Int, splitTabSpaces: Int) {
        let lineStart = currentLineSourceRange.lowerBound
        if bufferStart >= materializedTailBufferStart {
            // In the verbatim tail: copied byte-for-byte, so it maps by a constant delta with no split tab.
            return (lineStart + materializedRestStart + (bufferStart - materializedTailBufferStart), 0)
        }
        // In the expanded prefix: re-walk the original prefix, tracking each byte's buffer-column span.
        let prefixEnd = lineStart + materializedRestStart
        var col = 0
        var width = 0
        var i = lineStart
        while i < prefixEnd {
            width = sourceBytes[i] == UInt8(ascii: "\t") ? 4 - (col & 3) : 1
            if bufferStart < col + width {
                break
            }
            col += width
            i += 1
        }
        precondition(i < prefixEnd, "a buffer offset inside the expanded prefix is covered by the prefix walk")
        if bufferStart == col {
            return (i, 0)
        }
        // A tab split by the consumed indentation: emit its remaining columns as spaces, resume after it.
        return (i + 1, (col + width) - bufferStart)
    }

    // MARK: - NUL -> U+FFFD replacement (Insecure characters)

    /// `true` if `chunk`'s bytes contain a NUL (`U+0000`).
    private func containsNUL(_ chunk: Chunk) -> Bool {
        for i in chunk.range where readByte(at: i, in: chunk) == 0 {
            return true
        }
        return false
    }

    /// `true` if any segment's bytes contain a NUL (`U+0000`).
    private func segmentsContainNUL(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        for i in 0..<segs.count where containsNUL(segs[i].chunk) {
            return true
        }
        return false
    }

    /// Replace every NUL (`U+0000`) in `chunk` with U+FFFD (the three bytes `EF BF BD`), per Insecure
    /// characters, under every parse option.
    ///
    /// Returns `chunk` unchanged - so NUL-free content stays a zero-copy slice - when it has no NUL.
    /// Otherwise copies it into the additions arena with each 1-byte NUL expanded to the 3-byte
    /// replacement character, and returns a `Chunk` addressing that arena copy.
    private mutating func replacingNUL(_ chunk: Chunk) -> Chunk {
        guard containsNUL(chunk) else { return chunk }
        let offset = storage.strings.count
        for i in chunk.range {
            let b = readByte(at: i, in: chunk)
            if b == 0 {
                storage.strings.append(0xEF)
                storage.strings.append(0xBF)
                storage.strings.append(0xBD)
            } else {
                storage.strings.append(b)
            }
        }
        return Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
    }

    /// `replacingNUL(_:)` that also updates `map`, `chunk`'s content-relative arena→source run map, to image the replaced content.
    ///
    /// Each of a U+FFFD's three bytes images the one NUL byte it replaces, so an inline node starting or ending at it covers exactly that source byte; every other byte keeps its image. An empty `map` on a source-backed `chunk` means the chunk images itself (see `sourceImage(of:map:)`). With positions off, `map` is left untouched.
    private mutating func replacingNUL(_ chunk: Chunk, map: inout [ArenaRun]) -> Chunk {
        guard positionsEnabled, containsNUL(chunk) else { return replacingNUL(chunk) }
        let image = sourceImage(of: chunk, map: map)
        assert(image.isEmpty || image.reduce(0) { $0 + Int($1.length) } == chunk.length, "a run map must tile its chunk")
        var replacedMap: [ArenaRun] = []
        var i = chunk.offset
        for run in image {
            for local in 0..<Int(run.length) {
                let sourceOffset = run.sourceOffset < 0 ? -1 : Int(run.sourceOffset) + local
                for _ in 0..<(readByte(at: i, in: chunk) == 0 ? 3 : 1) {
                    Self.appendContentByte(imaging: sourceOffset, to: &replacedMap)
                }
                i += 1
            }
        }
        map = replacedMap
        return replacingNUL(chunk)
    }

    /// `chunk`'s content-relative arena→source run map: `map` itself, or, when `map` is empty and `chunk` is source-backed, the single run by which the chunk images its own source range.
    private func sourceImage(of chunk: Chunk, map: [ArenaRun]) -> [ArenaRun] {
        if map.isEmpty, chunk.inSource, chunk.length > 0 {
            return [ArenaRun(length: Int32(chunk.length), sourceOffset: Int32(chunk.offset))]
        }
        return map
    }

    /// The content-relative arena→source run map of `raw` after `TableParser.unescapePipes`, given `map`, `raw`'s own.
    ///
    /// Each stripped backslash's image is dropped, and every other byte keeps its own image. A U+FFFD's three
    /// bytes image one NUL byte.
    func unescapedPipesMap(_ map: [ArenaRun], of raw: Chunk) -> [ArenaRun] {
        assert(map.reduce(0) { $0 + Int($1.length) } == raw.length, "a run map must tile its chunk")
        var unescapedMap: [ArenaRun] = []
        var i = raw.offset
        let end = raw.offset + raw.length
        for run in map {
            for local in 0..<Int(run.length) {
                defer { i += 1 }
                // The same `\|` match as `unescapePipes`: a backslash immediately followed by a pipe.
                if readByte(at: i, in: raw) == UInt8(ascii: "\\"), i + 1 < end, readByte(at: i + 1, in: raw) == UInt8(ascii: "|") {
                    continue
                }
                let sourceOffset = run.sourceOffset < 0 ? -1 : Int(run.sourceOffset) + local
                Self.appendContentByte(imaging: sourceOffset, to: &unescapedMap)
            }
        }
        return unescapedMap
    }

    /// Replace NUL with U+FFFD in a code/HTML block body's segment list, in place.
    ///
    /// A body segment carrying a NUL is re-materialized into the arena via `replacingNUL`; NUL-free
    /// segments and the interned line ending separators stay zero-copy. Safe for code/HTML bodies because
    /// they are read through `StorageView`'s buffer-aware accessors, which resolve an arena segment
    /// correctly - unlike inline multi-segment content, which must flatten instead (see
    /// `flattenSegments`).
    private mutating func replacingNULInSegments(_ segs: inout UniqueArray<Segment>) {
        for i in 0..<segs.count {
            let chunk = segs[i].chunk
            if containsNUL(chunk) {
                segs[i] = Segment(replacingNUL(chunk))
            }
        }
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
    ///
    /// Returns the segments and the leaf with `node`'s content cleared (handed back untouched if `node` isn't the pending leaf).
    private func drainSegments(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafSegments {
        switch consume pending {
        case .none:
            return LeafSegments(segments: UniqueArray(), pending: nil)
        case .some(let leaf):
            precondition(leaf.node == node, "pending content belongs to the one open leaf, which drains when it closes")
            switch consume leaf.content {
            case .segments(let segs):
                return LeafSegments(segments: segs, pending: nil)
            default:
                // Only code/HTML blocks drain here, and they only ever accumulate segments.
                fatalError("drainSegments called on non-segment content")
            }
        }
    }

    /// Materialize the pending content of the open paragraph `node` and return a `Chunk` pointing at it, along with the leaf with `node`'s content cleared.
    ///
    /// A `.lazy` entry resolves to a `Chunk(inSource: true)` addressing the original source - no copy (this covers source-contiguous multi-line paragraphs). A `.materialized` entry is appended to `storage.strings` and a `Chunk(inSource: false)` is returned.
    private mutating func materializePendingContent(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafMaterialization {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        let leaf = pending!
        precondition(leaf.node == node, "the pending leaf is the open paragraph's")
        switch consume leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            return LeafMaterialization(chunk: Chunk(offset: range.lowerBound, length: range.count, inSource: true), pending: nil)
        case .materialized(let content):
            let offset = storage.strings.count
            storage.strings.append(copying: content.bytes.span)
            return LeafMaterialization(chunk: Chunk(offset: offset, length: content.count, inSource: false), pending: nil, map: content.map)
        case .segments(let segs):
            // Flatten a segment list to one arena chunk (used when a `Chunk` is required - e.g. a setext heading's paragraph re-seed, or matcher-eligible content). The common multi-line paragraph path keeps segments zero-copy via the finalize segment branch. Capture the arena→source run map so the re-seed can carry per-line source columns onto the heading's inlines.
            var map: [ArenaRun] = []
            let chunk = flattenSegments(segs, map: &map)
            return LeafMaterialization(chunk: chunk, pending: nil, map: map)
        }
    }

    /// Record whether the open paragraph `node` is "table-pending": its single accumulated line, the
    /// header row, plus the just-arrived delimiter-candidate line `delimSpan[delimRange]` would open a
    /// table (Tables (extension)).
    ///
    /// Materializes the two lines (header + `\n` + delimiter) into a scratch region of the string arena,
    /// runs `classifyTableOpen`, then truncates the scratch back off (`parseTable` re-materializes at
    /// finalize). Reads `pending` through a borrow, so the paragraph's zero-copy accumulated content is
    /// untouched. A header row whose cell count differs from the delimiter row's means the paragraph never
    /// forms a table (`false`); a candidate that isn't a delimiter row leaves the flag unset so a later line
    /// can open a table. `detectPendingTable` handles a header preceded by other paragraph lines.
    private mutating func recordTablePending(_ node: DocumentStorage.Index, delimSpan: Span<UInt8>, delimRange: Range<Int>, pending: borrowing PendingLeaf) {
        let scratchStart = storage.strings.count
        switch pending.content {
        case .lazy(let r, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            for i in r { storage.strings.append(sourceBytes[i]) }
        case .materialized:
            preconditionFailure("a single-line materialized paragraph has already resolved its table fate")
        case .segments:
            preconditionFailure("a single-line table header is a source range")
        }
        storage.strings.append(UInt8(ascii: "\n"))
        for i in delimRange {
            storage.strings.append(delimSpan[i])
        }
        let chunk = Chunk(offset: scratchStart, length: storage.strings.count - scratchStart, inSource: false)
        switch classifyTableOpen(chunk: chunk) {
        case .opens:
            paragraphTablePending[node] = true
        case .headerMismatch:
            paragraphTablePending[node] = false
        case .notDelimiterRow:
            break   // leave unset so a later line can open a table
        }
        // Keeping the scratch would leave dead bytes in the arena for the parse's lifetime.
        storage.strings.removeLast(storage.strings.count - scratchStart)
    }

    /// Shape of an open paragraph's accumulated content, as it bears on table detection when a
    /// delimiter-candidate continuation line arrives.
    private enum PendingTableShape {
        /// A single line (no embedded `\n`): the header row is the whole content.
        case single
        /// Multiple lines held as a zero-copy source range: the header is the last line, and the
        /// earlier lines can split off into a preceding paragraph. `lastNewline` is the source offset of the
        /// `\n` before the header line.
        case multiContiguous(range: Range<Int>, lastNewline: Int)
        /// Multiple lines in a non-contiguous representation: a zero-copy segment list (a nested
        /// block-quote / list continuation, or a CRLF join) or a materialized buffer. The header and the
        /// preceding lines are reconstructed from that representation by `splitNoncontiguousPendingTable`.
        case multiOther
    }

    /// Classify `pending`'s content for table detection without consuming it.
    private func pendingTableShape(_ pending: borrowing PendingLeaf) -> PendingTableShape {
        /// The offset of the last `\n` in the source range, or `nil` if the range is a single line.
        func lastNewline(in r: Range<Int>) -> Int? {
            var i = r.upperBound - 1
            while i >= r.lowerBound {
                if sourceBytes[i] == UInt8(ascii: "\n") { return i }
                i -= 1
            }
            return nil
        }
        switch pending.content {
        case .lazy(let r, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            return lastNewline(in: r).map { .multiContiguous(range: r, lastNewline: $0) } ?? .single
        case .materialized(let text):
            for k in 0..<text.count where text[k] == UInt8(ascii: "\n") {
                return .multiOther
            }
            // A single-line materialized paragraph is a table-header re-seed (`splitMaterializedHeader`), which
            // sets `paragraphTablePending`, so table detection never runs on one.
            preconditionFailure("a single-line materialized paragraph has already resolved its table fate")
        case .segments:
            return .multiOther
        }
    }

    /// Decide whether the just-arrived delimiter-candidate line `delimSpan[delimRange]` opens a table with
    /// the open paragraph's last accumulated line as the header row, and set `paragraphTablePending`
    /// accordingly. A table has a single header row (Tables (extension)), so the header is always the line
    /// immediately before the delimiter row.
    ///
    /// When earlier paragraph lines precede that header, they are split off here into a fresh paragraph
    /// inserted before `node`, and `node`'s pending content is re-seeded to the header line alone so the
    /// finalize-time two-line detection builds the table. This handles both multi-line representations: a
    /// source-contiguous range (`.multiContiguous`) and the non-contiguous forms (`.multiOther` - a
    /// zero-copy segment list from a nested block-quote / list continuation or a CRLF join, or a
    /// materialized buffer). The single-line case (the header is the paragraph) is delegated to
    /// `recordTablePending`.
    ///
    /// After a multi-line split the delimiter row becomes the re-seeded paragraph's second line, so its
    /// `delimIndent` and non-laziness are recorded as the paragraph's second-line metadata (see
    /// `recordSplitDelimiterLine`); the values captured from the paragraph's original second line may be
    /// indented or lazy, which would wrongly veto the finalize-time table check.
    private mutating func detectPendingTable(_ node: DocumentStorage.Index, delimSpan: Span<UInt8>, delimRange: Range<Int>, delimIndent: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        switch pendingTableShape(pending!) {
        case .single:
            recordTablePending(node, delimSpan: delimSpan, delimRange: delimRange, pending: pending!)
            return pending
        case .multiOther:
            // The header is the last accumulated line, held in a non-contiguous representation
            // (segment list or materialized buffer). Classify header + delimiter through a borrow (like
            // `recordTablePending`); only split when a table actually opens.
            switch classifyMultiLineHeader(delimSpan: delimSpan, delimRange: delimRange, pending: pending!) {
            case .notDelimiterRow:
                return pending
            case .headerMismatch:
                paragraphTablePending[node] = false
                return pending
            case .opens:
                recordSplitDelimiterLine(node, delimIndent: delimIndent)
                return splitNoncontiguousPendingTable(node, pending: pending)
            }
        case .multiContiguous(let range, let lastNewline):
            // The header is the last line; everything before its `\n` is the preceding paragraph.
            let headerRange = (lastNewline + 1)..<range.upperBound
            // Classify the header + delimiter exactly as the two-line path does: materialize both into a
            // scratch region, run `classifyTableOpen`, then truncate it back off.
            let scratchStart = storage.strings.count
            for i in headerRange { storage.strings.append(sourceBytes[i]) }
            storage.strings.append(UInt8(ascii: "\n"))
            for i in delimRange { storage.strings.append(delimSpan[i]) }
            let scratch = Chunk(offset: scratchStart, length: storage.strings.count - scratchStart, inSource: false)
            let classification = classifyTableOpen(chunk: scratch)
            storage.strings.removeLast(storage.strings.count - scratchStart)
            switch classification {
            case .notDelimiterRow:
                // Not a delimiter row: leave the flag unset so a later line can open a table.
                return pending
            case .headerMismatch:
                // The header and delimiter rows differ in cell count, so the paragraph never forms a table.
                paragraphTablePending[node] = false
                return pending
            case .opens:
                // Split the earlier lines off into a preceding paragraph, then re-seed `node` to the header
                // line so the two-line finalize detection builds the table from `header` + delimiter (+ body).
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
                recordSplitDelimiterLine(node, delimIndent: delimIndent)
                paragraphTablePending[node] = true
                return PendingLeaf(node: node, content: .lazy(range: headerRange))
            }
        }
    }

    /// Queue a table-preceding paragraph's `content` for inline parsing after replacing NUL with U+FFFD, and
    /// register the arena→source run map its inlines stamp positions through.
    ///
    /// `map` is `content`'s content-relative run map (empty for source-backed content).
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

    /// Insert the paragraph formed from the lines before a table's header row as `node`'s preceding
    /// sibling, and return it.
    private mutating func insertTablePrecedingParagraph(before node: DocumentStorage.Index) -> DocumentStorage.Index {
        let paragraph = storage.appendNode(NodeRecord(kind: .paragraph, parent: storage[node].parent))
        storage.insertChildBefore(paragraph, before: node)
        return paragraph
    }

    /// After a multi-line paragraph is split so the delimiter row becomes the re-seeded paragraph's second
    /// line, record the delimiter row's indent and non-laziness as the paragraph's second-line metadata.
    ///
    /// `paragraphSecondLineIndent` and `paragraphSecondLineLazy` hold the paragraph's original second line,
    /// which may be indented four or more columns or a lazy continuation line, but the finalize-time table
    /// check must see the delimiter row, which `detectPendingTable`'s caller has confirmed is indented
    /// fewer than four columns and not lazy.
    private mutating func recordSplitDelimiterLine(_ node: DocumentStorage.Index, delimIndent: Int) {
        paragraphSecondLineIndent[node] = delimIndent
        paragraphSecondLineLazy[node] = false
    }

    /// Classify whether the open paragraph's last accumulated line (the header) plus the just-arrived
    /// delimiter-candidate line open a table, for a non-contiguous paragraph representation (a zero-copy
    /// segment list, or a materialized buffer with embedded line endings). Reconstructs the header line from the
    /// stored representation into a scratch region of the arena, appends `\n` + the delimiter, runs
    /// `classifyTableOpen`, then truncates the scratch back off - reading `pending` through a borrow so the
    /// paragraph's accumulated content is untouched (mirrors `recordTablePending`).
    private mutating func classifyMultiLineHeader(delimSpan: Span<UInt8>, delimRange: Range<Int>, pending: borrowing PendingLeaf) -> TableOpenClassification {
        let scratchStart = storage.strings.count
        switch pending.content {
        case .segments(let segs):
            // Content segments (one line each) alternate with the shared `newlineSegment`; the
            // header is every segment after the last line-join.
            let nl = storage.newlineSegment
            var lastNewlineIndex = -1
            for i in 0..<segs.count where segs[i] == nl {
                lastNewlineIndex = i
            }
            precondition(lastNewlineIndex >= 0, "a paragraph's segment list holds a line join")
            for i in (lastNewlineIndex + 1)..<segs.count {
                let seg = segs[i]
                for j in 0..<Int(seg.length) {
                    storage.strings.append(segmentByte(seg, j))
                }
            }
        case .materialized(let text):
            // The header is the bytes after the last embedded line ending.
            var lastNewline = -1
            for k in 0..<text.count where text[k] == UInt8(ascii: "\n") {
                lastNewline = k
            }
            precondition(lastNewline >= 0, "a multi-line materialized paragraph holds a line join")
            for k in (lastNewline + 1)..<text.count {
                storage.strings.append(text[k])
            }
        case .lazy:
            preconditionFailure("a single source range is never a non-contiguous multi-line paragraph")
        }
        storage.strings.append(UInt8(ascii: "\n"))
        for i in delimRange {
            storage.strings.append(delimSpan[i])
        }
        let scratch = Chunk(offset: scratchStart, length: storage.strings.count - scratchStart, inSource: false)
        let classification = classifyTableOpen(chunk: scratch)
        storage.strings.removeLast(storage.strings.count - scratchStart)
        return classification
    }

    /// Split a non-contiguous multi-line paragraph at its last line: the earlier lines become a preceding
    /// paragraph inserted before `node`, and `node` is re-seeded to the header line alone with
    /// `paragraphTablePending` set, so the finalize-time two-line detection builds the table from the header
    /// + the delimiter line the caller is about to append. The mirror of `detectPendingTable`'s
    /// `.multiContiguous` split for the segment-list / materialized representations. Called only after
    /// `classifyMultiLineHeader` returns `.opens`.
    private mutating func splitNoncontiguousPendingTable(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        let leaf = pending!
        switch consume leaf.content {
        case .segments(let segs):
            return splitSegmentHeader(node, segments: segs)
        case .materialized(let text):
            return splitMaterializedHeader(node, text: text)
        case .lazy:
            preconditionFailure("a single source range is never a non-contiguous multi-line paragraph")
        }
    }

    /// Split a segment-list paragraph (nested block-quote / list continuation, or a CRLF join) into a
    /// preceding paragraph plus a header-only re-seed. The header is every segment after the last line-join;
    /// the earlier segments become the preceding paragraph, stamped with the source span of those lines.
    private mutating func splitSegmentHeader(_ node: DocumentStorage.Index, segments: consuming UniqueArray<Segment>) -> PendingLeaf? {
        var segs = segments
        let nl = storage.newlineSegment
        var lastNewlineIndex = -1
        for i in 0..<segs.count where segs[i] == nl {
            lastNewlineIndex = i
        }
        precondition(lastNewlineIndex >= 0, "a paragraph's segment list holds a line join")
        var header = UniqueArray<Segment>()
        for i in (lastNewlineIndex + 1)..<segs.count {
            header.append(segs[i])
        }
        segs.removeSubrange(lastNewlineIndex..<segs.count)
        let untrimmedLastLine = segs[segs.count - 1]
        segs = trimSegments(segs)
        let trimmedLastLength = Int(segs[segs.count - 1].length)
        let preceding = segs
        let trailingSeparator = trimmedLastLength < Int(untrimmedLastLine.length)
            ? segmentByte(untrimmedLastLine, trimmedLastLength)
            : nil
        let precedingNode = insertTablePrecedingParagraph(before: node)
        // Stamp the preceding lines' source span, read through a borrow so `preceding` can then be
        // consumed by `intern`.
        if positionsEnabled {
            let span = segmentsSourceSpan(preceding)
            storage.setSourceStart(precedingNode, span.start)
            storage.setSourceEnd(precedingNode, span.end)
        }
        // A NUL (replaced by U+FFFD) in the split-off preceding lines forces a flatten into one normalized
        // arena chunk with the replacement applied: this content bypasses `drainLeaf`, so it is normalized
        // here at its own intern (see `ContentSpan` for why a segment list can't carry the replacement).
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
        paragraphTablePending[node] = true
        return PendingLeaf(node: node, content: .segments(header))
    }

    /// The source byte span of a paragraph's accumulated segment list - the first content line's start to
    /// the last content line's end - read through a borrow so the segments can then be consumed. The first
    /// and last entries of a paragraph segment list are content lines (source segments), so their byte-read
    /// offsets are real source positions.
    private func segmentsSourceSpan(_ segs: borrowing UniqueArray<Segment>) -> (start: Int, end: Int) {
        precondition(segs.count > 0, "a paragraph's split-off lines and header line are never empty")
        let first = segs[0]
        let last = segs[segs.count - 1]
        precondition(first.inSource && last.inSource, "a paragraph's lines start and end on a source byte")
        return (Int(first.offset), Int(last.offset) + Int(last.length))
    }

    /// Split a materialized paragraph (a byte buffer with embedded line endings) into a preceding paragraph
    /// plus a header-only re-seed, each carrying its part of the buffer's run map. A paragraph is materialized
    /// when its definitions are restored while an underline line is examined (`processLine` PHASE 2c) and
    /// its lines were not contiguous in the source.
    private mutating func splitMaterializedHeader(_ node: DocumentStorage.Index, text: consuming MaterializedText) -> PendingLeaf? {
        var lastNewline = -1
        for k in 0..<text.count where text[k] == UInt8(ascii: "\n") {
            lastNewline = k
        }
        precondition(lastNewline >= 0, "a multi-line materialized paragraph holds a line join")
        let precedingStart = storage.strings.count
        for k in 0..<lastNewline {
            storage.strings.append(text[k])
        }
        let precedingLines = Chunk(offset: precedingStart, length: lastNewline, inSource: false)
        // The split-off lines are a paragraph that bypasses finalize, so its raw content is formed here.
        if let precedingChunk = tableSplitParagraphContent(precedingLines.trimmingWhitespace(using: self), in: precedingLines, node: node) {
            let precedingNode = insertTablePrecedingParagraph(before: node)
            let precedingMap = sliceRuns(text.map, from: precedingChunk.offset - precedingStart, length: precedingChunk.length)
            if positionsEnabled {
                let span = sourceSpan(of: precedingChunk.isEmpty ? sliceRuns(text.map, from: 0, length: lastNewline) : precedingMap)
                storage.setSourceStart(precedingNode, span.start)
                storage.setSourceEnd(precedingNode, span.end)
            }
            enqueueTablePrecedingContent(precedingChunk, map: precedingMap, of: precedingNode)
        }
        var header = UniqueArray<UInt8>()
        for k in (lastNewline + 1)..<text.count {
            header.append(text[k])
        }
        let headerMap = sliceRuns(text.map, from: lastNewline + 1, length: text.count - lastNewline - 1)
        if positionsEnabled {
            storage.setSourceStart(node, sourceSpan(of: headerMap).start)
        }
        paragraphTablePending[node] = true
        return PendingLeaf(node: node, content: .materialized(MaterializedText(bytes: header, map: headerMap)))
    }

    /// The source extent imaged by the run map of trimmed paragraph content: from its first run's byte to just past
    /// its last run's.
    private func sourceSpan(of map: [ArenaRun]) -> (start: Int, end: Int) {
        precondition(!map.isEmpty && map.first!.sourceOffset >= 0 && map.last!.sourceOffset >= 0, "trimmed paragraph content starts and ends on source bytes")
        return (Int(map.first!.sourceOffset), Int(map.last!.sourceOffset) + Int(map.last!.length))
    }

    // MARK: - Per-line dispatcher

    /// Process a line of Markdown.
    ///  - source: The line content
    ///  - lineRange: The range of the line in the original source, in order to lazily reference it.
    private mutating func processLine(source: Span<UInt8>, lineRange: Range<Int>, chain: inout UniqueArray<DocumentStorage.Index>, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        // PHASE 1: Walk the open-container chain, stripping each container's continuation prefix. `deepestMatched` is the deepest container whose continuation succeeded (always a container, never a leaf). `cursor` is the byte offset into the line after stripped prefixes.
        let walk = walkOpenContainers(source: source, lineRange: lineRange, chain: &chain)
        let deepestMatched = walk.deepestMatched
        let cursor = walk.cursor
        let prefixColumns = walk.prefixColumns
        let allMatched = walk.allMatched

        currentLineIsLazyContinuation = !allMatched

        let openKind = storage[current].kind

        // PHASE 2a: Code-block / HTML-block continuation - only when the prefix walk reached the leaf. If the walk failed before that, the block must close.
        if openKind.isCodeBlock && allMatched {
            let result = handleCodeBlockContinuation(
                source: source,
                lineRange: lineRange,
                cursor: cursor,
                prefixColumns: prefixColumns,
                pending: pending
            )
            let stillOpen = result.stillOpen
            pending = result.pending
            if stillOpen {
                return pending
            }
            // Fenced or indented code block ended on this line; fall through to dispatch the line content as a fresh block.
        } else if openKind.isCodeBlock && !allMatched {
            // Walk failed before reaching the code block - close it and any stale containers, then dispatch the line normally.
            pending = finalize(node: current, pending: pending)
        } else if openKind == .htmlBlock && allMatched {
            let result = handleHTMLBlockContinuation(
                source: source,
                lineRange: lineRange,
                cursor: cursor,
                pending: pending
            )
            let stillOpen = result.stillOpen
            pending = result.pending
            if stillOpen {
                return pending
            }
            // This line closed the HTML block.
        } else if openKind == .htmlBlock && !allMatched {
            pending = finalize(node: current, pending: pending)
        }

        let scan = leadingScan(source: source, range: cursor..<lineRange.upperBound)
        let firstNonSpace = scan.firstNonSpace
        let isBlank = scan.isBlank
        let indent = scan.indentColumns

        // PHASE 2b: Blank line.
        if isBlank {
            // Capture the deepest open block BEFORE we close any leaves - a blank line closes an open paragraph/heading, but the blank is attributed to that leaf for tight/loose detection.
            let blankLeaf = current
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
            // Mark the leaf as having had a blank line. Then clear on all ancestors so the blank doesn't bubble up.
            storage.nodes[blankLeaf].lastLineBlank = true
            // When the container survived this blank line and has a closed child block, the LAST CHILD also receives the flag so that `endsWithBlankLine` recursion picks it up later. Without this, a fenced/closed block followed by a blank between siblings of the same item wouldn't mark the list loose.
            if let lastChild = storage[blankLeaf].lastChild {
                storage.nodes[lastChild].lastLineBlank = true
            }
            var up = storage[blankLeaf].parent
            while let up_ = up {
                storage.nodes[up_].lastLineBlank = false
                up = storage[up_].parent
            }
            return pending
        }
        // Non-blank line - clear `lastLineBlank` on every ancestor of the current container so a stale blank flag doesn't outlive the continuing block. The blank's leaf flag (set above) is preserved because `current` after a non-blank can't be the blank leaf.
        var clearUp: DocumentStorage.Index? = current
        while let clearUp_ = clearUp {
            storage.nodes[clearUp_].lastLineBlank = false
            clearUp = storage[clearUp_].parent
        }

        var stillOpenKind = storage[current].kind

        // PHASE 2c: Setext heading underline transforms an open paragraph that's a direct descendant of the deepest matched container. Special case: when we're inside a list item AND the line is a dashes-style underline that ALSO matches a thematic break, the thematic break wins (it closes the list rather than turning the item's paragraph into a heading). See spec examples 64, 69, 27, 30.
        //
        // A table-pending paragraph (its first two lines form a header and delimiter row) is a table from its
        // delimiter row on, so a `-` or `=` line can't underline it as a setext heading (`r\n|-\n-` → table +
        // list; `r\n|-\n=` → table with a `=` body row). The line falls through to PHASE 2d.
        if stillOpenKind == .paragraph && allMatched && !(paragraphTablePending[current] ?? false),
           let level = matchSetextUnderline(source: source, range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
            // Strip any leading reference-link definitions from the paragraph's accumulated content first. If they consume the entire paragraph, the setext heading never forms - the underline line falls through to dispatch as plain text (per spec examples 184 / 185).
            let para = current
            let materialized = materializePendingContent(para, pending: pending)
            let raw = materialized.chunk
            // Content-relative arena→source run map for the flattened segments (empty unless the paragraph body is non-contiguous `.segments`, i.e. inside a block quote or list). Captured before `pending` is moved out.
            let flatMap = materialized.map
            pending = materialized.pending
            let trimmedHead = raw.trimmingWhitespace(using: self)
            let stripped = parseDefinitions(in: trimmedHead)
            if self.isBlank(chunk: stripped) {
                // A paragraph of only definitions forms no heading (spec "Setext headings": the
                // underline must follow lines that are a paragraph once definitions are removed), but it
                // is open while this line is examined. A line that cannot interrupt a paragraph -
                // a lone `-`, which would be an empty list item (spec "List items"), or a run of `=` or
                // `-` that is no thematic break - continues it, and becomes the paragraph's text when the
                // definitions are removed at finalize. A thematic break interrupts it.
                let continuesParagraph = !lineStartsNewBlock(
                    source: source,
                    range: cursor..<lineRange.upperBound,
                    firstNonSpace: firstNonSpace,
                    indent: indent,
                    currentKind: .paragraph,
                    interruptsParagraph: true,
                    lineStart: lineRange.lowerBound
                )
                if continuesParagraph {
                    // These leading definitions are registered already; restoring them below lets the
                    // paragraph's finalize, or the split of a table that forms first, remove them again.
                    pending = raw.inSource
                        ? PendingLeaf(node: para, content: .lazy(range: raw.range))
                        : addChunk(raw, map: flatMap, to: para, pending: pending)
                    pending = appendNewline(to: para, pending: pending)
                    pending = addLine(span: source, range: firstNonSpace..<lineRange.upperBound, to: para, pending: pending)
                    return pending
                }
                // Empty after link reference definition extraction - drop the paragraph and let the underline line dispatch as a fresh block. Refresh `stillOpenKind` so PHASE 2d doesn't try to continue the detached paragraph.
                storage.unlinkChild(para)
                guard let parent = storage[para].parent else {
                    fatalError("Invalid internal state - missing parent")
                }
                current = parent
                stillOpenKind = storage[current].kind
            } else {
                // Re-seed pending content with the stripped bytes so the heading's inline-parse pass sees only what's left after link reference definitions are extracted. Keep source-backed content zero-copy as a `.lazy` source range (its offset/length are source offsets when `inSource`), so the heading's inlines are source-mapped and get positions exactly as paragraph / ATX-heading content does; only arena-backed content (non-contiguous or normalized lines) is copied.
                if stripped.inSource {
                    pending = PendingLeaf(node: para, content: .lazy(range: stripped.range))
                } else {
                    // Arena-backed (non-contiguous) content: `addChunk` re-copies the stripped bytes into a fresh buffer. The flattened content's run map is content-relative, so narrow it to the re-seeded bytes and carry it with them, so the heading's text/emphasis keep their source positions.
                    pending = addChunk(stripped, map: sliceRuns(flatMap, from: stripped.offset - raw.offset, length: stripped.length), to: para, pending: pending)
                }
                let headingContent = stripped.trimmingWhitespace(using: self)
                if positionsEnabled, !headingContent.isEmpty,
                   let start = sourceStart(of: headingContent, in: raw, map: flatMap) {
                    storage.setSourceStart(para, start)
                }
                storage[para].kind = .heading(level: Int(level))
                // The heading stays open as `current` with its content pending so the per-line close path
                // finalizes it and stamps its end, as for any other block. No line can continue a heading,
                // so its content ends at the underline.
                return pending
            }
        }

        // PHASE 2d: When a paragraph is open, decide whether this line starts a new block (which closes the paragraph) or is absorbed as lazy/matched continuation. This is the ONLY case where the interrupt decision matters, so the matcher ladder is run only here - every other line goes straight to dispatch, which does its own (single) classification.
        //
        // A table-pending paragraph (its first two lines form a table's header and delimiter rows) is a
        // table from its delimiter row on, so a line that can't be a table row closes the table and its
        // enclosing container. Three kinds of line can't be a row:
        //   - a lazy continuation line, since laziness continues only a paragraph;
        //   - a line holding only a `|`, optionally padded with whitespace, which has no cells (finalize
        //     would otherwise autocomplete it into a one-empty-cell body row);
        //   - a line indented four or more columns, which starts an indented code block: an indented code
        //     block cannot interrupt a paragraph (Indented code blocks), but a table is not a paragraph.
        // These skip the absorb path and fall through to PHASE 3, which closes the paragraph (finalizing it
        // into the table) and the container, then dispatches this line anew.
        let tablePending = paragraphTablePending[current] ?? false
        let breaksOutOfPendingTable = tablePending
            && (currentLineIsLazyContinuation
                || indent >= 4
                || Self.isLonePipeRow(span: source, range: firstNonSpace..<lineRange.upperBound))
        if stillOpenKind == .paragraph && !breaksOutOfPendingTable {
            // The matcher ladder can only return true if the first content byte is one that some block construct starts with; for ordinary prose continuation lines it isn't, so we skip the whole ladder. `mightStartBlock` is a superset of every matcher's trigger byte, so a `false` here is exactly what `lineStartsNewBlock` would have returned.
            // `interruptsParagraph` is true iff the open paragraph's own container matched this line, i.e. `deepestMatched` is the paragraph's parent. When a shallower container matched, a list marker starts a sibling item at the list level rather than interrupting this paragraph.
            // A table-pending paragraph is a table, so the restrictions on interrupting a paragraph (List items, Lists) don't apply: an empty bullet item or an ordered marker with start ≠ 1 closes the table and opens a list (`r\n|-\n-` → table + list). A line that starts no block (e.g. `=`) stays a table body row.
            let interruptsParagraph = !(paragraphTablePending[current] ?? false)
                && storage[current].parent == deepestMatched
            let canInterrupt = Self.mightStartBlock(scan.firstNonSpaceByte)
                && lineStartsNewBlock(
                    source: source,
                    range: cursor..<lineRange.upperBound,
                    firstNonSpace: firstNonSpace,
                    indent: indent,
                    currentKind: stillOpenKind,
                    interruptsParagraph: interruptsParagraph,
                    lineStart: lineRange.lowerBound
                )
            if !canInterrupt {
                // Continue paragraph (matched or lazy). Don't close stale containers - the paragraph absorbs without breaking the chain.
                if storage.options.contains(.tables) {
                    // The first continuation line is the paragraph's second line, its table delimiter-row
                    // candidate. Finalize-time table detection can't see its stripped indentation or its
                    // laziness, so record both (`leadingScan` measured the indent against the container
                    // prefix) for `runParagraphMatchers`.
                    if paragraphSecondLineIndent[current] == nil {
                        paragraphSecondLineIndent[current] = indent
                        paragraphSecondLineLazy[current] = currentLineIsLazyContinuation
                    }
                    // Detect whether this line opens a table with the paragraph's last accumulated line as the
                    // header row. The first delimiter-shaped, non-indented, non-lazy continuation line that
                    // settles the question sets `paragraphTablePending` so it isn't re-evaluated; a candidate
                    // that isn't a delimiter row leaves the flag unset so a later line can open a table.
                    // When earlier lines precede the header, the split happens here. `couldBeDelimiterRow`
                    // keeps ordinary prose paragraphs from materializing.
                    if paragraphTablePending[current] == nil,
                       indent < 4, !currentLineIsLazyContinuation,
                       Self.couldBeDelimiterRow(span: source, range: firstNonSpace..<lineRange.upperBound) {
                        pending = detectPendingTable(current, delimSpan: source, delimRange: firstNonSpace..<lineRange.upperBound, delimIndent: indent, pending: pending)
                    }
                }
                pending = appendNewline(to: current, pending: pending)
                pending = addLine(span: source, range: firstNonSpace..<lineRange.upperBound, to: current, pending: pending)
                return pending
            }
        }

        // PHASE 3: Close stale containers down to deepestMatched.
        while current != deepestMatched {
            pending = finalize(node: current, pending: pending)
        }

        // PHASE 4: New-block dispatch. Containers (block quote) loop back so a single line like `> > foo` opens both quotes and then a paragraph.
        return dispatchNewBlocks(
            source: source,
            lineRange: lineRange,
            startCursor: cursor,
            startColumn: prefixColumns,
            pending: pending
        )
    }

    /// Walk the open-container chain top-down, stripping each container's continuation prefix.
    ///
    /// Returns the deepest container whose prefix matched (always a container, never a leaf), the cursor into the line after stripped prefixes, the absolute column the prefix consumption *intended* to reach, and whether every container in the chain matched.
    ///
    /// `prefixColumns` normally equals the column width of `[lineRange.lowerBound, cursor)`, but exceeds it when a container advance consumed *columns* into a tab it could not drop byte-wise (a list item's content indent landing mid-tab): `cursor` sits at that tab while `prefixColumns` records the column the strip reached. The leaf continuation folds the shortfall into its own strip so the straddling tab is split there, its leftover columns becoming spaces (Tabs).
    private mutating func walkOpenContainers(source: Span<UInt8>, lineRange: Range<Int>, chain: inout UniqueArray<DocumentStorage.Index>) -> (deepestMatched: DocumentStorage.Index, cursor: Int, prefixColumns: Int, allMatched: Bool) {
        var cursor = lineRange.lowerBound
        var deepestMatched = documentIndex
        var prefixColumns = 0

        // Build top-down chain via parent walk + reverse. `chain` is a caller-owned reused buffer (reset here per line) so we don't allocate/zero a fresh array each line.
        chain.removeSubrange(0..<chain.count)
        var idx: DocumentStorage.Index? = current
        while let idx_ = idx {
            chain.append(idx_)
            idx = storage[idx_].parent
        }

        var i = chain.count - 1
        while i >= 0 {
            let node = chain[i]
            i -= 1
            
            let kind = storage[node].kind
            switch kind {
            case .document:
                deepestMatched = node
            case .blockQuote:
                let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
                // `baseColumn: prefixColumns` - an outer quote's marker on this line can leave `cursor`
                // mid-tab (see `blockQuotePrefixEnd`), so this marker's indent is measured from the
                // column already reached, as in `dispatchNewBlocks`.
                if let advanced = matchBlockQuoteMarker(
                    source: source,
                    range: cursor..<lineRange.upperBound,
                    firstNonSpace: firstNonSpace,
                    baseColumn: prefixColumns
                ) {
                    // The block quote marker consumes `>` plus one optional following space column. Per
                    // Tabs, when that column falls on a tab wider than one column the marker consumes only
                    // part of it: leave the tab byte at `cursor` so the leaf strip can split it, and record
                    // the intended column (one past `>`) in `prefixColumns`, as for a list item's content
                    // indent. `handleCodeBlockContinuation` folds the shortfall into `stripFenceIndent`,
                    // surfacing the tab's leftover columns as leading spaces. This arises only on a
                    // source-mapped fenced code body line; every other line has its prefix tabs expanded
                    // to spaces (`expandPrefixTabs`).
                    (cursor, prefixColumns) = blockQuotePrefixEnd(
                        source: source,
                        lineStart: lineRange.lowerBound,
                        markerEnd: firstNonSpace + 1,
                        advanced: advanced
                    )
                    deepestMatched = node
                } else {
                    // No `>` on this line: the block quote's paragraph may continue lazily. The walk stops
                    // here (`allMatched: false`), and `cursor` marks where the last matched prefix ended.
                    // `processLine` turns that into `currentLineIsLazyContinuation`.
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .list:
                // Lists themselves don't have a per-line continuation rule; their items do. The list as a container "matches" trivially as long as we get to one of its items.
                deepestMatched = node
            case .item:
                // Item continuation (List items): the line's indent, measured from the parent container's
                // consumed prefix (`cursor`), is tested against the item's content column first, for an
                // empty item and a non-empty one alike. Only if that fails does a blank line inside a
                // non-empty item keep it open. Because `cursor` advances as each ancestor item consumes its
                // own padding, a nested item is measured against its own content column, not an
                // ancestor's.
                let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
                let isBlank = firstNonSpace == lineRange.upperBound
                let padding = itemPadding(of: node)
                // Compare in columns, not bytes, so a leading tab counts as up to 4 columns of indent.
                // Measured from `prefixColumns`, the column the outer prefixes reached: `cursor` can sit
                // after a marker at any column, or mid-tab after a partially consumed tab, and a tab's
                // width depends on the column it starts at (Tabs).
                let availCols = indentColumns(source: source, from: cursor, to: firstNonSpace, baseColumn: prefixColumns)
                if availCols >= padding {
                    // The indent reaches the item's content column: consume exactly `padding` columns and
                    // match. This precedes the empty-item check, so a whitespace-only line whose expanded
                    // indent covers the content column extends even an empty item onto it (a tab after a
                    // bare `-`: 4 columns >= the content column 2).
                    cursor = advanceColumns(
                        source: source,
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: padding,
                        baseColumn: prefixColumns
                    )
                    // The item intends to consume `padding` columns even when a straddling tab kept
                    // `advanceColumns` from advancing `cursor` past it: record the intended column so the
                    // leaf continuation can split that tab (Tabs).
                    prefixColumns += padding
                    deepestMatched = node
                } else if isBlank, storage[node].firstChild != nil {
                    // A blank line inside an item that already has content keeps the item open even though
                    // the indent falls short of the content column. Advance `cursor` to first-non-space (the
                    // line end for a blank line) so any deeper open item measures its indent from here rather
                    // than the line start. An empty item closes on such a line, since a list item can begin
                    // with at most one blank line (List items).
                    cursor = firstNonSpace
                    prefixColumns = columnWidth(source: source, from: lineRange.lowerBound, to: cursor)
                    deepestMatched = node
                } else {
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .footnoteDefinition:
                // Footnote definition continuation: a line indented four or more columns past the parent's
                // consumed prefix stays in the definition with 4 columns stripped, and a blank line keeps
                // the definition open. Any other line fails the prefix, so the definition's open paragraph
                // may continue lazily (the walk stops here with `allMatched: false`).
                let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
                let isBlank = firstNonSpace == lineRange.upperBound
                // Measured from `prefixColumns`, like the item branch above: `cursor` can sit mid-tab.
                let availCols = indentColumns(source: source, from: cursor, to: firstNonSpace, baseColumn: prefixColumns)
                if availCols >= 4 {
                    cursor = advanceColumns(
                        source: source,
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: 4,
                        baseColumn: prefixColumns
                    )
                    prefixColumns += 4
                    deepestMatched = node
                } else if isBlank {
                    cursor = firstNonSpace
                    prefixColumns = columnWidth(source: source, from: lineRange.lowerBound, to: cursor)
                    deepestMatched = node
                } else {
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .paragraph, .heading, .codeBlock, .htmlBlock, .text, .thematicBreak:
                // Leaves; they don't have container-level prefix matching. The chain effectively ends here. Caller decides leaf-specific continuation (e.g. code-block fence detection).
                return (deepestMatched, cursor, prefixColumns, true)
            default:
                break
            }
        }
        return (deepestMatched, cursor, prefixColumns, true)
    }

    /// Returns `true` if the line's content (starting at `firstNonSpace`) begins a new block that would interrupt an open paragraph.
    ///
    /// `interruptsParagraph` is `true` when the open paragraph's own container matched this line's continuation prefix, so the line interrupts that paragraph, and `false` when only a shallower container matched, so a list marker starts a sibling item in an existing list.
    private func lineStartsNewBlock(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, indent: Int, currentKind: MarkdownNode.Kind, interruptsParagraph: Bool, lineStart: Int) -> Bool {
        if matchThematicBreak(source: source, range: range, firstNonSpace: firstNonSpace) {
            return true
        }
        if matchATXHeading(source: source, range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        if matchOpeningFence(source: source, range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        if matchBlockQuoteMarker(source: source, range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        // HTML blocks of types 1–6 interrupt a paragraph; type 7 does not (HTML blocks). When the paragraph's
        // own container failed to match (`!interruptsParagraph`), the line is not paragraph continuation text,
        // so a type 7 start opens a block at the ancestor that did match: `>o\n<d>` closes the block quote and
        // opens a top-level HTML block, while a top-level `o\n<d>` keeps `<d>` as paragraph text.
        // `dispatchNewBlocks` then opens it against that ancestor.
        if matchHTMLBlockStart(source: source, range: range, firstNonSpace: firstNonSpace, allowType7: !interruptsParagraph) != nil {
            return true
        }
        // A footnote definition opener `[^label]:` interrupts a paragraph, so `[^a]: A\n[^b]: B` opens two
        // definitions rather than folding the second into the first definition's paragraph.
        if storage.options.contains(.footnotes),
           indent < 4,
           matchFootnoteDefinition(source: source, range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        // A list marker interrupts a paragraph only if it starts a non-empty item, and an ordered one only if it starts with 1 (List items, Lists). This applies at every nesting level: `- a\n  2. b` (the item matched, so `2. b` would interrupt the item's paragraph) keeps `2. b` as text, while `1. a\n2. b` (the item did not match, so the marker sits at the list level) opens a sibling item regardless of start.
        if let marker = matchListMarker(source: source, range: range, firstNonSpace: firstNonSpace, lineStart: lineStart, indent: indent) {
            if marker.isEmpty {
                // `- a\n  +` (the item matched, so the marker would interrupt the item's paragraph) keeps `+` as text, and so does a top-level `a\n+`; `> a\n+` (the block quote failed to match, so nothing is interrupted) opens a new top-level list.
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

    /// Continue an open HTML block. Returns `true` if the block remains open after handling this line; `false` if the line closed it (for types 1–5 the line is appended in either case; for types 6 and 7, a blank line closes the block without being appended).
    private mutating func handleHTMLBlockContinuation(source: Span<UInt8>, lineRange: Range<Int>, cursor: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        guard case .htmlBlock(let type, _) = storage[current].data else {
            preconditionFailure("an HTML block node always carries its block type")
        }
        let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound

        if type == 6 || type == 7 {
            // Types 6 and 7 end on a blank line; the blank line is *not* part of the block content.
            if isBlank {
                pending = finalize(node: current, pending: pending)
                return LeafContinuation(stillOpen: false, pending: pending)
            }
            pending = appendNewline(to: current, pending: pending)
            pending = addLine(span: source, range: cursor..<lineRange.upperBound, to: current, pending: pending)
            return LeafContinuation(stillOpen: true, pending: pending)
        }

        // Types 1–5: every line (including blank ones, until the close pattern is seen) is appended verbatim. The line that contains the end pattern is appended *and* closes the block - it's fully consumed, so we return `true` to suppress new-block redispatch on the closing line.
        pending = appendNewline(to: current, pending: pending)
        pending = addLine(span: source, range: cursor..<lineRange.upperBound, to: current, pending: pending)
        if htmlBlockLineMatchesEndCondition(
            type: type,
            source: source,
            range: cursor..<lineRange.upperBound
        ) {
            pending = finalize(node: current, pending: pending)
        }
        return LeafContinuation(stillOpen: true, pending: pending)
    }

    /// Continue an open code block. Returns `stillOpen: true` if the block remains open after handling this line; `false` if the line closed it (or is a closing fence). When this returns `false` the caller should *not* dispatch the line content as a fresh block - the closing fence is fully consumed.
    private mutating func handleCodeBlockContinuation(source: Span<UInt8>, lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound
        let indent = indentColumns(source: source, from: cursor, to: firstNonSpace)

        if case .codeBlock(let info) = storage[current].kind, info.isFenced {
            // Fenced. The closing fence's indent is measured in columns: the absolute column of the first
            // non-space byte minus the column the container prefixes advanced to. A tab counts to its next
            // tab stop (Tabs); a fenced code body line skips leading-tab pre-expansion, so a raw leading tab
            // must not be mistaken for the ≤3-column indent of a closing fence.
            let closingFenceIndent =
                columnWidth(source: source, from: lineRange.lowerBound, to: firstNonSpace) - prefixColumns
            if matchClosingFence(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                indentColumns: closingFenceIndent,
                expectedChar: info.fenceCharacter,
                minimumLength: info.fenceLength
            ) {
                pending = finalize(node: current, pending: pending)
                return LeafContinuation(stillOpen: true, pending: pending)
            }
            // Continuation: strip the code block's content indentation - the container prefixes'
            // intended `prefixColumns` plus the fence's own `fenceOffset` - in columns, tab-stop-aware,
            // then append. `startColumn` is the column physically reached at `cursor`; the bytes before
            // `cursor` already cover `startColumn` of the indent, so `prefixColumns + fenceOffset -
            // startColumn` columns remain to strip here. That shortfall is non-zero when a container
            // advance (e.g. a list item's content indent) consumed columns into a tab it could not drop
            // byte-wise, leaving `cursor` at that tab: folding those columns into this strip splits the
            // tab here - its consumed columns dropped, its leftover columns surfaced as leading spaces
            // with the rest of the line copied verbatim, so any content tab stays literal (Tabs).
            pending = appendNewline(to: current, pending: pending)
            let startColumn = columnWidth(source: source, from: lineRange.lowerBound, to: cursor)
            let (bodyStart, leadingSpaces) = stripFenceIndent(
                source: source,
                range: cursor..<lineRange.upperBound,
                maxColumns: prefixColumns + info.fenceOffset - startColumn,
                startColumn: startColumn
            )
            if leadingSpaces == 0 {
                pending = addLine(span: source, range: bodyStart..<lineRange.upperBound, to: current, pending: pending)
            } else {
                pending = appendSplitTabCodeContent(
                    spaces: leadingSpaces,
                    sourceStart: bodyStart,
                    lineEnd: lineRange.upperBound,
                    to: current,
                    pending: pending
                )
            }
            return LeafContinuation(stillOpen: true, pending: pending)
        }
        // Indented.
        if isBlank {
            // For an open indented code block, a "blank" line that actually contains 5+ columns of whitespace preserves the extra columns as content (per spec example 82 - `      ` between two code lines becomes `  ` in the rendered code block).
            let availCols = indentColumns(source: source, from: cursor, to: lineRange.upperBound)
            pending = appendNewline(to: current, pending: pending)
            if availCols > 4 {
                let bodyStart = advanceColumns(
                    source: source,
                    from: cursor,
                    to: lineRange.upperBound,
                    columns: 4
                )
                pending = addLine(span: source, range: bodyStart..<lineRange.upperBound, to: current, pending: pending)
            }
            return LeafContinuation(stillOpen: true, pending: pending)
        }
        if indent >= 4 {
            let bodyStart = advanceColumns(
                source: source,
                from: cursor,
                to: lineRange.upperBound,
                columns: 4
            )
            pending = appendNewline(to: current, pending: pending)
            pending = addLine(span: source, range: bodyStart..<lineRange.upperBound, to: current, pending: pending)
            return LeafContinuation(stillOpen: true, pending: pending)
        }
        // Non-indented, non-blank line ends the block.
        pending = finalize(node: current, pending: pending)
        return LeafContinuation(stillOpen: false, pending: pending)
    }

    /// Open a list item under `current`. If `current` is already a list of compatible kind/marker, the item is added as another child of that list. Otherwise a new list is opened first.
    ///
    /// On exit, `current` points at the newly-opened item.
    private mutating func openListItem(marker: ListMarkerInfo, firstNonSpace: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        let start = sourceOffset(firstNonSpace)
        let parentList: DocumentStorage.Index
        if case .list(let info) = storage[current].kind,
           Self.marker(marker, continues: info) {
            parentList = current
            // Tight/loose detection runs at list-finalize time via `detectLooseList` + the `endsWithBlankLine` recursion, which catches the "blank between sibling items" case at finalize.
        } else {
            // Either there's no open list, or the marker style differs from the open list. In the latter case, finalize the open list so the new list opens as a sibling - `- foo\n+ bar` becomes two top-level lists, not a nested one (Lists).
            if storage[current].kind.isList {
                pending = finalize(node: current, pending: pending)
            }
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

    /// Open new blocks at `current` based on the line's content from `startCursor`. Loops when a container (block quote, list item) opens so that `> > foo` or `- - foo` correctly opens nested containers plus a paragraph in one pass.
    ///
    /// `startColumn` is the absolute column the surviving container prefixes intended to reach (the walk's
    /// `prefixColumns`), which can exceed `startCursor`'s physical column when a prefix partially consumed a
    /// straddling tab (a block quote `>`'s optional column, or a list item's content-indent advance, landing
    /// mid-tab). The re-dispatch indent is measured from that column (`firstNonSpaceColumn - column`) so the
    /// tab's consumed columns are not recounted from column 0, which would flip the indented-code /
    /// paragraph decision.
    private mutating func dispatchNewBlocks(source: Span<UInt8>, lineRange: Range<Int>, startCursor: Int, startColumn: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        var cursor = startCursor
        var column = startColumn
        // The depth of the block start being matched on this line; `maxListNesting` caps list opening by it.
        var depth = 0
        while true {
            depth += 1
            let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
            let isBlank = firstNonSpace == lineRange.upperBound
            if isBlank {
                return pending
            }
            let indent = columnWidth(source: source, from: lineRange.lowerBound, to: firstNonSpace) - column

            // Block quote opens a container; loop to keep dispatching the rest.
            // `baseColumn: column` - `cursor` can sit mid-tab here (a prior iteration's marker on this
            // same line partially consumed a tab; see the partial-tab branch below), so the matcher must
            // measure the tab's remaining columns from the column already reached, not from an assumed 0.
            if let advanced = matchBlockQuoteMarker(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                baseColumn: column
            ) {
                // A list contains only list items, so an enclosing list closes first - e.g. a `>` line after list items ends the list and starts a top-level block quote.
                if storage[current].kind.isList {
                    pending = finalize(node: current, pending: pending)
                }
                let quoteIdx = addChild(
                    kind: .blockQuote,
                    parent: current,
                    start: sourceOffset(firstNonSpace)
                )
                current = quoteIdx
                // The block quote marker consumes `>` plus one optional following space column. Per Tabs,
                // when that column falls on a tab wider than one column the marker consumes only part of
                // it: leave the tab byte at `cursor` so a leaf opened later on this line (an indented or
                // fenced code block straddling the tab) can split it, and record the intended column (one
                // past `>`) in `column`, as `walkOpenContainers` does for a continuation. This arises only
                // when a raw prefix tab reaches here unexpanded (`expandPrefixTabs` is skipped while
                // continuing an open fenced code block).
                (cursor, column) = blockQuotePrefixEnd(
                    source: source,
                    lineStart: lineRange.lowerBound,
                    markerEnd: firstNonSpace + 1,
                    advanced: advanced
                )
                continue
            }

            // Thematic break (must be before ATX so `---` etc. wins over content matchers, and before list-marker so `- - -` etc. wins over nested lists).
            // A line indented four or more columns is indented code, not a break. A raw prefix tab reaches here unexpanded only on a fenced code body line; see the fenced-code branch below.
            if indent < 4, matchThematicBreak(source: source, range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
                // A list contains only list items, so an enclosing list closes first.
                if storage[current].kind.isList {
                    pending = finalize(node: current, pending: pending)
                }
                let breakIdx = addChild(
                    kind: .thematicBreak,
                    parent: current,
                    start: sourceOffset(firstNonSpace)
                )
                // The thematic break stays open as `current` so the per-line close path finalizes it and
                // stamps its end, as for any other block.
                current = breakIdx
                return pending
            }

            // Footnote definition (after thematic break, before list marker). Opens a block container
            // that absorbs the rest of the line as its first content and continues via indent-≥4 / blank
            // lines (see walkOpenContainers). An indented `[^x]:` is code, not a definition.
            if storage.options.contains(.footnotes),
               indent < 4,
               let fn = matchFootnoteDefinition(
                   source: source,
                   range: cursor..<lineRange.upperBound,
                   firstNonSpace: firstNonSpace
               ) {
                // A list contains only list items, so an enclosing list closes first.
                if storage[current].kind.isList {
                    pending = finalize(node: current, pending: pending)
                }
                let fnIdx = openFootnoteDefinition(label: fn.label, firstNonSpace: firstNonSpace)
                current = fnIdx
                cursor = fn.consumedTo
                column = columnWidth(source: source, from: lineRange.lowerBound, to: cursor)
                continue
            }

            // List marker - opens a list (or extends an existing one) and an item. Both are containers; loop so we keep dispatching the rest of the line as content within the new item.
            // Capped at `maxListNesting` containers per line: past the cap a marker becomes paragraph text.
            // A marker indented four or more columns is indented code, not a list item, even when its byte
            // distance from the cursor is ≤ 3 because a straddling tab widened it (the `-` after
            // `marker\t\t`, six columns in but two bytes over, falls through to the indented-code branch).
            if indent < 4, depth < Self.maxListNesting, let marker = matchListMarker(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                lineStart: lineRange.lowerBound,
                indent: indent
            ) {
                pending = openListItem(marker: marker, firstNonSpace: firstNonSpace, pending: pending)
                cursor = marker.consumedTo
                // The item content begins at `marker.contentStartColumn`, which exceeds the physical
                // column of `cursor` when the optional padding column partially consumed a tab (the tab
                // byte stays at `cursor`); use it so the re-dispatch indent below is measured from the
                // column the marker reached, not the tab's left edge (Tabs).
                column = marker.contentStartColumn
                continue
            }

            // From this point on the line isn't a list item, and a list contains only list items, so any open list at `current` closes before the new block attaches.
            if storage[current].kind.isList {
                pending = finalize(node: current, pending: pending)
            }

            // ATX heading. A line indented four or more columns is indented code, not a heading; see the fenced-code branch below for how a raw prefix tab reaches an opener unexpanded.
            if indent < 4, let heading = matchATXHeading(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                let headingIdx = addChild(
                    kind: .heading(level: Int(heading.level)),
                    parent: current,
                    start: sourceOffset(firstNonSpace)
                )
                current = headingIdx
                if !heading.contentRange.isEmpty {
                    pending = addLine(span: source, range: heading.contentRange, to: headingIdx, pending: pending)
                }
                return finalize(node: headingIdx, pending: pending, atxHeadingEnd: heading.end)
            }

            // Fenced code block. A line indented four or more columns is indented code, not a fence, even
            // when its byte distance from the cursor is <= 3 because a straddling tab widened it. A raw prefix tab reaches here only on a line processed while an open fenced
            // code block is `current` (the one case `expandPrefixTabs` is skipped, per the `inFencedCode`
            // guard); every other line has its prefix tabs expanded to spaces first, so its byte distance
            // already equals its column indent. Example: in `>~~~` then `\t~~~`, the second line closes the
            // quote's fence and its tab-indented `~~~` opens a top-level indented code block whose content
            // is `~~~` rather than a second empty fence.
            if indent < 4, let fence = matchOpeningFence(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                // Decode backslash escapes and HTML entities in the info string so consumers see the canonical language tag (e.g. `foo\+bar` → `foo+bar`, `f&ouml;&ouml;` → `föö`).
                // The info string lives in `expandPrefixTabs`'s verbatim tail (the fence char isn't a prefix byte), so on a tab-materialized line the matcher measured its bounds against the transient buffer. Map them back to source (the tail copies byte-for-byte, so the constant delta preserves the length) before interning, giving the same `inSource: true` chunk a source-mapped line produces; the mapping reads only unconditionally-tracked line state, so it is correct even when `.sourcePosition` is off. A source-mapped line already carries real source offsets.
                let infoChunk: Chunk
                if currentLineMapsToSource {
                    infoChunk = fence.infoChunk
                } else {
                    let start = materializedSourceStart(bufferStart: fence.infoChunk.offset).sourceStart
                    let end = materializedSourceStart(bufferStart: fence.infoChunk.range.upperBound).sourceStart
                    infoChunk = Chunk(offset: start, length: end - start, inSource: true)
                }
                let cleanInfo = EntityParser.unescapeInfoStringChunk(infoChunk, source: sourceBytes, into: &storage)
                let infoRef = storage.intern(replacingNUL(cleanInfo))
                // The fence offset counts source bytes, so a tab straddling the container prefix and the
                // fence counts once even though it spans several columns. On a materialized line the prefix
                // tabs are expanded to spaces, so the buffer distance over-counts that tab; map both
                // endpoints back to source so a fence opened after a partially consumed tab (`>\t```) strips
                // only one column from its continuation lines, not the tab's full width.
                let fenceOffset = currentLineMapsToSource
                    ? fence.fenceOffset
                    : materializedSourceOffset(firstNonSpace) - materializedSourceOffset(cursor)
                let codeIdx = addChild(
                    kind: .codeBlock(MarkdownNode.CodeBlockInfo(
                        isFenced: true,
                        fenceCharacter: fence.character,
                        fenceLength: fence.length,
                        fenceOffset: fenceOffset
                    )),
                    parent: current,
                    data: .codeBlock(info: infoRef, literal: .empty),
                    start: sourceOffset(firstNonSpace)
                )
                current = codeIdx
                return pending
            }

            // HTML block (types 1–7). Leading 0–3 spaces of indent are preserved verbatim in the block's content. Type 7 is detected only when the current container isn't a paragraph, since it can't interrupt one (HTML blocks).
            // A line indented four or more columns is indented code, not an HTML block; see the fenced-code branch above for how a raw prefix tab reaches an opener unexpanded.
            let allowType7 = storage[current].kind != .paragraph
            if indent < 4, let htmlType = matchHTMLBlockStart(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                allowType7: allowType7
            ) {
                let htmlIdx = addChild(
                    kind: .htmlBlock,
                    parent: current,
                    data: .htmlBlock(type: htmlType, literal: .empty),
                    start: sourceOffset(firstNonSpace)
                )
                current = htmlIdx
                // `cursor` can sit mid-tab here (an ancestor container - block quote or list item -
                // partially consumed it with its own optional-column/padding advance; see the
                // block-quote-open and list-marker branches above). Split that tab the same way the
                // indented-code-block opener below does (Tabs): leftover columns become synthetic leading
                // spaces, then the rest of the line copies verbatim. `maxColumns` is 0 in the ordinary
                // (non-straddling) case, so `stripFenceIndent` is a no-op and the zero-copy `addLine` path
                // is taken.
                let priorColumn = columnWidth(source: source, from: lineRange.lowerBound, to: cursor)
                let (bodyStart, leadingSpaces) = stripFenceIndent(
                    source: source,
                    range: cursor..<lineRange.upperBound,
                    maxColumns: column - priorColumn,
                    startColumn: priorColumn
                )
                if leadingSpaces == 0 {
                    pending = addLine(span: source, range: bodyStart..<lineRange.upperBound, to: htmlIdx, pending: pending)
                } else {
                    pending = appendSplitTabCodeContent(spaces: leadingSpaces, sourceStart: bodyStart, lineEnd: lineRange.upperBound, to: htmlIdx, pending: pending)
                }
                // Check whether this same line also satisfies the end condition.
                if htmlBlockLineMatchesEndCondition(
                    type: htmlType,
                    source: source,
                    range: firstNonSpace..<lineRange.upperBound
                ) {
                    pending = finalize(node: htmlIdx, pending: pending)
                }
                return pending
            }

            // Indented code block (only when current container can't continue a paragraph).
            if indent >= 4 && storage[current].kind != .paragraph {
                // The block's source range starts after the four-column code indent, where its content
                // begins; indentation beyond four columns is content (Indented code blocks). Strip the
                // four columns tab-stop-aware from the current `column`: when a straddling tab crosses
                // the boundary its consumed columns are dropped and its leftover columns surface as
                // leading spaces (Tabs), the rest of the line copied verbatim so any content tab stays
                // literal.
                // A leftover only ever arises on a source-mapped line (materialized lines pre-expand
                // their prefix tabs to spaces), where `source` is the shared source buffer and `bodyStart`
                // a real source offset, so the arena split-tab append is well-formed.
                let (bodyStart, leadingSpaces) = stripFenceIndent(
                    source: source,
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
                    start: sourceOffset(bodyStart)
                )
                current = codeIdx
                if leadingSpaces == 0 {
                    return addLine(span: source, range: bodyStart..<lineRange.upperBound, to: codeIdx, pending: pending)
                }
                return appendSplitTabCodeContent(
                    spaces: leadingSpaces,
                    sourceStart: bodyStart,
                    lineEnd: lineRange.upperBound,
                    to: codeIdx,
                    pending: pending
                )
            }

            // Paragraph fallback. By this point the list-close-if-needed step above has already ensured `current` isn't a list.
            let textRange = firstNonSpace..<lineRange.upperBound
            precondition(storage[current].kind != .paragraph, "dispatch starts below the deepest matched container and opens only containers before a leaf, so `current` is never a paragraph here")
            let paragraphIdx = addChild(kind: .paragraph, parent: current, start: sourceOffset(firstNonSpace))
            current = paragraphIdx
            return addLine(span: source, range: textRange, to: paragraphIdx, pending: pending)
        }
    }

    // MARK: - Finalize

    // MARK: Segment-content finalize (segment model)

    /// Drained leaf content: either one contiguous `Chunk` (`.lazy`/`.materialized`) or a multi-line segment list (`.segments`, kept zero-copy).
    ///
    /// Lets paragraph/heading finalize decide whether to keep segments or run the chunk-based matchers without consuming `pending` twice.
    private enum DrainedLeaf: ~Copyable {
        case chunk(Chunk)
        case segments(UniqueArray<Segment>)
    }

    private struct LeafDrainResult: ~Copyable {
        var content: DrainedLeaf
        var pending: PendingLeaf?
        /// A `.chunk` content's content-relative arena→source run map when it is arena content with a source image (NUL-replaced content, or a re-seeded setext heading); empty otherwise.
        var map: [ArenaRun] = []
    }

    /// Drain `node`'s pending content, tagging it as a flat chunk or a segment list (mirrors `materializePendingContent` for the chunk cases; returns `.segments` zero-copy instead of flattening).
    ///
    /// A `.materialized` content's run map is carried through NUL replacement so its inlines keep source positions.
    private mutating func drainLeaf(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafDrainResult {
        switch consume pending {
        case .none:
            return LeafDrainResult(content: .chunk(.empty), pending: nil)
        case .some(let leaf):
            precondition(leaf.node == node, "pending content belongs to the one open leaf, which drains when it closes")
            switch consume leaf.content {
            case .segments(let segs):
                // A NUL anywhere in the body forces a flatten into one normalized arena chunk (U+FFFD
                // substituted): inline multi-segment content can't carry an arena content segment (a
                // non-source segment is only the interned line ending or synthetic filler with no inline syntax,
                // `ContentSpan.multiNextSignificant`), so the segment representation can't hold the replacement. NUL-free bodies stay zero-copy segments.
                if segmentsContainNUL(segs) {
                    var map: [ArenaRun] = []
                    let flat = flattenSegments(segs, map: &map)
                    let replaced = replacingNUL(flat, map: &map)
                    return LeafDrainResult(content: .chunk(replaced), pending: nil, map: map)
                }
                return LeafDrainResult(content: .segments(segs), pending: nil)
            case .lazy(let range, let joinPending):
                precondition(!joinPending, "a deferred line join is always consumed by the next line")
                var map: [ArenaRun] = []
                let replaced = replacingNUL(Chunk(offset: range.lowerBound, length: range.count, inSource: true), map: &map)
                return LeafDrainResult(content: .chunk(replaced), pending: nil, map: map)
            case .materialized(let content):
                let offset = storage.strings.count
                storage.strings.append(copying: content.bytes.span)
                var map = content.map
                let replaced = replacingNUL(Chunk(offset: offset, length: content.count, inSource: false), map: &map)
                return LeafDrainResult(content: .chunk(replaced), pending: nil, map: map)
            }
        }
    }

    /// Read byte `local` of `seg` (source segments from `sourceBytes`; arena/newline segments from `storage.strings`).
    private func segmentByte(_ seg: Segment, _ local: Int) -> UInt8 {
        if seg.inSource {
            return sourceBytes[Int(seg.offset) + local]
        }
        return storage.strings[Int(seg.offset) + local]
    }

    /// Trim trailing whitespace off the last segment (matching `Chunk.trimming(using:)`), in place. Interior segments - the line joins and any hard line break trailing spaces before them - are untouched. A last segment trimmed to zero length is harmless (read as empty).
    ///
    /// The first segment is a paragraph's opening line, which starts at its first non-space byte, so there is no leading whitespace to trim.
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

    /// Cheap, over-approximate gate: could this segment content match a finalize-time matcher (a link reference definition or task list item marker starts with `[`, an attribute reference definition with `^[` when `.attributes` is set, or a GFM table)?
    ///
    /// A false positive only costs an avoidable materialization; a false negative would skip a real matcher, so the checks must cover every matcher's necessary condition. The table necessary condition is on the delimiter (second) line, not the header: a single-column table's header need not contain a pipe (`a\n|-`, `a\n:-`). The segment list is isomorphic to `\n`-separated lines, so the second line is scanned directly.
    private func segmentsCouldMatchMatcher(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        // First content byte == '['  ⇒ possible link reference definition or task list item marker.
        // First content bytes == '^['  ⇒ possible attribute reference definition (`^[label]: attrs`), with `.attributes`.
        // The skip passes every whitespace character, line tabulation and form feed included, because the
        // paragraph's raw content begins at its first non-whitespace byte.
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
        // Table: the delimiter row is the paragraph's second line. It can only be a delimiter row if
        // it holds solely `-`, `:`, `|`, and delimiter-marker whitespace (space, tab, VT, FF) with at
        // least one `-` (a false positive only costs a materialization; `parseTable`/`parseDelimRow`
        // apply the exact rule). Scanning the second line - not the header - is what admits pipe-less-header
        // single-column tables.
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
                        // Line tabulation (0x0B) and form feed (0x0C) are whitespace in a delimiter row;
                        // `parseDelimRow` applies the exact rule.
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

    /// Flatten a segment list into one arena chunk, recording a content-relative arena→source run map in `map` as it copies: one run per non-empty segment. A source segment images its own source range; the interned `\n` line join, the only non-source segment, becomes a synthetic gap (`sourceOffset < 0`). The map tiles the flattened content from its first byte, so it survives a later arena re-copy of the content (the byte layout is unchanged) and lets inline stamping recover per-line source columns.
    ///
    /// Used when content must be a contiguous `Chunk` - the matcher-eligible path and code/HTML-block fallback.
    private mutating func flattenSegments(_ segs: borrowing UniqueArray<Segment>, map: inout [ArenaRun]) -> Chunk {
        var total = 0
        for i in 0..<segs.count { total += Int(segs[i].length) }
        var buf = UniqueArray<UInt8>(minimumCapacity: total)
        let offset = storage.strings.count
        for i in 0..<segs.count {
            let seg = segs[i]
            let len = Int(seg.length)
            let end = Int(seg.offset) + len
            if seg.inSource {
                for j in Int(seg.offset)..<end { buf.append(sourceBytes[j]) }
            } else {
                for j in Int(seg.offset)..<end { buf.append(storage.strings[j]) }
            }
            if len > 0 {
                if seg.inSource {
                    // A source segment images its source range.
                    map.append(ArenaRun(length: Int32(len), sourceOffset: seg.offset))
                } else {
                    // The interned `\n` join: a synthetic gap.
                    map.append(ArenaRun(length: Int32(len), sourceOffset: -1))
                }
            }
        }
        storage.strings.append(copying: buf.span)
        return Chunk(offset: offset, length: total, inSource: false)
    }

    /// Narrow a content-relative arena→source run map to the sub-window `[start, start + length)` of the original flattened content, rebased so its first run begins at content offset 0.
    ///
    /// Drops runs outside the window and advances a partially-included source run's `sourceOffset` by the trimmed-off prefix; synthetic gaps stay gaps. Used when a flattened setext heading's content is re-seeded after leading/trailing whitespace trim and link reference definition stripping, so the stored map matches exactly the bytes that reach inline parsing.
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

    /// The source byte at which `content`, a window of the leaf content `raw` whose arena→source run map is
    /// `map` (empty for source-backed content), begins, or `nil` when it begins on bytes that stand for no
    /// single source byte.
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

    /// Run the paragraph finalize-time matchers on a single flat content `Chunk`: table detection, then the paragraph's raw content (`paragraphContent`) - which it queues for inline parsing, or drops the node if nothing remains.
    ///
    /// Factored out so both the flat-content path and the (eligibility-gated) segment path can reuse it. `map` is the content's arena→source run map (empty for source-backed content): when the content is flattened from a non-contiguous segment list it carries per-line source columns, and when NULs are replaced it images each U+FFFD back to its NUL. It is sliced to the surviving `contentChunk` window and stamped on the node so the inline pass can stamp positions.
    private mutating func runParagraphMatchers(node: DocumentStorage.Index, raw: Chunk, map: [ArenaRun]) {
        let trimmed = raw.trimmingWhitespace(using: self)
        if trimmed.isEmpty {
            // A non-blank line can hold only line tabulations and form feeds, which leave the
            // paragraph no raw content (spec "Paragraphs").
            return
        }
        // Table detection: a header line plus delimiter row turns the node into a `.table` in place.
        // It runs before link reference definition extraction because the paragraph is a table from its
        // delimiter row on, and only a paragraph holds link reference definitions, so `[\n|-\n]:/` is a
        // table. `paragraphTablePending` records whether the table formed during block parsing. A pipe-less
        // run of `-` or `=` is a setext heading underline instead, handled first by PHASE 2c, which extracts
        // the definitions: `[o]:o\n-` is a definition followed by a paragraph, while `[o]:o\n|-` is a
        // table. A delimiter row indented four or more columns or arriving as a lazy continuation line is
        // paragraph text; its indentation and laziness are gone here, so consult
        // `paragraphSecondLineIndent` and `paragraphSecondLineLazy`.
        let tablePending = storage.options.contains(.tables) && (paragraphTablePending[node] ?? false)
        precondition(!tablePending || (paragraphSecondLineIndent[node] != nil && paragraphSecondLineLazy[node] != nil), "a table-pending paragraph recorded its second line's indent and laziness when that line arrived")
        if tablePending && paragraphSecondLineIndent[node]! < 4 && !paragraphSecondLineLazy[node]! {
            // The header is the raw paragraph content, before link reference definitions are extracted.
            let tableContent = raw.trimmingTrailing(using: self)
            // Rows that aren't source-contiguous (a container prefix, leading whitespace, or a CRLF between
            // them) make the paragraph a segment list, so its content reaches here flattened with a run map
            // imaging each row's content on its source line. Content whose NULs were
            // replaced likewise carries a run map imaging each U+FFFD back to its NUL. Narrow that map to the
            // content window the table parser sees. The contiguous fast path passes an empty map (the table
            // parser maps by a constant source delta instead).
            let tableMap = (positionsEnabled && !map.isEmpty)
                ? sliceRuns(map, from: tableContent.offset - raw.offset, length: tableContent.length)
                : []
            parseTable(node: node, chunk: tableContent, sourceMap: tableMap)
            return
        }
        let contentChunk = paragraphContent(of: node, trimmed: trimmed, trailingSeparator: byte(after: trimmed, in: raw))
        if contentChunk.isEmpty {
            // The whole paragraph is link reference definitions, or a task list item marker - drop the empty paragraph node.
            storage.unlinkChild(node)
            return
        }
        if positionsEnabled, let start = sourceStart(of: contentChunk, in: raw, map: map) {
            storage.setSourceStart(node, start)
        }
        // Stamp the run map for the content that reaches inline parsing, narrowed to its window. Source-backed content passes an empty map.
        if positionsEnabled, !map.isEmpty {
            let slice = sliceRuns(map, from: contentChunk.offset - raw.offset, length: contentChunk.length)
            if !slice.isEmpty {
                arenaSourceMaps[node] = slice
            }
        }
        pendingInlines.append((node, storage.intern(contentChunk)))
    }

    /// Close `node`, materialize its accumulated content, and back the parser's `current` pointer up to `node`'s parent.
    private mutating func finalize(node: DocumentStorage.Index, pending: consuming PendingLeaf?, atEOF: Bool = false, atxHeadingEnd: Int? = nil) -> PendingLeaf? {
        var pending = pending
        let kind = storage[node].kind

        if positionsEnabled {
            // A block ends on the current line at EOF, for the document or a fenced code block, or when it opened on this same line (e.g. an ATX heading finalized immediately); otherwise it ends on the previous line, the last line that is part of it.
            let startByte = storage.sourceRanges[node].start
            let startedThisLine = startByte >= Int32(currentLineSourceRange.lowerBound)
            let isFenced: Bool
            if case .codeBlock(let info) = kind { isFenced = info.isFenced } else { isFenced = false }
            let end: Int
            if let atxHeadingEnd {
                // An ATX heading ends at its trimmed content extent, not the raw line. Map the line-offset through `sourceOffset` exactly like the heading start, so tab-expanded lines resolve correctly.
                let mappedEnd = sourceOffset(atxHeadingEnd)
                precondition(mappedEnd != nil, "with positions tracked, every line offset maps to source")
                end = mappedEnd!
                // A block whose end is later attributed to this line - notably the document, whose end is stamped from the final line - ends at the heading's content end, not the raw line end, so shrink the tracked current-line end to match.
                currentLineSourceRange = currentLineSourceRange.lowerBound..<end
            } else {
                end = (atEOF || startedThisLine || kind == .document || isFenced)
                    ? currentLineSourceRange.upperBound
                    : lastLineSourceEnd
            }
            storage.setSourceEnd(node, end)
        }

        switch kind {
        case .paragraph:
            let drained = drainLeaf(node, pending: pending)
            pending = drained.pending
            let map = drained.map
            switch consume drained.content {
            case .chunk(let raw):
                runParagraphMatchers(node: node, raw: raw, map: map)
            case .segments(let segs):
                // Multi-line non-contiguous body held as zero-copy source segments. Trim, then only materialize (flatten) if it could match a finalize matcher; plain prose stays segments.
                let trimmed = trimSegments(segs)
                if segmentsCouldMatchMatcher(trimmed) || segmentsEndInControlWhitespace(trimmed) {
                    // Flatten for the chunk-based matchers, capturing the arena→source run map so a continuation line's inline content is stamped (matchers that survive re-seed the map via `runParagraphMatchers`).
                    var map: [ArenaRun] = []
                    let raw = flattenSegments(trimmed, map: &map)
                    runParagraphMatchers(node: node, raw: raw, map: map)
                } else {
                    pendingInlines.append((node, storage.intern(trimmed)))
                }
            }
        case .heading:
            let drained = drainLeaf(node, pending: pending)
            pending = drained.pending
            let map = drained.map
            switch consume drained.content {
            case .chunk(let raw):
                // An ATX heading's content range already excludes its surrounding spaces and tabs, and holds no line ending.
                let trimmed = atxHeadingEnd == nil ? raw.trimmingWhitespace(using: self) : raw
                if !trimmed.isEmpty {
                    if positionsEnabled, !map.isEmpty {
                        arenaSourceMaps[node] = sliceRuns(map, from: trimmed.offset - raw.offset, length: trimmed.length)
                    }
                    pendingInlines.append((node, storage.intern(trimmed)))
                }
            case .segments:
                preconditionFailure("heading content is never a segment list: a setext heading re-seeds as a range or an arena chunk")
            }
        case .codeBlock(let info):
            // Body lines were accumulated as zero-copy source segments; normalize the segment list (drop the leading separator, strip trailing blank lines for indented code, ensure one trailing `\n`) without copying the bodies into the arena.
            let drained = drainSegments(node, pending: pending)
            var segs = drained.segments
            pending = drained.pending
            normalizeCodeBlockSegments(&segs, isFenced: info.isFenced)
            replacingNULInSegments(&segs)
            let literalRef = storage.intern(segs)
            if case .codeBlock(let info, _) = storage[node].data {
                storage[node].data = .codeBlock(info: info, literal: literalRef)
            }
        case .htmlBlock:
            // Body lines accumulate as zero-copy source segments (same as code blocks). Normalize: ensure a single trailing `\n`.
            let drained = drainSegments(node, pending: pending)
            var segs = drained.segments
            pending = drained.pending
            normalizeHTMLBlockSegments(&segs)
            replacingNULInSegments(&segs)
            let literalRef = storage.intern(segs)
            if case .htmlBlock(let type, _) = storage[node].data {
                storage[node].data = .htmlBlock(type: type, literal: literalRef)
            }
        case .list:
            detectLooseList(node)
        case .footnoteDefinition:
            // A label's winning definition is the first to close, so a definition nested in a
            // same-label definition (`[^b]:[^b]:A`) wins over its encloser: a container closes only
            // after all its children have.
            if case .footnoteDefinition(let labelRef, _) = storage[node].data {
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

    /// Normalize an HTML block's accumulated body segments: ensure a single trailing `\n`.
    private func normalizeHTMLBlockSegments(_ segs: inout UniqueArray<Segment>) {
        let nl = storage.newlineSegment
        precondition(segs.count > 0 && segs[0] != nl, "an HTML block's body starts with its opening line, which is never empty")
        if segs[segs.count - 1] != nl {
            segs.append(nl)
        }
    }

    /// Normalize a code block's accumulated body segments (Indented code blocks, Fenced code blocks) without copying the line bodies.
    ///
    /// Drops the leading separator our accumulator inserts before the first fenced line, strips trailing blank lines for indented code, and ensures the body ends with exactly one `\n` (an empty fenced body stays empty).
    ///
    /// The list alternates body-line content segments with the shared `newlineSegment`. Content segments never contain a `\n` (lines are split on line endings), so `\n` occurs only at separator positions - the list is isomorphic to "lines separated by `\n`".
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
            // An indented code block opens on a line with content, so only a fenced body can be empty.
            precondition(isFenced, "an indented code block's first line holds content, so its body is never empty")
            segs = UniqueArray()
            return
        }

        segs.removeSubrange(hi..<segs.count)
        segs.removeSubrange(0..<lo)
        // Ensure a single trailing line ending. For fenced code, re-add the separator we conceptually moved from the leading strip (so a block ending on a blank line keeps that blank).
        if segs[segs.count - 1] != nl {
            segs.append(nl)
        } else if isFenced && strippedLeading {
            segs.append(nl)
        }
    }

    /// `true` if `segment`'s bytes are entirely ASCII spaces/tabs. Code-block content segments never contain `\n`, so only space/tab are checked.
    private func isAllWhitespace(_ segment: Segment) -> Bool {
        let s = Int(segment.offset)
        let e = s + Int(segment.length)
        if segment.inSource {
            for i in s..<e {
                let b = sourceBytes[i]
                if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") { return false }
            }
        } else {
            for i in s..<e {
                let b = storage.strings[i]
                if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") { return false }
            }
        }
        return true
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

    /// Walk the leading whitespace of `range` once, computing the first-non-space offset, the indent column width (4-column tab stops, per Tabs), the blank-line flag, and the first content byte.
    private func leadingScan(source: Span<UInt8>, range: Range<Int>) -> LeadingScan {
        var i = range.lowerBound
        var col = 0
        while i < range.upperBound {
            let b = source[i]
            if b == UInt8(ascii: " ") {
                col += 1
            } else if b == UInt8(ascii: "\t") {
                col += 4 - (col & 3)
            } else {
                return LeadingScan(firstNonSpace: i, indentColumns: col, isBlank: false, firstNonSpaceByte: b)
            }
            i += 1
        }
        return LeadingScan(firstNonSpace: range.upperBound, indentColumns: col, isBlank: true, firstNonSpaceByte: 0)
    }

    /// Find the first non-space, non-tab byte in `range`. Returns `range.upperBound` if the range is all whitespace.
    private func indexOfFirstNonSpace(source: Span<UInt8>, range: Range<Int>) -> Int {
        var i = range.lowerBound
        while i < range.upperBound {
            let b = source[i]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return i
            }
            i += 1
        }
        return range.upperBound
    }

    /// Count the column-width of the leading whitespace `start..<end` with 4-column tab stops (Tabs): a tab advances the column to the next multiple of 4.
    /// `baseColumn` is the true column of `start` (default 0, i.e. `start` is a line's own left edge).
    /// It must be supplied explicitly when `start` sits mid-tab after an ancestor partially consumed
    /// that tab's leading columns: a tab's expansion depends on the column it starts at, so measuring
    /// from an assumed column 0 would recompute the remaining tab as a fresh 4-column tab instead of
    /// the columns actually left over.
    private func indentColumns(source: Span<UInt8>, from start: Int, to end: Int, baseColumn: Int = 0) -> Int {
        var col = baseColumn
        for i in start..<end {
            let b = source[i]
            if b == UInt8(ascii: " ") {
                col += 1
            } else {
                assert(b == UInt8(ascii: "\t"), "an indent run holds only spaces and tabs")
                col += 4 - (col & 3)
            }
        }
        return col - baseColumn
    }

    /// A line whose leading tabs were expanded into spaces, plus the mapping needed to recover original-source byte offsets for positions on that line (consumed by `sourceOffset`).
    struct MaterializedLine: ~Copyable {
        /// The expanded line: prefix tabs turned into spaces, the rest of the line copied verbatim.
        var buffer: UniqueArray<UInt8>
        /// Original-line byte offset where the verbatim tail begins (the prefix is `[0, restStart)`).
        var restStart: Int
        /// Buffer offset where the verbatim tail begins.
        var tailBufferStart: Int
    }

    /// Pre-expand tabs that appear in the line's "marker prefix" - leading whitespace plus block quote (`>`) and list (`-`, `+`, `*`, digits + `.`/`)`) markers.
    ///
    /// We materialize the line with each prefix tab expanded to the right number of spaces. Tabs in content (after the first non-prefix byte) are preserved.
    ///
    /// Returns nil if the prefix has no tabs (most lines).
    private func expandPrefixTabs(line: Span<UInt8>) -> MaterializedLine? {
        // Scan the prefix region, counting tabs, stopping at the first non-prefix byte.
        //
        // Every prefix byte (space, tab, `>`, `-`, `+`, `*`, digits, `.`, `)`) is ASCII - so a raw byte scan is correct: those bytes never appear inside a multi-byte UTF-8 sequence, and the first non-prefix (including any multi-byte lead) byte stops the scan. We must count *every* prefix tab (not just detect the first) so the materialized buffer can be sized for the worst-case expansion below.
        let bytes = line
        let count = bytes.count
        var prefixTabs = 0
        var k = 0
        
        func isPrefixByte(_ b: UInt8) -> Bool {
            switch b {
            case UInt8(ascii: " "), UInt8(ascii: "\t"),
                UInt8(ascii: ">"),
                UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "*"),
                UInt8(ascii: "."), UInt8(ascii: ")"),
                UInt8(ascii: "0")...UInt8(ascii: "9"):
                return true
            default:
                return false
            }
        }
        
        while k < count {
            let b = bytes[k]
            // Stop at first non-prefix byte.
            if !isPrefixByte(b) {
                break
            }
            if b == UInt8(ascii: "\t") {
                prefixTabs += 1
            }
            k += 1
        }
        guard prefixTabs > 0 else {
            // No need to materialize
            return nil
        }

        // Walk the prefix, expanding tabs to spaces. Stop at the first non-prefix byte and copy the rest verbatim. Each prefix tab expands to between 1 and 4 spaces, so it can add at most 3 bytes; every other byte is copied as-is.
        var output = UniqueArray<UInt8>(minimumCapacity: count + 3 * prefixTabs)
        var col = 0
        // `i` consumes each byte (advancing past it) before classifying. `restStart` marks where the verbatim tail begins; it stays at `count` if the whole line is prefix (nothing left to copy).
        var i = 0
        var restStart = count

        prefix: while i < count {
            let b = bytes[i]
            i += 1
            switch b {
            case UInt8(ascii: " "), UInt8(ascii: ">"), UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "*"):
                output.append(b)
                col += 1
            case UInt8(ascii: "\t"):
                let advance = 4 - (col & 3)
                for _ in 0..<advance {
                    output.append(UInt8(ascii: " "))
                }
                col += advance
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                // A digit run. If it's an ordered-list marker (`.`/`)`), its trailing whitespace is prefix - a tab after it must keep expanding, exactly as after a bullet marker - so emit the marker and continue the loop. Otherwise the digit begins content. `i` is just past the first digit.
                var j = i
                while j < count, bytes[j].isASCIIDigit {
                    j += 1
                }
                if j < count, bytes[j] == UInt8(ascii: ".") || bytes[j] == UInt8(ascii: ")") {
                    // An ordered-list marker: emit the digits and delimiter as-is. Each is one column, so advance `col` by the marker's byte width and resume the prefix scan just past the delimiter - keeping the tab-expansion column in lockstep with the position re-walks (`originalPrefixSourceOffset`, `materializedSourceStart`), which re-derive it byte-by-byte with the same one-column-per-marker-byte rule.
                    output.append(b)
                    for m in i..<(j + 1) {
                        output.append(bytes[m])
                    }
                    col += (j + 1) - (i - 1)
                    i = j + 1
                } else {
                    // Not a marker: the digit begins the content, copy it verbatim with the rest.
                    restStart = i - 1
                    break prefix
                }
            default:
                // A non-prefix byte begins the content; back up so it is copied verbatim.
                restStart = i - 1
                break prefix
            }
        }

        // Copy the (un-expanded) remainder of the line verbatim.
        let tailBufferStart = output.count
        for n in restStart..<count {
            output.append(bytes[n])
        }

        return MaterializedLine(buffer: output, restStart: restStart, tailBufferStart: tailBufferStart)
    }

    /// A superset of the first-content bytes that any block construct can start with.
    ///
    /// Thematic break / list bullet (`-` `_` `*` `+`), ATX (`#`), fence (`` ` `` `~`), block quote (`>`), HTML (`<`), footnote definition (`[`), and ordered-list digits. If a line's first non-space byte isn't one of these, no block matcher can match it, so it can't interrupt an open paragraph.
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
    ///
    /// `baseColumn` is the true column of `start` (default 0), as for `indentColumns`: a tab's width depends on
    /// the column it starts at, including a `start` left mid-tab by an outer container's partial consumption.
    private func advanceColumns(source: Span<UInt8>, from start: Int, to end: Int, columns: Int, baseColumn: Int = 0) -> Int {
        var i = start
        var col = baseColumn
        let target = baseColumn + columns
        while i < end && col < target {
            let b = source[i]
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
        /// The heading's source end, as a line-offset in `matchATXHeading`'s coordinate space (same as `firstNonSpace`), to be mapped through `sourceOffset`. An ATX heading ends at its trimmed content, not the line end: non-empty content ends at the trimmed content; empty content whose closing `#` sequence is stripped ends just past the opening `#`s; otherwise (empty, no closing run) it ends at the raw line end.
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
        var markerOffset: Int     // columns of leading whitespace before marker
        var markerWidth: Int      // bytes of marker (1 for bullet, 2..10 for ordered)
        var contentColumn: Int    // column at which item content begins (after marker + space)
        // Absolute column the item content begins at. Exceeds the physical column of `consumedTo` when the
        // optional padding column partially consumed a tab (the tab byte stays at `consumedTo`).
        var contentStartColumn: Int
        var consumedTo: Int       // source offset of first byte of item content
        var isEmpty: Bool         // marker opens an empty item (only whitespace to the line end)
    }

    /// Read the padding stored on an `.item` node.
    private func itemPadding(of node: DocumentStorage.Index) -> Int {
        guard case .item(let padding) = storage[node].data else {
            preconditionFailure("an item node always carries its padding")
        }
        return padding
    }

    /// Try to match a list marker at `firstNonSpace` within `range` (List items):
    /// - Bullet: one of `-`, `+`, `*` followed by a space, tab, or end of line.
    /// - Ordered: 1-9 ASCII digits, then `.` or `)`, then space/tab/end.
    /// `≤3` leading spaces; markers immediately at end-of-line are valid (empty item).
    ///
    /// `lineStart` is the physical line start; the marker's absolute column (needed for tab-stop math in
    /// the padding run) is `columnWidth(lineStart, firstNonSpace)`.
    ///
    /// `indent` is the marker's leading indent in columns, measured from the column the enclosing prefixes
    /// reached. A byte count would under-measure a tab before the marker, including a tab an enclosing `>`
    /// left partially consumed.
    private func matchListMarker(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, lineStart: Int, indent: Int) -> ListMarkerInfo? {
        let markerOffset = indent
        if markerOffset > 3 {
            return nil
        }
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let first = source[firstNonSpace]

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
            while i < range.upperBound, source[i].isASCIIDigit {
                if digits >= 9 {
                    return nil
                }
                n = n * 10 + Int(source[i] - UInt8(ascii: "0"))
                digits += 1
                i += 1
            }
            if digits == 0 || i >= range.upperBound {
                return nil
            }
            let delim = source[i]
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
        // The marker's absolute column (a tab before the marker widens to its stop); the optional padding
        // run after the marker is measured in columns from here so a tab counts to its next tab stop.
        let markerColumn = columnWidth(source: source, from: lineStart, to: firstNonSpace)
        let contentColumnAfterMarker = markerColumn + markerWidth
        // Marker must be followed by a space, tab, or end of line.
        var contentStart: Int
        var contentColumn: Int
        var contentStartColumn: Int
        var isEmpty = false
        if afterMarker >= range.upperBound {
            // Empty item - the line is just `- ` (or end of input after marker).
            contentStart = afterMarker
            contentColumn = markerOffset + markerWidth + 1
            contentStartColumn = contentColumnAfterMarker + 1
            isEmpty = true
        } else {
            let next = source[afterMarker]
            if next != UInt8(ascii: " ") && next != UInt8(ascii: "\t") {
                return nil
            }
            // Per List items, measure the whitespace run after the marker in columns (tab stops at
            // 1,5,9,…). With 1–4 columns the content column is the first non-blank character's column.
            // With ≥5 columns (or an all-blank line after the marker) only one optional column is
            // consumed and the rest becomes content (an indented code block within the item); when that
            // one column falls on a tab wider than a column it is only partially consumed, so the tab
            // byte stays at the content start and its leftover columns surface later (Tabs).
            var col = contentColumnAfterMarker
            var k = afterMarker
            while k < range.upperBound {
                let b = source[k]
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
            // `k` sits at the first non-whitespace byte or the line end (the run is scanned in full), so
            // an all-blank tail is exactly `k == upperBound`.
            let blankAfter = k >= range.upperBound
            isEmpty = blankAfter
            if blankAfter || runColumns >= 5 {
                // Consume exactly one optional column. If it lands mid-tab (the tab spans more than the one
                // column consumed), leave the tab byte at the content start for the leaf strip to split.
                if next == UInt8(ascii: "\t") && (4 - (contentColumnAfterMarker & 3)) > 1 {
                    contentStart = afterMarker
                } else {
                    contentStart = afterMarker + 1
                }
                contentColumn = markerOffset + markerWidth + 1
                contentStartColumn = contentColumnAfterMarker + 1
            } else {
                // 1–4 columns: the whole run is padding; content begins at the first non-blank byte.
                contentStart = k
                contentColumn = markerOffset + markerWidth + runColumns
                contentStartColumn = contentColumnAfterMarker + runColumns
            }
        }

        return ListMarkerInfo(
            kind: kind,
            bulletMarker: bulletMarker,
            orderedDelimiter: orderedDelimiter,
            start: startNumber,
            markerOffset: markerOffset,
            markerWidth: markerWidth,
            contentColumn: contentColumn,
            contentStartColumn: contentStartColumn,
            consumedTo: contentStart,
            isEmpty: isEmpty
        )
    }

    /// Tag names that trigger an HTML block of type 6 (HTML blocks), sorted alphabetically, as UTF-8 bytes.
    ///
    /// The HTML-block matchers compare these byte by byte for every candidate line, so they're stored as arrays rather than strings, whose UTF-8 view is slower to index in those loops.
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

    /// Tag names that trigger an HTML block of type 1 (their *closing* tag also ends the block), as UTF-8 bytes.
    private static let htmlBlockType1Tags: [[UInt8]] = [
        "pre", "script", "style",
    ].map { Array($0.utf8) }

    /// The end conditions of HTML blocks of types 2 (`-->`), 3 (`?>`) and 5 (`]]>`), as UTF-8 bytes.
    private static let htmlCommentEnd = Array("-->".utf8)
    private static let processingInstructionEnd = Array("?>".utf8)
    private static let cdataEnd = Array("]]>".utf8)

    /// Compare a byte range to a lowercase ASCII string case-insensitively (for tag matching).
    private func bytesEqualASCIICaseInsensitive(span: Span<UInt8>, range: Range<Int>, target: [UInt8]) -> Bool {
        let len = range.upperBound - range.lowerBound
        if len != target.count {
            return false
        }
        for i in 0..<len {
            var a = span[range.lowerBound + i]
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

    /// Try to match the start of an HTML block at `firstNonSpace` and return the type number (1–7), or `nil` if no HTML block starts here. Type 7 is matched only when `allowType7` is set (it cannot interrupt a paragraph).
    ///
    /// The start conditions are those of HTML blocks.
    private func matchHTMLBlockStart(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, allowType7: Bool) -> UInt8? {
        if firstNonSpace - range.lowerBound > 3 {
            return nil
        }
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        if source[firstNonSpace] != UInt8(ascii: "<") {
            return nil
        }
        let after = firstNonSpace + 1
        if after >= range.upperBound {
            return nil
        }
        let next = source[after]

        // Type 2: `<!--`
        if next == UInt8(ascii: "!"),
           after + 2 < range.upperBound,
           source[after + 1] == UInt8(ascii: "-"),
           source[after + 2] == UInt8(ascii: "-") {
            return 2
        }
        // Type 5: `<![CDATA[`. The two brackets are literal; the letters `CDATA` are matched
        // case-sensitively per start condition 5.
        if next == UInt8(ascii: "!"),
           after + 7 < range.upperBound,
           source[after + 1] == UInt8(ascii: "["),
           source[after + 7] == UInt8(ascii: "[") {
            let matched = source[after + 2] == UInt8(ascii: "C")
                && source[after + 3] == UInt8(ascii: "D")
                && source[after + 4] == UInt8(ascii: "A")
                && source[after + 5] == UInt8(ascii: "T")
                && source[after + 6] == UInt8(ascii: "A")
            if matched {
                return 5
            }
        }
        // Type 4: `<!` followed by an uppercase ASCII letter (start condition 4).
        if next == UInt8(ascii: "!"),
           after + 1 < range.upperBound,
           source[after + 1].isUppercaseASCIILetter {
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
        if nameStart >= range.upperBound || !source[nameStart].isASCIILetter {
            return nil
        }
        var nameEnd = nameStart + 1
        while nameEnd < range.upperBound,
              isHTMLTagNameChar(source[nameEnd]) {
            nameEnd += 1
        }
        let nameRange = nameStart..<nameEnd

        // Type 1: pre/script/style, open tag only. A closing tag such as `</pre>` doesn't meet start condition 1, but may start a type 7 block.
        if !isClosing {
            for tag in Self.htmlBlockType1Tags {
                if bytesEqualASCIICaseInsensitive(span: source, range: nameRange, target: tag) {
                    // Must be followed by whitespace (`[ \t\v\f\r\n]`), `>`, or the line end.
                    if nameEnd >= range.upperBound { return 1 }
                    let follow = source[nameEnd]
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
            if bytesEqualASCIICaseInsensitive(span: source, range: nameRange, target: tag) {
                // Must be followed by whitespace (`[ \t\v\f\r\n]`), `>`, `/>`, or the line end.
                if nameEnd >= range.upperBound { return 6 }
                let follow = source[nameEnd]
                if follow.isASCIISpace || follow == UInt8(ascii: ">") {
                    return 6
                }
                if follow == UInt8(ascii: "/"),
                   nameEnd + 1 < range.upperBound,
                   source[nameEnd + 1] == UInt8(ascii: ">") {
                    return 6
                }
                return nil
            }
        }

        // Type 7: any complete open or close tag (with optional attributes for opens) followed only by whitespace until end of line. Type 7 can't interrupt a paragraph - the caller passes `allowType7=false` when the current container is a paragraph.
        if allowType7, let tagEnd = matchType7Tag(span: source, range: range, nameEnd: nameEnd, isClosing: isClosing) {
            if isOnlyWhitespaceToEnd(span: source, from: tagEnd, end: range.upperBound) {
                return 7
            }
        }
        return nil
    }

    /// After parsing a tag name (open or close), validate the rest of the tag per the inline-HTML grammar.
    ///
    /// Returns the byte position just past the closing `>` if valid, otherwise nil. Open tags allow any number of attributes; close tags allow optional whitespace before `>`.
    private func matchType7Tag(span: Span<UInt8>, range: Range<Int>, nameEnd: Int, isClosing: Bool) -> Int? {
        var i = nameEnd
        if isClosing {
            i = skipSpacechars(span: span, from: i, to: range.upperBound)
            if i >= range.upperBound || span[i] != UInt8(ascii: ">") {
                return nil
            }
            return i + 1
        }
        // Open tag: zero or more attributes, optional `/`, then `>`.
        while i < range.upperBound {
            // Attempt to consume one attribute: `spacechar+ name (= value)?`.
            let beforeAttr = i
            i = skipSpacechars(span: span, from: i, to: range.upperBound)
            if i == beforeAttr {
                break
            }
            // Attribute name must start with [a-zA-Z_:].
            if i >= range.upperBound {
                break
            }
            let first = span[i]
            let isFirstChar = first.isASCIILetter
                || first == UInt8(ascii: "_")
                || first == UInt8(ascii: ":")
            if !isFirstChar {
                i = beforeAttr
                break
            }
            i += 1
            while i < range.upperBound {
                let b = span[i]
                let ok = b.isASCIILetter
                    || b.isASCIIDigit
                    || b == UInt8(ascii: ":") || b == UInt8(ascii: ".")
                    || b == UInt8(ascii: "_") || b == UInt8(ascii: "-")
                if !ok { break }
                i += 1
            }
            // Optional value spec.
            let afterName = i
            i = skipSpacechars(span: span, from: i, to: range.upperBound)
            if i < range.upperBound && span[i] == UInt8(ascii: "=") {
                i += 1
                i = skipSpacechars(span: span, from: i, to: range.upperBound)
                if i >= range.upperBound {
                    return nil
                }
                let opener = span[i]
                if opener == UInt8(ascii: "\"") || opener == UInt8(ascii: "'") {
                    i += 1
                    while i < range.upperBound, span[i] != opener {
                        i += 1
                    }
                    if i >= range.upperBound { return nil }
                    i += 1
                } else {
                    // An unquoted attribute value (Raw HTML): a nonempty run without whitespace, `"`, `'`, `=`, `<`, `>`, or `` ` ``.
                    let valueStart = i
                    while i < range.upperBound {
                        let b = span[i]
                        if b.isASCIISpace
                            || b == UInt8(ascii: "\"") || b == UInt8(ascii: "'")
                            || b == UInt8(ascii: "=") || b == UInt8(ascii: "<")
                            || b == UInt8(ascii: ">") || b == UInt8(ascii: "`") {
                            break
                        }
                        i += 1
                    }
                    // An empty unquoted value (`<a b=>`, `<a b= >`) makes no valid tag, so this is not a type-7 HTML block.
                    if i == valueStart {
                        return nil
                    }
                }
            } else {
                i = afterName
            }
        }
        i = skipSpacechars(span: span, from: i, to: range.upperBound)
        if i < range.upperBound && span[i] == UInt8(ascii: "/") {
            i += 1
        }
        if i >= range.upperBound || span[i] != UInt8(ascii: ">") {
            return nil
        }
        return i + 1
    }

    /// Skip a run of whitespace bytes (`[ \t\v\f\r\n]`, i.e. `UInt8.isASCIISpace`), the class the inline HTML scanner also uses, so block and inline HTML agree on what separates tag parts.
    private func skipSpacechars(span: Span<UInt8>, from start: Int, to end: Int) -> Int {
        var i = start
        while i < end {
            if !span[i].isASCIISpace {
                break
            }
            i += 1
        }
        return i
    }

    private func isOnlyWhitespaceToEnd(span: Span<UInt8>, from start: Int, end: Int) -> Bool {
        skipSpacechars(span: span, from: start, to: end) == end
    }

    /// Check whether a line satisfies the end condition for an HTML block of the given type. The check looks for the closing pattern *anywhere* on the line (HTML blocks).
    private func htmlBlockLineMatchesEndCondition(type: UInt8, source: Span<UInt8>, range: Range<Int>) -> Bool {
        switch type {
        case 1:
            // `</pre>`, `</script>`, or `</style>` (case-insensitive).
            for tag in Self.htmlBlockType1Tags {
                if findClosingTag(span: source, range: range, name: tag) {
                    return true
                }
            }
            return false
        case 2:
            return findSubstring(span: source, range: range, needle: Self.htmlCommentEnd)
        case 3:
            return findSubstring(span: source, range: range, needle: Self.processingInstructionEnd)
        case 4:
            return findByte(span: source, range: range, byte: UInt8(ascii: ">"))
        case 5:
            return findSubstring(span: source, range: range, needle: Self.cdataEnd)
        default:
            return false
        }
    }

    /// Search `range` of `span` for any byte equal to `byte`.
    private func findByte(span: Span<UInt8>, range: Range<Int>, byte: UInt8) -> Bool {
        for i in range {
            if span[i] == byte {
                return true
            }
        }
        return false
    }

    /// Search `range` of `span` for the first occurrence of the ASCII bytes in `needle`. Caller must ensure the needle is non-empty.
    private func findSubstring(span: Span<UInt8>, range: Range<Int>, needle: [UInt8]) -> Bool {
        let len = needle.count
        if len == 0 || range.upperBound - range.lowerBound < len {
            return false
        }
        var i = range.lowerBound
        let limit = range.upperBound - len
        while i <= limit {
            var matched = true
            for k in 0..<len {
                if span[i + k] != needle[k] {
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

    /// Search for `</tagname>` (case-insensitive) anywhere within `range`. `name` is one of the lowercase `htmlBlockType1Tags`.
    // why: this scans every byte of every type-1 HTML block line once per tag; left to its own heuristics the optimizer calls it out of line, which costs about 2% of corpus parse instructions.
    @inline(__always)
    private func findClosingTag(span: Span<UInt8>, range: Range<Int>, name: [UInt8]) -> Bool {
        let nameLen = name.count
        // `</` + name + `>` length:
        let totalLen = nameLen + 3
        if range.upperBound - range.lowerBound < totalLen {
            return false
        }
        var i = range.lowerBound
        let limit = range.upperBound - totalLen
        while i <= limit {
            if span[i] == UInt8(ascii: "<"),
               span[i + 1] == UInt8(ascii: "/") {
                let nameRange = (i + 2)..<(i + 2 + nameLen)
                var matched = true
                for k in 0..<nameLen {
                    var a = span[nameRange.lowerBound + k]
                    if a.isUppercaseASCIILetter {
                        a += 32
                    }
                    if a != name[k] {
                        matched = false
                        break
                    }
                }
                if matched, span[i + 2 + nameLen] == UInt8(ascii: ">") {
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

    /// Try to match a block quote marker at `firstNonSpace` (Block quotes): up to 3 columns of indentation, then `>`, then optionally one space or tab. Returns the offset just past the consumed marker, or `nil` if no match.
    ///
    /// `baseColumn` is the true column of `range.lowerBound` (default 0). It must be supplied when
    /// `range.lowerBound` sits mid-tab because an ancestor marker on this line partially consumed that
    /// tab's leading columns; otherwise `indentColumns` below would measure the tab's remaining columns as
    /// if it started fresh at column 0.
    private func matchBlockQuoteMarker(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, baseColumn: Int = 0) -> Int? {
        // The indent is measured in columns. Leading whitespace is byte-identical to its column width unless
        // it contains a tab, which reaches here only on a fenced code body line (every other line has its
        // prefix tabs expanded by `expandPrefixTabs`). A byte count would under-measure a tab and admit a `>`
        // indented four columns (`\t>` inside an open block quote's fenced code is not a continuation
        // marker).
        if indentColumns(source: source, from: range.lowerBound, to: firstNonSpace, baseColumn: baseColumn) > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
        if source[firstNonSpace] != UInt8(ascii: ">") { // >
            return nil
        }
        var i = firstNonSpace + 1
        if i < range.upperBound && (source[i] == UInt8(ascii: " ") || source[i] == UInt8(ascii: "\t")) {
            i += 1
        }
        return i
    }

    /// Where a matched block-quote marker leaves the line: the byte cursor and the absolute column reached,
    /// for the `>` ending at `markerEnd` and `matchBlockQuoteMarker`'s `advanced` result.
    ///
    /// The optional character after `>` is consumed as one column (Tabs). A tab there is fully consumed
    /// only when its tab stop is one column away; a wider tab is partially consumed, so the cursor stays on
    /// the tab byte while the column moves one past `>`. Callers rely on a cursor left on a tab
    /// having a column strictly inside that tab: measuring from a column already at the tab's stop would
    /// recount the whole tab as four fresh columns.
    private func blockQuotePrefixEnd(source: Span<UInt8>, lineStart: Int, markerEnd: Int, advanced: Int) -> (cursor: Int, column: Int) {
        let markerEndColumn = columnWidth(source: source, from: lineStart, to: markerEnd)
        if advanced == markerEnd + 1, source[markerEnd] == UInt8(ascii: "\t"), 4 - (markerEndColumn & 3) > 1 {
            return (markerEnd, markerEndColumn + 1)
        }
        return (advanced, columnWidth(source: source, from: lineStart, to: advanced))
    }

    /// Try to match an opening code fence line (Fenced code blocks).
    private func matchOpeningFence(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> FenceMatch? {
        let fenceOffset = firstNonSpace - range.lowerBound
        if fenceOffset > 3 {
            return nil
        }
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let markerCharacter = source[firstNonSpace]
        guard let marker = MarkdownNode.CodeBlockInfo.FenceCharacter(character: markerCharacter) else {
            return nil
        }
        var i = firstNonSpace
        while i < range.upperBound && source[i] == marker.character {
            i += 1
        }
        let runLength = i - firstNonSpace
        if runLength < 3 {
            return nil
        }
        var infoStart = i
        while infoStart < range.upperBound && source[infoStart].isASCIISpace {
            infoStart += 1
        }
        var infoEnd = range.upperBound
        while infoEnd > infoStart && source[infoEnd - 1].isASCIISpace {
            infoEnd -= 1
        }
        if marker == .backtick {
            for j in infoStart..<infoEnd where source[j] == UInt8(ascii: "`") {
                return nil
            }
        }
        return FenceMatch(
            character: marker,
            length: runLength,
            fenceOffset: fenceOffset,
            infoChunk: Chunk(
                offset: infoStart,
                length: infoEnd - infoStart,
                inSource: true
            )
        )
    }

    /// Try to match a closing code fence line (Fenced code blocks): at most 3 columns of leading
    /// indentation, then a run of the same fence character at least as long as the opening fence, then
    /// only trailing spaces or tabs. A tab advances to the next tab stop, so a tab-led line (4 columns)
    /// fails the test and stays content.
    private func matchClosingFence(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, indentColumns: Int, expectedChar: MarkdownNode.CodeBlockInfo.FenceCharacter?, minimumLength: Int) -> Bool {
        precondition(expectedChar != nil, "a fenced code block always records its fence character")
        let fenceByte = expectedChar!.character
        if indentColumns > 3 {
            return false
        }
        guard firstNonSpace < range.upperBound else {
            return false
        }
        if source[firstNonSpace] != fenceByte {
            return false
        }
        var i = firstNonSpace
        while i < range.upperBound && source[i] == fenceByte {
            i += 1
        }
        let runLength = i - firstNonSpace
        if runLength < minimumLength {
            return false
        }
        while i < range.upperBound {
            let b = source[i]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return false
            }
            i += 1
        }
        return true
    }

    /// Strip up to `maxColumns` columns of leading whitespace from a code or HTML block line, tab-stop-aware.
    /// `startColumn` is the absolute column at `range.lowerBound` (0 for a top-level fence; the consumed
    /// container-prefix width when the fence is nested) so a tab's width is measured from the correct tab
    /// stop.
    ///
    /// Returns the source offset where the surviving content begins and the number of leading spaces a
    /// tab straddling the boundary contributes: per Tabs, such a tab's byte is dropped and its leftover
    /// columns become spaces before the rest of the line. A non-straddling strip returns
    /// `leadingSpaces == 0` and stays a zero-copy slice.
    private func stripFenceIndent(source: Span<UInt8>, range: Range<Int>, maxColumns: Int, startColumn: Int) -> (bodyStart: Int, leadingSpaces: Int) {
        var i = range.lowerBound
        var column = startColumn
        var consumed = 0
        while i < range.upperBound && consumed < maxColumns {
            let b = source[i]
            if b == UInt8(ascii: " ") {
                column += 1
                consumed += 1
                i += 1
            } else if b == UInt8(ascii: "\t") {
                let width = 4 - (column & 3)
                if consumed + width <= maxColumns {
                    // The tab fits entirely within the strip; drop it whole.
                    column += width
                    consumed += width
                    i += 1
                } else {
                    // The tab straddles the boundary: consume its share of columns and surface the
                    // remainder as spaces, dropping the tab byte.
                    return (i + 1, width - (maxColumns - consumed))
                }
            } else {
                break
            }
        }
        return (i, 0)
    }

    /// The absolute column reached after `source[from..<to]`: a tab advances to the next multiple of 4
    /// (Tabs), every other byte counts as one column. Unlike `indentColumns` this does not stop at the
    /// first non-whitespace byte - it measures the full column width of a consumed prefix, container
    /// markers included.
    private func columnWidth(source: Span<UInt8>, from: Int, to: Int) -> Int {
        var column = 0
        for i in from..<to {
            column += source[i] == UInt8(ascii: "\t") ? 4 - (column & 3) : 1
        }
        return column
    }

    /// Try to match a setext heading underline at `firstNonSpace` within `range` (Setext headings).
    private func matchSetextUnderline(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> UInt8? {
        if firstNonSpace - range.lowerBound > 3 {
            return nil
        }
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let marker = source[firstNonSpace]
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
        while i < range.upperBound && source[i] == marker {
            i += 1
        }
        while i < range.upperBound {
            let b = source[i]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return nil
            }
            i += 1
        }
        return level
    }

    /// Try to match a thematic break starting at `firstNonSpace` within `range` (Thematic breaks).
    private func matchThematicBreak(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> Bool {
        if firstNonSpace - range.lowerBound > 3 {
            return false
        }
        precondition(firstNonSpace < range.upperBound, "block-start matchers run only on a non-blank line")
        let marker = source[firstNonSpace]
        if marker != UInt8(ascii: "-") && marker != UInt8(ascii: "_") && marker != UInt8(ascii: "*") {
            return false
        }
        var count = 0
        var i = firstNonSpace
        while i < range.upperBound {
            let b = source[i]
            if b == marker {
                count += 1
            } else if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return false
            }
            i += 1
        }
        return count >= 3
    }

    /// Try to match an ATX heading (ATX headings).
    private func matchATXHeading(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> ATXMatch? {
        if firstNonSpace - range.lowerBound > 3 {
            return nil
        }
        var i = firstNonSpace
        var level: Int = 0
        while i < range.upperBound && source[i] == UInt8(ascii: "#") { // #
            level += 1
            i += 1
        }
        if level < 1 || level > 6 {
            return nil
        }
        if i < range.upperBound {
            let b = source[i]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                return nil
            }
        }
        var contentStart = i
        while contentStart < range.upperBound
            && (source[contentStart] == UInt8(ascii: " ") || source[contentStart] == UInt8(ascii: "\t")) {
            contentStart += 1
        }
        var contentEnd = range.upperBound
        while contentEnd > contentStart
            && (source[contentEnd - 1] == UInt8(ascii: " ") || source[contentEnd - 1] == UInt8(ascii: "\t")) {
            contentEnd -= 1
        }
        let beforeHashes = contentEnd
        while contentEnd > contentStart && source[contentEnd - 1] == UInt8(ascii: "#") {
            contentEnd -= 1
        }
        let removedHashes = beforeHashes - contentEnd
        if removedHashes > 0 {
            if contentEnd > contentStart {
                let preceding = source[contentEnd - 1]
                if preceding == UInt8(ascii: " ") || preceding == UInt8(ascii: "\t") {
                    while contentEnd > contentStart
                        && (source[contentEnd - 1] == UInt8(ascii: " ") || source[contentEnd - 1] == UInt8(ascii: "\t")) {
                        contentEnd -= 1
                    }
                } else {
                    contentEnd = beforeHashes
                }
            }
        }

        // The heading's source range ends at its trimmed content, not the raw line end:
        //   1. non-empty content        → the content end (trailing spaces and the optional closing `#` run already excluded).
        //   2. empty content, closing `#` run removed → the marker end `i` (just past the opening `#`s, before the space skip).
        //   3. empty content, no closing run          → the raw line end.
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

    /// At list finalize, decide whether the list is loose.
    ///
    /// A list is loose (Lists) if any item directly contains two block-level children separated by a blank line - i.e., the item has more than one block child AND a blank line is observed inside it. (The other criterion - a blank line between sibling items - is case (a) below.)
    private mutating func detectLooseList(_ list: DocumentStorage.Index) {
        var loose = false
        var item = storage[list].firstChild
        outer: while let item_ = item {
            let nextItem = storage[item_].next
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

    /// Walks down the rightmost spine of lists/items to a leaf, returning whether that leaf has the `lastLineBlank` flag.
    private func endsWithBlankLine(_ node: DocumentStorage.Index) -> Bool {
        var cur = node
        while true {
            let kind = storage[cur].kind
            let isListOrItem = switch kind {
            case .list, .item: true
            default: false
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

    /// The raw content of the paragraph `node` whose trimmed lines are `trimmed`: what follows its leading link
    /// reference definitions (spec "Link reference definitions"), from its first non-whitespace byte.
    ///
    /// When `node` is a list item's first block and that content begins with a task list item marker - `[ ]`, `[x]`
    /// or `[X]` followed by whitespace (spec "Task list items (extension)") - the item is a task item, and the marker
    /// and the whitespace after it are not part of the content. `trailingSeparator` is the byte after `trimmed` on
    /// its line, which follows a marker that fills the content.
    private mutating func paragraphContent(of node: DocumentStorage.Index, trimmed: Chunk, trailingSeparator: UInt8?) -> Chunk {
        let content = parseDefinitions(in: trimmed).trimmingWhitespace(using: self)
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

    /// Match a footnote definition opener `[^label]:` at `firstNonSpace` on the current line.
    ///
    /// The label is `[^` followed by one or more bytes other than an unescaped `[` or `]`, space, tab,
    /// CR, or LF, then `]:` and optional trailing spaces/tabs.
    /// Returns the label (raw source bytes between `^` and `]`) and the within-line offset just past
    /// the consumed marker (`]:` plus trailing whitespace), where the definition's content begins,
    /// or `nil` if this line is not a footnote-definition opener.
    private func matchFootnoteDefinition(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> (label: Chunk, consumedTo: Int)? {
        let end = range.upperBound
        guard firstNonSpace + 1 < end,
              source[firstNonSpace] == UInt8(ascii: "["),
              source[firstNonSpace + 1] == UInt8(ascii: "^") else {
            return nil
        }
        let labelStart = firstNonSpace + 2
        var i = labelStart
        while i < end {
            let b = source[i]
            if b == UInt8(ascii: "]") {
                break
            }
            // As in a link label (spec "Links"), a square bracket inside the label must be escaped.
            if b == UInt8(ascii: "[") {
                return nil
            }
            if b == UInt8(ascii: "\\"), i + 1 < end, !source[i + 1].isSpaceTabOrNewline {
                i += 2
                continue
            }
            // A NUL is allowed: it stands for U+FFFD (Insecure characters), which it becomes wherever
            // the label is materialized.
            if b == UInt8(ascii: " ") || b == UInt8(ascii: "\t")
                || b == UInt8(ascii: "\r") || b == UInt8(ascii: "\n") {
                return nil
            }
            i += 1
        }
        let labelLen = i - labelStart
        guard labelLen > 0,
              i < end, source[i] == UInt8(ascii: "]"),
              i + 1 < end, source[i + 1] == UInt8(ascii: ":") else {
            return nil
        }
        var contentStart = i + 2
        while contentStart < end {
            let b = source[contentStart]
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                break
            }
            contentStart += 1
        }
        // The label is read back from the original source. On a line whose prefix tabs were expanded, the
        // label (which follows `[^`) lies in the copy's verbatim tail, so it maps back by the tail's constant
        // delta whether or not positions are tracked.
        let labelOffset = currentLineMapsToSource ? labelStart : materializedSourceOffset(labelStart)
        return (
            label: Chunk(offset: labelOffset, length: labelLen, inSource: true),
            consumedTo: contentStart
        )
    }

    /// Open a `.footnoteDefinition` container as a child of `current`. Returns the new definition's
    /// index; `finalize` registers it in `storage.footnoteMap` when it closes.
    private mutating func openFootnoteDefinition(label rawLabel: Chunk, firstNonSpace: Int) -> DocumentStorage.Index {
        // Replace NUL with U+FFFD in the label (Insecure characters) so a `[^<NUL>]` definition shares
        // its key with a `[^<NUL>]` reference, whose paragraph content is NUL-replaced before inline
        // parsing.
        let label = replacingNUL(rawLabel)
        let labelRef = storage.intern(label)
        let fnIdx = addChild(
            kind: .footnoteDefinition,
            parent: current,
            data: .footnoteDefinition(label: labelRef, referenceCount: 0),
            start: sourceOffset(firstNonSpace)
        )
        storage.footnoteDefinitionOrder.append(fnIdx)
        return fnIdx
    }

    // MARK: Reference Parser
    
    // Detects and consumes link reference definitions at the start of a paragraph's materialized content during block finalization.
    //
    // Per Link reference definitions, a definition has the form:
    //
    // ``` [label]: destination optional-title ```
    //
    // With `.attributes`, the extended-attribute reference form `^[label]: attrs` is recognized in the same loop and stored separately on `DocumentStorage.attributeReferenceMap`.
    //
    // Multiple definitions may stack consecutively at the start of a paragraph. After consuming all that match, the remaining (possibly blank) content is returned for the inline parser to handle. If everything is consumed, a block-mode caller is expected to detach the paragraph node from its parent (the inline-only path keeps it).

    /// Repeatedly consume `[label]: dest "title"` definitions, and with `.attributes` `^[label]: attrs` definitions, from the start of `chunk`.
    ///
    /// Each successful match registers the entry in the appropriate reference map on `storage` (the first definition of a label wins, per Link reference definitions) and advances the cursor. Returns the remaining chunk after the last consumed definition.
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

    /// `true` if `chunk` contains only whitespace characters.
    private func isBlank(chunk: Chunk) -> Bool {
        chunk.trimmingWhitespace(using: self).isEmpty
    }

    // MARK: - Link definition

    /// Try to parse exactly one `[label]: dest title?` form.
    ///
    /// Returns the offset just past the consumed bytes (including the trailing line end), or `nil` if no valid definition starts at `start`.
    private mutating func parseOneLinkDefinition(_ chunk: Chunk) -> Int? {
        let end = chunk.range.upperBound
        let inSource = chunk.inSource
        guard let label = matchLinkLabel(chunk) else {
            return nil
        }
        var i = label.afterEnd
        if i >= end || readByte(at: i, in: chunk) != UInt8(ascii: ":") {
            return nil
        }
        i += 1
        i = skipSpacesAndOneLineEnd(from: i, in: chunk)
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
        i = dest.afterEnd
        // Optional title (after spnl). If we find one but the line then doesn't end cleanly, rewind and try a no-title commit instead.
        let beforeTitle = i
        let afterTitleSpnl = skipSpacesAndOneLineEnd(from: i, in: chunk)
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
        // `normalizeLabel` folds a NUL in the label to U+FFFD itself (Insecure characters), so the key
        // matches a reference's even when this definition comes from content not yet NUL-replaced by
        // `drainLeaf` (the setext-underline path, PHASE 2c).
        let key = normalizeLabel(
            chunk: label.interior
        )
        if key.isEmpty {
            return nil
        }
        if storage.referenceMap[key] == nil {
            // A NUL in the destination or title becomes U+FFFD (Insecure characters). Definitions are
            // parsed from paragraph content that may not be NUL-replaced yet, so normalize here, the one
            // point every stored definition passes through.
            let destination = replacingNUL(cleanURLChunk(dest.chunk))
            let title = replacingNUL(unescapeURLChunk(titleChunk))
            storage.referenceMap[key] = ReferenceDefinition(
                destination: destination,
                title: title
            )
        }
        return afterAll
    }

    // MARK: - Attribute definition

    /// Try to parse exactly one `^[label]: attrs` attribute reference definition.
    ///
    /// Returns the offset just past the consumed bytes (including the trailing line end), or `nil` if no valid definition starts at `start`.
    private mutating func parseOneAttributeDefinition(_ chunk: Chunk) -> Int? {
        let start = chunk.offset
        let end = chunk.range.upperBound
        let inSource = chunk.inSource
        precondition(start < end && readByte(at: start, in: chunk) == UInt8(ascii: "^"), "an attribute definition is parsed only from a `^`")
        guard let label = matchLinkLabel(chunk.extracting(1..<chunk.length)) else {
            return nil
        }
        var i = label.afterEnd
        if i >= end || readByte(at: i, in: chunk) != UInt8(ascii: ":") {
            return nil
        }
        i += 1
        i = skipSpacesAndOneLineEnd(from: i, in: chunk)
        let attrsStart = i
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
        let key = normalizeLabel(
            chunk: label.interior
        )
        if key.isEmpty {
            return nil
        }
        if storage.attributeReferenceMap[key] == nil {
            // The attributes are stored trimmed and unescaped like a link destination, with each NUL
            // replaced by U+FFFD (Insecure characters) as for link reference definitions above.
            let attrs = replacingNUL(cleanURLChunk(Chunk(
                offset: attrsStart,
                length: attrsLen,
                inSource: inSource
            )))
            storage.attributeReferenceMap[key] = attrs
        }
        return afterAll
    }

    /// If `chunk` contains backslash escapes (`\<ASCII punct>`) or HTML entity references, append a clean copy to the strings arena and return a chunk pointing at the new region.
    ///
    /// Reads via `readByte(at:in:)`, so it works for both source-backed and arena-backed (`inSource == false`) chunks - used by block-level reference definitions, by inline links whose destination lives in flattened/arena content, and by autolinks.
    ///
    /// Returns `chunk` untouched if no escapes are present.
    ///
    /// With `backslashEscapes: false` only entity references are decoded and backslashes stay literal - the
    /// autolink form: backslash escapes do not work inside autolinks (Autolinks), but entity and numeric
    /// character references do (Entity and numeric character references).
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
        return Chunk(
            offset: outOffset,
            length: storage.strings.count - outOffset,
            inSource: false
        )
    }

    /// Clean a link destination: trim surrounding spaces, tabs and line-ending bytes
    /// (`Chunk.trimming(using:)`; line tabulation and form feed are kept), then remove backslash escapes
    /// and decode entity and numeric character references. Interior whitespace is preserved. Titles are
    /// not trimmed, so the title path calls `unescapeURLChunk` directly.
    mutating func cleanURLChunk(_ chunk: Chunk) -> Chunk {
        let trimmed = chunk.trimming(using: self)
        return unescapeURLChunk(trimmed)
    }
}

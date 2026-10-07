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
    /// `walkOpenContainers` rebuilds the open block-quote/list ancestor chain into this buffer each line;
    /// the buffer grows on demand for deeper nesting, so this is only a starting reservation that avoids
    /// reallocation for typical documents. Block-quote nesting itself is uncapped, matching cmark (which
    /// caps only list/footnote opening, mirrored by `maxListNesting`).
    static let initialOpenContainerCapacity = 256

    /// The number of containers a single line may open before it stops opening lists, matching cmark's
    /// `MAX_LIST_DEPTH` (blocks.c).
    ///
    /// While opening the blocks on one line, once this many containers have been opened a list marker -
    /// bullet or ordered - no longer opens a list and its text falls through to a paragraph. cmark caps
    /// list opening here (block quotes are uncapped) to avoid quadratic blowup on deeply nested lists;
    /// the cap counts the containers opened on the current line, so nesting spread across lines is
    /// unaffected.
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
    /// A `.lazy` span with `joinPending` set holds a deferred separator: a continuation `\n` was requested after the span but not yet committed, so that if the *next* line turns out to be contiguous in source (single-LF terminated, no stripped prefix) the whole multi-line run can stay a single zero-copy source range - the embedded `\n` comes from the source itself rather than a synthesized copy. Only `appendNewline` sets it, and the next `addLine` always clears it, so content that is drained or inspected between lines never has it set.
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

    /// Result of `materializePendingContent`: the materialized `Chunk` plus the (now-drained) leaf. `map` carries a content-relative arena→source run map when the content was flattened from a source-mapped segment list (empty otherwise).
    struct LeafMaterialization : ~Copyable {
        var chunk: Chunk
        var pending: PendingLeaf?
        var map: [ArenaRun] = []
    }

    /// Result of `drainSegments`: the drained segment list plus the (now-cleared) leaf.
    struct LeafSegments : ~Copyable {
        var segments: UniqueArray<Segment>
        var pending: PendingLeaf?
    }

    /// Result of the code/HTML block continuation handlers: whether the block stays open plus the updated leaf.
    struct LeafContinuation : ~Copyable {
        var stillOpen: Bool
        var pending: PendingLeaf?
    }

    /// `true` when the line currently being processed was passed to `processLine` as a slice of `self.source` (i.e. no per-line tab-expansion pre-processing was applied).
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

    /// Original-source byte range of the line currently being processed, tracked for every line (positions on or off). Used to stamp block end positions at finalize time and to recover a materialized code/HTML body line's literal source bytes. `lastLineSourceEnd` keeps the previous line's content end so a block closed by a *later* line can attribute its end to the line it actually ended on.
    var currentLineSourceRange: Range<Int> = 0..<0
    var lastLineSourceEnd: Int = 0

    /// `true` when the line currently being processed is a *lazy* paragraph continuation: at least one open container's continuation prefix failed to match on this line (a block quote with no `>`, or a list item indented less than its content column), so the container-prefix walk stopped short of the open leaf. Set per line in `processLine` from the walk's `allMatched`.
    var currentLineIsLazyContinuation: Bool = false

    /// Inline-parsing tasks deferred until after all block parsing completes.
    ///
    /// This delay is what lets a `[foo]` shortcut reference resolve against a `[foo]: url` ref-def that appears later in the document. Each entry is a `(node, content chunk)` pair: when the parse pass finishes, `BlockParser.parse` drains this list and invokes `InlineParser.parse` on each.
    var pendingInlines: [(DocumentStorage.Index, ContentRef)] = []

    /// Arena→source run maps for flattened inline content that has a source pre-image, keyed by the content's node.
    ///
    /// Registered at finalize for paragraph, heading, table-cell and table-preceding-paragraph content that reaches inline parsing as one arena `Chunk` (flattened from segments, materialized, NUL-replaced or pipe-unescaped), which loses the per-line source mapping the content had. The content-relative run map lets the inline pass stamp the node's inlines with real source positions. Consulted in the inline pass when building an arena single-segment `ContentSpan`.
    var arenaSourceMaps: [DocumentStorage.Index: [ArenaRun]] = [:]

    /// The indent, in columns, of each paragraph's SECOND physical line — its first continuation line —
    /// keyed by the paragraph node and recorded the first time the paragraph is continued.
    ///
    /// A GFM table's delimiter row is the paragraph's second line, and cmark opens a table only when that
    /// line is NOT indented (`try_opening_table_block`'s `!indented` gate: the 4-column indented-code
    /// threshold, measured relative to the container content column). Table detection runs at paragraph
    /// finalize, by which point each continuation line's leading whitespace has already been stripped, so
    /// the delimiter row's indentation is no longer observable there. Capturing it here — where
    /// `leadingScan` already measured it against the container prefix — lets `runParagraphMatchers` reject a
    /// delimiter row indented >= 4 columns, matching cmark across every content representation (contiguous,
    /// materialized, or segment). Only populated when `.tables` is enabled.
    var paragraphSecondLineIndent: [DocumentStorage.Index: Int] = [:]

    /// `true` when a paragraph's SECOND physical line — its first continuation line, i.e. the GFM table
    /// delimiter-row candidate — was a LAZY continuation (an open container's prefix failed to match on
    /// it). Keyed by the paragraph node, recorded once alongside `paragraphSecondLineIndent`.
    ///
    /// cmark opens a table only while processing the delimiter line as a normal (prefix-matched) line.
    /// On a lazy line, `check_open_blocks` backs `last_matched_container` up to the failed container's
    /// parent, so `open_new_blocks` (and thus `try_opening_table_block`) runs against that ancestor, not
    /// the open paragraph; since `try_opening_table_block` converts only a PARAGRAPH parent into a table
    /// (`table.c`), the table never opens and the lazy line is absorbed into the paragraph
    /// (`add_text_to_container`'s lazy branch). So a delimiter row that arrives as a lazy continuation
    /// (e.g. `>o\n--`, or `>o\n>|-` without the `>`) must NOT form a table; finalize-time detection can't
    /// see the laziness, so it is recorded here.
    var paragraphSecondLineLazy: [DocumentStorage.Index: Bool] = [:]

    /// `true` when a paragraph's first two physical lines (header + delimiter row) would open a GFM table,
    /// keyed by the paragraph node and recorded once alongside `paragraphSecondLineIndent`.
    ///
    /// cmark opens a table while processing the delimiter line (`try_opening_table_block`), so by the time a
    /// later LAZY continuation line arrives the open block is a TABLE, not a paragraph: the lazy-paragraph
    /// branch in `add_text_to_container` cannot fire, and the table and its enclosing container close so the
    /// line starts a fresh block at the container's ancestor. The rewrite detects tables at finalize, so
    /// without this flag it would absorb the lazy line into the block-quote paragraph and turn it into a
    /// body row. `processLine` consults this flag to break a table-pending paragraph's FIRST lazy
    /// continuation (and everything after it) out of the table + container. Only populated when `.tables` is
    /// enabled and the delimiter row was a non-indented, non-lazy continuation (the only kind that opens a
    /// table).
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
            
            // The document root is never passed to `finalize`; stamp its whole-source span here, from the first line's start (after any leading BOM, so it projects to 1:1) to the last line's content end. A truly-empty document (no lines) is left unstamped so it reports no source range - cmark emits `1:1-0:0` for empty input, which downstream treats as "no position".
            if positionsEnabled, reader.lineNumber > 0 {
                storage.setSourceStart(documentIndex, storage.lineStarts[0])
                storage.setSourceEnd(documentIndex, currentLineSourceRange.upperBound)
            } else if positionsEnabled, reader.nextStart > 0 {
                // A BOM alone is still one empty line for cmark (`S_process_line` skips the BOM within it), so the document spans that empty line after the BOM.
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
                    // Arena content with a source image carries an arena→source run map so its inlines still get source positions; arena content without one (positions off) parses unmapped.
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

        // Footnote post-processing (mirrors cmark's `process_footnotes`, run after inline parsing):
        // drop definitions that were never referenced and move the referenced ones to the end of the
        // document in first-reference (index) order.
        processFootnotes()

        storage.lineCount = reader.lineNumber
        return storage
    }

    /// Replicate cmark's `process_footnotes` over the finalized tree: number the footnote references
    /// in document order, drop definitions that no reference resolves to, and move the referenced ones
    /// to the end of the document root in index order. Definitions can be nested anywhere (a block
    /// quote, a list item); cmark extracts them all to the document root, leaving any emptied container
    /// behind.
    ///
    /// Numbering is decided here from the references that survive in the finalized tree, not when they
    /// were emitted during inline parsing.
    private mutating func processFootnotes() {
        guard storage.options.contains(.footnotes) else { return }
        // No definitions means no reference can have been emitted (a reference resolves only against a
        // registered definition), so there is nothing to number, keep, or drop.
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
    /// definition its reference count, mirroring cmark's `process_footnotes` reference walk (blocks.c).
    /// Returns the referenced definitions in index order (the order of their first reference).
    ///
    /// A definition's index is fixed by its first reference in document pre-order; later references to
    /// the same definition reuse it. Every reference label resolves through `footnoteMap` exactly as it
    /// did at emit time. The walk covers every container, including footnote definitions (whose own
    /// content can reference other footnotes), matching cmark's whole-tree iteration. It keeps an
    /// explicit stack of pending nodes rather than recursing, so arbitrarily deep trees (e.g. thousands
    /// of nested block quotes) do not overflow the call stack.
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
    /// Bypasses block structure completely: any non-empty input (even a BOM-only one) becomes a single `.paragraph`, and empty input yields no paragraph. The paragraph's content is the source with a leading UTF-8 BOM skipped and line endings normalized to `\n`, but with every other byte preserved verbatim - leading indentation, interior space runs, trailing spaces, and all newlines (including a trailing one). Markers like `#`, `* `, `> `, fences and 4-space indents stay literal text; only *inline* syntax (emphasis, code spans, links, autolinks, …) is parsed, and even newlines remain literal text rather than becoming soft/hard breaks.
    private mutating func parseInlineOnly() {
        let count = sourceBytes.count

        // Empty input yields an empty document with no paragraph: cmark's `S_parser_feed` (src/blocks.c) processes no line for zero bytes, so no paragraph is ever opened.
        guard count > 0 else {
            return
        }

        // Skip a leading UTF-8 BOM, matching cmark's first-line BOM skip.
        var start = 0
        if count >= 3, sourceBytes[0] == 0xEF, sourceBytes[1] == 0xBB, sourceBytes[2] == 0xBF {
            start = 3
        }

        // Count lines and detect whether any CR needs normalizing to LF, in a single pass that SIMD-skips the runs of content bytes between line breaks (`nextLineBreak`) rather than stepping one byte at a time. The count mirrors cmark's per-line `line_number` (`\r\n`, lone `\r`, and `\n` each count once; a final unterminated line counts as a line). Detecting CR in the same scan is what lets the common LF-only / break-free case stay zero-copy below, addressing the source directly - so line-counting costs no extra pass.
        var hasCR = false
        var lines = 0
        // Where the last line's content ends: its terminator's first byte, or the end of input for an unterminated last line.
        var contentEnd = count
        var i = start
        // A BOM-only input is still one (empty) line: cmark's `S_process_line` skips the BOM within that line, then opens the paragraph for what remains.
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

        // Link reference definitions leading the content are still consumed, and the paragraph is kept even when
        // nothing (or only whitespace) remains: cmark's paragraph `finalize` (src/blocks.c) runs
        // `resolve_reference_link_definitions` in every mode but gates the empty-paragraph removal off for
        // `CMARK_OPT_PRESERVE_WHITESPACE` - whose `options & …` mask also matches a bare `CMARK_OPT_INLINE_ONLY`.
        let paragraph = addChild(kind: .paragraph, parent: documentIndex, start: start)
        // The paragraph's content is the whole post-BOM input, trailing line ending included (it is literal text here), and the document spans exactly its one paragraph. Both end where the last line's content ends, as in block mode, so a final line ending doesn't carry the range past the last line.
        storage.setSourceStart(documentIndex, start)
        storage.setSourceEnd(documentIndex, contentEnd)
        storage.setSourceEnd(paragraph, contentEnd)

        var delimiters = UniqueArray<DelimiterRecord>()
        var brackets = UniqueArray<BracketRecord>()
        // A NUL forces the arena-copy path below (CommonMark §2.3: NUL -> U+FFFD); scanned here so a
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

    /// Post-process a leaf's freshly parsed inline children, mirroring cmark's `cmark_parser_finish` (consolidate, then extension postprocess).
    ///
    /// Consolidation runs unconditionally, in every parse mode including inline-only (swift-cmark `src/blocks.c` `cmark_parser_finish` calls `cmark_consolidate_text_nodes` with no option gate), so failed delimiters, entities and escapes merge with their neighbouring text.
    ///
    /// `image` maps the leaf's content back to source when it is one arena chunk with a source image.
    private mutating func finishInlines(_ leaf: DocumentStorage.Index, image: ContentImage?) {
        consolidateTextNodes(leaf)
        // GFM email autolinks are detected over the consolidated inline tree, matching cmark's autolink
        // `postprocess` (which runs after emphasis + `cmark_consolidate_text_nodes`).
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
    /// When the line maps to source the passed offset is already a global source offset (the line was processed as a slice of `sourceBytes`). For a tab-expanded (materialized) line, the offset is a transient-buffer offset: `expandPrefixTabs` only rewrites the leading whitespace/marker prefix and copies the rest of the line verbatim, so a tail offset maps back by a constant delta and a prefix offset is recovered by re-walking the original line's prefix (see `originalPrefixSourceOffset`). Returns `nil` for a materialized line when positions are off, since its callers only stamp positions; content that must be read back from source uses `materializedSourceOffset`, which doesn't depend on `.sourcePosition`.
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
    /// Re-walks the original line's prefix (`[lineStart, lineStart + materializedRestStart)`) with the same tab-expansion rule `expandPrefixTabs` used, tracking each byte's span in the expanded buffer, and returns the source offset of the byte whose expansion covers `bufferOffset`. A tab covers its whole `4 - (col & 3)` run, so a buffer offset landing mid-tab resolves to that tab's byte - matching cmark, which reports the raw source byte after consumed indentation. O(prefix).
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
        
        fatalError("pending content for node \(leaf.node) was not drained before node \(node) began accumulating")
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
    /// Used when re-seeding a node's content after a transformation step (e.g. setext-heading content trimmed of leading ref-defs).
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
            // Tab-expanded line: map the first-line content back to its literal source range rather than copying the expanded buffer into the arena, so inline stamping recovers real source positions and any content tab stays literal. `expandPrefixTabs` rewrites only the consumed indentation and copies the rest verbatim, so the first non-space content byte maps to a genuine source byte (a marker byte or a tail byte, never inside an expanded tab's spaces) and the content end maps to the source line end. cmark expands tabs only for block-structure indentation and keeps them literal in inline content, so the source range - which carries any interior tab as one byte (one column) - is what matches the reference. This covers both content that maps 1:1 (e.g. the `*` of `*5*` after `*\t`/`>\t`) and content straddling an expanded tab (e.g. `**\tx`, whose doubled marker bytes are inline content that no block marker consumes, so the tab lands inside the paragraph). The mapping reads only unconditionally tracked line state, so the content is the same whether or not `.sourcePosition` is set.
            return PendingLeaf(node: node, content: .lazy(range: materializedSourceOffset(range.lowerBound)..<materializedSourceOffset(range.upperBound)))
        case .some(let existing):
            // Contiguity fast path: a `\n` separator was deferred after a `.lazy` span (`appendNewline` set its `joinPending`). If this line is also source-backed and immediately follows the previous span in the source - i.e. it starts one byte past the previous span and that byte is a single `\n` - then the join needs no synthesized separator: the embedded `\n` already lives in the source, so we keep the whole run as one zero-copy `.lazy` range. This holds for top-level paragraphs with LF line endings and no stripped container prefix; blockquote/list continuation (prefix stripped → non-adjacent range), CRLF/CR (separator isn't a lone `\n` at `prev.upperBound`), and tab-expanded lines (`!currentLineMapsToSource`) all fall through to the segment-list arm below.
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
                // A tab-expanded current line (`!currentLineMapsToSource`) has `span` pointing at the per-line expanded buffer, not source - appending `span[range]` directly would bake the expanded-tab spaces into the arena as if they were literal content. Map back to the literal source range instead (same rule as the `.none` case above and `addLineSegment`'s materialized branch): cmark expands tabs only for block-structure indentation and keeps them literal in inline content.
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
    /// Used to rejoin lines during paragraph continuation, since `LineReader` returns ranges without their line terminators. When the current content is a `.lazy` source span, the separator is *deferred* by setting its `joinPending` so the next `addLine` can keep the run zero-copy if it's source-contiguous; otherwise the `\n` is committed into a materialized buffer immediately.
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
        // Materialized (tab-expanded) line. `expandPrefixTabs` turned leading whitespace and container markers into spaces so column-based matching works on byte offsets, but that expansion is lossy for a code/HTML block BODY: cmark copies the body verbatim from `parser->offset` (blocks.c `add_line`), so a content tab survives literally - only the single tab that the consumed indentation splits becomes spaces. Recover the literal source bytes instead of copying the expanded buffer, so content tabs are preserved.
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            // `appendMaterializedCodeContent` maps the content end to the source line end, so every code/HTML body add must run to the buffer's line end (`span.count`) - which all current callers do (fenced code, the one construct that trims content, never materializes).
            assert(range.upperBound == span.count, "materialized code/HTML body must extend to the line end")
            return appendMaterializedCodeContent(bufferStart: range.lowerBound, to: node, pending: pending)
        }
        // A tab-expanded paragraph continuation. Its surviving content - the first non-space byte to the line end - is byte-identical to source: `expandPrefixTabs` only rewrites the prefix and copies the tail verbatim, and the content begins at the first non-space byte, so no expanded-tab space reaches it. Map it back to a zero-copy source segment rather than copying the expanded bytes into the arena. Keeping the content in-source also keeps it readable: a multi-segment inline `ContentSpan` resolves source segments plus the interned `\n` directly (see `ContentSpan.multiByte`).
        assert(range.upperBound == span.count, "materialized paragraph continuation must extend to the line end")
        let sourceStart = materializedSourceOffset(range.lowerBound)
        let lineEnd = currentLineSourceRange.upperBound
        return appendSegment(Segment(offset: Int32(sourceStart), length: Int32(lineEnd - sourceStart), inSource: true), to: node, pending: pending)
    }

    /// Append one body line of a materialized (tab-expanded) code/HTML block as its literal source content, preserving content tabs that `expandPrefixTabs` expanded into spaces.
    ///
    /// `bufferStart` is the body's start offset in the per-line materialized buffer (past the consumed indentation). The line's remaining source bytes - tabs and all - become the content, preceded by synthetic spaces for a tab that the consumed indentation split (cmark's `partially_consumed_tab`, whose split tab byte is dropped and replaced by its remaining columns in spaces). Callers always add the whole rest of the line, so the content runs to the source line end. The common no-split case stays a zero-copy `inSource` segment; a split tab copies the spaces plus the literal tail into the arena as one segment (the code/HTML segment list is one content segment per line, which the finalize normalizers rely on).
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
    /// Used for a code/HTML block body line whose consumed indentation split a tab: cmark drops the tab
    /// byte and emits its leftover columns as spaces (`partially_consumed_tab`; blocks.c `add_line`), then
    /// copies the rest of the line verbatim so any content tab stays literal. The result is one segment,
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
    /// A non-zero space count arises only when `bufferStart` lands inside an expanded tab - the consumed indentation split that tab, so its remaining columns become spaces and the split tab byte itself is dropped (the source start advances past it), mirroring cmark's `partially_consumed_tab`. Re-walks the original prefix like `originalPrefixSourceOffset`; reads `sourceBytes` directly so it is independent of `positionsEnabled`.
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

    // MARK: - NUL -> U+FFFD replacement (CommonMark §2.3)

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

    /// `true` if any segment's bytes contain a `\|` (backslash immediately followed by a pipe).
    ///
    /// A `\|` never straddles two content segments: a paragraph's physical lines are joined by the interned
    /// newline segment, so a backslash ending one line and a pipe starting the next have a `\n` between them
    /// - which cmark's `unescape_pipes` sees, so it isn't a `\|`. A per-segment scan is therefore exact.
    private func segmentsContainEscapedPipe(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        for i in 0..<segs.count {
            let seg = segs[i]
            let len = Int(seg.length)
            var j = 0
            while j + 1 < len {
                if segmentByte(seg, j) == UInt8(ascii: "\\") && segmentByte(seg, j + 1) == UInt8(ascii: "|") {
                    return true
                }
                j += 1
            }
        }
        return false
    }

    /// CommonMark §2.3: replace every NUL (`U+0000`) in `chunk` with U+FFFD (the three bytes `EF BF BD`).
    ///
    /// Returns `chunk` unchanged - so NUL-free content stays a zero-copy slice - when it has no NUL.
    /// Otherwise materializes a copy into the additions arena, expanding each 1-byte NUL to the 3-byte
    /// replacement character (exactly the arena materialization tab expansion uses for a byte that
    /// widens; see `appendSplitTabCodeContent`), and returns a `Chunk` addressing that arena copy. cmark
    /// does this at feed time, before parsing, so this replacement is unconditional (independent of any
    /// parse option).
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

    /// `replacingNUL(_:)` that also rewrites `map`, `chunk`'s content-relative arena→source run map, to image the replaced content.
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

    /// cmark's table `unescape_pipes` (`extensions/table.c`): replace each `\|` with `|`.
    ///
    /// cmark runs this over a table's raw text before inline parsing, including the text it splits off into
    /// the table's preceding paragraph (`try_inserting_table_header_paragraph`). Because the substitution is
    /// on the raw bytes, a `\|` there - even inside a code span, which normally keeps backslash escapes
    /// literal - unescapes to `|`. The row/cell path applies the same rule in `TableParser.unescapePipes`;
    /// this is its preceding-paragraph twin, used when a paragraph is split ahead of a table it opens.
    ///
    /// Returns `chunk` unchanged - so escape-free content stays a zero-copy slice - when it has no `\|`.
    /// Otherwise materializes a copy into the additions arena with each `\|` collapsed to `|` (the
    /// arena-materialization pattern: only the affected content is copied, the single backslash dropped) and
    /// returns a `Chunk` addressing that copy.
    private mutating func unescapingPipes(_ chunk: Chunk) -> Chunk {
        let end = chunk.offset + chunk.length
        var hasEscape = false
        var i = chunk.offset
        while i + 1 < end {
            if readByte(at: i, in: chunk) == UInt8(ascii: "\\")
                && readByte(at: i + 1, in: chunk) == UInt8(ascii: "|") {
                hasEscape = true
                break
            }
            i += 1
        }
        guard hasEscape else { return chunk }
        let offset = storage.strings.count
        var j = chunk.offset
        while j < end {
            let b = readByte(at: j, in: chunk)
            if b == UInt8(ascii: "\\"), j + 1 < end, readByte(at: j + 1, in: chunk) == UInt8(ascii: "|") {
                storage.strings.append(UInt8(ascii: "|"))
                j += 2
                continue
            }
            storage.strings.append(b)
            j += 1
        }
        return Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
    }

    /// The content-relative arena→source run map of `unescapingPipes(raw)`, given `map`, `raw`'s own.
    ///
    /// cmark stamps pipe-unescaped text by its offset in the unescaped buffer, ignoring each stripped backslash
    /// (its escape-oblivious column), so every byte after a stripped backslash images one source byte earlier
    /// than its raw byte does: the backslash's image is dropped and each later image on its line shifts left
    /// by one per backslash stripped before it there. cmark counts columns per line, so the shift ends at the
    /// line break. A U+FFFD's three bytes still image one (shifted) NUL byte.
    func unescapedPipesMap(_ map: [ArenaRun], of raw: Chunk) -> [ArenaRun] {
        assert(map.reduce(0) { $0 + Int($1.length) } == raw.length, "a run map must tile its chunk")
        var unescapedMap: [ArenaRun] = []
        var stripped = 0
        var i = raw.offset
        let end = raw.offset + raw.length
        for run in map {
            for local in 0..<Int(run.length) {
                defer { i += 1 }
                // The same `\|` match as `unescapingPipes`: a backslash immediately followed by a pipe.
                if readByte(at: i, in: raw) == UInt8(ascii: "\\"), i + 1 < end, readByte(at: i + 1, in: raw) == UInt8(ascii: "|") {
                    stripped += 1
                    continue
                }
                let sourceOffset = run.sourceOffset < 0 ? -1 : Int(run.sourceOffset) + local - stripped
                Self.appendContentByte(imaging: sourceOffset, to: &unescapedMap)
                if readByte(at: i, in: raw) == UInt8(ascii: "\n") {
                    stripped = 0
                }
            }
        }
        return unescapedMap
    }

    /// Replace NUL with U+FFFD in a code/HTML block body's segment list, in place.
    ///
    /// A body segment carrying a NUL is re-materialized into the arena via `replacingNUL`; NUL-free
    /// segments and the interned newline separators stay zero-copy. Safe for code/HTML bodies because
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

    /// Record whether the open paragraph `node` is "table-pending": its header line (the sole accumulated
    /// content in `pending`, for the two-line case this helper serves) plus the just-arrived
    /// delimiter-candidate line `delimSpan[delimRange]` would open a GFM table. Materializes the two lines
    /// (header + `\n` + delimiter) into a scratch region of the string arena and runs `classifyTableOpen`,
    /// then truncates the scratch back off (nothing keeps a reference to it - `parseTable` re-materializes at
    /// finalize). Reads `pending` through a borrow, so the paragraph's zero-copy accumulated content is
    /// untouched. Sets `paragraphTablePending[node]` per cmark's `CMARK_NODE__TABLE_VISITED` semantics: a
    /// header/delimiter column mismatch marks the paragraph as never-a-table (`false`), but a candidate that
    /// isn't a valid delimiter row leaves the flag unset so a LATER line can still open a table.
    /// `couldBeDelimiterRow` gates the cost. `detectPendingTable` routes the MULTI-line (header-preceded-by-text) case elsewhere;
    /// this handles only the case where `pending` is a single line (the header itself).
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
            break   // leave unset: cmark's scan_table_start failed, so no header check ran and a later line can still open a table
        }
        // Drop the scratch: it was needed only for the predicate above. Keeping it would leak dead bytes
        // into the arena for the parse's lifetime.
        storage.strings.removeLast(storage.strings.count - scratchStart)
    }

    /// Shape of an open paragraph's accumulated content, as it bears on GFM table detection when a
    /// delimiter-candidate continuation line arrives.
    private enum PendingTableShape {
        /// A single physical line (no embedded `\n`): the header is the whole pending, the two-line case.
        case single
        /// Multiple physical lines held as a zero-copy source range: the header is the last line, and the
        /// earlier lines can split off into a preceding paragraph. `lastNewline` is the source offset of the
        /// `\n` before the header line.
        case multiContiguous(range: Range<Int>, lastNewline: Int)
        /// Multiple physical lines in a non-contiguous representation: a zero-copy segment list (a nested
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

    /// Decide whether the just-arrived delimiter-candidate line `delimSpan[delimRange]` opens a GFM table
    /// with the open paragraph's LAST accumulated line as the header, and set `paragraphTablePending`
    /// accordingly. This mirrors cmark, which opens the table while processing the delimiter line
    /// (`try_opening_table_header`): its `row_from_string` reads the entire accumulated paragraph and treats
    /// every earlier newline-terminated segment as a preceding-paragraph offset, so the header is always the
    /// line immediately before the delimiter.
    ///
    /// When earlier paragraph lines precede that header, they are split off here into a fresh paragraph
    /// inserted before `node` (cmark's `try_inserting_table_header_paragraph`), and `node`'s pending content
    /// is re-seeded to the header line alone so the existing finalize-time two-line detection builds the
    /// table. This handles both multi-line representations: a source-contiguous range (`.multiContiguous`)
    /// and the non-contiguous forms (`.multiOther` - a zero-copy segment list from a nested block-quote /
    /// list continuation or a CRLF join, or a materialized buffer), reconstructing the header and preceding
    /// lines from whichever representation `pending` holds. The single-line case (the header IS the
    /// paragraph) is delegated to `recordTablePending` unchanged.
    ///
    /// After a multi-line split the delimiter row becomes the re-seeded paragraph's second physical line, so
    /// its `delimIndent` / non-laziness are recorded as the paragraph's second-line gate metadata (see
    /// `recordSplitDelimiterLine`): the values captured from the ORIGINAL second line may be indented or
    /// lazy, which would wrongly veto the finalize-time table gate.
    private mutating func detectPendingTable(_ node: DocumentStorage.Index, delimSpan: Span<UInt8>, delimRange: Range<Int>, delimIndent: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        switch pendingTableShape(pending!) {
        case .single:
            recordTablePending(node, delimSpan: delimSpan, delimRange: delimRange, pending: pending!)
            return pending
        case .multiOther:
            // The header is the last accumulated physical line, held in a non-contiguous representation
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
            // The header is the last physical line; everything before its `\n` is the preceding paragraph.
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
                // cmark's scan_table_start failed on this line: no header check ran, so leave the flag unset
                // and let a later delimiter line still open a table.
                return pending
            case .headerMismatch:
                // cmark marks the paragraph TABLE_VISITED here — it never becomes a table.
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

    /// Queue a table-preceding paragraph's `content` for inline parsing after cmark's substitutions on it -
    /// feed-time NUL→U+FFFD, then the table's `unescape_pipes` (`\|`→`|`, even inside a code span) - and
    /// register the arena→source run map its inlines stamp positions through.
    ///
    /// `map` is `content`'s content-relative run map (empty for source-backed content). The unescaped text
    /// keeps cmark's escape-oblivious columns, as for a table cell (see `unescapedPipesMap`).
    private mutating func enqueueTablePrecedingContent(_ content: Chunk, map: [ArenaRun], of node: DocumentStorage.Index) {
        if content.isEmpty {
            return
        }
        var map = map
        let nulReplaced = replacingNUL(content, map: &map)
        let unescaped = unescapingPipes(nulReplaced)
        if positionsEnabled, !unescaped.inSource {
            let image = sourceImage(of: nulReplaced, map: map)
            let unescapedImage = image.isEmpty || unescaped == nulReplaced ? image : unescapedPipesMap(image, of: nulReplaced)
            if !unescapedImage.isEmpty {
                arenaSourceMaps[node] = unescapedImage
            }
        }
        pendingInlines.append((node, storage.intern(unescaped)))
    }

    /// Insert the paragraph cmark splits off the lines before a table's header
    /// (`try_inserting_table_header_paragraph`) as `node`'s preceding sibling, and return it.
    private mutating func insertTablePrecedingParagraph(before node: DocumentStorage.Index) -> DocumentStorage.Index {
        let paragraph = storage.appendNode(NodeRecord(kind: .paragraph, parent: storage[node].parent))
        storage.insertChildBefore(paragraph, before: node)
        return paragraph
    }

    /// After a multi-line paragraph is split so the delimiter row becomes the re-seeded paragraph's second
    /// physical line, record the delimiter's indent and non-laziness as the paragraph's "second line" gate
    /// metadata. `paragraphSecondLineIndent` / `paragraphSecondLineLazy` were captured from the ORIGINAL
    /// second line (which may be indented >= 4 or a lazy continuation), but the finalize-time table gate
    /// must see the delimiter line - which `detectPendingTable`'s caller already confirmed is non-indented
    /// (`< 4`) and non-lazy - or it would wrongly veto the table cmark opens.
    private mutating func recordSplitDelimiterLine(_ node: DocumentStorage.Index, delimIndent: Int) {
        paragraphSecondLineIndent[node] = delimIndent
        paragraphSecondLineLazy[node] = false
    }

    /// Classify whether the open paragraph's LAST accumulated line (the header) plus the just-arrived
    /// delimiter-candidate line open a GFM table, for a NON-contiguous paragraph representation (a zero-copy
    /// segment list, or a materialized buffer with embedded newlines). Reconstructs the header line from the
    /// stored representation into a scratch region of the arena, appends `\n` + the delimiter, runs
    /// `classifyTableOpen`, then truncates the scratch back off - reading `pending` through a borrow so the
    /// paragraph's accumulated content is untouched (mirrors `recordTablePending`).
    private mutating func classifyMultiLineHeader(delimSpan: Span<UInt8>, delimRange: Range<Int>, pending: borrowing PendingLeaf) -> TableOpenClassification {
        let scratchStart = storage.strings.count
        switch pending.content {
        case .segments(let segs):
            // Content segments (one physical line each) alternate with the shared `newlineSegment`; the
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
            // The header is the bytes after the last embedded newline.
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
    /// `.multiContiguous` split for the segment-list / materialized representations (cmark's
    /// `try_inserting_table_header_paragraph`). Called only after `classifyMultiLineHeader` returns `.opens`.
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
        // A NUL (feed-time U+FFFD) or a `\|` (cmark's table `unescape_pipes`) in the split-off preceding
        // lines forces a flatten into one normalized arena chunk with both substitutions applied: this
        // content bypasses `drainLeaf`, so it is normalized here at its own intern (see `ContentSpan`
        // for why a segment list can't carry the replacement).
        let substitutes = segmentsContainNUL(preceding) || segmentsContainEscapedPipe(preceding)
        let trimsControlWhitespace = segmentsEndInControlWhitespace(preceding)
        let mayHoldDefinition = segmentsCouldMatchMatcher(preceding)
        if substitutes || trimsControlWhitespace || mayHoldDefinition {
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

    /// Split a materialized paragraph (a byte buffer with embedded newlines) into a preceding paragraph
    /// plus a header-only re-seed, each carrying its part of the buffer's run map. A paragraph is materialized
    /// when its definitions were restored while an underline line was examined (`processLine` PHASE 2c) and
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
            // The HTML block was closed by this line.
        } else if openKind == .htmlBlock && !allMatched {
            pending = finalize(node: current, pending: pending)
        }

        let scan = leadingScan(source: source, range: cursor..<lineRange.upperBound)
        let firstNonSpace = scan.firstNonSpace
        let isBlank = scan.isBlank
        let indent = scan.indentColumns

        // PHASE 2b: Blank line.
        if isBlank {
            // Capture the deepest open block BEFORE we close any leaves - a blank line closes an open paragraph/heading, but the blank is still attributed to that leaf for tight/loose detection.
            let blankLeaf = current
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
        // A table-pending paragraph (its first two lines form a header + delimiter) is NOT a setext-heading
        // candidate: cmark opens the table while processing the delimiter line, so by the underline line the
        // open block is a table, not a paragraph, and the `-`/`=` can't underline it (`r\n|-\n-` → Table +
        // list; `r\n|-\n=` → Table with a `=` body row). Skip the setext transform so the line falls through
        // to PHASE 2d, which finalizes the paragraph into a table and dispatches the underline line anew.
        if stillOpenKind == .paragraph && allMatched && !(paragraphTablePending[current] ?? false),
           let level = matchSetextUnderline(source: source, range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
            // Strip any leading reference-link definitions from the paragraph's accumulated content first. If they consume the entire paragraph, the setext heading never forms - the underline line falls through to dispatch as plain text (per spec examples 184 / 185).
            let para = current
            let materialized = materializePendingContent(para, pending: pending)
            let raw = materialized.chunk
            // Content-relative arena→source run map for the flattened segments (empty unless the paragraph body was non-contiguous `.segments`, i.e. inside a blockquote/list). Captured before `pending` is moved out.
            let flatMap = materialized.map
            pending = materialized.pending
            let trimmedHead = raw.trimmingWhitespace(using: self)
            let stripped = parseDefinitions(in: trimmedHead)
            if self.isBlank(chunk: stripped) {
                // A paragraph of only definitions forms no heading (spec "Setext headings": the
                // underline must follow lines that are a paragraph once definitions are removed), but it
                // is still open while this line is examined. A line that cannot interrupt a paragraph -
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
                // Empty after ref-def extraction - drop the paragraph and let the underline line dispatch as a fresh block. Refresh `stillOpenKind` so PHASE 2d doesn't try to continue the (now-detached) paragraph.
                storage.unlinkChild(para)
                guard let parent = storage[para].parent else {
                    fatalError("Invalid internal state - missing parent")
                }
                current = parent
                stillOpenKind = storage[current].kind
            } else {
                // Re-seed pending content with the stripped bytes so the heading's inline-parse pass sees only what's left after ref-defs were extracted. Keep source-backed content zero-copy as a `.lazy` source range (its offset/length are source offsets when `inSource`), so the heading's inlines are source-mapped and get positions exactly as paragraph / ATX-heading content does; only arena-backed content (non-contiguous or normalized lines) is copied.
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
                // why: cmark finalizes a setext heading only when a later line or EOF closes it
                // (blocks.c) and stamps its end from that closing line, like the document / fenced code
                // (blocks.c:327) - not from the underline. Its content already ends at the underline (a
                // heading can't be continued, so the next line never accumulates into it), so leave the
                // heading open as `current` with its content pending and let the normal per-line close
                // path stamp the end from the line that closes it. Same finalize-timing class as the
                // deferred thematic break (FINDINGS #7).
                return pending
            }
        }

        // PHASE 2d: When a paragraph is open, decide whether this line starts a new block (which closes the paragraph) or is absorbed as lazy/matched continuation. This is the ONLY case where the interrupt decision matters, so the matcher ladder is run only here - every other line goes straight to dispatch, which does its own (single) classification.
        //
        // A GFM table opens (in cmark) while processing the delimiter line, so once a paragraph is
        // "table-pending" (its first two lines form a header + delimiter that would open a table) its open
        // block is a TABLE, not a paragraph. A subsequent line that cannot be a table body row therefore
        // closes the table and its enclosing container and starts a fresh block at the container's ancestor.
        // Three kinds of line can't be a body row:
        //   - a LAZY continuation: cmark opens blocks against an ancestor of the (now-table) block, so the
        //     lazy-paragraph branch never fires (block-quote / list only),
        //   - a line that scans to ZERO table columns — a lone `|` optionally padded with delimiter-marker
        //     whitespace. cmark's table `matches` calls `row_from_string`, which yields no columns, so the
        //     row doesn't match. Without this the finalize-time table builder absorbs the line and
        //     `splitCells` autocompletes it into a spurious one-empty-cell body row, and
        //   - a line indented >= 4 columns: cmark's `open_new_blocks` computes `maybe_lazy` from whether the
        //     CURRENT block is a paragraph (blocks.c:1152). Once the table opened, the current block is a
        //     TABLE, so `maybe_lazy` is false and the `indented && !maybe_lazy && !blank` branch
        //     (blocks.c:1325) opens an INDENTED CODE BLOCK ahead of the table extension's block opener
        //     (`try_opening_table_block`, `!indented`-gated at table.c:648-652, the dispatcher that would
        //     otherwise call `try_opening_table_row`); `add_child` can't nest that code block under the
        //     table, so the table closes. This is why an indented line breaks out of a table but a lazy
        //     paragraph continuation (where `maybe_lazy` stays true) does not.
        // Reproduce cmark by NOT entering the absorb path — fall through to PHASE 3, which closes the
        // paragraph (finalizing it into the header-only table) and the container, then dispatches this line
        // anew at the ancestor level.
        let tablePending = paragraphTablePending[current] ?? false
        let breaksOutOfPendingTable = tablePending
            && (currentLineIsLazyContinuation
                || indent >= 4
                || Self.isLonePipeRow(span: source, range: firstNonSpace..<lineRange.upperBound))
        if stillOpenKind == .paragraph && !breaksOutOfPendingTable {
            // The matcher ladder can only return true if the first content byte is one that some block construct starts with; for ordinary prose continuation lines it isn't, so we skip the whole ladder. `mightStartBlock` is a superset of every matcher's trigger byte, so a `false` here is exactly what `lineStartsNewBlock` would have returned.
            // `interruptsParagraph` mirrors cmark's flag (blocks.c: `check_open_blocks` backs `container` up to its parent on a failed continuation): true iff the open paragraph's OWN container matched this line, i.e. `deepestMatched` is the paragraph's parent. When a shallower container matched, the marker is a sibling item at the list level, not an interruption of this paragraph.
            // A table-pending paragraph's "real" open block (in cmark) is a table, not a paragraph, so the
            // paragraph-interrupt restrictions do NOT apply: a bare bullet / an ordered marker with start ≠ 1
            // closes the table and opens a list (`r\n|-\n-` → Table + list), exactly as a block start closes
            // a table. Model that by treating the line as NOT interrupting a paragraph (the lenient rule). A
            // non-block-start line (e.g. `=`) still isn't a marker, so it stays absorbed as a table body row.
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
                    // The FIRST continuation line is the paragraph's second physical line — the two-line GFM
                    // table delimiter-row candidate. cmark opens a table only when that line is NOT indented
                    // (`try_opening_table_block`'s `!indented` gate) and is a matched (non-lazy) continuation;
                    // finalize-time table detection can't see the stripped leading whitespace or the laziness,
                    // so record both (`leadingScan` measured the indent against the container prefix) for
                    // `runParagraphMatchers` to consult.
                    if paragraphSecondLineIndent[current] == nil {
                        paragraphSecondLineIndent[current] = indent
                        paragraphSecondLineLazy[current] = currentLineIsLazyContinuation
                    }
                    // Detect whether this line opens a table with the paragraph's LAST accumulated line as the
                    // header (cmark opens the table while processing the delimiter line, `try_opening_table_header`).
                    // Fires on the FIRST delimiter-shaped, non-indented, non-lazy continuation line and, once it
                    // resolves the paragraph's table fate, sets `paragraphTablePending` so it isn't re-evaluated
                    // (cmark's `CMARK_NODE__TABLE_VISITED`); a candidate that isn't a valid delimiter row leaves the
                    // flag unset so a later line can still open a table. The flag is consulted for a lazy /
                    // lone-pipe break-out (`breaksOutOfPendingTable` above) AND to stop a setext underline / let a
                    // block start close the table (PHASE 2c/2d). When earlier lines precede the header, the split
                    // off happens here. `couldBeDelimiterRow` keeps ordinary prose paragraphs from materializing.
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
    /// `prefixColumns` normally equals the column width of `[lineRange.lowerBound, cursor)`, but exceeds it when a container advance consumed *columns* into a tab it could not drop byte-wise (a list item's content indent landing mid-tab): `cursor` still sits at that tab while `prefixColumns` records the column the strip reached. The leaf continuation folds the shortfall into its own strip so the straddling tab is split there (cmark's `partially_consumed_tab`).
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
                    // The marker consumes `>` plus one optional following space or tab COLUMN (cmark's
                    // `parse_block_quote_prefix`). When that optional column falls on a TAB wider than one
                    // column it only PARTIALLY consumes it: leave the tab byte at `cursor` so the leaf strip can split
                    // it, and record the intended column in `prefixColumns` (one column past `>`),
                    // mirroring the list-item content-indent straddle. `handleCodeBlockContinuation`
                    // folds the shortfall into `stripFenceIndent`, surfacing the tab's leftover columns
                    // as leading spaces (cmark's `partially_consumed_tab`; blocks.c `add_line`). This
                    // only arises on a source-mapped fenced-code body line - every other line
                    // pre-expands its prefix tabs to spaces (`expandPrefixTabs`), so the optional
                    // character is a space and the leaf is the fenced code block.
                    (cursor, prefixColumns) = blockQuotePrefixEnd(
                        source: source,
                        lineStart: lineRange.lowerBound,
                        markerEnd: firstNonSpace + 1,
                        advanced: advanced
                    )
                    deepestMatched = node
                } else {
                    // No `>` on this line: the block quote's paragraph continues lazily. The walk stops
                    // here (`allMatched: false`), and `cursor` marks where the last matched prefix ended.
                    // `processLine` turns that into `currentLineIsLazyContinuation`.
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .list:
                // Lists themselves don't have a per-line continuation rule; their items do. The list as a container "matches" trivially as long as we get to one of its items.
                deepestMatched = node
            case .item:
                // Item continuation, mirroring cmark's `parse_node_item_prefix` (blocks.c): the line's
                // indent, measured relative to the parent container's already-consumed prefix (`cursor`),
                // is tested against the item's content column FIRST - for an empty (childless) item and a
                // non-empty one alike. Only if that fails does a blank line inside a NON-empty item keep it
                // open. Because `cursor` advances as each ancestor item consumes its own padding, the indent
                // an inner item sees is relative to its OWN marker, so a nested empty item is measured against
                // its own content column - not a shallower ancestor's.
                let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
                let isBlank = firstNonSpace == lineRange.upperBound
                let padding = itemPadding(of: node)
                // Compare in COLUMNS, not bytes, so a leading tab counts as up to 4 cols of indent.
                // Measured from `prefixColumns`, the column the outer prefixes reached: `cursor` can sit
                // after a marker at any column, or mid-tab after a partially consumed tab, and a tab's
                // width depends on the column it starts at (cmark's `parser->indent`,
                // `first_nonspace_column - column`).
                let availCols = indentColumns(source: source, from: cursor, to: firstNonSpace, baseColumn: prefixColumns)
                if availCols >= padding {
                    // The indent reaches the item's content column: consume exactly `padding` columns and
                    // match. cmark tests this BEFORE the childless-blank check, so a whitespace-only line
                    // whose expanded indent covers the content column extends even a childless item onto it
                    // (e.g. a tab after a bare `-`: 4 columns >= the content column 2).
                    cursor = advanceColumns(
                        source: source,
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: padding,
                        baseColumn: prefixColumns
                    )
                    // The item intends to consume `padding` columns even when a straddling tab kept
                    // `advanceColumns` from advancing `cursor` past it: record the intended column so the
                    // leaf continuation can split that tab (cmark's `partially_consumed_tab`).
                    prefixColumns += padding
                    deepestMatched = node
                } else if isBlank, storage[node].firstChild != nil {
                    // A blank line inside an item that already has content keeps the item open even though
                    // the indent falls short of the content column. Advance `cursor` to first-non-space (the
                    // line end for a blank line), mirroring cmark's `S_advance_offset(... first_nonspace ...)`,
                    // so any deeper open item measures its indent from here rather than the shallower line
                    // start. A childless item on such a line closes (CommonMark §5.2: `first_child == NULL`).
                    cursor = firstNonSpace
                    prefixColumns = columnWidth(source: source, from: lineRange.lowerBound, to: cursor)
                    deepestMatched = node
                } else {
                    return (deepestMatched, cursor, prefixColumns, false)
                }
            case .footnoteDefinition:
                // Footnote-definition continuation, mirroring cmark's
                // `parse_footnote_definition_block_prefix` (blocks.c): a line indented >= 4 columns
                // (relative to the parent's consumed prefix) stays in the definition with 4 columns
                // stripped; a blank line keeps the definition open; any other
                // (non-indented, non-blank) line fails the prefix, so the definition's open paragraph
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
                    // why: CommonMark counts a whitespace-only line as blank (§4.9), so
                    // any blank line keeps the definition open.
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
    /// `interruptsParagraph` mirrors cmark's `interrupts_paragraph` flag: `true` when the open paragraph's OWN container matched this line's continuation prefix (so the line is genuinely interrupting THAT paragraph), `false` when only a shallower container matched (the marker is a sibling item continuing an existing list, not interrupting the paragraph).
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
        // HTML blocks of types 1–6 interrupt a paragraph (CommonMark 0.31 §4.6). Type 7 does NOT interrupt a
        // paragraph in the matched container; but on a lazy continuation whose own container failed to match
        // (`!interruptsParagraph`), cmark opens the block at the ANCESTOR that did match — where there is no
        // open paragraph to interrupt — so type 7 is allowed there and breaks out (`>o\n<d>` closes the
        // block-quote's paragraph and opens a top-level HTML block; a top-level `o\n<d>` keeps `<d>` as a lazy
        // continuation). Allow type 7 exactly when it isn't interrupting a paragraph; `dispatchNewBlocks` then
        // opens it against the ancestor (its own `allowType7` gate fires there, `current` no longer a paragraph).
        if matchHTMLBlockStart(source: source, range: range, firstNonSpace: firstNonSpace, allowType7: !interruptsParagraph) != nil {
            return true
        }
        // A GFM footnote definition opener `[^label]:` interrupts a paragraph (cmark's footnote-def
        // opener carries no paragraph-non-interruption guard). Gated `indent < 4` like the block-open
        // dispatch. So `[^a]: A\n[^b]: B` opens two definitions rather than folding the second into the
        // first definition's paragraph.
        if storage.options.contains(.footnotes),
           indent < 4,
           matchFootnoteDefinition(source: source, range: range, firstNonSpace: firstNonSpace) != nil {
            return true
        }
        // List markers interrupt a paragraph only if they'd start a non-empty first item (CommonMark 0.31 §5.2/§5.3). An ORDERED list can interrupt a paragraph only when its start number is 1; bullets are exempt. This is cmark's `interrupts_paragraph && start != 1` decline in `parse_list_marker` (blocks.c), and it applies at EVERY nesting level - `interruptsParagraph` is true exactly when the open paragraph's own container matched this line, so `- a\n  2. b` (the item matched → `2. b` interrupts the item's paragraph) keeps `2. b` as text, while `1. a\n2. b` (the item did NOT match → the marker sits at the list level) opens a sibling item regardless of start.
        if let marker = matchListMarker(source: source, range: range, firstNonSpace: firstNonSpace, lineStart: lineStart, indent: indent) {
            if marker.isEmpty {
                // An EMPTY marker opens a list only when it does NOT interrupt the open paragraph, exactly as cmark's `parse_list_marker` accepts an empty bullet/ordered marker iff `!interrupts_paragraph` (blocks.c). Same `interruptsParagraph` signal as the ordered rule below: `- a\n  +` (the item matched → the marker interrupts the item's paragraph) keeps `+` as text, `> a\n+` (the block quote's continuation failed → the marker doesn't interrupt that paragraph) opens a new top-level list, and `a\n+` at the top level (the document always matches the paragraph) keeps `+` as text (FINDINGS #43).
                return !interruptsParagraph
            }
            if interruptsParagraph
                && marker.kind == .ordered
                && marker.start != 1 {
                return false
            }
            return true
        }
        // Indented code does not interrupt a paragraph (CommonMark 0.31 §4.4).
        return false
    }

    /// Continue an open HTML block. Returns `true` if the block remains open after handling this line; `false` if the line closed it (the line itself was already appended in either case for types 1–5; for type 6, blank lines close without being appended).
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

    /// Continue an open code block. Returns `stillOpen: true` if the block remains open after handling this line; `false` if the line closed it (or was a closing fence). When this returns `false` the caller should *not* dispatch the line content as a fresh block - the closing fence is fully consumed.
    private mutating func handleCodeBlockContinuation(source: Span<UInt8>, lineRange: Range<Int>, cursor: Int, prefixColumns: Int, pending: consuming PendingLeaf?) -> LeafContinuation {
        var pending = pending
        let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound
        let indent = indentColumns(source: source, from: cursor, to: firstNonSpace)

        if case .codeBlock(let info) = storage[current].kind, info.isFenced {
            // Fenced. The closing-fence indent is measured in COLUMNS (cmark's `first_nonspace_column -
            // column`, blocks.c `S_find_first_nonspace`): the absolute column of the first non-space byte
            // minus the column the container prefixes advanced to. A tab therefore counts to its next tab
            // stop, not one byte - a fenced-code body line skips leading-tab pre-expansion, so a raw
            // leading tab must not be mistaken for the ≤3-column indent of a closing fence.
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
            // intended `prefixColumns` plus the fence's own `fenceOffset` - in COLUMNS, tab-stop-aware,
            // then append. `startColumn` is the column physically reached at `cursor`; the bytes before
            // `cursor` already cover `startColumn` of the indent, so `prefixColumns + fenceOffset -
            // startColumn` columns remain to strip here. That shortfall is non-zero when a container
            // advance (e.g. a list item's content indent) consumed columns into a tab it could not drop
            // byte-wise, leaving `cursor` at that tab: folding those columns into this strip splits the
            // tab here - its consumed columns dropped, its leftover columns surfaced as leading spaces
            // with the rest of the line copied verbatim (cmark's `partially_consumed_tab`; blocks.c
            // `add_line` + `S_advance_offset`), so any content tab stays literal.
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
            // For an open indented code block, a "blank" line that actually contains 5+ columns of whitespace preserves the EXTRA columns as content (per spec example 82 - `      ` between two code lines becomes `  ` in the rendered code block).
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
            // Either there's no open list, or the marker style differs from the open list. In the latter case, finalize the open list so the new list opens as a sibling - `- foo\n+ bar` becomes two top-level lists, not a nested one (CommonMark §5.3).
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
    /// `prefixColumns`), which can EXCEED `startCursor`'s physical column when a prefix partially consumed a
    /// straddling tab (a block-quote `>`'s optional column, or a list item's content-indent advance, landing
    /// mid-tab). The re-dispatch indent is measured from that column - `firstNonSpaceColumn - column`, cmark's
    /// `parser->indent` - so the tab's already-consumed columns are not recounted from column 0 (which would
    /// under-count a block-quote straddle's dropped leftover, or over-count a list-item straddle's consumed
    /// columns, flipping the indented-code / paragraph decision).
    private mutating func dispatchNewBlocks(source: Span<UInt8>, lineRange: Range<Int>, startCursor: Int, startColumn: Int, pending: consuming PendingLeaf?) -> PendingLeaf? {
        var pending = pending
        var cursor = startCursor
        var column = startColumn
        // Containers opened on this line so far, matching cmark's per-line `depth` (open_new_blocks):
        // incremented once per iteration and used to cap list opening at `maxListNesting`.
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
            // `baseColumn: column` - `cursor` can sit mid-tab here (a PRIOR iteration's marker on this
            // same line partially consumed a tab; see the partial-tab branch below), so the matcher must
            // measure the tab's remaining columns from the column already reached, not from an assumed 0.
            if let advanced = matchBlockQuoteMarker(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                baseColumn: column
            ) {
                // A block quote can't be a direct child of a list (lists only contain items), so an enclosing list closes first - e.g. a `>` line after list items ends the list and starts a top-level quote, matching cmark's `add_child` ancestor-finalize rule.
                if storage[current].kind.isList {
                    pending = finalize(node: current, pending: pending)
                }
                let quoteIdx = addChild(
                    kind: .blockQuote,
                    parent: current,
                    start: sourceOffset(firstNonSpace)
                )
                current = quoteIdx
                // The marker consumes `>` plus one optional following space or tab COLUMN (cmark's
                // `open_new_blocks`, the same `S_advance_offset(parser, input, 1, true)` call
                // `parse_block_quote_prefix` uses for a continuation). When that optional column falls
                // on a TAB wider than one column it only PARTIALLY consumes it: leave the tab byte at `cursor` so a leaf opened
                // later on this line (an indented/fenced code block straddling the tab) can split it, and
                // record the intended column in `column` (one column past `>`) - the opening-line sibling
                // of `walkOpenContainers`'s continuation case. This only arises when a raw prefix tab
                // reaches here unexpanded (`expandPrefixTabs` is skipped while continuing an open fenced
                // code block); every other line's tabs are already spaces, so the byte check below is a
                // no-op there.
                (cursor, column) = blockQuotePrefixEnd(
                    source: source,
                    lineStart: lineRange.lowerBound,
                    markerEnd: firstNonSpace + 1,
                    advanced: advanced
                )
                continue
            }

            // Thematic break (must be before ATX so `---` etc. wins over content matchers, and before list-marker so `- - -` etc. wins over nested lists).
            // Gated `indent < 4` (COLUMNS), cmark's `!indented` in the thematic-break branch (`open_new_blocks`; blocks.c): a line whose indent reaches four columns is indented code, not a break. A raw prefix tab reaches here unexpanded only on a fenced-code body line - see the fenced-code branch below for the full mechanism.
            if indent < 4, matchThematicBreak(source: source, range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
                // Thematic breaks close any enclosing list - they don't become children of a list (lists can only contain items).
                if storage[current].kind.isList {
                    pending = finalize(node: current, pending: pending)
                }
                let breakIdx = addChild(
                    kind: .thematicBreak,
                    parent: current,
                    start: sourceOffset(firstNonSpace)
                )
                // why: cmark leaves a thematic break open as `parser->current` and finalizes it only
                // when a later line or EOF forces it (blocks.c:1482). Its end position is therefore
                // finalize-timing-dependent - the previous line's length when a later line closes it,
                // or the last processed line's content end at EOF - so we defer to the normal per-line
                // close path rather than guessing the end on the HR's own line.
                current = breakIdx
                return pending
            }

            // GFM footnote definition (after thematic break, before list marker, per cmark's
            // open_new_blocks order). Opens a block container that absorbs the rest of the line as
            // its first content and continues via indent-≥4 / blank lines (see walkOpenContainers).
            // Gated `indent < 4` (cmark's `!indented`), so an indented `[^x]:` is code, not a def.
            if storage.options.contains(.footnotes),
               indent < 4,
               let fn = matchFootnoteDefinition(
                   source: source,
                   range: cursor..<lineRange.upperBound,
                   firstNonSpace: firstNonSpace
               ) {
                // A footnote definition can't be a direct child of a list (lists hold only items), so
                // an enclosing list closes first, mirroring the block-quote / thematic-break openers.
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
            // Capped at `maxListNesting` containers per line, matching cmark's `depth < MAX_LIST_DEPTH`
            // gate (open_new_blocks): once nesting reaches the cap the marker no longer opens a list -
            // it falls through to the paragraph fallback as text. Applies to bullet and ordered lists
            // alike; block quotes above are uncapped.
            // Gated on `indent < 4` (COLUMNS), cmark's `parser->indent < 4` in the list-marker branch
            // (open_new_blocks). A marker whose content indent reaches four columns is indented code, not a
            // list - even when its byte distance from the cursor is ≤ 3 because a straddling tab widened it
            // (e.g. the `-` after `marker\t\t`, six columns in but two bytes over: falls through to the
            // indented-code branch below).
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
                // column cmark reached, not the tab's left edge (cmark's `partially_consumed_tab`).
                column = marker.contentStartColumn
                continue
            }

            // From this point on the line isn't a list item, so any open list at `current` must close before we attach the new block (lists can't have direct non-item children).
            if storage[current].kind.isList {
                pending = finalize(node: current, pending: pending)
            }

            // ATX heading. Gated `indent < 4` (COLUMNS), cmark's `!indented` in the ATX branch (`open_new_blocks`; blocks.c): a line whose indent reaches four columns is indented code, not a heading - see the fenced-code branch below for how a raw prefix tab reaches an opener unexpanded.
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

            // Fenced code block. Gated `indent < 4` (COLUMNS), cmark's `!indented` in the fence-opener
            // branch (`open_new_blocks`; blocks.c). A line whose indent reaches four columns is indented
            // code, not a fence - even when its byte distance from the cursor is <= 3 because a straddling
            // tab widened it. A raw prefix tab reaches here only on a line processed while an open fenced
            // code block was `current` (the one case `expandPrefixTabs` is skipped, per the `inFencedCode`
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
                // The info string lives in `expandPrefixTabs`'s verbatim tail (the fence char isn't a prefix byte), so on a tab-materialized line the matcher measured its bounds against the transient buffer. Map them back to source (the tail copies byte-for-byte, so the constant delta preserves the length) before interning, matching the source-mapped/space case's `inSource: true` chunk exactly; the mapping reads only unconditionally-tracked line state, so it is correct even when `.sourcePosition` is off. A source-mapped line already carries real source offsets.
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
                // cmark stores `fence_offset` in raw SOURCE bytes (`first_nonspace - offset`), which counts
                // a tab straddling the container prefix and the fence as a SINGLE byte even though it spans
                // several columns. On a materialized line the prefix tabs were expanded to spaces, so the
                // buffer distance over-counts that tab; map both endpoints back to source so a fence opened
                // after a partially-consumed tab (e.g. `>\t```) strips only the tab's remaining column on
                // its continuation lines, not the tab's full width.
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

            // HTML block (types 1–7). Leading 0–3 spaces of indent are preserved verbatim in the block's content. Type 7 is detected only when the current container isn't a paragraph, since it can't interrupt one (per CommonMark 0.31 §4.6).
            // Gated `indent < 4` (COLUMNS), cmark's `!indented` in the HTML-block branch (`open_new_blocks`; blocks.c): a line whose indent reaches four columns is indented code, not an HTML block - see the fenced-code branch above for how a raw prefix tab reaches an opener unexpanded.
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
                // indented-code-block opener below does: leftover columns become synthetic leading
                // spaces, then the rest of the line copies verbatim (cmark's `partially_consumed_tab`;
                // blocks.c `add_line`). `maxColumns` is 0 in the ordinary (non-straddling) case, so
                // `stripFenceIndent` is a no-op and the ORIGINAL zero-copy `addLine` path is taken.
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
                // The block starts where content begins *after* the four-column code indent is consumed
                // (cmark's convention: extra indentation beyond four is preserved as content, and the
                // start column is that post-indent position - not the first non-space char). Strip the
                // four columns tab-stop-aware from the current `column`: when a straddling tab crosses
                // the boundary its consumed columns are dropped and its leftover columns surface as
                // leading spaces (cmark's `partially_consumed_tab`; blocks.c `S_advance_offset` +
                // `add_line`), the rest of the line copied verbatim so any content tab stays literal.
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
                // non-source segment is only the interned newline or synthetic filler with no inline syntax,
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

    /// Trim trailing whitespace off the last segment (matching `Chunk.trimming(using:)`), in place. Interior segments - the newline joins and any hard-break trailing spaces before them - are untouched. A last segment trimmed to zero length is harmless (read as empty).
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

    /// Cheap, over-approximate gate: could this segment content match a finalize-time matcher (a link reference definition or task list item marker starts with `[`, an attribute def with `^[` when `.attributes` is set, or a GFM table)?
    ///
    /// A false positive only costs an avoidable materialization; a false negative would skip a real matcher, so the checks must cover every matcher's necessary condition. The table necessary condition is on the DELIMITER (second) line, not the header: a single-column table's header need not contain a pipe (`a\n|-`, `a\n:-`), so the header-`|` check that once lived here would skip such tables. The segment list is isomorphic to `\n`-separated lines, so the second line is scanned directly.
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
                // An attribute def opens with a `^` immediately followed by `[` — the same contiguity
                // cmark requires (`chunk.data[0] == '^' && chunk.data[1] == '['`), so a `^` split from its
                // `[` by a line join is correctly not admitted (the `[` would fall in the next segment).
                if b == UInt8(ascii: "^"), attributesEnabled, j + 1 < Int(seg.length),
                   segmentByte(seg, j + 1) == UInt8(ascii: "[") {
                    return true
                }
                break outer   // first non-whitespace byte doesn't open a definition
            }
        }
        // Table: the delimiter row is the paragraph's SECOND line. It can only be a delimiter row if
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
                        // VT (0x0B) / FF (0x0C) are delimiter-marker whitespace (`scan_table_start`'s
                        // `spacechar`), so admit them here alongside space/tab; `parseDelimRow` applies
                        // the exact rule.
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

    /// Flatten a segment list into one arena chunk, recording a content-relative arena→source run map in `map` as it copies: one run per non-empty segment. A source segment images its own source range; a non-source segment - the interned `\n` line-join, or an arena-only line with no source pre-image - becomes a synthetic gap (`sourceOffset < 0`). The map tiles the flattened content from its first byte, so it survives a later arena re-copy of the content (the byte layout is unchanged) and lets inline stamping recover per-line source columns.
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
                    // The interned `\n` join, or an arena-only line: a synthetic gap.
                    map.append(ArenaRun(length: Int32(len), sourceOffset: -1))
                }
            }
        }
        storage.strings.append(copying: buf.span)
        return Chunk(offset: offset, length: total, inSource: false)
    }

    /// Narrow a content-relative arena→source run map to the sub-window `[start, start + length)` of the original flattened content, rebased so its first run begins at content offset 0.
    ///
    /// Drops runs outside the window and advances a partially-included source run's `sourceOffset` by the trimmed-off prefix; synthetic gaps stay gaps. Used when a flattened setext heading's content is re-seeded after leading/trailing whitespace trim and ref-def stripping, so the stored map matches exactly the bytes that reach inline parsing.
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
    /// the lines before `lines` was formed, if any.
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

    /// Run the paragraph finalize-time matchers on a single flat content `Chunk`: GFM table detection, then the paragraph's raw content (`paragraphContent`) - which it queues for inline parsing, or drops the node if nothing remains.
    ///
    /// Factored out so both the flat-content path and the (eligibility-gated) segment path can reuse it. `map` is the content's arena→source run map (empty for source-backed content): when the content was flattened from a non-contiguous segment list it carries per-line source columns, and when NULs were replaced it images each U+FFFD back to its NUL. It is sliced to the surviving `contentChunk` window and stamped on the node so the inline pass can stamp positions.
    private mutating func runParagraphMatchers(node: DocumentStorage.Index, raw: Chunk, map: [ArenaRun]) {
        let trimmed = raw.trimmingWhitespace(using: self)
        if trimmed.isEmpty {
            // A non-blank line can still hold only line tabulations and form feeds, which leave the
            // paragraph no raw content (spec "Paragraphs").
            return
        }
        // GFM table detection: header line + delimiter row mutates the node in place to `.table`.
        // This runs BEFORE reference-link-definition extraction because cmark opens a table while
        // processing the delimiter row (`try_opening_table_block`), converting the still-open paragraph to
        // a table before it is ever finalized — and `resolve_reference_link_definitions` runs only at
        // PARAGRAPH finalize (`src/blocks.c`). A paragraph that became a table is never probed for ref-defs,
        // so a paragraph whose second line is a delimiter row is a table even when it reads as a multi-line
        // ref-def (`[\n|-\n]:/`), matching cmark.
        //
        // Gated on `paragraphTablePending`: the table wins over ref-def extraction ONLY when the table
        // extension actually opened during block parsing. That flag is set (`detectPendingTable`) exactly
        // when cmark's `try_opening_table_block` would open the table, and is the necessary refinement over
        // an unconditional table-first ordering. cmark's `open_new_blocks` tries the setext-heading-underline
        // branch (`scan_setext_heading_line`, a pipe-less run of `-`/`=`) BEFORE the table extension (the
        // last-resort block opener): a BARE `-`/`=` delimiter row therefore never reaches the table extension
        // — it is consumed by the setext branch, which first resolves the paragraph's ref-defs. So a complete
        // ref-def followed by a bare `-` (`[o]:o\n-`) resolves the ref-def and the `-` becomes a paragraph,
        // while a PIPE delimiter (`[o]:o\n|-`) — which the setext scanner rejects — opens a table over the
        // would-be ref-def. Only a pipe-less all-dashes/all-equals row is a setext underline, and cmark
        // never opens a table on such a row (the setext branch consumes it first, before the extension), so
        // a legitimate table's delimiter always went through `detectPendingTable` and set this flag; the only
        // way table-shaped content reaches finalize with the flag unset is the setext/ref-def
        // reconstruction (PHASE 2c), which cmark treats as a ref-def. The delimiter row is the paragraph's
        // second physical line; cmark opens a table only when that line is NOT indented >= 4 columns
        // (`try_opening_table_block`'s
        // `!indented` gate) AND is a normal (prefix-matched) continuation, not a LAZY one (on a lazy line
        // cmark opens blocks against an ancestor of the paragraph, so `try_opening_table_block` never sees a
        // PARAGRAPH parent and the table never opens). Its leading whitespace / laziness are gone by the time
        // content reaches here, so consult what was recorded during block parsing (`paragraphSecondLineIndent`
        // / `paragraphSecondLineLazy`); an over-indented or lazy delimiter row stays a paragraph continuation,
        // as in cmark.
        let tablePending = storage.options.contains(.tables) && (paragraphTablePending[node] ?? false)
        precondition(!tablePending || (paragraphSecondLineIndent[node] != nil && paragraphSecondLineLazy[node] != nil), "a table-pending paragraph recorded its second line's indent and laziness when that line arrived")
        if tablePending && paragraphSecondLineIndent[node]! < 4 && !paragraphSecondLineLazy[node]! {
            // cmark's header is the raw paragraph content (never ref-def-stripped), so the table parser sees
            // the content before `parseDefinitions` touches it.
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
            // Whole paragraph was ref-defs, or a task list item marker - drop the empty paragraph node.
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
            // Mirror cmark's finalize end-position cases (src/blocks.c:309-337): the block ends on the CURRENT line at EOF, for the document / fenced code, for a setext heading, or for a block that opened on this same line (e.g. an ATX heading finalized immediately); otherwise it ends on the PREVIOUS line (the last line that was actually part of it).
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
                // cmark's chop_trailing_hashtags shrinks the line chunk before `last_line_length` is recorded (src/blocks.c), so a block later attributed to this line - notably the document, whose end is stamped from the final line - inherits the trimmed extent, not the raw line end. Mirror that by shrinking the tracked current-line end to the heading's content end.
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
                    // Flatten for the chunk-based matchers, capturing the arena→source run map so a continuation line's inline content is still stamped (matchers that survive re-seed the map via `runParagraphMatchers`).
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
                // An ATX heading's content range already excludes its surrounding spaces and tabs.
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
            // Body lines accumulate as zero-copy source segments (same as code blocks). Normalize: ensure a single trailing `\n` (cmark).
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
            // A label's winning definition is the first to close: cmark's
            // `process_footnotes` (blocks.c) registers definitions on the tree walk's EXIT events and
            // `sort_map` (map.c) keeps the earliest-registered one, so a definition nested in a
            // same-label definition (`[^b]:[^b]:A`) wins over its encloser. Blocks close in that
            // post-order: a container closes only after all its children have.
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

    /// Normalize an HTML block's accumulated body segments: ensure a single trailing `\n` (matching cmark).
    private func normalizeHTMLBlockSegments(_ segs: inout UniqueArray<Segment>) {
        let nl = storage.newlineSegment
        precondition(segs.count > 0 && segs[0] != nl, "an HTML block's body starts with its opening line, which is never empty")
        if segs[segs.count - 1] != nl {
            segs.append(nl)
        }
    }

    /// Normalize a code block's accumulated body segments (CommonMark 0.31 §4.4) without copying the line bodies.
    ///
    /// Drops the leading separator our accumulator inserts before the first fenced line, strips trailing blank lines for indented code, and ensures the body ends with exactly one `\n` (an empty fenced body stays empty).
    ///
    /// The list alternates body-line content segments with the shared `newlineSegment`. Content segments never contain a `\n` (lines are split on newlines), so `\n` occurs only at separator positions - the list is isomorphic to "lines separated by `\n`".
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
        // Ensure a single trailing newline. For fenced code, re-add the separator we conceptually moved from the leading strip (so a block ending on a blank line keeps that blank).
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

    /// Walk the leading whitespace of `range` once, computing the first-non-space offset, the indent column width (CommonMark's 4-column tab rule), the blank-line flag, and the first content byte.
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

    /// Count the column-width of the leading whitespace `start..<end` per CommonMark's 4-column tab rule: a tab advances the column to the next multiple of 4.
    /// `baseColumn` is the true column of `start` (default 0, i.e. `start` is a line's own left edge).
    /// It must be supplied explicitly when `start` sits mid-tab after an ancestor partially consumed
    /// that tab's leading columns (cmark's `partially_consumed_tab`): a tab's expansion depends on the
    /// column it starts at, so measuring from an assumed column 0 would recompute the REMAINING tab as
    /// a fresh 4-column tab instead of the columns actually left over.
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

    /// Pre-expand tabs that appear in the line's "marker prefix" - leading whitespace plus blockquote (`>`) and list (`-`, `+`, `*`, digits + `.`/`)`) markers.
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
    /// Thematic break / list bullet (`-` `_` `*` `+`), ATX (`#`), fence (`` ` `` `~`), block quote (`>`), HTML (`<`), and ordered-list digits. If a line's first non-space byte isn't one of these, no block matcher can match it, so it can't interrupt an open paragraph.
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
        /// The heading's source end, as a line-offset in `matchATXHeading`'s coordinate space (same as `firstNonSpace`), to be mapped through `sourceOffset`. cmark ends an ATX heading at its trimmed content, not the physical line: non-empty content ends at the trimmed content; empty content whose closing `#` sequence was stripped ends just past the opening `#`s; otherwise (empty, no closing run) it ends at the raw line end.
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

    /// Try to match a list marker at `firstNonSpace` within `range`. CommonMark 0.31 §5.2:
    /// - Bullet: one of `-`, `+`, `*` followed by a space, tab, or end of line.
    /// - Ordered: 1-9 ASCII digits, then `.` or `)`, then space/tab/end.
    /// `≤3` leading spaces; markers immediately at end-of-line are valid (empty item).
    ///
    /// `lineStart` is the physical line start; the marker's absolute column (needed for tab-stop math in
    /// the padding run) is `columnWidth(lineStart, firstNonSpace)`.
    ///
    /// `indent` is the marker's leading indent in COLUMNS, measured from the column the enclosing prefixes
    /// reached (cmark's `parser->indent`, stored as the item's `marker_offset`; blocks.c `open_new_blocks`).
    /// A byte count would under-measure a tab before the marker, including a tab an enclosing `>` left
    /// partially consumed.
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
        // run after the marker is measured in COLUMNS from here so a tab counts to its next tab stop -
        // cmark's `parse_list_marker` (blocks.c) advances columns, not bytes.
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
            // CommonMark §5.2 / cmark `parse_list_marker`: measure the whitespace run after the marker in
            // COLUMNS (tab stops at 1,5,9,…). With 1–4 columns the content column is the first non-blank
            // char's column. With ≥5 columns (or an all-blank line after the marker) only ONE optional
            // column is consumed and the rest becomes content (an indented code block within the item);
            // when that one column falls on a TAB wider than a column it is only PARTIALLY consumed, so
            // the tab byte stays at the content start and its leftover columns surface later (cmark's
            // `partially_consumed_tab`; blocks.c `add_line`).
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
            // `k` sits at the first non-whitespace byte or the line end (the run was scanned in full), so
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

    /// Tag names that trigger an HTML block of type 6, sorted alphabetically, as UTF-8 bytes. CommonMark 0.31 §4.6.
    ///
    /// The HTML-block matchers compare these byte by byte for every candidate line, so they're stored as arrays rather than strings, whose UTF-8 view is slower to index in those loops.
    private static let htmlBlockType6Tags: [[UInt8]] = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body",
        "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header",
        "hr", "html", "iframe", "legend", "li", "link", "main", "menu",
        "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param",
        "search", "section", "summary", "table", "tbody", "td", "tfoot", "th",
        "thead", "title", "tr", "track", "ul",
    ].map { Array($0.utf8) }

    /// Tag names that trigger an HTML block of type 1 (their *closing* tag also ends the block), as UTF-8 bytes.
    private static let htmlBlockType1Tags: [[UInt8]] = [
        "pre", "script", "style", "textarea",
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
    /// CommonMark 0.31 §4.6.
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
        // case-SENSITIVELY per CommonMark start condition 5.
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
        // Type 4: `<!` followed by an uppercase ASCII letter (CommonMark start condition 4).
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

        // Type 1: pre/script/style/textarea (open tag only - closing tag goes to type 6 since `</pre>` etc. don't fit type 1's start condition either way).
        if !isClosing {
            for tag in Self.htmlBlockType1Tags {
                if bytesEqualASCIICaseInsensitive(span: source, range: nameRange, target: tag) {
                    // Must be followed by a spacechar (`[ \t\v\f\r\n]`, cmark's `(spacechar | [>])`), `>`, or EOL.
                    if nameEnd >= range.upperBound { return 1 }
                    let follow = source[nameEnd]
                    if follow.isASCIISpace || follow == UInt8(ascii: ">") {
                        return 1
                    }
                    // A disqualifying follow char (e.g. `/` in `<script/>`) means this is not a type-1
                    // start, but cmark's scanner backtracks and still tries type 6/7 - the tag may be a
                    // complete open tag followed only by EOL (type 7). Fall through rather than aborting.
                    break
                }
            }
        }

        // Type 6: block-tag-name list.
        for tag in Self.htmlBlockType6Tags {
            if bytesEqualASCIICaseInsensitive(span: source, range: nameRange, target: tag) {
                // Must be followed by a spacechar (`[ \t\v\f\r\n]`), `>`, `/>`, or EOL (cmark's `(spacechar | [/]? [>])`).
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
                    // Unquoted value: `[^ \t\r\n\v\f"'=<>` \x00]+`. Any spacechar terminates it, matching cmark's `unquotedvalue` and the inline scanner.
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
                    // The `+` requires at least one character: an empty unquoted value (`<a b=>`, `<a b= >`) is not a valid tag, so this is not a type-7 HTML block. Mirrors the inline scanner's `count == 0` guard.
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

    /// Skip a run of HTML `spacechar` bytes (`[ \t\v\f\r\n]`, i.e. `UInt8.isASCIISpace`) - cmark's tag-whitespace class (scanners.re), shared with the inline HTML scanner so block and inline agree on what separates tag parts.
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
        var i = start
        while i < end {
            let b = span[i]
            // cmark's type-7 start allows only `[\t\n\f ]` after the tag (scanners.re): space, tab, form feed. Vertical tab is deliberately NOT here - it is a `spacechar` inside a tag but not trailing whitespace, so `<a>\u{0B}` stays a paragraph while `<a>\u{0C}` is an HTML block.
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t")
                && b != UInt8(ascii: "\n") && b != UInt8(ascii: "\r")
                && b != 0x0C {
                return false
            }
            i += 1
        }
        return true
    }

    /// Check whether a line satisfies the end condition for an HTML block of the given type. The check looks for the closing pattern *anywhere* on the line (per CommonMark 0.31 §4.6).
    private func htmlBlockLineMatchesEndCondition(type: UInt8, source: Span<UInt8>, range: Range<Int>) -> Bool {
        switch type {
        case 1:
            // `</pre>`, `</script>`, `</style>`, or `</textarea>` (case-insensitive).
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

    /// Try to match a block-quote marker at `firstNonSpace`. CommonMark 0.31 §5.1: up to 3 leading spaces, then `>`, then optionally one space or tab. Returns the offset just past the consumed marker, or `nil` if no match.
    ///
    /// `baseColumn` is the true column of `range.lowerBound` (default 0). It must be supplied when
    /// `range.lowerBound` sits mid-tab because an ancestor marker on THIS line already partially consumed
    /// that tab's leading columns (cmark's `partially_consumed_tab`) - otherwise `indentColumns` below would
    /// measure the tab's REMAINING columns as if it started fresh at column 0.
    private func matchBlockQuoteMarker(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, baseColumn: Int = 0) -> Int? {
        // cmark gates the block-quote marker on `parser->indent <= 3`, an indent measured in COLUMNS
        // (`parse_block_quote_prefix` / `open_new_blocks`; blocks.c). Leading whitespace is byte-identical to
        // its column width unless it contains a tab, which only reaches here on a fenced-code body line - every
        // other line pre-expands its prefix tabs to spaces (`expandPrefixTabs`). A tab spans up to four
        // columns, so a byte count would under-measure it and wrongly admit a `>` cmark rejects (e.g. `\t>`
        // inside an open block quote's fenced code: 4 columns of indent, not a continuation marker).
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
    /// The optional character after `>` is consumed as ONE COLUMN (cmark's `S_advance_offset(parser, input,
    /// 1, true)`, blocks.c). A tab there is fully consumed only when its tab stop is one column away; a
    /// wider tab is partially consumed (`partially_consumed_tab = chars_to_tab > count`), so the cursor
    /// stays on the tab byte while the column moves one past `>`. Callers rely on a cursor left on a tab
    /// having a column strictly inside that tab: measuring from a column already at the tab's stop would
    /// recount the whole tab as four fresh columns.
    private func blockQuotePrefixEnd(source: Span<UInt8>, lineStart: Int, markerEnd: Int, advanced: Int) -> (cursor: Int, column: Int) {
        let markerEndColumn = columnWidth(source: source, from: lineStart, to: markerEnd)
        if advanced == markerEnd + 1, source[markerEnd] == UInt8(ascii: "\t"), 4 - (markerEndColumn & 3) > 1 {
            return (markerEnd, markerEndColumn + 1)
        }
        return (advanced, columnWidth(source: source, from: lineStart, to: advanced))
    }

    /// Try to match an opening fenced code-block line. CommonMark 0.31 §4.5.
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
        while infoStart < range.upperBound
            && (source[infoStart] == UInt8(ascii: " ") || source[infoStart] == UInt8(ascii: "\t")) {
            infoStart += 1
        }
        var infoEnd = range.upperBound
        while infoEnd > infoStart
            && (source[infoEnd - 1] == UInt8(ascii: " ") || source[infoEnd - 1] == UInt8(ascii: "\t")) {
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

    /// Try to match a closing fence line: at most 3 COLUMNS of leading indentation, then a run of the
    /// same fence character at least as long as the opening fence, then only trailing whitespace.
    /// CommonMark 0.31 §4.5. The indent is measured in columns (cmark's `parser->indent <= 3`), where a
    /// tab advances to the next tab stop, so a tab-led line (4 columns) fails the test and stays content.
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

    /// Strip up to `maxColumns` COLUMNS of leading whitespace from a fenced-code continuation line,
    /// tab-stop-aware, mirroring cmark's `parse_code_block_prefix` (blocks.c) which advances
    /// `fence_offset` columns. `startColumn` is the absolute column at `range.lowerBound` (0 for a
    /// top-level fence; the consumed container-prefix width when the fence is nested) so a tab's width is
    /// measured from the correct tab stop.
    ///
    /// Returns the source offset where the surviving content begins and the number of leading spaces a
    /// tab straddling the boundary contributes: cmark's `partially_consumed_tab` (blocks.c `add_line`)
    /// drops such a tab's byte and emits its leftover columns as spaces before copying the rest of the
    /// line verbatim. A non-straddling strip returns `leadingSpaces == 0` and stays a zero-copy slice.
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
                    // remainder as spaces, dropping the tab byte (cmark's partially_consumed_tab).
                    return (i + 1, width - (maxColumns - consumed))
                }
            } else {
                break
            }
        }
        return (i, 0)
    }

    /// The absolute column reached after `source[from..<to]`, per cmark's tab-stop rule: a tab advances
    /// to the next multiple of 4, every other byte counts as one column. Unlike `indentColumns` this does
    /// NOT stop at the first non-whitespace byte - it measures the full column width of an already-consumed
    /// prefix (container markers included), matching cmark's absolute `parser->column` after prefix matching.
    private func columnWidth(source: Span<UInt8>, from: Int, to: Int) -> Int {
        var column = 0
        for i in from..<to {
            column += source[i] == UInt8(ascii: "\t") ? 4 - (column & 3) : 1
        }
        return column
    }

    /// Try to match a setext heading underline at `firstNonSpace` within `range`. CommonMark 0.31 §4.3.
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

    /// Try to match a thematic break starting at `firstNonSpace` within `range`. CommonMark 0.31 §4.1.
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

    /// Try to match an ATX heading. CommonMark 0.31 §4.2.
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

        // cmark ends the heading at its trimmed content extent, not the raw line (src/blocks.c stamps `end_column` from the stripped content). Three cases, using the offsets already computed above:
        //   1. non-empty content        → the content end (trailing spaces and the optional closing `#` run already excluded).
        //   2. empty content, closing `#` run removed → the marker end `i` (just past the opening `#`s, before the space skip).
        //   3. empty content, no closing run          → the raw line end (unchanged from prior behavior).
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
    /// A list is loose per CommonMark §5.3 if any item directly contains two block-level children separated by a blank line - i.e., the item has more than one block child AND a blank line was observed inside it. (The other criterion - a blank line between sibling items - is case (a) below.)
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

    /// Match a GFM footnote definition opener `[^label]:` at `firstNonSpace` on the current line.
    ///
    /// The label is `[^` followed by one or more bytes that are none of `]`, space, tab, CR, LF, or
    /// NUL (cmark's `_scan_footnote_definition`), then `]:` and optional trailing spaces/tabs.
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
            // cmark replaces NUL with U+FFFD before scanning, so its scanner (which excludes NUL)
            // never rejects a source NUL — the replacement character is an allowed label byte. The
            // zero-copy scanner reads the raw NUL here, so it must NOT reject it, matching cmark; the
            // NUL surfaces as U+FFFD wherever the label is materialized.
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
        // Materialize NUL -> U+FFFD in the label so its stored form and map key match the reference
        // side, whose paragraph content is NUL-replaced before inline parsing (cmark replaces NUL in
        // the whole input buffer, so a `[^<NUL>]` definition and a `[^<NUL>]` reference share the
        // U+FFFD-normalized key).
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
    // CommonMark 0.31 §4.7. A definition has the form:
    //
    // ``` [label]: destination optional-title ```
    //
    // With `.attributes`, the extended-attribute reference form `^[label]: attrs` is recognized in the same loop and stored separately on `DocumentStorage.attributeReferenceMap`.
    //
    // Multiple definitions may stack consecutively at the start of a paragraph. After consuming all that match, the remaining (possibly blank) content is returned for the inline parser to handle. If everything was consumed, a block-mode caller is expected to detach the paragraph node from its parent (the inline-only path keeps it, as cmark does).

    /// Repeatedly consume `[label]: dest "title"` definitions, and with `.attributes` `^[label]: attrs` definitions, from the start of `chunk`.
    ///
    /// Each successful match registers the entry in the appropriate refmap on `storage` (first definition wins per spec) and advances the cursor. Returns the remaining chunk after the last consumed def.
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
        // why: cmark's `manual_scan_link_url` / `manual_scan_link_url_2` (src/inlines.c) reject a
        // destination that reaches the end of their input (`if (i >= input->len) return -1;`). Block-mode
        // paragraph content always ends in a newline, so only inline-only content - whose final line
        // `cmark_parser_finish` leaves unterminated (`ensureEndsInNewline` is off when the
        // `CMARK_OPT_PRESERVE_WHITESPACE` mask matches, which a bare `CMARK_OPT_INLINE_ONLY` also does) -
        // hits it, leaving e.g. a lone `[a]: /u` literal while `[a]: /u "t"` is consumed. Inline-only mode
        // has no spec and its clients (Foundation's AttributedString inline modes) shipped on cmark, so this
        // applies in both flag states rather than silently dropping the text of such a definition.
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
        // `normalizeLabel` folds a NUL in the label to U+FFFD itself (CommonMark §2.3), matching the
        // reference side's key even though this definition may be keyed straight from the
        // setext-underline path's pre-`drainLeaf` content (PHASE 2c reads `materializePendingContent`
        // directly, before the leftover heading text is drained through `drainLeaf`'s own NUL
        // replacement) - the label never needs its own arena materialization here.
        let key = normalizeLabel(
            chunk: label.interior
        )
        if key.isEmpty {
            return nil
        }
        if storage.referenceMap[key] == nil {
            // CommonMark §2.3: a NUL in the destination/title becomes U+FFFD. Ref-defs are parsed
            // straight from the (possibly still source-backed) paragraph content on both the normal
            // (`runParagraphMatchers`) and the setext-underline (`processLine`) paths, so normalize here -
            // the single point every stored definition passes through.
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

    /// Try to parse exactly one `^[label]: attrs` form (fork-specific extended-attribute definition).
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
            // cmark stores the value through `cmark_clean_attributes`, which is `cmark_clean_url`
            // (swift-cmark `src/inlines.c`): trimmed and unescaped, like a link ref-def destination.
            // CommonMark §2.3: a NUL in the stored attributes becomes U+FFFD, symmetric with the link
            // ref-def store above. Parsed straight from the (possibly source-backed) content, so normalize
            // here.
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
    /// autolink form, where CommonMark §6.5 disables backslash escapes but §6.2 still recognizes references.
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

    /// Clean a link destination the way cmark's `cmark_clean_url` does (`src/inlines.c`): trim
    /// surrounding whitespace, then remove backslash escapes / decode entities. Interior whitespace is
    /// preserved. The trim is cmark's `cmark_chunk_trim` over the `cmark_isspace` set — exactly
    /// {space, tab, `\n`, `\r`} (the `cmark_ctype_class` class-1 bytes; VT/FF are NOT whitespace) —
    /// which is `Chunk.trimming(using:)`'s `isSpaceTabOrNewline`. Only DESTINATIONS are cleaned this
    /// way; titles use cmark's `cmark_clean_title`, which does NOT trim, so the title path calls
    /// `unescapeURLChunk` directly instead.
    mutating func cleanURLChunk(_ chunk: Chunk) -> Chunk {
        let trimmed = chunk.trimming(using: self)
        return unescapeURLChunk(trimmed)
    }
}

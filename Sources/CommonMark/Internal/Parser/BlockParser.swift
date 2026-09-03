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

    /// Bounds container-nesting depth (open block-quote/list ancestors) as a DoS guard.
    ///
    /// The parser throws `parsingLimitExceeded` rather than building an unbounded-depth tree that could overflow a recursive consumer.
    static let maxContainerNesting = 256

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

    /// Either a single source-range slice (`.lazy`, addressable directly into `BlockParser.source` with no copy) or a materialized byte buffer (`.materialized`, populated when the content needed synthesized newlines, came from a tab-expanded line, or was further appended to).
    ///
    /// Single-line paragraphs/headings parsed from the original source stay `.lazy` until `materializePendingContent` emits them as a `Chunk(inSource: true)`.
    ///
    /// `.lazyNewline` is the deferred-separator state: a continuation `\n` was requested after a `.lazy` span but not yet committed, so that if the *next* line turns out to be contiguous in source (single-LF terminated, no stripped prefix) the whole multi-line run can stay a single zero-copy source range - the embedded `\n` comes from the source itself rather than a synthesized copy.
    enum PendingContent : ~Copyable {
        case lazy(range: Range<Int>)
        case lazyNewline(range: Range<Int>)
        case materialized(UniqueArray<UInt8>)
        /// An ordered segment list.
        ///
        /// Used for code/HTML block bodies: each body line is a zero-copy source `Segment` (or an arena copy for a non-source-mapped, e.g. tab-expanded, line) and each line join is the shared `newlineSegment`. Drained at finalize into a multi-segment `ContentRef` with no source bytes copied. Only produced for nodes that are never inline-parsed (`.codeBlock` / `.htmlBlock`).
        case segments(UniqueArray<Segment>)
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

    /// For a tab-expanded (materialized) line, the buffer offset where `expandPrefixTabs`'s verbatim tail begins, and the corresponding original-line byte offset. Since the tail is copied byte-for-byte, every content offset in it maps back to source by the constant delta `currentLineSourceRange.lowerBound + materializedRestStart - materializedTailBufferStart`; offsets inside the expanded prefix are recovered by a column walk on the original line. Only meaningful while `!currentLineMapsToSource` (see `sourceOffset` for the positions path and `materializedSourceStart` for the positions-independent code-content path).
    var materializedTailBufferStart: Int = 0
    var materializedRestStart: Int = 0

    /// `true` when `.sourcePosition` tracking is on.
    ///
    /// Hoisted so the per-node stamping in `addChild` and `finalize` is a single bool test on the hot path when positions are off.
    let positionsEnabled: Bool

    /// Original-source byte range of the line currently being processed, tracked for every line (positions on or off). Used to stamp block end positions at finalize time and to recover a materialized code/HTML body line's literal source bytes. `lastLineSourceEnd` keeps the previous line's content end so a block closed by a *later* line can attribute its end to the line it actually ended on.
    var currentLineSourceRange: Range<Int> = 0..<0
    var lastLineSourceEnd: Int = 0

    /// The open leaf's `block_offset`: the byte distance from a line's start to the block's content column, established from the leaf's FIRST line and held for the block's lifetime.
    ///
    /// A paragraph continuation line's inline content is re-indented to this column: cmark fixes `block_offset` at the paragraph's first-line content column (`start_column - 1`) and reports EVERY *matched* continuation line's surviving content there, discarding each line's own leading whitespace. So a matched continuation segment maps its source to `currentLineSourceRange.lowerBound + currentContentIndent` (the bytes are still read from their true offset). It equals a continuation line's own content column only when the first line has no indentation beyond its container marker (the common case), so this is usually a no-op. A *lazy* continuation is the exception - cmark keeps the residual whitespace after the last matched prefix (see `currentLineIsLazyContinuation` / `currentLineContentCursor`). Set in `addLine` when a leaf's first line is accumulated; consumed by `addLineSegment`. Code/HTML bodies preserve their true offset instead.
    var currentContentIndent: Int = 0

    /// `true` when the line currently being processed is a *lazy* paragraph continuation: at least one open container's continuation prefix failed to match on this line (a block quote with no `>`, or a list item indented less than its content column), so the container-prefix walk stopped short of the open leaf. Set per line in `processLine` from the walk's `allMatched`; consumed by `addLineSegment` under `.cmarkBugCompatibility`.
    ///
    /// cmark strips a *matched* paragraph continuation's leading whitespace - it advances the line offset to the first non-space (`add_text_to_container`'s `accepts_lines` branch, blocks.c:1465) before adding the line - but a *lazy* continuation is added straight from the offset where prefix matching stopped (`add_line(parser->current, …)`, blocks.c:1408), so the residual whitespace between that stopping point and the first non-space survives in the content and shifts the reported column right. The inline parser then maps a continuation line's first content byte to `residual + block_offset + 1` columns (blocks.c/inlines.c `handle_newline`), where `residual` is the leading-space count in the added content. So a lazy continuation re-indents to `currentLineContentCursor`-relative residual plus the block-content column; a matched continuation discards its residual and re-indents to the block-content column outright.
    var currentLineIsLazyContinuation: Bool = false

    /// The byte offset into the current line where container-prefix matching stopped (the walk's `cursor`): the point past every *matched* container prefix, from which cmark measures a lazy continuation's residual whitespace. Set per line in `processLine`; consumed by `addLineSegment` only for a lazy continuation, where the preserved residual is `range.lowerBound - currentLineContentCursor` (the un-consumed leading whitespace after the last matched prefix). For a matched continuation the residual is discarded, so this is unused.
    var currentLineContentCursor: Int = 0

    /// Inline-parsing tasks deferred until after all block parsing completes.
    ///
    /// This delay is what lets a `[foo]` shortcut reference resolve against a `[foo]: url` ref-def that appears later in the document. Each entry is a `(node, content chunk)` pair: when the parse pass finishes, `BlockParser.parse` drains this list and invokes `InlineParser.parse` on each.
    var pendingInlines: [(DocumentStorage.Index, ContentRef)] = []

    /// Arena→source run maps for flattened inline content that has a source pre-image, keyed by the content's node.
    ///
    /// Populated only for a non-contiguous setext heading (PHASE 2c): its content is flattened into one arena `Chunk` by `flattenSegments`, which drops the per-line source mapping the segments carried. The run map (content-relative, so it survives the re-seed's arena re-copy) lets the inline pass stamp the heading's text/emphasis with real source positions instead of leaving them unstamped. Consulted in the inline pass when building an arena single-segment `ContentSpan`.
    var arenaSourceMaps: [DocumentStorage.Index: [ArenaRun]] = [:]

    /// List-item nodes whose GFM task-list checkbox is eligible for recognition: the item's list marker
    /// is preceded on its own physical line by only whitespace (`taskMarkerLineAnchored`), cmark's
    /// `scan_tasklist` condition. This is a PHYSICAL-LINE property, not block-nesting depth: a
    /// block-nested item that sits alone on its own (indented) line still qualifies, while an item whose
    /// line carries a block-quote `>` or an outer list marker before this marker does not. Recorded at
    /// item-open time, where the marker's line context is available, and consulted by the two
    /// finalize-time consumers - the checkbox strip in `runParagraphMatchers` and the continuation
    /// re-indent bump in `tasklistContentIndentBump` - so an item sharing its line with a `>` or an outer
    /// marker keeps its `[ ]`/`[x]` as literal paragraph text and re-indents like a plain bullet. (Empty
    /// task items are consumed at open time in `emptyTaskItemChecked`; this set carries the
    /// content-bearing case to finalize.)
    var lineAnchoredTaskItems: Set<DocumentStorage.Index> = []

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

    /// The deepest list that has seen a blank line since its last item boundary.
    ///
    /// When a new item is added to that list (i.e., the blank line was between sibling items), the list gets marked loose. Cleared on each item open after the check, and stays stale (but harmless) when the list closes.
    var pendingLooseList: DocumentStorage.Index? = nil

    // MARK: - Inline code-span backtick-closer cache (cmark bug-compat)

    /// Longest backtick run for which the closer cache holds a slot - cmark's `MAXBACKTICKS`. A run longer than this is never a code-span opener (`matchCodeSpan` step 1) and is never recorded.
    static let codeSpanMaxBacktickRun = 80

    /// `true` once a closing-backtick scan in the current `parseInline` pass has run to the content end without finding a closer - cmark's `subject.scanned_for_backticks`. Once set, a later open of a length whose cached run-start lies at/before the open short-circuits (the stale-cache code-span miss). Meaningful only flag-ON (`.cmarkBugCompatibility`); reset per pass.
    var codeSpanScannedForBackticks = false

    /// Per-run-length cache of the latest backtick run START offset a closing scan has passed - cmark's `subject.backticks[]`, indexed by run length (1...`codeSpanMaxBacktickRun`; index 0 unused). Combined with `codeSpanScannedForBackticks`, a stored value `<=` a new opener's post-run offset means "no closer of this length at/after here" and skips the rescan. Offsets are `ContentSpan` (content/virtual) offsets, the same space the closing scan walks. Meaningful only flag-ON; reset per pass.
    var codeSpanBackticks = [Int](repeating: 0, count: BlockParser.codeSpanMaxBacktickRun + 1)

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
        // The document root spans the whole source; its start is byte 0 (1:1). Its end is stamped at EOF finalize.
        self.storage.setSourceStart(documentIndex, 0)
    }
    
    // MARK: - Parse
    
    consuming func parse() throws (MarkdownDocument.Error) -> DocumentStorage {
        // Inline-only modes (`.inlineOnly` / `.preserveWhitespace`) bypass block structure entirely.
        if storage.options.contains(.inlineOnly) {
            try parseInlineOnly()
            return storage
        }

        var reader = LineReader(source: sourceBytes)

        // One reused buffer for the open-container ancestor chain that `walkOpenContainers` rebuilds per line. Heap-backed and reserved once to the nesting limit; reset (keeping capacity) per line. The single open leaf's accumulated content (`pending`) is `~Copyable`, threaded by move through the per-line dispatch and drained to `nil` by the EOF-finalize loop below.
        var chain = UniqueArray<DocumentStorage.Index>(minimumCapacity: Self.maxContainerNesting)
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
                // Tracked unconditionally: recovering a materialized code/HTML body line's literal source bytes (`appendMaterializedCodeContent`) needs the current line's source range even when positions are off, since code content must preserve tabs regardless of `.sourcePosition`.
                currentLineSourceRange = lineRangeInOriginalSource
                
                // Per-line materialized buffer used when a line's leading tabs need to be expanded into spaces so partial-tab consumption by container markers works correctly.
                if !inFencedCode, let materialized = expandPrefixTabs(line: line) {
                    currentLineMapsToSource = false
                    materializedTailBufferStart = materialized.tailBufferStart
                    materializedRestStart = materialized.restStart
                    let span = materialized.buffer.span
                    pending = try processLine(source: span, lineRange: 0..<span.count, chain: &chain, pending: pending)
                } else {
                    currentLineMapsToSource = true
                    pending = try processLine(source: sourceBytes, lineRange: lineRangeInOriginalSource, chain: &chain, pending: pending)
                }
            }

            // EOF: finalize all open blocks back up to the document root. Runs inside this closure (it doesn't touch `chain`) so `pending` stays local - by the end every leaf is drained and `pending` is `nil`.
            while current != documentIndex {
                pending = try finalize(node: current, pending: pending, atEOF: true)
            }
            
            // The document root is never passed to `finalize`; stamp its end (whole-source span) here. A truly-empty document (no lines) is left unstamped so it reports no source range - cmark emits `1:1-0:0` for empty input, which downstream treats as "no position".
            if positionsEnabled, reader.lineNumber > 0 {
                storage.setSourceEnd(documentIndex, currentLineSourceRange.upperBound)
            }
        }

        // Inline-parsing pass: with all blocks closed (and `storage`'s `referenceMap` / `attributeReferenceMap` / `footnoteMap` fully populated), run inline parsing for every paragraph and heading queued during finalize. Forward references like `[foo]\n\n[foo]: url` resolve correctly because the def is in the map by the time the ref's paragraph is parsed.
        let pending = pendingInlines
        
        var delimiters = UniqueArray<DelimiterRecord>()
        var brackets = UniqueArray<BracketRecord>()
        
        // Reused scratch buffers: `scratch` holds an arena-content copy while it is parsed; `segScratch` holds a stable copy of a multi-segment content's segment list (the live `storage.segments` pool grows as `parseInline` interns node content); `runScratch` holds a stable copy of a flattened block's arena→source run map. All owned here so their borrow is independent of the `storage` mutations `parseInline` performs.
        var scratch = UniqueArray<UInt8>()
        var segScratch = UniqueArray<Segment>()
        var runScratch = UniqueArray<ArenaRun>()
        
        for (node, ref) in pending {
            if ref.count == 0 || ref.totalLength == 0 {
                continue
            }
            if ref.count == 1 {
                let chunk = storage.segments[Int(ref.first)].chunk
                if chunk.inSource {
                    // Source-backed: zero-copy slice of the source span.
                    try parseInline(
                        content: ContentSpan(span: sourceBytes.extracting(chunk.range), base: chunk.offset, inSource: true),
                        into: node,
                        delimiters: &delimiters,
                        brackets: &brackets
                    )
                } else {
                    // Arena-backed: copy the content region out of `storage.strings` so the read view is independent of the appends `parseInline` makes to that same array.
                    scratch.removeAll(keepingCapacity: true)
                    do {
                        storage.strings.span.extracting(chunk.range).withUnsafeBufferPointer { buffer in
                            scratch.append(copying: buffer)
                        }
                    }
                    // Flattened content (a non-contiguous setext heading) carries an arena→source run map so its inlines still get source positions; plain arena content (no map) parses unmapped as before.
                    if let map = arenaSourceMaps[node], !map.isEmpty {
                        runScratch.removeAll(keepingCapacity: true)
                        for run in map {
                            runScratch.append(run)
                        }
                        try parseInline(
                            content: ContentSpan(span: scratch.span, base: chunk.offset, inSource: false, arenaRuns: runScratch.span),
                            into: node,
                            delimiters: &delimiters,
                            brackets: &brackets
                        )
                    } else {
                        try parseInline(
                            content: ContentSpan(span: scratch.span, base: chunk.offset, inSource: false),
                            into: node,
                            delimiters: &delimiters,
                            brackets: &brackets
                        )
                    }
                }
            } else {
                // Multi-segment content (multi-line non-contiguous paragraph/heading): copy the segment list into stable storage and parse it directly from the source - no flattening into the arena.
                segScratch.removeAll(keepingCapacity: true)
                for i in 0..<Int(ref.count) {
                    segScratch.append(storage.segments[Int(ref.first) + i])
                }
                try parseInline(
                    content: ContentSpan(source: sourceBytes, segments: segScratch.span, virtualLength: Int(ref.totalLength)),
                    into: node,
                    delimiters: &delimiters,
                    brackets: &brackets
                )
            }
            
            // Coalesce adjacent text nodes so smart-punct / entity substitutions don't leave the content split across sibling text nodes.
            consolidateTextNodes(node)
        }

        storage.lineCount = reader.lineNumber
        return storage
    }

    /// Inline-only parse path for `.inlineOnly` / `.preserveWhitespace`.
    ///
    /// Bypasses block structure completely: the entire input becomes a single `.paragraph` whose content is the source with a leading UTF-8 BOM skipped and line endings normalized to `\n`, but with every other byte preserved verbatim - leading indentation, interior space runs, trailing spaces, and all newlines (including a trailing one). Markers like `#`, `* `, `> `, fences and 4-space indents stay literal text; only *inline* syntax (emphasis, code spans, links, autolinks, …) is parsed, and even newlines remain literal text rather than becoming soft/hard breaks.
    private mutating func parseInlineOnly() throws (MarkdownDocument.Error) {
        let count = sourceBytes.count

        // Skip a leading UTF-8 BOM, matching cmark's first-line BOM skip.
        var start = 0
        if count >= 3, sourceBytes[0] == 0xEF, sourceBytes[1] == 0xBB, sourceBytes[2] == 0xBF {
            start = 3
        }

        // Count lines and detect whether any CR needs normalizing to LF, in a single pass that SIMD-skips the runs of content bytes between line breaks (`nextLineBreak`) rather than stepping one byte at a time. The count mirrors cmark's per-line `line_number` (`\r\n`, lone `\r`, and `\n` each count once; a final unterminated line counts as a line). Detecting CR in the same scan is what lets the common LF-only / break-free case stay zero-copy below, addressing the source directly - so line-counting costs no extra pass.
        var hasCR = false
        var lines = 0
        var i = start
        while i < count {
            let brk = i + LineReader.firstLineTerminator(in: sourceBytes.extracting(i..<count))
            if brk == count {
                // Trailing content with no terminator → one final unterminated line.
                lines += 1
                break
            }
            lines += 1
            if sourceBytes[brk] == UInt8(ascii: "\r") {
                hasCR = true
                // A `\r` immediately followed by `\n` is a single CRLF terminator.
                i = (brk + 1 < count && sourceBytes[brk + 1] == UInt8(ascii: "\n")) ? brk + 2 : brk + 1
            } else {
                i = brk + 1
            }
        }
        storage.lineCount = lines

        // Empty input (or BOM-only) yields an empty document with no paragraph, as cmark does.
        guard start < count else {
            return
        }

        let paragraph = addChild(kind: .paragraph, parent: documentIndex)

        var delimiters = UniqueArray<DelimiterRecord>()
        var brackets = UniqueArray<BracketRecord>()
        if !hasCR {
            // Zero-copy: the paragraph content is a source slice; emitted text references the source in place.
            let content = ContentSpan(span: sourceBytes.extracting(start..<count), base: start, inSource: true)
            try parseInline(
                content: content,
                into: paragraph,
                preserveWhitespace: true,
                delimiters: &delimiters,
                brackets: &brackets
            )
        } else {
            // Normalize `\r\n` and lone `\r` to `\n` into the string arena, then read from an independent scratch copy (the inline parser appends to `storage.strings` as it runs).
            let arenaStart = storage.strings.count
            var j = start
            while j < count {
                let byte = sourceBytes[j]
                if byte == UInt8(ascii: "\r") {
                    storage.strings.append(UInt8(ascii: "\n"))
                    if j + 1 < count, sourceBytes[j + 1] == UInt8(ascii: "\n") {
                        j += 1
                    }
                } else {
                    storage.strings.append(byte)
                }
                j += 1
            }
            let arenaEnd = storage.strings.count
            var scratch = UniqueArray<UInt8>()
            storage.strings.span.extracting(arenaStart..<arenaEnd).withUnsafeBufferPointer { buffer in
                scratch.append(copying: buffer)
            }
            let content = ContentSpan(span: scratch.span, base: arenaStart, inSource: false)
            try parseInline(
                content: content,
                into: paragraph,
                preserveWhitespace: true,
                delimiters: &delimiters,
                brackets: &brackets
            )
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
    /// When the line maps to source the passed offset is already a global source offset (the line was processed as a slice of `sourceBytes`). For a tab-expanded (materialized) line, the offset is a transient-buffer offset: `expandPrefixTabs` only rewrites the leading whitespace/marker prefix and copies the rest of the line verbatim, so a tail offset maps back by a constant delta and a prefix offset is recovered by re-walking the original line's prefix (see `originalPrefixSourceOffset`). Returns `nil` for a materialized line when positions are off, since the source-line coordinates it needs (`currentLineSourceRange`) are only tracked then.
    private func sourceOffset(_ lineOffset: Int) -> Int? {
        if currentLineMapsToSource {
            return lineOffset
        }
        guard positionsEnabled else { return nil }
        if lineOffset >= materializedTailBufferStart {
            // Verbatim tail: a single constant delta covers every content offset.
            return currentLineSourceRange.lowerBound + materializedRestStart + (lineOffset - materializedTailBufferStart)
        }
        // Inside the expanded prefix (e.g. an indented-code `bodyStart` landing mid-prefix, or a container marker): re-walk the original prefix to find the byte covering this buffer offset.
        return originalPrefixSourceOffset(bufferOffset: lineOffset)
    }

    /// Map a buffer offset lying inside a materialized line's expanded prefix back to an original-source byte offset.
    ///
    /// Re-walks the original line's prefix (`[lineStart, lineStart + materializedRestStart)`) with the same tab-expansion rule `expandPrefixTabs` used, tracking each byte's span in the expanded buffer, and returns the source offset of the byte whose expansion covers `bufferOffset`. A tab covers its whole `4 - (col & 3)` run, so a buffer offset landing mid-tab resolves to that tab's byte - matching cmark, which reports the raw source byte after consumed indentation. O(prefix).
    private func originalPrefixSourceOffset(bufferOffset: Int) -> Int {
        let lineStart = currentLineSourceRange.lowerBound
        let prefixEnd = lineStart + materializedRestStart
        var col = 0
        var buf = 0
        var i = lineStart
        while i < prefixEnd {
            let width = sourceBytes[i] == UInt8(ascii: "\t") ? 4 - (col & 3) : 1
            if bufferOffset < buf + width {
                return i
            }
            buf += width
            col += width
            i += 1
        }
        // `bufferOffset` is always `< materializedTailBufferStart` here, so the walk covers it; the prefix end is a safe fallback.
        return prefixEnd
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

    /// Consume `content` and materialize it into a `UniqueArray<UInt8>` ready for further appends.
    ///
    /// A `.lazy` entry is copied out of `source`; a `.lazyNewline` entry is copied out plus its deferred trailing `\n`; a `.materialized` entry's buffer is *moved* out (no copy). `nil` yields an empty buffer.
    private func unwrap(_ content: consuming PendingContent?) -> UniqueArray<UInt8> {
        switch consume content {
        case .none:
            return UniqueArray()
        case .lazy(let range)?:
            return UniqueArray(capacity: range.count) { span in
                for i in range {
                    span.append(sourceBytes[i])
                }
            }
        case .lazyNewline(let range)?:
            return UniqueArray(capacity: range.count + 1) { span in
                for i in range {
                    span.append(sourceBytes[i])
                }
                span.append(UInt8(ascii: "\n"))
            }
        case .materialized(let existing)?:
            return existing
        case .segments?:
            // Segment lists are only produced for code/HTML blocks, which never re-seed via this path.
            fatalError("unwrap called on segment-list content")
        }
    }

    /// Append the bytes of `chunk` (which may live in either `storage.strings` or `self.source`) to `pending` for `node`, returning the updated leaf.
    ///
    /// Used when re-seeding a node's content after a transformation step (e.g. setext-heading content trimmed of leading ref-defs).
    private mutating func addChunk(_ chunk: Chunk, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf {
        var buffer = unwrap(take(pending, ifNode: node))
        buffer.reserveCapacity(buffer.count + chunk.length)
        let end = chunk.offset + chunk.length
        if chunk.inSource {
            for i in chunk.offset..<end {
                buffer.append(sourceBytes[i])
            }
        } else {
            for i in chunk.offset..<end {
                buffer.append(storage.strings[i])
            }
        }
        return PendingLeaf(node: node, content: .materialized(buffer))
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
            // First content for this leaf: fix its `block_offset` (the content column) from this line, so any continuation line re-indents to it. `range.lowerBound` is the first-non-space byte; measure its distance from the source line start (via `sourceOffset` for a tab-expanded line). For a task-list item, add the checkbox marker width the tasklist extension consumes at finalize (see `tasklistContentIndentBump`).
            if positionsEnabled, nodeKind.canAccumulateText, let s = sourceOffset(range.lowerBound) {
                currentContentIndent = s - currentLineSourceRange.lowerBound
                    + tasklistContentIndentBump(node: node, span: span, range: range)
            }
            // Fast path: first content for this node and the current line maps directly into `self.source` - store the range lazily and skip the byte copy.
            if currentLineMapsToSource, nodeKind.canAccumulateText {
                return PendingLeaf(node: node, content: .lazy(range: range))
            }
            // Tab-expanded line: map the first-line content back to its literal source range rather than copying the expanded buffer into the arena, so inline stamping recovers real source positions and any content tab stays literal. `expandPrefixTabs` rewrites only the consumed indentation and copies the rest verbatim, so the first non-space content byte maps to a genuine source byte (a marker byte or a tail byte, never inside an expanded tab's spaces) and the content end maps to the source line end. cmark expands tabs only for block-structure indentation and keeps them literal in inline content, so the source range - which carries any interior tab as one byte (one column) - is what matches the reference. This covers both content that maps 1:1 (e.g. the `*` of `*5*` after `*\t`/`>\t`) and content straddling an expanded tab (e.g. `**\tx`, whose doubled marker bytes are inline content that no block marker consumes, so the tab lands inside the paragraph). Gated on positions (the source mapping `sourceOffset` needs is only tracked then).
            if positionsEnabled, nodeKind.canAccumulateText,
               let sourceLow = sourceOffset(range.lowerBound), let sourceHigh = sourceOffset(range.upperBound) {
                return PendingLeaf(node: node, content: .lazy(range: sourceLow..<sourceHigh))
            }
            let buffer = UniqueArray(capacity: range.count) { buffer in
                for i in range {
                    buffer.append(span[i])
                }
            }
            return PendingLeaf(node: node, content: .materialized(buffer))
        case .some(let existing):
            // Contiguity fast path: a `\n` separator was deferred after a `.lazy` span (`appendNewline` left it as `.lazyNewline`). If this line is also source-backed and immediately follows the previous span in the source - i.e. it starts one byte past the previous span and that byte is a single `\n` - then the join needs no synthesized separator: the embedded `\n` already lives in the source, so we keep the whole run as one zero-copy `.lazy` range. This holds for top-level paragraphs with LF line endings and no stripped container prefix; blockquote/list continuation (prefix stripped → non-adjacent range), CRLF/CR (separator isn't a lone `\n` at `prev.upperBound`), and tab-expanded lines (`!currentLineMapsToSource`) all fall through to materialization below.
            //
            // A LAZY continuation line into an indented container (a blockquote/list paragraph with no marker on the continuation line) IS source-contiguous, so it would collapse here and map to its true column. That equals cmark's output only at the top level, where the block-content column is 1; inside an indented container cmark re-indents every continuation line relative to the fixed block-content column (`currentContentIndent`) - the Quirk E re-indent (matched continuations to that column, lazy blockquote continuations to `true_col + block_offset`; see `addLineSegment`). Either target differs from the plain true column the collapse would produce, so flag-ON with a positive content indent is excluded from the collapse and falls through to the segment path below, which re-indents each continuation line via `addLineSegment` (the first line stays a plain source segment at its true column). Flag-OFF and the top-level `currentContentIndent == 0` case keep the zero-copy collapse (spec-correct there anyway).
            switch consume existing {
            case .lazyNewline(let prev) where currentLineMapsToSource
                    && range.lowerBound == prev.upperBound + 1
                    && prev.upperBound < sourceBytes.count
                    && sourceBytes[prev.upperBound] == UInt8(ascii: "\n")
                    && !(storage.options.contains(.cmarkBugCompatibility) && currentContentIndent > 0):
                return PendingLeaf(node: node, content: .lazy(range: prev.lowerBound..<range.upperBound))
            case .lazyNewline(let prev):
                // Non-contiguous continuation (block-quote/list prefix stripped, CRLF, tab): switch to a source-segment list rather than copying bytes - the previous span becomes a zero-copy source segment, joined to this line by the shared interned `\n`.
                var segs = UniqueArray<Segment>()
                segs.append(Segment(offset: Int32(prev.lowerBound), length: Int32(prev.count), inSource: true))
                segs.append(storage.newlineSegment)
                return addLineSegment(span: span, range: range, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
            case .segments(let segs):
                return addLineSegment(span: span, range: range, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
            case let other:
                var buffer = unwrap(other)
                buffer.reserveCapacity(buffer.count + range.count)
                for i in range {
                    buffer.append(span[i])
                }
                return PendingLeaf(node: node, content: .materialized(buffer))
            }
        }
    }

    /// Extra content-indent columns a task-list item contributes to a paragraph's continuation re-indent base.
    ///
    /// A GFM task-list item's checkbox marker (`[ ] ` / `[x] `) is stripped from the item's first paragraph at finalize (`runParagraphMatchers`), which advances the paragraph's own start past the marker but leaves the block-content column - the base every continuation line re-indents to (Quirk E, `addLineSegment`) - fixed at the *plain* item content column (where `[` sits). cmark-gfm fixes that base at the checkbox-adjusted content column instead, so a task-item continuation lands the marker's column-width further right than a plain bullet's would. Add that width here, at the point the base is first fixed, when this leaf is the first paragraph of a list item and its first line begins with a checkbox marker. Returns 0 otherwise (plain bullets, ordered lists, non-item paragraphs), so nothing else moves.
    ///
    /// `currentContentIndent` is a *column* count. A space-separated marker (`[ ] `) is exactly `tasklistMarkerWidth` single-byte columns, so the bump equals its byte width. A TAB-separated marker (`[ ]\t`) is still recognized by `matchTasklistMarker` but its column width is tab-stop-dependent, not its byte width, so it is left to the deferred tab class (see CLAUDE.md "tab after a list marker") rather than bumped with a wrong column count - `require`ing a space separator here keeps the arithmetic column-exact. The recognition otherwise mirrors `matchTasklistMarker` (same `tasklistMarkerChecked` predicate, same first-child-of-item condition, same `lineAnchoredTaskItems` gate so an item whose marker shares its line with a `>` or an outer marker - whose checkbox stays literal - re-indents like a plain bullet), so in the common case - marker on the first line, no preceding ref-def / footnote / table matcher redirecting finalize - the finalize consumption and this re-indent bump agree.
    ///
    /// This bump assumes a SINGLE separator space (`tasklistMarkerWidth`). `matchTasklistMarker` strips the whole post-checkbox whitespace run for the item's first-line CONTENT, so a MULTI-space marker (`[x]  a`) puts the true content column one-plus further right than this bump records - a flag-ON re-indent-base inaccuracy for a multi-space task item's continuation. It is unobservable: source positions are not part of the differential compare surface (see `DiffSupport.newSurface`) and this base is Quirk-E (`.cmarkBugCompatibility`) machinery only; the deliverable's spec-correct positions come from the true column, and no position suite exercises a multi-space task marker.
    private func tasklistContentIndentBump(node: DocumentStorage.Index, span: Span<UInt8>, range: Range<Int>) -> Int {
        guard storage.options.contains(.tasklist),
              storage[node].kind == .paragraph,
              let parent = storage[node].parent,
              case .item = storage[parent].kind,
              storage[parent].firstChild == node,
              lineAnchoredTaskItems.contains(parent),
              range.lowerBound + Self.tasklistMarkerWidth <= range.upperBound,
              Self.tasklistMarkerChecked(
                span[range.lowerBound],
                span[range.lowerBound + 1],
                span[range.lowerBound + 2],
                span[range.lowerBound + 3]
              ) != nil,
              span[range.lowerBound + 3] == UInt8(ascii: " ")   // space separator: byte width == column width
        else {
            return 0
        }
        return Self.tasklistMarkerWidth
    }

    /// Append a single `\n` to `pending` for `node`, returning the updated leaf.
    ///
    /// Used to rejoin lines during paragraph continuation, since `LineReader` returns ranges without their line terminators. When the current content is a `.lazy` source span, the separator is *deferred* into `.lazyNewline` so the next `addLine` can keep the run zero-copy if it's source-contiguous; otherwise the `\n` is committed into a materialized buffer immediately.
    private mutating func appendNewline(to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            return appendSegment(storage.newlineSegment, to: node, pending: pending)
        }
        switch take(pending, ifNode: node) {
        case .lazy(let range)?:
            return PendingLeaf(node: node, content: .lazyNewline(range: range))
        case .segments(let segs)?:
            // A multi-line paragraph already accumulating as segments: the line join is the shared interned `\n` segment (zero-copy), not a byte appended to a materialized buffer.
            return appendSegment(storage.newlineSegment, to: node, pending: PendingLeaf(node: node, content: .segments(segs)))
        case .none:
            return PendingLeaf(node: node, content: .materialized(UniqueArray(repeating: UInt8(ascii: "\n"), count: 1)))
        case .some(let existing):
            var buffer = unwrap(existing)
            buffer.append(UInt8(ascii: "\n"))
            return PendingLeaf(node: node, content: .materialized(buffer))
        }
    }

    /// Append one body line of a code/HTML block as a `Segment`, without copying source bytes, returning the updated leaf.
    ///
    /// A source-mapped line (`currentLineMapsToSource`) becomes a zero-copy `inSource` segment; a line that doesn't map to source (e.g. a tab-expanded line whose `span` is a transient per-line buffer) is copied into the additions arena and referenced by an `inSource: false` segment. Empty ranges append nothing (the surrounding `\n` separators carry blank lines), leaving `pending` unchanged.
    private mutating func addLineSegment(span: Span<UInt8>, range: Range<Int>, to node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> PendingLeaf? {
        guard !range.isEmpty else { return pending }
        if currentLineMapsToSource {
            // why: a paragraph continuation line's surviving content is mapped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). Code/HTML block bodies are excluded either way (they preserve their own indentation and keep their true offset). When the line has no whitespace beyond `block_offset` the two coincide, so this is a no-op.
            //
            // Flag ON reproduces cmark-gfm's continuation re-indent: cmark fixes the paragraph's content column from the FIRST line (`block_offset` = `currentContentIndent`) and reports every continuation line's surviving content relative to it. The inline parser (inlines.c `handle_newline`) columns a continuation line's first content byte at `leadingSpacesInAddedContent + block_offset + 1`, where the "added content" is whatever `add_line` copied - and cmark copies from `parser->offset` (blocks.c `add_line`), i.e. the point where container-prefix matching stopped. The base the block_offset is added to is therefore container-agnostic once expressed via that stopping point (`currentLineContentCursor`):
            //
            //   - A *matched* continuation (every open container's prefix matched down to the paragraph, INCLUDING a list-item or block-quote continuation whose indent the prefix consumed) has cmark advance the offset to the first non-space before `add_line` (blocks.c:1465), so the leading whitespace is DISCARDED: the content lands at the block-content column. Base = this line's start (`currentLineSourceRange.lowerBound`), residual dropped.
            //   - A *lazy* continuation (some container prefix failed - a block quote with no `>`, or a list item indented below its content column) is added straight from the stopping point without advancing to the first non-space (blocks.c:1408), so the residual whitespace between the stopping point and the first non-space is PRESERVED and shifts the content right by that width. Base = this line's start plus that residual (`range.lowerBound - currentLineContentCursor`), so the column is `residual + block_offset + 1`. This is the single rule for every lazy container - top-level or nested, block quote or list - because the residual is measured from wherever the last matched prefix stopped, which is the line start at the top level and the post-prefix cursor when an outer container already consumed columns.
            //
            // Because cmark's lazy buffer keeps that residual, it is not only a source column: a LITERAL inline (a code span) reads it out of the buffer as content (`> `x\n y`` -> `x  y`), while a TEXT run does not (the inline parser's `handle_newline` skips it in text flow). So flag ON a lazy continuation's segment BEGINS at the prefix-match stop (`currentLineContentCursor`), carrying the residual bytes, not at the first non-space; the code-span content path then captures them and `InlineParser` (gated on the same flag) strips them back out of text. A matched continuation and every flag-OFF continuation begin at the first non-space, so the residual never enters the content.
            //
            // Flag OFF is spec-correct: the continuation content keeps its TRUE first-non-space column (`range.lowerBound`), so its range is consistent with the block's true-width end, and no residual whitespace enters the content.
            let kind = storage[node].kind
            let isBodyLiteral = kind.isCodeBlock || kind == .htmlBlock
            let reindent = positionsEnabled && storage.options.contains(.cmarkBugCompatibility) && !isBodyLiteral
            let residual = currentLineIsLazyContinuation ? (range.lowerBound - currentLineContentCursor) : 0
            let keepResidual = residual > 0 && storage.options.contains(.cmarkBugCompatibility) && !isBodyLiteral
            let segStart = keepResidual ? currentLineContentCursor : range.lowerBound
            let reindentBase = currentLineSourceRange.lowerBound + residual
            // `mapsAt` is the source projection of the FIRST NON-SPACE byte (`range.lowerBound`). When the segment begins at the prefix stop (residual kept), back its projection up by the residual so the first non-space keeps the column the re-indent assigns it - the residual bytes take the columns before it.
            let mapsAt = reindent ? reindentBase + currentContentIndent : range.lowerBound
            let segSourceOffset = keepResidual ? mapsAt - residual : mapsAt
            return appendSegment(Segment(offset: Int32(segStart), length: Int32(range.upperBound - segStart), inSource: true, sourceOffset: Int32(segSourceOffset)), to: node, pending: pending)
        }
        // Materialized (tab-expanded) line. `expandPrefixTabs` turned leading whitespace and container markers into spaces so column-based matching works on byte offsets, but that expansion is lossy for a code/HTML block BODY: cmark copies the body verbatim from `parser->offset` (blocks.c `add_line`), so a content tab survives literally - only the single tab that the consumed indentation splits becomes spaces. Recover the literal source bytes instead of copying the expanded buffer, so content tabs are preserved.
        let nodeKind = storage[node].kind
        if nodeKind.isCodeBlock || nodeKind == .htmlBlock {
            // `appendMaterializedCodeContent` maps the content end to the source line end, so every code/HTML body add must run to the buffer's line end (`span.count`) - which all current callers do (fenced code, the one construct that trims content, never materializes).
            assert(range.upperBound == span.count, "materialized code/HTML body must extend to the line end")
            return appendMaterializedCodeContent(bufferStart: range.lowerBound, to: node, pending: pending)
        }
        // A tab-expanded paragraph continuation. Its surviving content - the first non-space byte to the line end - is byte-identical to source: `expandPrefixTabs` only rewrites the prefix and copies the tail verbatim, and the content begins at the first non-space byte, so no expanded-tab space reaches it. Map it back to a zero-copy source segment rather than copying the expanded bytes into the arena. This is required for correctness, not just to avoid a copy: a multi-segment inline `ContentSpan` resolves only source segments plus the interned `\n` (see `ContentSpan.multiByte`), so an arena content segment there reads back as `\n` per byte - dropping the text and multiplying soft breaks.
        assert(range.upperBound == span.count, "materialized paragraph continuation must extend to the line end")
        let (sourceStart, splitTabSpaces) = materializedSourceStart(bufferStart: range.lowerBound)
        assert(splitTabSpaces == 0, "a paragraph continuation's content never begins inside an expanded tab")
        let lineEnd = currentLineSourceRange.upperBound
        // The source-position mapping mirrors the source-mapped branch above (the `.cmarkBugCompatibility` continuation re-indent). `range.lowerBound` / `currentLineContentCursor` are buffer offsets here, which equal columns for a tab-expanded line, so the residual is a column count as required; the base stays the source line start. Flag-off maps to the content's true source byte (`sourceStart`).
        //
        // Unlike the source-mapped branch, a lazy continuation's residual is NOT carried into the CONTENT here: the residual is a column count of expanded-tab space, not a run of literal source bytes (a leading tab is one source byte spanning several columns), so it cannot be a zero-copy source slice and an arena segment is unusable in multi-segment inline content (see above). So a code span closing on a TAB-indented lazy continuation stays short of cmark's residual flag-ON - the deferred tab-materialization class (FINDINGS #41's `**\tx` sibling), which the fuzzer may re-find; the common space-indented case is handled in the source-mapped branch.
        let reindent = positionsEnabled && storage.options.contains(.cmarkBugCompatibility)
        let residual = currentLineIsLazyContinuation ? (range.lowerBound - currentLineContentCursor) : 0
        let mapsAt = reindent ? currentLineSourceRange.lowerBound + residual + currentContentIndent : sourceStart
        return appendSegment(Segment(offset: Int32(sourceStart), length: Int32(lineEnd - sourceStart), inSource: true, sourceOffset: Int32(mapsAt)), to: node, pending: pending)
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
        let offset = storage.strings.count
        storage.strings.reserveCapacity(offset + splitTabSpaces + (lineEnd - sourceStart))
        for _ in 0..<splitTabSpaces {
            storage.strings.append(UInt8(ascii: " "))
        }
        for i in sourceStart..<lineEnd {
            storage.strings.append(sourceBytes[i])
        }
        return appendSegment(
            Segment(offset: Int32(offset), length: Int32(splitTabSpaces + (lineEnd - sourceStart)), inSource: false),
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
        var i = lineStart
        while i < prefixEnd {
            let width = sourceBytes[i] == UInt8(ascii: "\t") ? 4 - (col & 3) : 1
            if bufferStart < col + width {
                if bufferStart == col {
                    return (i, 0)
                }
                // A tab split by the consumed indentation: emit its remaining columns as spaces, resume after it.
                return (i + 1, (col + width) - bufferStart)
            }
            col += width
            i += 1
        }
        return (prefixEnd, 0)
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
            guard leaf.node == node else { return LeafSegments(segments: UniqueArray(), pending: leaf) }
            switch consume leaf.content {
            case .segments(let segs):
                return LeafSegments(segments: segs, pending: nil)
            default:
                // Only code/HTML blocks drain here, and they only ever accumulate segments.
                fatalError("drainSegments called on non-segment content")
            }
        }
    }

    /// Materialize the pending content for `node` and return a `Chunk` pointing at it, along with the leaf with `node`'s content cleared (handed back untouched if `node` isn't the pending leaf).
    ///
    /// A `.lazy` entry resolves to a `Chunk(inSource: true)` addressing the original source - no copy (this covers source-contiguous multi-line paragraphs). A `.lazyNewline` entry (a dangling deferred separator with no following line - not produced by the normal continuation flow) materializes its span plus the trailing `\n`. A `.materialized` entry is appended to `storage.strings` and a `Chunk(inSource: false)` is returned.
    private mutating func materializePendingContent(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafMaterialization {
        guard let leaf = pending else {
            return LeafMaterialization(chunk: .empty, pending: nil)
        }
        
        guard leaf.node == node else {
            return LeafMaterialization(chunk: .empty, pending: leaf)
        }
        
        switch consume leaf.content {
        case .lazy(let range):
            if range.isEmpty {
                return LeafMaterialization(chunk: .empty, pending: nil)
            }
            return LeafMaterialization(chunk: Chunk(offset: range.lowerBound, length: range.count, inSource: true), pending: nil)
        case .lazyNewline(let range):
            let offset = storage.strings.count
            for i in range {
                storage.strings.append(sourceBytes[i])
            }
            storage.strings.append(UInt8(ascii: "\n"))
            return LeafMaterialization(chunk: Chunk(offset: offset, length: range.count + 1, inSource: false), pending: nil)
        case .materialized(let content):
            if content.isEmpty {
                return LeafMaterialization(chunk: .empty, pending: nil)
            }
            let offset = storage.strings.count
            content.span.withUnsafeBufferPointer { buffer in
                storage.strings.append(copying: buffer)
            }
            return LeafMaterialization(chunk: Chunk(offset: offset, length: content.count, inSource: false), pending: nil)
        case .segments(let segs):
            // Flatten a segment list to one arena chunk (used when a `Chunk` is required - e.g. a setext heading's paragraph re-seed, or matcher-eligible content). The common multi-line paragraph path keeps segments zero-copy via the finalize segment branch. Capture the arena→source run map so the re-seed can carry per-line source columns onto the heading's inlines.
            var map: [ArenaRun] = []
            let chunk = flattenSegments(segs, map: &map)
            return LeafMaterialization(chunk: chunk, pending: nil, map: map)
        }
    }

    // MARK: - Per-line dispatcher

    /// Process a line of Markdown.
    ///  - source: The line content
    ///  - lineRange: The range of the line in the original source, in order to lazily reference it.
    private mutating func processLine(source: Span<UInt8>, lineRange: Range<Int>, chain: inout UniqueArray<DocumentStorage.Index>, pending: consuming PendingLeaf?) throws(MarkdownDocument.Error) -> PendingLeaf? {
        var pending = pending
        // PHASE 1: Walk the open-container chain, stripping each container's continuation prefix. `deepestMatched` is the deepest container whose continuation succeeded (always a container, never a leaf). `cursor` is the byte offset into the line after stripped prefixes.
        let walk = try walkOpenContainers(source: source, lineRange: lineRange, chain: &chain)
        let deepestMatched = walk.deepestMatched
        let cursor = walk.cursor
        let allMatched = walk.allMatched

        // A paragraph continuation on this line re-indents relative to where the container-prefix walk
        // stopped. A *lazy* continuation (some prefix failed → `!allMatched`) preserves the residual
        // whitespace after that stopping point; a *matched* one discards it. `addLineSegment` reads both
        // under `.cmarkBugCompatibility`.
        currentLineContentCursor = cursor
        currentLineIsLazyContinuation = !allMatched

        let openKind = storage[current].kind

        // PHASE 2a: Code-block / HTML-block continuation - only when the prefix walk reached the leaf. If the walk failed before that, the block must close.
        if openKind.isCodeBlock && allMatched {
            let result = try handleCodeBlockContinuation(
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
            // Fenced or indented code block ended on this line; fall through to dispatch the line content as a fresh block.
        } else if openKind.isCodeBlock && !allMatched {
            // Walk failed before reaching the code block - close it and any stale containers, then dispatch the line normally.
            pending = try finalize(node: current, pending: pending)
        } else if openKind == .htmlBlock && allMatched {
            let result = try handleHTMLBlockContinuation(
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
            pending = try finalize(node: current, pending: pending)
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
                pending = try finalize(node: current, pending: pending)
            }
            // If a container in the chain failed to continue, close it now.
            if !allMatched {
                while current != deepestMatched {
                    pending = try finalize(node: current, pending: pending)
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
        if stillOpenKind == .paragraph && allMatched,
           let level = matchSetextUnderline(source: source, range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
            // Strip any leading reference-link definitions from the paragraph's accumulated content first. If they consume the entire paragraph, the setext heading never forms - the underline line falls through to dispatch as plain text (per spec examples 184 / 185).
            let para = current
            let materialized = materializePendingContent(para, pending: pending)
            let raw = materialized.chunk
            // Content-relative arena→source run map for the flattened segments (empty unless the paragraph body was non-contiguous `.segments`, i.e. inside a blockquote/list). Captured before `pending` is moved out.
            let flatMap = materialized.map
            pending = materialized.pending
            let trimmedHead = raw.trimming(using: self)
            let stripped = parseDefinitions(in: trimmedHead)
            if self.isBlank(chunk: stripped) {
                // why: the paragraph is nothing but reference definitions, so the setext underline
                // never forms a heading - but the two implementations then diverge in BLOCK
                // STRUCTURE. cmark resolves (drops) the leading ref-defs from the paragraph's
                // content buffer the moment it scans the underline (`resolve_reference_link_definitions`,
                // blocks.c:1228-1240); finding no content left, it neither promotes to a heading nor
                // advances the offset, and - because the setext branch matched - the thematic-break
                // branch below it is skipped. The still-open, now-empty paragraph then absorbs the
                // underline line as ordinary continuation text, keeping its ORIGINAL start line. The
                // spec-correct default instead drops the empty paragraph and redispatches the underline
                // as a fresh block (a new paragraph for `===`, a thematic break for `---`) at true
                // positions.
                //
                // Reproduce cmark's structure flag-ON by keeping the paragraph open and appending this
                // line as a normal continuation (as PHASE 2d would), restoring the accumulated content
                // - drained by the materialize above - as a zero-copy source range so the EXISTING
                // finalize path extracts the ref-def. Gated on `raw.inSource`: that is the validity
                // condition for the `.lazy` reconstruction (it addresses `sourceBytes`), and is true
                // whenever the accumulated pre-underline content is source-backed - the common
                // single-source-line ref-def, including one inside a block quote / list item. A ref-def
                // whose accumulated content is not source-backed at all (a multi-line def broken across
                // a stripped prefix, `!raw.inSource`) falls through to the spec-correct drop below.
                if storage.options.contains(.cmarkBugCompatibility), raw.inSource {
                    pending = PendingLeaf(node: para, content: .lazy(range: raw.range))
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
                    // Arena-backed (non-contiguous) content: `addChunk` re-copies the stripped bytes into a fresh arena buffer, so a plain arena chunk would reach inline parsing unmapped and leave the heading's text/emphasis unstamped (spec #12). The flattened content's run map is content-relative, so it survives the re-copy; narrow it to the window that actually reaches inline parsing - the stripped remainder after finalize's own leading/trailing trim (mirrored here by `stripped.trimming`) - keyed from `raw`'s first content byte, and stamp it on the heading via `arenaSourceMaps`.
                    if positionsEnabled, !flatMap.isEmpty {
                        let finalWindow = stripped.trimming(using: self)
                        if !finalWindow.isEmpty {
                            arenaSourceMaps[para] = sliceRuns(flatMap, from: finalWindow.offset - raw.offset, length: finalWindow.length)
                        }
                    }
                    pending = addChunk(stripped, to: para, pending: pending)
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
        if stillOpenKind == .paragraph {
            // The matcher ladder can only return true if the first content byte is one that some block construct starts with; for ordinary prose continuation lines it isn't, so we skip the whole ladder. `mightStartBlock` is a superset of every matcher's trigger byte, so a `false` here is exactly what `lineStartsNewBlock` would have returned.
            // `interruptsParagraph` mirrors cmark's flag (blocks.c: `check_open_blocks` backs `container` up to its parent on a failed continuation): true iff the open paragraph's OWN container matched this line, i.e. `deepestMatched` is the paragraph's parent. When a shallower container matched, the marker is a sibling item at the list level, not an interruption of this paragraph.
            let interruptsParagraph = storage[current].parent == deepestMatched
            let canInterrupt = Self.mightStartBlock(scan.firstNonSpaceByte)
                && lineStartsNewBlock(
                    source: source,
                    range: cursor..<lineRange.upperBound,
                    firstNonSpace: firstNonSpace,
                    indent: indent,
                    currentKind: stillOpenKind,
                    interruptsParagraph: interruptsParagraph
                )
            if !canInterrupt {
                // Continue paragraph (matched or lazy). Don't close stale containers - the paragraph absorbs without breaking the chain.
                // This continuation is the paragraph's second physical line the first time it runs, i.e. the
                // GFM table delimiter-row candidate. cmark opens a table only when that line is NOT indented
                // (`try_opening_table_block`'s `!indented` gate); finalize-time table detection can't see the
                // stripped leading whitespace, so record the indent (`leadingScan` measured it against the
                // container prefix) for `runParagraphMatchers` to consult.
                if storage.options.contains(.tables), paragraphSecondLineIndent[current] == nil {
                    paragraphSecondLineIndent[current] = indent
                }
                pending = appendNewline(to: current, pending: pending)
                pending = addLine(span: source, range: firstNonSpace..<lineRange.upperBound, to: current, pending: pending)
                return pending
            }
        }

        // PHASE 3: Close stale containers down to deepestMatched.
        while current != deepestMatched {
            pending = try finalize(node: current, pending: pending)
        }

        // PHASE 4: New-block dispatch. Containers (block quote) loop back so a single line like `> > foo` opens both quotes and then a paragraph.
        return try dispatchNewBlocks(
            source: source,
            lineRange: lineRange,
            startCursor: cursor,
            pending: pending
        )
    }

    /// Walk the open-container chain top-down, stripping each container's continuation prefix.
    ///
    /// Returns the deepest container whose prefix matched (always a container, never a leaf), the cursor into the line after stripped prefixes, and whether every container in the chain matched.
    private mutating func walkOpenContainers(source: Span<UInt8>, lineRange: Range<Int>, chain: inout UniqueArray<DocumentStorage.Index>) throws (MarkdownDocument.Error) -> (deepestMatched: DocumentStorage.Index, cursor: Int, allMatched: Bool) {
        var cursor = lineRange.lowerBound
        var deepestMatched = documentIndex

        // Build top-down chain via parent walk + reverse. `chain` is a caller-owned reused buffer (reset here per line) so we don't allocate/zero a fresh array each line.
        chain.removeAll(keepingCapacity: true)
        var idx: DocumentStorage.Index? = current
        while let idx_ = idx {
            if chain.count >= Self.maxContainerNesting {
                throw MarkdownDocument.Error.parsingLimitExceeded
            }
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
                if let advanced = matchBlockQuoteMarker(
                    source: source,
                    range: cursor..<lineRange.upperBound,
                    firstNonSpace: firstNonSpace
                ) {
                    cursor = advanced
                    deepestMatched = node
                } else {
                    // No `>` on this line: the block quote's paragraph continues lazily. The walk stops
                    // here (`allMatched: false`), and `cursor` marks where the last matched prefix ended.
                    // `processLine` turns that into `currentLineIsLazyContinuation`, and `addLineSegment`
                    // preserves the residual whitespace after `cursor` in the re-indent column - the same
                    // rule for a top-level, nested, or list-wrapped lazy block quote.
                    return (deepestMatched, cursor, false)
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
                guard let padding = itemPadding(of: node) else {
                    return (deepestMatched, cursor, false)
                }
                // Compare in COLUMNS, not bytes, so a leading tab counts as up to 4 cols of indent.
                let availCols = indentColumns(source: source, from: cursor, to: firstNonSpace)
                if availCols >= padding {
                    // The indent reaches the item's content column: consume exactly `padding` columns and
                    // match. cmark tests this BEFORE the childless-blank check, so a whitespace-only line
                    // whose expanded indent covers the content column extends even a childless item onto it
                    // (e.g. a tab after a bare `-`: 4 columns >= the content column 2).
                    cursor = advanceColumns(
                        source: source,
                        from: cursor,
                        to: lineRange.upperBound,
                        columns: padding
                    )
                    deepestMatched = node
                } else if isBlank, storage[node].firstChild != nil {
                    // A blank line inside an item that already has content keeps the item open even though
                    // the indent falls short of the content column. Advance `cursor` to first-non-space (the
                    // line end for a blank line), mirroring cmark's `S_advance_offset(... first_nonspace ...)`,
                    // so any deeper open item measures its indent from here rather than the shallower line
                    // start. A childless item on such a line closes (CommonMark §5.2: `first_child == NULL`).
                    cursor = firstNonSpace
                    deepestMatched = node
                } else {
                    return (deepestMatched, cursor, false)
                }
            case .paragraph, .heading, .codeBlock, .htmlBlock, .text, .thematicBreak:
                // Leaves; they don't have container-level prefix matching. The chain effectively ends here. Caller decides leaf-specific continuation (e.g. code-block fence detection).
                return (deepestMatched, cursor, true)
            default:
                break
            }
        }
        return (deepestMatched, cursor, true)
    }

    /// Returns `true` if the line's content (starting at `firstNonSpace`) begins a new block that would interrupt an open paragraph.
    ///
    /// `interruptsParagraph` mirrors cmark's `interrupts_paragraph` flag: `true` when the open paragraph's OWN container matched this line's continuation prefix (so the line is genuinely interrupting THAT paragraph), `false` when only a shallower container matched (the marker is a sibling item continuing an existing list, not interrupting the paragraph).
    private func lineStartsNewBlock(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, indent: Int, currentKind: MarkdownNode.Kind, interruptsParagraph: Bool) -> Bool {
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
        // HTML blocks of types 1–6 interrupt a paragraph (CommonMark 0.31 §4.6). Type 7 does not interrupt, so we restrict the scan to types 1–6 here.
        if let type = matchHTMLBlockStart(source: source, range: range, firstNonSpace: firstNonSpace, allowType7: false),
           type != 7 {
            return true
        }
        // List markers interrupt a paragraph only if they'd start a non-empty first item (CommonMark 0.31 §5.2/§5.3). An ORDERED list can interrupt a paragraph only when its start number is 1; bullets are exempt. This is cmark's `interrupts_paragraph && start != 1` decline in `parse_list_marker` (blocks.c), and it applies at EVERY nesting level - `interruptsParagraph` is true exactly when the open paragraph's own container matched this line, so `- a\n  2. b` (the item matched → `2. b` interrupts the item's paragraph) keeps `2. b` as text, while `1. a\n2. b` (the item did NOT match → the marker sits at the list level) opens a sibling item regardless of start.
        if let marker = matchListMarker(source: source, range: range, firstNonSpace: firstNonSpace) {
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
    private mutating func handleHTMLBlockContinuation(source: Span<UInt8>, lineRange: Range<Int>, cursor: Int, pending: consuming PendingLeaf?) throws(MarkdownDocument.Error) -> LeafContinuation {
        var pending = pending
        guard case .htmlBlock(let type, _) = storage[current].data else {
            return LeafContinuation(stillOpen: false, pending: pending)
        }
        let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound

        if type == 6 || type == 7 {
            // Types 6 and 7 end on a blank line; the blank line is *not* part of the block content.
            if isBlank {
                pending = try finalize(node: current, pending: pending)
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
            pending = try finalize(node: current, pending: pending)
        }
        return LeafContinuation(stillOpen: true, pending: pending)
    }

    /// Continue an open code block. Returns `stillOpen: true` if the block remains open after handling this line; `false` if the line closed it (or was a closing fence). When this returns `false` the caller should *not* dispatch the line content as a fresh block - the closing fence is fully consumed.
    private mutating func handleCodeBlockContinuation(source: Span<UInt8>, lineRange: Range<Int>, cursor: Int, pending: consuming PendingLeaf?) throws(MarkdownDocument.Error) -> LeafContinuation {
        var pending = pending
        let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
        let isBlank = firstNonSpace == lineRange.upperBound
        let indent = indentColumns(source: source, from: cursor, to: firstNonSpace)

        if case .codeBlock(let info) = storage[current].kind, info.isFenced {
            // Fenced.
            if matchClosingFence(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace,
                expectedChar: info.fenceCharacter,
                minimumLength: info.fenceLength
            ) {
                pending = try finalize(node: current, pending: pending)
                return LeafContinuation(stillOpen: true, pending: pending)
            }
            // Continuation: strip up to `fenceOffset` columns of leading whitespace and append.
            pending = appendNewline(to: current, pending: pending)
            let bodyStart = stripLeadingSpaces(
                source: source,
                range: cursor..<lineRange.upperBound,
                maxColumns: info.fenceOffset
            )
            pending = addLine(span: source, range: bodyStart..<lineRange.upperBound, to: current, pending: pending)
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
        pending = try finalize(node: current, pending: pending)
        return LeafContinuation(stillOpen: false, pending: pending)
    }

    /// Open a list item under `current`. If `current` is already a list of compatible kind/marker, the item is added as another child of that list. Otherwise a new list is opened first.
    ///
    /// On exit, `current` points at the newly-opened item.
    private mutating func openListItem(marker: ListMarkerInfo, firstNonSpace: Int, pending: consuming PendingLeaf?) throws(MarkdownDocument.Error) -> PendingLeaf? {
        var pending = pending
        let start = sourceOffset(firstNonSpace)
        let parentList: DocumentStorage.Index
        if storage[current].kind.isList,
           let listInfo = storedListInfo(of: current),
           listInfo.matches(marker: marker) {
            parentList = current
            // Tight/loose detection runs at list-finalize time via `detectLooseList` + the `endsWithBlankLine` recursion, which catches the "blank between sibling items" case at finalize.
        } else {
            // Either there's no open list, or the marker style differs from the open list. In the latter case, finalize the open list so the new list opens as a sibling - `- foo\n+ bar` becomes two top-level lists, not a nested one (CommonMark §5.3).
            if storage[current].kind.isList {
                pending = try finalize(node: current, pending: pending)
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

    /// Read the kind/marker fields of a `.list` node.
    private func storedListInfo(of node: DocumentStorage.Index) -> StoredListInfo? {
        if case .list(let info) = storage[node].kind {
            return StoredListInfo(
                kind: info.kind,
                orderedDelimiter: info.orderedDelimiter,
                bulletMarker: info.bulletMarker
            )
        }
        return nil
    }

    private struct StoredListInfo {
        var kind: MarkdownNode.ListInfo.Kind
        var orderedDelimiter: MarkdownNode.ListInfo.OrderedDelimiter
        var bulletMarker: MarkdownNode.ListInfo.BulletMarker

        func matches(marker: ListMarkerInfo) -> Bool {
            if kind != marker.kind {
                return false
            }
            switch kind {
            case .bullet:
                return bulletMarker == marker.bulletMarker
            case .ordered:
                return orderedDelimiter == marker.orderedDelimiter
            }
        }
    }

    /// Open new blocks at `current` based on the line's content from `startCursor`. Loops when a container (block quote, list item) opens so that `> > foo` or `- - foo` correctly opens nested containers plus a paragraph in one pass.
    private mutating func dispatchNewBlocks(source: Span<UInt8>, lineRange: Range<Int>, startCursor: Int, pending: consuming PendingLeaf?) throws(MarkdownDocument.Error) -> PendingLeaf? {
        var pending = pending
        var cursor = startCursor
        while true {
            let firstNonSpace = indexOfFirstNonSpace(source: source, range: cursor..<lineRange.upperBound)
            let isBlank = firstNonSpace == lineRange.upperBound
            if isBlank {
                return pending
            }
            let indent = indentColumns(source: source, from: cursor, to: firstNonSpace)

            // Block quote opens a container; loop to keep dispatching the rest.
            if let advanced = matchBlockQuoteMarker(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                // A block quote can't be a direct child of a list (lists only contain items), so an enclosing list closes first - e.g. a `>` line after list items ends the list and starts a top-level quote, matching cmark's `add_child` ancestor-finalize rule.
                if storage[current].kind.isList {
                    pending = try finalize(node: current, pending: pending)
                }
                let quoteIdx = addChild(
                    kind: .blockQuote,
                    parent: current,
                    start: sourceOffset(firstNonSpace)
                )
                current = quoteIdx
                cursor = advanced
                continue
            }

            // Thematic break (must be before ATX so `---` etc. wins over content matchers, and before list-marker so `- - -` etc. wins over nested lists).
            if matchThematicBreak(source: source, range: cursor..<lineRange.upperBound, firstNonSpace: firstNonSpace) {
                // Thematic breaks close any enclosing list - they don't become children of a list (lists can only contain items).
                if storage[current].kind.isList {
                    pending = try finalize(node: current, pending: pending)
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

            // List marker - opens a list (or extends an existing one) and an item. Both are containers; loop so we keep dispatching the rest of the line as content within the new item.
            if let marker = matchListMarker(
                source: source,
                range: cursor..<lineRange.upperBound,
                firstNonSpace: firstNonSpace
            ) {
                pending = try openListItem(marker: marker, firstNonSpace: firstNonSpace, pending: pending)
                cursor = marker.consumedTo
                // Record whether this item's marker is line-anchored (preceded on its own physical line
                // by only whitespace) so the finalize-time checkbox recognition and continuation
                // re-indent bump fire only for such items, matching cmark's `scan_tasklist` (a marker
                // sharing its line with a block-quote `>` or an outer list marker has a non-space prefix
                // and keeps `[ ]` literal). `firstNonSpace` is the marker column; `lineRange.lowerBound`
                // is the physical line start (unchanged by any block-quote prefix already consumed this
                // line).
                if storage.options.contains(.tasklist),
                   taskMarkerLineAnchored(
                       source: source,
                       lineStart: lineRange.lowerBound,
                       markerStart: firstNonSpace
                   ) {
                    lineAnchoredTaskItems.insert(current)
                }
                // GFM empty task-list item: cmark's tasklist extension consumes the checkbox when the
                // ITEM opens (`open_tasklist_item`), so an item whose first line is nothing but a
                // checkbox gets no paragraph child - it stays empty, exactly like a plain `- ` empty
                // item, and a following unindented line closes it instead of lazily continuing into it.
                // The rewrite recognizes the checkbox at finalize (`runParagraphMatchers`, #65), which
                // is too late for an empty item (there is no paragraph to finalize), so the empty case
                // is caught here at open time. Content-bearing task items fail the whitespace-to-line-end
                // test and are left untouched - their checkbox is still stripped at finalize.
                if let checked = emptyTaskItemChecked(
                    source: source,
                    lineStart: lineRange.lowerBound,
                    markerStart: firstNonSpace,
                    contentStart: cursor,
                    lineEnd: lineRange.upperBound
                ) {
                    storage[current].kind = .item(checked: checked)
                    cursor = lineRange.upperBound
                }
                continue
            }

            // From this point on the line isn't a list item, so any open list at `current` must close before we attach the new block (lists can't have direct non-item children).
            if storage[current].kind.isList {
                pending = try finalize(node: current, pending: pending)
            }

            // ATX heading.
            if let heading = matchATXHeading(
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
                return try finalize(node: headingIdx, pending: pending, atxHeadingEnd: heading.end)
            }

            // Fenced code block.
            if let fence = matchOpeningFence(
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
                let cleanInfo = EntityParser.unescapeURLChunk(infoChunk, source: sourceBytes, into: &storage)
                let infoRef = storage.intern(cleanInfo)
                let codeIdx = addChild(
                    kind: .codeBlock(MarkdownNode.CodeBlockInfo(
                        isFenced: true,
                        fenceCharacter: fence.character,
                        fenceLength: fence.length,
                        fenceOffset: fence.fenceOffset
                    )),
                    parent: current,
                    data: .codeBlock(info: infoRef, literal: .empty),
                    start: sourceOffset(firstNonSpace)
                )
                current = codeIdx
                return pending
            }

            // HTML block (types 1–7). Leading 0–3 spaces of indent are preserved verbatim in the block's content. Type 7 is detected only when the current container isn't a paragraph, since it can't interrupt one (per CommonMark 0.31 §4.6).
            let allowType7 = storage[current].kind != .paragraph
            if let htmlType = matchHTMLBlockStart(
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
                pending = addLine(span: source, range: cursor..<lineRange.upperBound, to: htmlIdx, pending: pending)
                // Check whether this same line also satisfies the end condition.
                if htmlBlockLineMatchesEndCondition(
                    type: htmlType,
                    source: source,
                    range: firstNonSpace..<lineRange.upperBound
                ) {
                    pending = try finalize(node: htmlIdx, pending: pending)
                }
                return pending
            }

            // Indented code block (only when current container can't continue a paragraph).
            if indent >= 4 && storage[current].kind != .paragraph {
                // The block starts where content begins *after* the 4-space code indent is consumed (cmark's convention: the extra indentation beyond 4 is preserved as content, and the start column is that post-indent position - not the first non-space char).
                let bodyStart = advanceColumns(source: source, from: cursor, to: firstNonSpace, columns: 4)
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
                return addLine(span: source, range: bodyStart..<lineRange.upperBound, to: codeIdx, pending: pending)
            }

            // Paragraph fallback. By this point the list-close-if-needed step above has already ensured `current` isn't a list.
            let textRange = firstNonSpace..<lineRange.upperBound
            if storage[current].kind == .paragraph {
                pending = appendNewline(to: current, pending: pending)
                return addLine(span: source, range: textRange, to: current, pending: pending)
            } else {
                let paragraphIdx = addChild(kind: .paragraph, parent: current, start: sourceOffset(firstNonSpace))
                current = paragraphIdx
                return addLine(span: source, range: textRange, to: paragraphIdx, pending: pending)
            }
        }
    }

    // MARK: - Finalize

    // MARK: Segment-content finalize (segment model)

    /// Drained leaf content: either one contiguous `Chunk` (`.lazy`/`.lazyNewline`/`.materialized`) or a multi-line segment list (`.segments`, kept zero-copy).
    ///
    /// Lets paragraph/heading finalize decide whether to keep segments or run the chunk-based matchers without consuming `pending` twice.
    private enum DrainedLeaf: ~Copyable {
        case chunk(Chunk)
        case segments(UniqueArray<Segment>)
    }

    private struct LeafDrainResult: ~Copyable {
        var content: DrainedLeaf
        var pending: PendingLeaf?
    }

    /// Drain `node`'s pending content, tagging it as a flat chunk or a segment list (mirrors `materializePendingContent` for the chunk cases; returns `.segments` zero-copy instead of flattening).
    private mutating func drainLeaf(_ node: DocumentStorage.Index, pending: consuming PendingLeaf?) -> LeafDrainResult {
        switch consume pending {
        case .none:
            return LeafDrainResult(content: .chunk(.empty), pending: nil)
        case .some(let leaf):
            guard leaf.node == node else {
                return LeafDrainResult(content: .chunk(.empty), pending: leaf)
            }
            switch consume leaf.content {
            case .segments(let segs):
                return LeafDrainResult(content: .segments(segs), pending: nil)
            case .lazy(let range):
                if range.isEmpty {
                    return LeafDrainResult(content: .chunk(.empty), pending: nil)
                }
                return LeafDrainResult(content: .chunk(Chunk(offset: range.lowerBound, length: range.count, inSource: true)), pending: nil)
            case .lazyNewline(let range):
                let offset = storage.strings.count
                for i in range { storage.strings.append(sourceBytes[i]) }
                storage.strings.append(UInt8(ascii: "\n"))
                return LeafDrainResult(content: .chunk(Chunk(offset: offset, length: range.count + 1, inSource: false)), pending: nil)
            case .materialized(let content):
                if content.isEmpty {
                    return LeafDrainResult(content: .chunk(.empty), pending: nil)
                }
                let offset = storage.strings.count
                content.span.withUnsafeBufferPointer { storage.strings.append(copying: $0) }
                return LeafDrainResult(content: .chunk(Chunk(offset: offset, length: content.count, inSource: false)), pending: nil)
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

    /// Trim leading whitespace off the first segment and trailing whitespace off the last (matching `Chunk.trimming(using:)`), in place. Interior segments - the newline joins and any hard-break trailing spaces before them - are untouched. An edge segment trimmed to zero length is harmless (read as empty).
    private func trimSegments(_ segs: consuming UniqueArray<Segment>) -> UniqueArray<Segment> {
        var segs = segs
        if segs.count == 0 { return segs }
        var first = segs[0]
        var l = 0
        while l < Int(first.length) && segmentByte(first, l).isSpaceTabOrNewline { l += 1 }
        first.offset += Int32(l)
        // The first segment is a paragraph's opening line (never re-indented), so `sourceOffset == offset`; advance it in step to keep the source mapping aligned with the trimmed bytes.
        first.sourceOffset += Int32(l)
        first.length -= Int32(l)
        segs[0] = first
        let li = segs.count - 1
        var last = segs[li]
        var len = Int(last.length)
        while len > 0 && segmentByte(last, len - 1).isSpaceTabOrNewline { len -= 1 }
        last.length = Int32(len)
        segs[li] = last
        return segs
    }

    /// `true` if every byte across all segments is whitespace (the trimmed paragraph is empty).
    private func isBlankSegments(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        for i in 0..<segs.count {
            let seg = segs[i]
            for j in 0..<Int(seg.length) where !segmentByte(seg, j).isSpaceTabOrNewline {
                return false
            }
        }
        return true
    }

    /// Cheap, over-approximate gate: could this segment content match a finalize-time matcher (ref-def / footnote / tasklist start with `[`, or a GFM table)?
    ///
    /// A false positive only costs an avoidable materialization; a false negative would skip a real matcher, so the checks must cover every matcher's necessary condition. The table necessary condition is on the DELIMITER (second) line, not the header: a single-column table's header need not contain a pipe (`a\n|-`, `a\n:-`), so the header-`|` check that once lived here would skip such tables. The segment list is isomorphic to `\n`-separated lines, so the second line is scanned directly.
    private func segmentsCouldMatchMatcher(_ segs: borrowing UniqueArray<Segment>) -> Bool {
        // First content byte == '['  ⇒ possible ref-def / footnote def / tasklist marker.
        outer: for i in 0..<segs.count {
            let seg = segs[i]
            for j in 0..<Int(seg.length) {
                let b = segmentByte(seg, j)
                if b.isSpaceTabOrNewline { continue }
                if b == UInt8(ascii: "[") { return true }
                break outer   // first non-whitespace byte isn't '['
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

    /// Flatten a segment list into one arena chunk, recording a content-relative arena→source run map in `map` as it copies: one run per non-empty segment. A source segment images its (re-indented) source range (run `sourceOffset` = the segment's `sourceOffset`); a non-source segment - the interned `\n` line-join, or an arena-only line with no source pre-image - becomes a synthetic gap (`sourceOffset < 0`). The map tiles the flattened content from its first byte, so it survives a later arena re-copy of the content (the byte layout is unchanged) and lets inline stamping recover per-line source columns.
    ///
    /// Used when content must be a contiguous `Chunk` - the matcher-eligible path and code/HTML-block fallback.
    private mutating func flattenSegments(_ segs: borrowing UniqueArray<Segment>, map: inout [ArenaRun]) -> Chunk {
        var total = 0
        for i in 0..<segs.count { total += Int(segs[i].length) }
        if total == 0 { return .empty }
        var buf = UniqueArray<UInt8>(minimumCapacity: total)
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
                // A source segment images its (re-indented) source range - `sourceOffset` re-indents a continuation line to its block-content column; otherwise it equals `offset`. `physicalOffset` (the segment's byte-read `offset`) stays on the run's physical source line so inline stamping can anchor a re-indented run there. A non-source segment (the interned `\n` join, or an arena-only line) is a synthetic gap.
                map.append(ArenaRun(
                    length: Int32(len),
                    sourceOffset: seg.inSource ? seg.sourceOffset : -1,
                    physicalOffset: seg.inSource ? seg.offset : -1))
            }
        }
        let offset = storage.strings.count
        buf.span.withUnsafeBufferPointer { storage.strings.append(copying: $0) }
        return Chunk(offset: offset, length: total, inSource: false)
    }

    /// Narrow a content-relative arena→source run map to the sub-window `[start, start + length)` of the original flattened content, rebased so its first run begins at content offset 0.
    ///
    /// Drops runs outside the window and advances a partially-included source run's `sourceOffset` by the trimmed-off prefix; synthetic gaps stay gaps. Used when a flattened setext heading's content is re-seeded after leading/trailing whitespace trim and ref-def stripping, so the stored map matches exactly the bytes that reach inline parsing.
    private func sliceRuns(_ runs: [ArenaRun], from start: Int, length: Int) -> [ArenaRun] {
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
            // `physicalOffset` (the run's byte-read source line anchor) advances by the same trimmed-off prefix as `sourceOffset`; a synthetic gap stays a gap.
            let physicalOffset: Int32 = run.physicalOffset < 0 ? -1 : run.physicalOffset + Int32(lo - runStart)
            result.append(ArenaRun(length: Int32(hi - lo), sourceOffset: sourceOffset, physicalOffset: physicalOffset))
        }
        return result
    }

    /// Run the paragraph finalize-time matchers on a single flat content `Chunk`: footnote definition, reference-link definitions, GFM table detection, and tasklist marker - then queue the remaining content for inline parsing (or drop the node if it was entirely ref-defs).
    ///
    /// Factored out so both the flat-content path and the (eligibility-gated) segment path can reuse it. `map` is the flattened content's arena→source run map (empty for the contiguous flat-content path): when the content was flattened from a non-contiguous, re-indented segment list it carries per-line source columns, and is sliced to the surviving `contentChunk` window and stamped on the node so the inline pass can stamp positions.
    private mutating func runParagraphMatchers(node: DocumentStorage.Index, raw: Chunk, map: [ArenaRun] = []) throws(MarkdownDocument.Error) {
        var trimmed = raw.trimming(using: self)
        if trimmed.isEmpty {
            return
        }
        // GFM footnote definition: `[^label]: content`. Detected first because a footnote-def line shouldn't also be probed for link ref-defs or task markers.
        var isFootnoteDef = false
        if storage.options.contains(.footnotes),
           let fn = matchFootnoteDefinition(chunk: trimmed) {
            wrapInFootnoteDefinition(paragraph: node, label: fn.label)
            trimmed = fn.content
            isFootnoteDef = true
        }
        // Reference link definitions stack at the start of a paragraph; any that match are stripped and registered.
        if !isFootnoteDef {
            trimmed = parseDefinitions(in: trimmed)
        }
        if !isFootnoteDef && isBlank(chunk: trimmed) {
            // Whole paragraph was ref-defs - drop the empty paragraph node.
            storage.unlinkChild(node)
            return
        }
        var contentChunk = trimmed.trimming(using: self)
        // GFM table detection: header line + delimiter row mutates the node in place to `.table`.
        // The delimiter row is the paragraph's second physical line; cmark opens a table only when that
        // line is NOT indented >= 4 columns (`try_opening_table_block`'s `!indented` gate). Its leading
        // whitespace is stripped by the time content reaches here, so consult the indent recorded during
        // block parsing (`paragraphSecondLineIndent`); an over-indented delimiter row stays a lazy
        // paragraph continuation, as in cmark.
        if !isFootnoteDef && storage.options.contains(.tables)
            && (paragraphSecondLineIndent[node] ?? 0) < 4 {
            // A top-level row with leading whitespace makes the paragraph non-contiguous, so its content
            // reaches here flattened from a segment list carrying a re-indent run map (Quirk E): each row's
            // surviving content is mapped to the table's content column, exactly cmark's re-based cell
            // columns. Narrow that map to the content window the table parser sees. The contiguous fast path
            // passes an empty map (the table parser maps by a constant source delta instead), and a table
            // nested in a block quote / list keeps its cells unstamped as before (see `parseTable`).
            let tableMap = (positionsEnabled && !map.isEmpty)
                ? sliceRuns(map, from: contentChunk.offset - raw.offset, length: contentChunk.length)
                : []
            if try parseTable(node: node, chunk: contentChunk, sourceMap: tableMap) {
                return
            }
        }
        // GFM tasklist: first paragraph of a line-anchored list item starting with `[ ]`/`[x]`/`[X]`
        // marks the item. `lineAnchoredTaskItems` was recorded at open time; an item sharing its line
        // with a `>` or an outer marker is absent from it and keeps its marker as literal text (matching
        // cmark's `scan_tasklist`).
        if !isFootnoteDef && storage.options.contains(.tasklist) {
            if let parent = storage[node].parent,
               case .item = storage[parent].kind,
               storage[parent].firstChild == node,
               lineAnchoredTaskItems.contains(parent),
               let mark = matchTasklistMarker(chunk: contentChunk) {
                storage[parent].kind = .item(checked: mark.checked)
                // cmark attributes the paragraph's source range to the content after the checkbox and all the whitespace following it (the first non-space/tab). The marker+whitespace length is the offset delta between the content and the marker's remainder (buffer-agnostic), so advance the already-stamped paragraph start by that many bytes.
                if positionsEnabled {
                    let start = storage.sourceRanges[node].start
                    if start >= 0 {
                        storage.setSourceStart(node, Int(start) + (mark.remaining.offset - contentChunk.offset))
                    }
                }
                contentChunk = mark.remaining
            }
        }
        // Stamp the (re-indented) run map for the content that actually reaches inline parsing: narrow the flattened content's map to the surviving `contentChunk` window (after leading/trailing trim, ref-def stripping, and any tasklist marker). Only meaningful when the content was flattened from a re-indented segment list; the contiguous flat-content path passes an empty map.
        if positionsEnabled, !map.isEmpty {
            let slice = sliceRuns(map, from: contentChunk.offset - raw.offset, length: contentChunk.length)
            if !slice.isEmpty {
                arenaSourceMaps[node] = slice
            }
        }
        pendingInlines.append((node, storage.intern(contentChunk)))
    }

    /// Close `node`, materialize its accumulated content, and back the parser's `current` pointer up to `node`'s parent.
    private mutating func finalize(node: DocumentStorage.Index, pending: consuming PendingLeaf?, atEOF: Bool = false, atxHeadingEnd: Int? = nil) throws(MarkdownDocument.Error) -> PendingLeaf? {
        var pending = pending
        let kind = storage[node].kind

        if positionsEnabled {
            // Mirror cmark's finalize end-position cases (src/blocks.c:309-337): the block ends on the CURRENT line at EOF, for the document / fenced code, for a setext heading, or for a block that opened on this same line (e.g. an ATX heading finalized immediately); otherwise it ends on the PREVIOUS line (the last line that was actually part of it).
            let startByte = storage.sourceRanges[node].start
            let startedThisLine = startByte >= Int32(currentLineSourceRange.lowerBound)
            let isFenced: Bool
            if case .codeBlock(let info) = kind { isFenced = info.isFenced } else { isFenced = false }
            // A `.heading` reaching finalize's else-branch is always a setext heading: an ATX heading finalizes immediately via `atxHeadingEnd` and is never open at close time.
            let isSetextHeading: Bool
            if case .heading = kind { isSetextHeading = true } else { isSetextHeading = false }
            let end: Int
            if let atxHeadingEnd {
                // An ATX heading ends at its trimmed content extent, not the raw line. Map the line-offset through `sourceOffset` exactly like the heading start, so tab-expanded lines resolve correctly; fall back to the raw line end if the mapping is unavailable.
                end = sourceOffset(atxHeadingEnd) ?? currentLineSourceRange.upperBound
                // cmark's chop_trailing_hashtags shrinks the line chunk before `last_line_length` is recorded (src/blocks.c), so a block later attributed to this line - notably the document, whose end is stamped from the final line - inherits the trimmed extent, not the raw line end. Mirror that by shrinking the tracked current-line end to the heading's content end.
                currentLineSourceRange = currentLineSourceRange.lowerBound..<end
            } else {
                // cmark finalizes a setext heading like the document / fenced code (blocks.c:327), so its end is the line that CLOSES it - the current line when this deferred finalize runs (PHASE 2c leaves it open), not the underline. Same finalize-timing class as the deferred thematic break (FINDINGS #7).
                end = (atEOF || startedThisLine || isSetextHeading || kind == .document || isFenced)
                    ? currentLineSourceRange.upperBound
                    : lastLineSourceEnd
            }
            storage.setSourceEnd(node, end)
        }

        switch kind {
        case .paragraph:
            let drained = drainLeaf(node, pending: pending)
            pending = drained.pending
            switch consume drained.content {
            case .chunk(let raw):
                try runParagraphMatchers(node: node, raw: raw)
            case .segments(let segs):
                // Multi-line non-contiguous body held as zero-copy source segments. Trim, then only materialize (flatten) if it could match a finalize matcher; plain prose stays segments.
                let trimmed = trimSegments(segs)
                if isBlankSegments(trimmed) {
                    // Entirely whitespace after trim - leave the paragraph empty (matches the chunk path).
                } else if segmentsCouldMatchMatcher(trimmed) {
                    // Flatten for the chunk-based matchers, capturing the arena→source run map so a re-indented continuation line's inline content is still stamped (matchers that survive re-seed the map via `runParagraphMatchers`).
                    var map: [ArenaRun] = []
                    let raw = flattenSegments(trimmed, map: &map)
                    try runParagraphMatchers(node: node, raw: raw, map: map)
                } else {
                    pendingInlines.append((node, storage.intern(trimmed)))
                }
            }
        case .heading:
            let drained = drainLeaf(node, pending: pending)
            pending = drained.pending
            switch consume drained.content {
            case .chunk(let raw):
                let trimmed = raw.trimming(using: self)
                if !trimmed.isEmpty {
                    pendingInlines.append((node, storage.intern(trimmed)))
                }
            case .segments(let segs):
                let trimmed = trimSegments(segs)
                if !isBlankSegments(trimmed) {
                    pendingInlines.append((node, storage.intern(trimmed)))
                }
            }
        case .codeBlock:
            // Body lines were accumulated as zero-copy source segments; normalize the segment list (drop the leading separator, strip trailing blank lines for indented code, ensure one trailing `\n`) without copying the bodies into the arena.
            let drained = drainSegments(node, pending: pending)
            var segs = drained.segments
            pending = drained.pending
            let isFenced: Bool
            if case .codeBlock(let info) = storage[node].kind {
                isFenced = info.isFenced
            } else {
                isFenced = false
            }
            normalizeCodeBlockSegments(&segs, isFenced: isFenced)
            let literalRef = storage.intern(segs)
            if case .codeBlock(let info, _) = storage[node].data {
                storage[node].data = .codeBlock(info: info, literal: literalRef)
            }
        case .htmlBlock:
            // Body lines accumulate as zero-copy source segments (same as code blocks). Normalize: drop our accumulator's leading separator and ensure a single trailing `\n` (cmark).
            let drained = drainSegments(node, pending: pending)
            var segs = drained.segments
            pending = drained.pending
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

    /// Normalize an HTML block's accumulated body segments: drop the leading separator our accumulator inserts and ensure a single trailing `\n` (matching cmark).
    private func normalizeHTMLBlockSegments(_ segs: inout UniqueArray<Segment>) {
        let nl = storage.newlineSegment
        if segs.count > 0, segs[0] == nl {
            segs.remove(at: 0)
        }
        if segs.isEmpty {
            // Empty body - emit a single newline.
            segs.append(nl)
        }
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
            // Empty body: fenced → genuinely empty; indented → a single newline.
            segs = isFenced ? UniqueArray() : UniqueArray(repeating: nl, count: 1)
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
    private func indentColumns(source: Span<UInt8>, from start: Int, to end: Int) -> Int {
        var col = 0
        for i in start..<end {
            let b = source[i]
            if b == UInt8(ascii: " ") {
                col += 1
            } else if b == UInt8(ascii: "\t") {
                col += 4 - (col & 3)
            } else {
                break
            }
        }
        return col
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
                // First content byte. Scan the digit run and check for an ordered-list delimiter. `i` is just past the first digit.
                var j = i
                while j < count, bytes[j].isASCIIDigit {
                    j += 1
                }
                if j < count, bytes[j] == UInt8(ascii: ".") || bytes[j] == UInt8(ascii: ")") {
                    // An ordered-list marker: emit the digits and delimiter as-is, then copy whatever follows.
                    output.append(b)
                    for m in i..<(j + 1) {
                        output.append(bytes[m])
                    }
                    restStart = j + 1
                } else {
                    // Not a marker: the digit begins the content, copy it verbatim with the rest.
                    restStart = i - 1
                }
                break prefix
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
            UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return false
        }
    }

    /// Walk leading whitespace from `start` toward `end`, consuming up to `columns` columns of indentation (with tab = next 4-col boundary).
    ///
    /// Returns the byte position past the consumed indentation. If a tab would over-shoot `columns`, it isn't split - the function returns the byte before the tab, leaving callers to handle the partial case (rare for indented-code purposes).
    private func advanceColumns(source: Span<UInt8>, from start: Int, to end: Int, columns: Int) -> Int {
        var i = start
        var col = 0
        while i < end && col < columns {
            let b = source[i]
            if b == UInt8(ascii: " ") {
                col += 1
                i += 1
            } else if b == UInt8(ascii: "\t") {
                let advance = 4 - (col & 3)
                if col + advance > columns {
                    break
                }
                col += advance
                i += 1
            } else {
                break
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
        var consumedTo: Int       // source offset of first byte of item content
        var isEmpty: Bool         // marker opens an empty item (only whitespace to the line end)
    }

    /// Read the padding stored on an `.item` node. Returns `nil` if the node is not actually an item.
    private func itemPadding(of node: DocumentStorage.Index) -> Int? {
        if case .item(let padding) = storage[node].data {
            return padding
        }
        return nil
    }

    /// Try to match a list marker at `firstNonSpace` within `range`. CommonMark 0.31 §5.2:
    /// - Bullet: one of `-`, `+`, `*` followed by a space, tab, or end of line.
    /// - Ordered: 1-9 ASCII digits, then `.` or `)`, then space/tab/end.
    /// `≤3` leading spaces; markers immediately at end-of-line are valid (empty item).
    private func matchListMarker(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> ListMarkerInfo? {
        let markerOffset = firstNonSpace - range.lowerBound
        if markerOffset > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
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
        // Marker must be followed by a space, tab, or end of line.
        var contentStart: Int
        var contentColumn: Int
        var isEmpty = false
        if afterMarker >= range.upperBound {
            // Empty item - the line is just `- ` (or end of input after marker).
            contentStart = afterMarker
            contentColumn = markerOffset + markerWidth + 1
            isEmpty = true
        } else {
            let next = source[afterMarker]
            if next != UInt8(ascii: " ") && next != UInt8(ascii: "\t") {
                return nil
            }
            // Per CommonMark §5.2, count the run of spaces / tabs after the marker. With 1–4 spaces of padding, the content column is the column of the first non-blank char. With 5+ spaces, the extra beyond 1 are part of the content (indented code block within the item) and the content column is `marker + 1 space`.
            var spaces = 0
            var k = afterMarker
            while k < range.upperBound, k < afterMarker + 5 {
                let b = source[k]
                if b == UInt8(ascii: " ") {
                    spaces += 1
                    k += 1
                } else if b == UInt8(ascii: "\t") {
                    // Tab in indent - count it as 1 here; column math elsewhere handles the 4-column boundary.
                    spaces += 1
                    k += 1
                } else {
                    break
                }
            }
            // Treat a fully-blank line after the marker as an empty item (e.g. `-     \n` or `-` followed by EOF after the optional space).
            let blankAfter = k >= range.upperBound
            // Emptiness follows the WHOLE trailing run, not the 5-column-capped `spaces` count: CommonMark §5.2 (cmark `parse_list_marker`) treats the item as empty when only spaces/tabs remain to the line end. `k` sits at the first non-whitespace byte or at the cap, and the loop already proved `[afterMarker, k)` blank, so scanning `[k, upper)` decides emptiness even past the cap (e.g. `*` + 6 spaces).
            isEmpty = indexOfFirstNonSpace(source: source, range: k..<range.upperBound) >= range.upperBound
            if blankAfter {
                contentStart = afterMarker + 1
                contentColumn = markerOffset + markerWidth + 1
            } else if spaces >= 5 {
                contentStart = afterMarker + 1
                contentColumn = markerOffset + markerWidth + 1
            } else {
                contentStart = afterMarker + spaces
                contentColumn = markerOffset + markerWidth + spaces
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
            consumedTo: contentStart,
            isEmpty: isEmpty
        )
    }

    /// Tag names that trigger an HTML block of type 6, sorted alphabetically for the binary-search lookup. CommonMark 0.31 §4.6.
    private static let htmlBlockType6Tags: [StaticString] = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body",
        "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header",
        "hr", "html", "iframe", "legend", "li", "link", "main", "menu",
        "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param",
        "search", "section", "summary", "table", "tbody", "td", "tfoot", "th",
        "thead", "title", "tr", "track", "ul",
    ]

    /// Tag names that trigger an HTML block of type 1 (their *closing* tag also ends the block).
    private static let htmlBlockType1Tags: [StaticString] = [
        "pre", "script", "style", "textarea",
    ]

    /// Compare a byte range to an ASCII string case-insensitively (for tag matching).
    private func bytesEqualASCIICaseInsensitive(span: Span<UInt8>, range: Range<Int>, target: StaticString) -> Bool {
        let len = range.upperBound - range.lowerBound
        if len != target.utf8CodeUnitCount {
            return false
        }
        let pointer = target.utf8Start
        for i in 0..<len {
            var a = span[range.lowerBound + i]
            var b = pointer[i]
            if a.isUppercaseASCIILetter {
                a += 32
            }
            if b.isUppercaseASCIILetter {
                b += 32
            }
            if a != b {
                return false
            }
        }
        return true
    }

    /// Try to match the start of an HTML block at `firstNonSpace` and return the type number (1–7), or `nil` if no HTML block starts here. Type 7 is not yet implemented and returns `nil`.
    ///
    /// CommonMark 0.31 §4.6.
    private func matchHTMLBlockStart(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, allowType7: Bool) -> UInt8? {
        if firstNonSpace - range.lowerBound > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
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
        // Type 5: `<![CDATA[`
        if next == UInt8(ascii: "!"),
           after + 7 < range.upperBound,
           source[after + 1] == UInt8(ascii: "["),
           source[after + 2] == UInt8(ascii: "C"),
           source[after + 3] == UInt8(ascii: "D"),
           source[after + 4] == UInt8(ascii: "A"),
           source[after + 5] == UInt8(ascii: "T"),
           source[after + 6] == UInt8(ascii: "A"),
           source[after + 7] == UInt8(ascii: "[") {
            return 5
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
                    return nil
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
            return findSubstring(span: source, range: range, needle: "-->")
        case 3:
            return findSubstring(span: source, range: range, needle: "?>")
        case 4:
            return findByte(span: source, range: range, byte: UInt8(ascii: ">"))
        case 5:
            return findSubstring(span: source, range: range, needle: "]]>")
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
    private func findSubstring(span: Span<UInt8>, range: Range<Int>, needle: StaticString) -> Bool {
        let len = needle.utf8CodeUnitCount
        if len == 0 || range.upperBound - range.lowerBound < len {
            return false
        }
        let pointer = needle.utf8Start
        var i = range.lowerBound
        let limit = range.upperBound - len
        while i <= limit {
            var matched = true
            for k in 0..<len {
                if span[i + k] != pointer[k] {
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
    private func findClosingTag(span: Span<UInt8>, range: Range<Int>, name: StaticString) -> Bool {
        let nameLen = name.utf8CodeUnitCount
        // `</` + name + `>` length:
        let totalLen = nameLen + 3
        if range.upperBound - range.lowerBound < totalLen {
            return false
        }
        let pointer = name.utf8Start
        var i = range.lowerBound
        let limit = range.upperBound - totalLen
        while i <= limit {
            if span[i] == UInt8(ascii: "<"),
               span[i + 1] == UInt8(ascii: "/") {
                let nameRange = (i + 2)..<(i + 2 + nameLen)
                var matched = true
                for k in 0..<nameLen {
                    var a = span[nameRange.lowerBound + k]
                    var b = pointer[k]
                    if a.isUppercaseASCIILetter {
                        a += 32
                    }
                    if b.isUppercaseASCIILetter {
                        b += 32
                    }
                    if a != b {
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
    private func matchBlockQuoteMarker(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> Int? {
        if firstNonSpace - range.lowerBound > 3 {
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

    /// Try to match an opening fenced code-block line. CommonMark 0.31 §4.5.
    private func matchOpeningFence(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> FenceMatch? {
        let fenceOffset = firstNonSpace - range.lowerBound
        if fenceOffset > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
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

    /// Try to match a closing fence line: ≤3 leading spaces, then a run of the same fence character at least as long as the opening fence, then only trailing whitespace. CommonMark 0.31 §4.5.
    private func matchClosingFence(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int, expectedChar: MarkdownNode.CodeBlockInfo.FenceCharacter?, minimumLength: Int) -> Bool {
        guard let expectedChar else {
            return false
        }
        if firstNonSpace - range.lowerBound > 3 {
            return false
        }
        guard firstNonSpace < range.upperBound else {
            return false
        }
        if source[firstNonSpace] != expectedChar.character {
            return false
        }
        var i = firstNonSpace
        while i < range.upperBound && source[i] == expectedChar.character {
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

    /// Return the offset within `range` that's at most `maxColumns` ASCII spaces or tabs past `range.lowerBound`.
    ///
    /// Used to strip leading indentation from fenced-code-block continuation lines.
    private func stripLeadingSpaces(source: Span<UInt8>, range: Range<Int>, maxColumns: Int) -> Int {
        var i = range.lowerBound
        var columns = 0
        while i < range.upperBound && columns < maxColumns {
            let b = source[i]
            if b == UInt8(ascii: " ") {
                columns += 1
                i += 1
            } else if b == UInt8(ascii: "\t") {
                columns += 1
                i += 1
            } else {
                break
            }
        }
        return i
    }

    /// Try to match a setext heading underline at `firstNonSpace` within `range`. CommonMark 0.31 §4.3.
    private func matchSetextUnderline(source: Span<UInt8>, range: Range<Int>, firstNonSpace: Int) -> UInt8? {
        if firstNonSpace - range.lowerBound > 3 {
            return nil
        }
        guard firstNonSpace < range.upperBound else {
            return nil
        }
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
        guard firstNonSpace < range.upperBound else {
            return false
        }
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
    /// A list is loose per CommonMark §5.3 if any item directly contains two block-level children separated by a blank line - i.e., the item has more than one block child AND a blank line was observed inside it. (The other criterion - blank lines between sibling items - is detected eagerly in `openListItem` via `pendingLooseList`.)
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

    /// The fixed byte width of a GFM tasklist marker: `[`, the checkbox symbol, `]`, and one whitespace separator.
    static let tasklistMarkerWidth = 4

    /// Classify the four leading bytes of a candidate GFM tasklist marker (`[`, ` `/`x`/`X`, `]`, ` `/`\t`).
    ///
    /// Returns the checked state (`false` for `[ ]`, `true` for `[x]`/`[X]`), or `nil` if the bytes aren't a marker. Shared by `matchTasklistMarker` (finalize-time, over the flattened paragraph content) and the continuation re-indent base (`addLine`, over the first line's source bytes) so both agree on exactly what counts as a checkbox.
    static func tasklistMarkerChecked(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Bool? {
        guard b0 == UInt8(ascii: "[") else {
            return nil
        }
        let checked: Bool
        switch b1 {
        case UInt8(ascii: " "):
            checked = false
        case UInt8(ascii: "x"), UInt8(ascii: "X"):
            checked = true
        default:
            return nil
        }
        guard b2 == UInt8(ascii: "]"),
              b3 == UInt8(ascii: " ") || b3 == UInt8(ascii: "\t") else {
            return nil
        }
        return checked
    }

    /// Match a GFM tasklist marker at the start of a paragraph chunk: `[ ]`, `[x]`, or `[X]` followed by a space or tab.
    ///
    /// Returns the `checked` state and the remaining content, or `nil` if the chunk doesn't start with a marker. cmark's tasklist extension advances past the `[x]` (3 bytes) and then the paragraph's first-non-space logic strips the following whitespace, so the content begins at the first non-space/tab after the checkbox — the ENTIRE separator run is dropped, not just the one required byte. Paragraph content is always materialized so we only handle `inSource: false` here.
    private func matchTasklistMarker(chunk: Chunk) -> (checked: Bool, remaining: Chunk)? {
        if chunk.length < Self.tasklistMarkerWidth {
            return nil
        }
        let off = chunk.offset
        guard let checked = Self.tasklistMarkerChecked(
            readByte(at: off, in: chunk),
            readByte(at: off + 1, in: chunk),
            readByte(at: off + 2, in: chunk),
            readByte(at: off + 3, in: chunk)
        ) else {
            return nil
        }
        // Skip the whole `[x]`-to-content whitespace run (space/tab), starting at the required separator
        // byte (index 3). cmark strips all of it via the paragraph's leading-whitespace handling.
        var contentStart = 3
        while contentStart < chunk.length {
            let b = readByte(at: off + contentStart, in: chunk)
            if b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") {
                contentStart += 1
            } else {
                break
            }
        }
        return (checked, chunk.extracting(contentStart..<chunk.length))
    }

    /// True when the list marker at `markerStart` is preceded on its physical line (from `lineStart`)
    /// by only whitespace - cmark's condition for recognizing a GFM task-list checkbox in the item.
    ///
    /// cmark's `scan_tasklist` scans the WHOLE line from offset 0 with the pattern
    /// `spacechar* marker spacechar+ checkbox spacechar+` (`extensions/ext_scanners.re`), passed
    /// `input->data` at block-open time (`blocks.c` open_new_blocks). A block-quote marker or an OUTER
    /// list marker on the same line before the checkbox breaks that scan, so a checkbox is recognized
    /// only when the marker is preceded on its physical line by nothing but spaces/tabs. This is a
    /// PHYSICAL-LINE property, not block-nesting depth: a block-nested item alone on its own indented
    /// line still matches (the indentation is the `spacechar*` prefix), while an item sharing its line
    /// with a `>` or an outer marker does not. Both task paths share this test: the empty-item open-time
    /// consumer (`emptyTaskItemChecked`) and the content-bearing finalize gate (`lineAnchoredTaskItems`,
    /// consulted in `runParagraphMatchers` / `tasklistContentIndentBump`).
    private func taskMarkerLineAnchored(source: Span<UInt8>, lineStart: Int, markerStart: Int) -> Bool {
        indexOfFirstNonSpace(source: source, range: lineStart..<markerStart) >= markerStart
    }

    /// If the item content beginning at `contentStart` is a GFM task-list checkbox (`[ ]`/`[x]`/`[X]`)
    /// followed by a separator and then only whitespace to `lineEnd`, return its checked state;
    /// otherwise `nil`.
    ///
    /// cmark-gfm's tasklist extension consumes the checkbox at item-OPEN time (`open_tasklist_item`),
    /// so an item whose first line holds nothing but a checkbox gets no paragraph child - it stays
    /// empty, exactly like a plain `- ` empty item, and a following unindented line closes it rather
    /// than lazily continuing into it. A task item WITH content keeps the checkbox in its first
    /// paragraph, where finalize strips it (`runParagraphMatchers`, #65); the rewrite's finalize-time
    /// recognition cannot reach the empty case (there is no paragraph to finalize), so it is detected
    /// here at open time. The predicate mirrors `matchTasklistMarker` (shared `tasklistMarkerChecked`),
    /// and the whitespace-to-`lineEnd` test confines it to the empty case - content-bearing items fail
    /// it and are left to finalize. The line-anchoring requirement (`taskMarkerLineAnchored`) is shared
    /// with the content-bearing path: an item whose marker shares its line with a `>` or an outer marker
    /// is left untouched here.
    private func emptyTaskItemChecked(
        source: Span<UInt8>, lineStart: Int, markerStart: Int, contentStart: Int, lineEnd: Int
    ) -> Bool? {
        guard storage.options.contains(.tasklist),
              taskMarkerLineAnchored(source: source, lineStart: lineStart, markerStart: markerStart),
              contentStart + Self.tasklistMarkerWidth <= lineEnd,
              let checked = Self.tasklistMarkerChecked(
                  source[contentStart],
                  source[contentStart + 1],
                  source[contentStart + 2],
                  source[contentStart + 3]
              ),
              indexOfFirstNonSpace(
                  source: source,
                  range: (contentStart + Self.tasklistMarkerWidth)..<lineEnd
              ) >= lineEnd
        else {
            return nil
        }
        return checked
    }

    /// Match a GFM footnote definition `[^label]: content` at the start of a paragraph chunk.
    ///
    /// Returns `(label, content)` chunks or `nil` if no match. The label allows ASCII alphanumerics, `_`, and `-`.
    private func matchFootnoteDefinition(chunk: Chunk) -> (label: Chunk, content: Chunk)? {
        if chunk.length < 5 {
            return nil
        }
        let off = chunk.offset
        let endOff = chunk.offset + chunk.length
        if readByte(at: off, in: chunk) != UInt8(ascii: "[") || readByte(at: off + 1, in: chunk) != UInt8(ascii: "^") {
            return nil
        }
        let labelStart = off + 2
        var i = labelStart
        while i < endOff {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "]") {
                break
            }
            let isLabelChar = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: "_") || b == UInt8(ascii: "-")
            if !isLabelChar {
                return nil
            }
            i += 1
        }
        let labelLen = i - labelStart
        if labelLen == 0 || i >= endOff {
            return nil
        }
        if i + 1 >= endOff || readByte(at: i + 1, in: chunk) != UInt8(ascii: ":") {
            return nil
        }
        var contentStart = i + 2
        while contentStart < endOff {
            let b = readByte(at: contentStart, in: chunk)
            if b != UInt8(ascii: " ") && b != UInt8(ascii: "\t") {
                break
            }
            contentStart += 1
        }
        return (
            label: Chunk(offset: labelStart, length: labelLen, inSource: chunk.inSource),
            content: Chunk(offset: contentStart, length: endOff - contentStart, inSource: chunk.inSource)
        )
    }

    /// Splice a `.footnoteDefinition` node into the paragraph's parent in place of the paragraph, then re-parent the paragraph as the definition's only child. Registers the definition in `storage.footnoteMap` keyed on the normalized label.
    private mutating func wrapInFootnoteDefinition(paragraph: DocumentStorage.Index, label: Chunk) {
        let parent = storage[paragraph].parent
        let labelRef = storage.intern(label)
        let fnIdx = storage.appendNode(NodeRecord(
            kind: .footnoteDefinition,
            parent: parent,
            data: .footnoteDefinition(label: labelRef, referenceCount: 0)
        ))
        storage.insertChildBefore(fnIdx, before: paragraph)
        storage.unlinkChild(paragraph)
        storage.appendChild(paragraph, to: fnIdx)
        // The label may be materialized into `storage.strings` (e.g. a multi-line footnote definition whose join wasn't source-contiguous), so read it from whichever buffer it lives in rather than assuming the source.
        let key = normalizeLabel(
            chunk: label
        )
        if !key.isEmpty && storage.footnoteMap[key] == nil {
            storage.footnoteMap[key] = fnIdx
        }
    }
    
    // MARK: Reference Parser
    
    // Detects and consumes link reference definitions at the start of a paragraph's materialized content during block finalization.
    //
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

    /// `true` if `chunk` contains only ASCII whitespace bytes.
    private func isBlank(chunk: Chunk) -> Bool {
        let endOffset = chunk.offset + chunk.length
        var i = chunk.offset
        while i < endOffset {
            let b = readByte(at: i, in: chunk)
            switch b {
            case UInt8(ascii: " "), UInt8(ascii: "\t"),
                 UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                i += 1
            default:
                return false
            }
        }
        return true
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
            let afterSpaces = skipSpacesTabs(from: title.afterEnd, in: chunk)
            if let lineEnd = skipLineEndOrEOF(from: afterSpaces, in: chunk) {
                titleChunk = title.chunk
                afterAll = lineEnd
            }
        }
        if afterAll < 0 {
            let afterSpaces = skipSpacesTabs(from: dest.afterEnd, in: chunk)
            guard let lineEnd = skipLineEndOrEOF(from: afterSpaces, in: chunk) else {
                return nil
            }
            afterAll = lineEnd
        }
        let key = normalizeLabel(
            chunk: label.interior
        )
        if key.isEmpty {
            return nil
        }
        if storage.referenceMap[key] == nil {
            storage.referenceMap[key] = ReferenceDefinition(
                destination: unescapeURLChunk(dest.chunk),
                title: unescapeURLChunk(titleChunk)
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
        if start >= end || readByte(at: start, in: chunk) != UInt8(ascii: "^") {
            return nil
        }
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
            if b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") {
                break
            }
            i += 1
        }
        let attrsLen = i - attrsStart
        if attrsLen == 0 {
            return nil
        }
        let afterSpaces = skipSpacesTabs(from: i, in: chunk)
        guard let afterAll = skipLineEndOrEOF(from: afterSpaces, in: chunk) else {
            return nil
        }
        let key = normalizeLabel(
            chunk: label.interior
        )
        if key.isEmpty {
            return nil
        }
        if storage.attributeReferenceMap[key] == nil {
            storage.attributeReferenceMap[key] = Chunk(
                offset: attrsStart,
                length: attrsLen,
                inSource: inSource
            )
        }
        return afterAll
    }

    /// If `chunk` contains backslash escapes (`\<ASCII punct>`) or HTML entity references, append a clean copy to the strings arena and return a chunk pointing at the new region.
    ///
    /// Reads via `readByte(at:in:)`, so it works for both source-backed and arena-backed (`inSource == false`) chunks - used by block-level reference definitions and by inline links whose destination lives in flattened/arena content.
    ///
    /// Returns `chunk` untouched if no escapes are present.
    mutating func unescapeURLChunk(_ chunk: Chunk) -> Chunk {
        guard !chunk.isEmpty else {
            return chunk
        }
        
        let endOff = chunk.offset + chunk.length
        var hasEscape = false
        for i in chunk.offset..<endOff {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "\\"), i + 1 < endOff,
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
            if b == UInt8(ascii: "\\"), j + 1 < endOff {
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
}

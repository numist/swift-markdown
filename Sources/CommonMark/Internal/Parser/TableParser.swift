/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// GFM-tables detection and transformation.
///
/// Called from `BlockParser.finalize` for `.paragraph` nodes when the `.tables` parse option is set. If the paragraph's content matches the GFM table pattern (header line containing `|` followed by a delimiter line of `:?-+:?` cells), the paragraph node is mutated in place into a `.table` node with `.tableRow` / `.tableCell` descendants.
extension BlockParser {

    /// Transform `node` (a table-pending `.paragraph`) and its content `chunk` into a `.table`, enqueueing its cells for the deferred inline-parsing pass.
    ///
    /// The paragraph is table-pending only after `classifyTableOpen` returned `.opens` for this same header and delimiter line, so the content always opens a table.
    internal mutating func parseTable(node: DocumentStorage.Index, chunk inputChunk: Chunk, sourceMap: [ArenaRun]) {
        // The table machinery (line splitting, cell extraction, pipe-unescape) reads exclusively from `storage.strings`. Paragraph content is usually already materialized there, but the source-contiguity fast path can hand us an `inSource` chunk (a zero-copy multi-line source range), which is copied into the arena so the rest of this function can address it uniformly.
        let chunk: Chunk
        // How the flattened content maps back to source for stamping rows/cells/cell-text:
        //   - `.contiguous`: the arena copy below is a byte-for-byte image of an `inSource` range, so arena offset `A` maps to source `A + delta`. The common no-leading-whitespace table.
        //   - `.flattened`: arena content carrying a run map - the rows aren't source-contiguous (a container prefix, leading whitespace, or a CRLF separates them), so the paragraph arrived as a segment list, flattened with a run map that images each row's content on its source line (see `runParagraphMatchers`), or NULs were replaced and the map images each U+FFFD back to its NUL.
        //   - `.none`: positions are off, so nothing is stamped.
        let mode: TableSourceMode
        if inputChunk.inSource {
            let offset = storage.strings.count
            for i in inputChunk.offset..<(inputChunk.offset + inputChunk.length) {
                storage.strings.append(sourceBytes[i])
            }
            chunk = Chunk(offset: offset, length: inputChunk.length, inSource: false)
            mode = positionsEnabled ? .contiguous(delta: inputChunk.offset - offset) : .none
        } else {
            chunk = inputChunk
            precondition(!positionsEnabled || !sourceMap.isEmpty, "with positions tracked, arena table content carries its run map to the source")
            mode = positionsEnabled ? .flattened(sourceMap) : .none
        }
        let lines = splitLines(chunk: chunk)
        precondition(lines.count >= 2, "a table-pending paragraph holds its header and delimiter lines")
        let delimiterAlignments = parseDelimRow(line: lines[1])
        precondition(delimiterAlignments != nil, "a table-pending paragraph's delimiter line is a delimiter row")
        let alignments = delimiterAlignments!
        precondition(splitCells(line: lines[0]).cells.count == alignments.count, "a table-pending paragraph's header has the delimiter row's column count")
        let projection = TableProjection(mode: mode, chunk: chunk)
        let columnCount = alignments.count
        let header = lines[0]
        // Materialize alignments into the per-document table-alignment array.
        let alignmentsOffset = storage.tableAlignments.count
        for a in alignments {
            storage.tableAlignments.append(a)
        }
        // Mutate the paragraph node in place.
        storage[node].kind = .table
        storage[node].data = .table(
            columnCount: columnCount,
            alignmentsOffset: alignmentsOffset
        )
        let spansEnabled = storage.options.contains(.tableSpans)
        let dittoEnabled = storage.options.contains(.tableRowspanDitto)
        // Every row built so far (its cell node indices and how many of them were parsed rather than padded in), so a rowspan marker can find the cell above it. Only tracked when `.tableSpans` is on - otherwise it stays empty (no allocation) and the span machinery is skipped entirely, keeping the common table path identical to a span-free build.
        var previousRows: [SpanRow] = []
        // Header row.
        let headerRow = appendRow(
            parent: node,
            line: header,
            alignments: alignments,
            isHeader: true,
            isLastLine: false,
            spansEnabled: spansEnabled,
            dittoEnabled: dittoEnabled,
            previousRows: previousRows,
            mode: mode,
            projection: projection
        )
        if spansEnabled {
            previousRows.append(headerRow)
        }
        // Body rows. Each subsequent line becomes one `.tableRow`.
        for k in 2..<lines.count {
            let row = appendRow(
                parent: node,
                line: lines[k],
                alignments: alignments,
                isHeader: false,
                isLastLine: k == lines.count - 1,
                spansEnabled: spansEnabled,
                dittoEnabled: dittoEnabled,
                previousRows: previousRows,
                mode: mode,
                projection: projection
            )
            if spansEnabled {
                previousRows.append(row)
            }
        }
    }

    /// The outcome of testing whether a header line + a just-arrived delimiter-candidate line open a GFM
    /// table, distinguishing the two failure modes cmark treats differently (see `classifyTableOpen`).
    internal enum TableOpenClassification {
        /// The candidate line is a valid delimiter row and the header's cell count matches — a table opens.
        case opens
        /// The candidate line is a valid delimiter row but the header's cell count differs. cmark marks the
        /// paragraph `TABLE_VISITED` here, so it never becomes a table even if a later line would match.
        case headerMismatch
        /// The candidate line is not a valid delimiter row. cmark's `scan_table_start` fails, so it runs no
        /// header check and sets no flag — a LATER line can still open a table.
        case notDelimiterRow
    }

    /// Classify a materialized `chunk` (an `inSource == false` region of `storage.strings` holding a header
    /// line + its just-arrived delimiter-candidate line, separated by `\n`) against cmark's
    /// `try_opening_table_header`. Used by the block parser during parsing to mark a paragraph
    /// "table-pending", matching cmark, which opens the table while processing the delimiter line
    /// (`try_opening_table_block`) and therefore has a TABLE, not a paragraph, as the open block for the
    /// following line: a later lazy continuation breaks out, a setext underline is suppressed, and a block
    /// start closes the table rather than being absorbed as a body row. The three-way result mirrors cmark's
    /// `CMARK_NODE__TABLE_VISITED` semantics: a column mismatch poisons the paragraph, but a candidate that
    /// isn't a delimiter row at all leaves it open to a later delimiter.
    internal mutating func classifyTableOpen(chunk: Chunk) -> TableOpenClassification {
        let lines = splitLines(chunk: chunk)
        precondition(lines.count >= 2, "a table candidate holds a header line and a delimiter-candidate line")
        guard let alignments = parseDelimRow(line: lines[1]) else {
            return .notDelimiterRow
        }
        return splitCells(line: lines[0]).cells.count == alignments.count ? .opens : .headerMismatch
    }

    /// Whether `span[range]` consists solely of GFM delimiter-row bytes — `-`, `:`, `|`, and delimiter-marker
    /// whitespace (space, tab, VT, FF) — and contains at least one `-`. A cheap necessary condition for a
    /// table delimiter row (`parseDelimRow` applies the exact rule on the materialized cells); lets the
    /// block parser's table-pending pre-check skip materializing a paragraph's two lines when the second
    /// line obviously isn't a delimiter row (ordinary prose, which starts with a letter).
    internal static func couldBeDelimiterRow(span: Span<UInt8>, range: Range<Int>) -> Bool {
        var sawDash = false
        for i in range {
            switch span[i] {
            case UInt8(ascii: "-"):
                sawDash = true
            case UInt8(ascii: ":"), UInt8(ascii: "|"), UInt8(ascii: " "), UInt8(ascii: "\t"), 0x0B, 0x0C:
                break
            default:
                return false
            }
        }
        return sawDash
    }

    /// Whether `span[range]` is a lone-pipe table row — a single unescaped `|` bracketed only by
    /// delimiter-marker whitespace (space/tab/VT/FF) — which scans to ZERO table columns. cmark's
    /// `row_from_string` creates cells only inside its scan loop; the leading pipe's
    /// `scan_table_cell_end = [|] spacechar*` consumes the pipe (and any trailing whitespace) before the
    /// loop, which then finds nothing (`n_columns == 0`), so `matches` reports the line is not a table
    /// row and the open table closes. This is the source-span twin of `splitCells`' zero-cell case, used
    /// during parsing to break a lone-pipe line out of a pending table rather than absorb it into a
    /// spurious one-empty-cell body row.
    ///
    /// Every caller passes a `firstNonSpace..<end` range (a body-row candidate cmark reads from
    /// `input + first_nonspace`), so this never sees leading whitespace. It must NOT be repurposed to classify a HEADER row: cmark builds the header
    /// from the raw, un-first-non-spaced `parent_string`, where a leading space turns `<ws>|` into one empty
    /// cell (see `splitCells`), not the zero-column lone-pipe row this reports.
    internal static func isLonePipeRow(span: Span<UInt8>, range: Range<Int>) -> Bool {
        // cmark reads the row from the first non-space, then `cmark_strbuf_trim` (space/tab) bounds the
        // scan — trim trailing space/tab to isolate the pipe and its `spacechar` padding.
        var s = range.lowerBound
        var e = range.upperBound
        precondition(s == e || !span[s].isSpaceOrTab, "a body-row candidate starts at the line's first non-space byte")
        while e > s && span[e - 1].isSpaceOrTab { e -= 1 }
        // Must lead with a pipe (the leading pipe the scan consumes), ...
        guard s < e && span[s] == UInt8(ascii: "|") else { return false }
        s += 1
        // ... with nothing but delimiter-marker whitespace after it: a second unescaped pipe or any
        // content would make the scan loop yield at least one cell, so the row would be a real row.
        for i in s..<e where !span[i].isExtensionScannerSpace {
            return false
        }
        return true
    }

    // MARK: - Row construction

    /// Build a `.tableRow` node + its cells under `parent`. Missing trailing cells are emitted as empty; extras beyond `columnCount` are dropped.
    ///
    /// When `spansEnabled`, each cell carries `.tableCell` span data: an empty `||` cell becomes a colspan filler (colspan 0) and grows the nearest preceding real cell's colspan (a leading filler has none, so it just carries colspan 0); a cell whose content is the lone rowspan marker (`^`, or `"` when `dittoEnabled`) becomes a rowspan filler (rowspan 0) and grows the matching cell in the nearest non-filler row above, with its marker text suppressed. Returns the row's cells (for the next row's rowspan resolution).
    @discardableResult
    private mutating func appendRow(
        parent: DocumentStorage.Index,
        line: Range<Int>,
        alignments: [MarkdownNode.TableAlignment],
        isHeader: Bool,
        isLastLine: Bool,
        spansEnabled: Bool,
        dittoEnabled: Bool,
        previousRows: [SpanRow],
        mode: TableSourceMode,
        projection: TableProjection?
    ) -> SpanRow {
        let rowIdx = storage.appendNode(NodeRecord(
            kind: .tableRow(isHeader: isHeader),
            parent: parent,
            data: nil
        ))
        storage.appendChild(rowIdx, to: parent)
        // The row spans its whole source line. cmark sets a table row's end column to the parent table's end column (`try_opening_table_row`): the full source line INCLUDING trailing whitespace. Interior rows already reach their line-terminating newline via `splitLines`, but the paragraph→table content chunk had its outermost whitespace trimmed (`runParagraphMatchers`), so the LAST line stops one or more bytes short of the source line end. Recover the untrimmed end from the table node's own end (the paragraph extent, stamped before this runs).
        // `nil` when positions are off, leaving the row unstamped.
        // `sourceRanges` is populated only when positions are on, which a non-`nil` projection guarantees. Last row: the paragraph→table chunk trimmed this line's trailing whitespace, so its untrimmed physical extent ends at the table node's own end.
        let untrimmedLineEnd = isLastLine ? projection.map { _ in Int(storage.sourceRanges[parent].end) } : nil
        let proj = projection.map { RowProjection(table: $0) }
        // The untrimmed row-content extent's source end, reused for the row end and the rightmost-no-closing-pipe cell.
        var rowContentEnd: Int? = nil
        if let proj {
            stampStart(rowIdx, arena: line.lowerBound, proj)
            if let untrimmedLineEnd {
                rowContentEnd = untrimmedLineEnd
                storage.setSourceEnd(rowIdx, untrimmedLineEnd)
            } else {
                rowContentEnd = proj.end(arena: line.upperBound)
                stampEnd(rowIdx, arena: line.upperBound, proj)
            }
        }
        let (cells, hadClosingPipe, hadLeadingPipe, leadingWhitespace) = splitCells(line: line)
        let columnCount = alignments.count

        // Span bookkeeping is only allocated/computed when `.tableSpans` is on. With spans off these stay empty (the empty `Array` is a non-allocating singleton) and every per-cell read below is guarded by `spansEnabled`, so the common table path does no extra allocation or work.
        var colspans: [Int] = []
        var rowspans: [Int] = []
        var skipContent: [Bool] = []
        var cellIndices: [DocumentStorage.Index] = []
        if spansEnabled {
            // Colspan is accumulated over the WHOLE parsed row, not just its first `columnCount` cells:
            // cmark's `row_from_string` grows `row->n_columns` past the table's column count, so a
            // trailing empty cell BEYOND `columnCount` still grows the nearest preceding real cell's
            // colspan (which cmark never caps). The emit loop below drops cells past `columnCount`, but a
            // surviving cell keeps its accumulated colspan (possibly > `columnCount`). Size `colspans` to
            // the full cell list so a filler / real cell beyond `columnCount` has its own slot (a real
            // cell there shields earlier cells from further increments).
            colspans = [Int](repeating: 1, count: max(columnCount, cells.count))
            rowspans = [Int](repeating: 1, count: columnCount)
            skipContent = [Bool](repeating: false, count: columnCount)
            cellIndices.reserveCapacity(columnCount)
            let markerByte = dittoEnabled ? UInt8(ascii: "\"") : UInt8(ascii: "^")
            for col in 0..<cells.count {
                let raw = cells[col]
                // Colspan filler: a zero-width cell. cmark marks any zero-width cell colspan 0 (`row_from_string`: empty buf AND start_offset == end_offset), including the first column — its `n_columns > 0` guard is always satisfied because the cell was already appended. A pipe-delimited cell is zero-width iff literally empty (`||`). A first cell's leading whitespace (only a lazy continuation header keeps it) is excluded from `raw`, but cmark scans it as the cell's bytes (`end_offset = start_offset + cell_matched - 1`), so a whitespace-only first cell is zero-width only when that whitespace is a single byte (` |` is a filler, `  |` a plain empty cell). The nearest preceding real cell (if any) absorbs the span; a leading filler has none, so it just carries colspan 0.
                if raw.isEmpty && (col > 0 || leadingWhitespace <= 1) {
                    colspans[col] = 0
                    var j = col - 1
                    while j >= 0 {
                        if colspans[j] > 0 {
                            colspans[j] += 1
                            break
                        }
                        j -= 1
                    }
                }
                // Rowspan marker: the trimmed cell is exactly the marker byte. cmark's rowspan pass (and
                // the cell emit) both stop at `columnCount`, so a marker beyond it is dropped, never
                // resolved — only track markers for cells that survive to emit. cmark tests the cell's
                // CONTENT buffer, so a pipe-preceded cell's leading VT/FF is padding here too.
                if col < columnCount {
                    let trimmed = trimCellContent(range: raw, stripLeadingVTFF: col > 0 || hadLeadingPipe)
                    if trimmed.count == 1 && storage.strings[trimmed.lowerBound] == markerByte {
                        rowspans[col] = 0
                    }
                }
            }
            // Resolve rowspan markers against the cell directly above (body rows only - the header has no row above). Scan upward past filler rows to the cell that owns the span and grow it.
            if !isHeader {
                for col in 0..<columnCount where rowspans[col] == 0 {
                    var r = previousRows.count - 1
                    var spanning: DocumentStorage.Index? = nil
                    while r >= 0 {
                        let prev = previousRows[r]
                        precondition(col < prev.cells.count, "every row of a table holds one cell per column")
                        let candidate = prev.cells[col]
                        if cellRowspan(candidate) == 0 {
                            r -= 1
                            continue
                        }
                        spanning = candidate
                        break
                    }
                    if let spanning {
                        setCellRowspan(spanning, cellRowspan(spanning) + 1)
                        skipContent[col] = true
                    }
                }
            }
        }

        for col in 0..<columnCount {
            let alignment = alignments[col]
            let cellIdx = storage.appendNode(NodeRecord(
                kind: .tableCell(
                    alignment: alignment,
                    columns: spansEnabled ? colspans[col] : 1,
                    rows: spansEnabled ? rowspans[col] : 1
                ),
                parent: rowIdx,
                data: nil
            ))
            storage.appendChild(cellIdx, to: rowIdx)
            if spansEnabled {
                cellIndices.append(cellIdx)
            }
            // Stamp the cell's source range: the between-pipes span. cmark's cell end offset spans the UNTRIMMED extent (`row_from_string`): a content cell ends at its last non-pipe byte, so `cr.upperBound` (already sitting just past it, at the closing pipe) is the half-open end. But a cell whose content trims to empty has cmark's end offset point AT the closing pipe itself (inclusive), so its half-open end is one byte further — past the closing pipe. A zero-width `||` cell is the same case (`cr` empty ⇒ `upperBound == lowerBound`). A whitespace-only or zero-width cell always has a closing pipe (a trailing empty cell is stripped by `splitCells` into autocompletion), so `+1` never overshoots the row.
            if let proj, col < cells.count {
                let cr = cells[col]
                stampStart(cellIdx, arena: cr.lowerBound, proj)
                if col == cells.count - 1 && !hadClosingPipe {
                    // Rightmost cell on a row with no closing pipe: cmark's `scan_table_cell` matches through the cell's trailing whitespace to the line end (there is no pipe to stop at), so its end offset reaches the row's untrimmed end - the same extent the row spans - rather than the trimmed-content end that `splitCells` (and the last body line's trailing-trimmed chunk) leaves in `cr.upperBound`. A closing pipe, an interior cell, or content already flush with the line end all keep the trimmed end below via the else branch.
                    storage.setSourceEnd(cellIdx, rowContentEnd)
                } else {
                    let endArena = trimCellContent(range: cr, stripLeadingVTFF: col > 0 || hadLeadingPipe).isEmpty ? cr.upperBound + 1 : cr.upperBound
                    stampEnd(cellIdx, arena: endArena, proj)
                }
            }
            if col < cells.count && !(spansEnabled && skipContent[col]) {
                let cellRange = trimCellContent(range: cells[col], stripLeadingVTFF: col > 0 || hadLeadingPipe)
                if !cellRange.isEmpty {
                    // Pre-process: replace `\|` with `|` so that whatever pipe-escaping the writer used to keep the cell intact is invisible to inline parsing - even inside a code span.
                    let cellChunk = unescapePipes(range: cellRange)
                    // Defer the cell's inline parsing to `BlockParser`'s post-block pass (via `pendingInlines`),
                    // exactly as paragraphs and headings do, so a link/footnote reference in the cell resolves
                    // against reference definitions that appear ANYWHERE in the document - including AFTER the
                    // table. cmark marks table cells `contains_inlines` and parses them in the same late
                    // `process_inlines` pass, which runs after the reference map is fully populated; parsing
                    // eagerly here would miss any definition that follows the table. The deferred pass copies the
                    // cell content, parses it, then consolidates text nodes and runs the GFM email-autolink pass -
                    // the same finishing steps a paragraph gets.
                    //
                    // No `\|` was present iff `unescapePipes` returned the range unchanged. For a contiguous
                    // source-mapped table with no escapes, the cell content is a contiguous source slice, so
                    // enqueue a source-backed chunk and inline stamping lands real source positions on the cell's
                    // text/code/etc. A flattened or escaped cell instead parses from its arena copy
                    // carrying an arena→source run map (registered on `arenaSourceMaps`); with positions off no map
                    // is registered.
                    let noEscape = cellChunk.offset == cellRange.lowerBound && cellChunk.length == cellRange.count
                    if case .contiguous(let sourceDelta) = mode, noEscape {
                        let srcLo = cellRange.lowerBound + sourceDelta
                        pendingInlines.append((cellIdx, storage.intern(
                            Chunk(offset: srcLo, length: cellRange.count, inSource: true))))
                    } else {
                        // The cell's arena→source mapping is the table's run map over the cell: one constant-shift
                        // run for a contiguous table, the row's runs for a `.flattened` one, and split at
                        // each U+FFFD so its three bytes image the one NUL. cmark stamps cell inlines by their offset
                        // in the unescaped buffer added to the cell start, ignoring any stripped `\|` backslash
                        // (`unescapedPipesMap`). why:
                        // table-cell inline positions track the reference's escape-oblivious columns
                        // unconditionally. With positions off there is no projection, so no mapping is registered.
                        if let projection {
                            let cellMap = projection.runs(from: cellRange.lowerBound, length: cellRange.count, in: self)
                            arenaSourceMaps[cellIdx] = noEscape
                                ? cellMap
                                : unescapedPipesMap(cellMap, of: Chunk(offset: cellRange.lowerBound, length: cellRange.count, inSource: false))
                        }
                        pendingInlines.append((cellIdx, storage.intern(cellChunk)))
                    }
                }
            }
        }
        return SpanRow(cells: cellIndices)
    }

    // MARK: - Source projection

    /// How a source-mapped table projects flattened-content arena offsets back to source byte offsets.
    private enum TableSourceMode {
        /// Not source-mapped: positions are off.
        case none
        /// A contiguous `inSource` range copied into the arena: arena offset `A` maps to source `A + delta`. The common no-leading-whitespace table.
        case contiguous(delta: Int)
        /// Non-contiguous rows (a container prefix, leading whitespace, or a CRLF) or replaced NULs: the paragraph arrived as arena content with a content-relative arena→source run map that images each row's content on its source line.
        case flattened([ArenaRun])
    }

    /// A source-mapped table's arena→source projection: the table content's content-relative run map, keyed from `chunkOffset` (the content's first arena byte), and its running end offsets.
    private struct TableProjection {
        let runs: [ArenaRun]
        let runEnds: [Int]
        let chunkOffset: Int

        /// `nil` when `mode` isn't source-mapped. A `.contiguous` table images its source range as one run.
        init?(mode: TableSourceMode, chunk: Chunk) {
            switch mode {
            case .none:
                return nil
            case .contiguous(let delta):
                runs = [ArenaRun(length: Int32(chunk.length), sourceOffset: Int32(chunk.offset + delta))]
            case .flattened(let flattened):
                runs = flattened
            }
            var end = 0
            runEnds = runs.map { run in
                end += Int(run.length)
                return end
            }
            chunkOffset = chunk.offset
        }

        /// The run covering the content byte at arena offset `arena`, and the content-relative offset of that run's first byte.
        func run(covering arena: Int) -> (run: ArenaRun, start: Int) {
            let k = arena - chunkOffset
            precondition(k >= 0, "a table offset lies inside its content")
            let i = firstRun(endingAfter: k)
            precondition(i < runs.count, "a table offset lies inside its content")
            return (runs[i], runStart(i))
        }

        /// The runs imaging the content bytes `[arena, arena + length)`, rebased so the first begins at offset 0 (`sliceRuns` over just the runs the window overlaps, so a table's per-cell slices stay linear in its size).
        func runs(from arena: Int, length: Int, in parser: borrowing BlockParser) -> [ArenaRun] {
            let k = arena - chunkOffset
            let first = firstRun(endingAfter: k)
            let last = max(first, firstRun(endingAfter: k + length - 1) + 1)
            let window = Array(runs[first..<min(last, runs.count)])
            return parser.sliceRuns(window, from: k - runStart(first), length: length)
        }

        /// The index of the first run ending past content-relative offset `k` (`ContentSpan.firstIndex(endingAfter:in:)`, over an array), or `runs.count` when none does.
        private func firstRun(endingAfter k: Int) -> Int {
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
            return lo
        }

        /// The content-relative offset of run `i`'s first byte.
        private func runStart(_ i: Int) -> Int {
            i == 0 ? 0 : runEnds[i - 1]
        }
    }

    /// A single row's arena→source projection: each content byte of the row images a source byte on the row's own
    /// source line.
    private struct RowProjection {
        let table: TableProjection

        /// The source offset imaged by the content byte at arena offset `arena`.
        func start(arena: Int) -> Int {
            let (run, runStart) = table.run(covering: arena)
            precondition(run.sourceOffset >= 0, "a table row or cell boundary byte images its source")
            return Int(run.sourceOffset) + (arena - table.chunkOffset - runStart)
        }

        /// The half-open source end for a range of content ending at arena offset `arena`: just past the source byte its last byte images, so a range ending in a U+FFFD ends just past its NUL.
        func end(arena: Int) -> Int {
            start(arena: arena - 1) + 1
        }
    }

    /// Stamp a node's start from an arena offset, through the row projection.
    private mutating func stampStart(_ node: DocumentStorage.Index, arena: Int, _ proj: RowProjection) {
        storage.setSourceStart(node, proj.start(arena: arena))
    }

    /// Stamp a node's half-open end from an arena offset, through the row projection.
    private mutating func stampEnd(_ node: DocumentStorage.Index, arena: Int, _ proj: RowProjection) {
        storage.setSourceEnd(node, proj.end(arena: arena))
    }

    /// A built row's cell node indices, kept so the rows below it can resolve their rowspan markers.
    private struct SpanRow {
        let cells: [DocumentStorage.Index]
    }

    /// Current rowspan of a `.tableCell` node.
    private func cellRowspan(_ idx: DocumentStorage.Index) -> Int {
        guard case .tableCell(_, _, let rowspan) = storage[idx].kind else {
            preconditionFailure("a span row holds only table cells")
        }
        return rowspan
    }

    /// Set the rowspan of a `.tableCell` node, preserving its alignment and colspan.
    private mutating func setCellRowspan(_ idx: DocumentStorage.Index, _ value: Int) {
        if case .tableCell(let alignment, let colspan, _) = storage[idx].kind {
            storage[idx].kind = .tableCell(alignment: alignment, columns: colspan, rows: value)
        }
    }

    /// If `range` (in `storage.strings`) contains any `\|` sequences, materialize a copy with each replaced by `|` and return a chunk pointing at the new region. Otherwise return a chunk pointing at the original range.
    private mutating func unescapePipes(range: Range<Int>) -> Chunk {
        var hasEscape = false
        var i = range.lowerBound
        while i + 1 < range.upperBound {
            if storage.strings[i] == UInt8(ascii: "\\")
                && storage.strings[i + 1] == UInt8(ascii: "|") {
                hasEscape = true
                break
            }
            i += 1
        }
        if !hasEscape {
            return Chunk(
                offset: range.lowerBound,
                length: range.count,
                inSource: false
            )
        }
        let outOffset = storage.strings.count
        var j = range.lowerBound
        while j < range.upperBound {
            let b = storage.strings[j]
            if b == UInt8(ascii: "\\"), j + 1 < range.upperBound,
               storage.strings[j + 1] == UInt8(ascii: "|") {
                storage.strings.append(UInt8(ascii: "|"))
                j += 2
                continue
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

    // MARK: - Line / cell splitting

    /// Split `chunk` on `\n` boundaries. Returns ranges into `storage.strings` (caller must have `chunk.inSource == false`).
    private mutating func splitLines(chunk: Chunk) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        let endOff = chunk.offset + chunk.length
        var i = chunk.offset
        var lineStart = i
        while i < endOff {
            if storage.strings[i] == UInt8(ascii: "\n") {
                lines.append(lineStart..<i)
                lineStart = i + 1
            }
            i += 1
        }
        if lineStart < endOff {
            lines.append(lineStart..<endOff)
        }
        return lines
    }

    /// Parse the delimiter row into per-column alignments. Returns nil if the line isn't a valid delimiter row. After pipe splitting, each cell must be a valid GFM delimiter marker: `:?-+:?` bracketed by delimiter-marker whitespace (space, tab, VT, FF), with at least one column. Alignment colons are read from a space/tab-trimmed cell, reproducing cmark's alignment test on the `cmark_strbuf_trim`'d buffer (whose whitespace set excludes VT/FF), so a colon hidden behind a leading/trailing VT/FF does not set the column's alignment even though the marker stays valid.
    private func parseDelimRow(line: Range<Int>) -> [MarkdownNode.TableAlignment]? {
        let cells = splitCells(line: line).cells
        precondition(!cells.isEmpty, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        var alignments: [MarkdownNode.TableAlignment] = []
        alignments.reserveCapacity(cells.count)
        for cell in cells {
            // Validity: cmark's `scan_table_start` validates a marker as
            // `table_marker = spacechar*[:]?[-]+[:]?spacechar*` with `spacechar = [ \t\v\f]`, so trim
            // space/tab AND VT/FF to isolate the `:?-+:?` shape. An interior VT/FF is untouched by this
            // edge trim, so it (correctly) fails the all-dashes check below.
            let marker = trimTableDelimiterSpace(range: cell)
            var s = marker.lowerBound
            var e = marker.upperBound
            if s < e && storage.strings[s] == UInt8(ascii: ":") {
                s += 1
            }
            if e > s && storage.strings[e - 1] == UInt8(ascii: ":") {
                e -= 1
            }
            if s >= e {
                return nil
            }
            for j in s..<e {
                if storage.strings[j] != UInt8(ascii: "-") {
                    return nil
                }
            }
            // Alignment: cmark reads the colon flags from the cell buffer produced by `cmark_strbuf_trim`,
            // whose whitespace set (`cmark_isspace`) is space/tab/CR/LF and EXCLUDES VT/FF. So a colon
            // hidden behind a leading/trailing VT/FF is not the buffer's first/last byte and does not set
            // the alignment - the marker stays valid but the column reports no alignment. Reading colons
            // from a space/tab-trimmed window (`trimSpaceTabs`, not `marker`) reproduces that: a delimiter
            // cell never contains CR/LF (`splitLines` drops the LF; a CR is resolved as a line terminator
            // upstream), so dropping CR/LF from this trim can't differ from `cmark_strbuf_trim` here.
            // `aligned` is non-empty because it is a superset of the non-empty `marker`.
            let aligned = trimSpaceTabs(range: cell)
            let leftColon = storage.strings[aligned.lowerBound] == UInt8(ascii: ":")
            let rightColon = storage.strings[aligned.upperBound - 1] == UInt8(ascii: ":")
            let a: MarkdownNode.TableAlignment
            switch (leftColon, rightColon) {
            case (true, true): a = .center
            case (true, false): a = .left
            case (false, true): a = .right
            case (false, false): a = .none
            }
            alignments.append(a)
        }
        return alignments
    }

    /// Split `line` into cells on unescaped `|`. Strips a single trailing `|` if present (with optional surrounding whitespace), and a single leading `|` only when the row's first byte is that pipe (no whitespace before it). `hadClosingPipe` reports whether a trailing `|` was stripped, so the caller can tell a rightmost cell capped by a pipe from one that runs to the line end. `leadingWhitespace` is zero: a row starts at its first non-space byte.
    private func splitCells(line: Range<Int>) -> (cells: [Range<Int>], hadClosingPipe: Bool, hadLeadingPipe: Bool, leadingWhitespace: Int) {
        var s = line.lowerBound
        var e = line.upperBound
        let leadingWhitespace = 0
        let trimmedLeadingSpace = leadingWhitespace > 0
        while e > s && storage.strings[e - 1].isSpaceOrTab {
            e -= 1
        }
        // cmark's `row_from_string` strips a leading pipe only through `scan_table_cell_end` at offset 0
        // (`[|] spacechar*`), which requires the FIRST byte to be `|`. A pipe reached only after leading
        // whitespace is therefore NOT a stripped leading pipe: cmark leaves that whitespace as an empty
        // leading cell's content and treats the pipe as its closing delimiter (` |` → one empty cell,
        // `colspan 0`, not the zero-column lone-pipe row that `|` alone yields).
        var hadLeadingPipe = false
        if s < e && storage.strings[s] == UInt8(ascii: "|") && !trimmedLeadingSpace {
            s += 1
            hadLeadingPipe = true
        }
        var hadClosingPipe = false
        // A closing pipe may be followed by `spacechar*` (space/tab/VT/FF) per cmark's
        // `scan_table_cell_end = [|] spacechar*`. Space/tab were trimmed above; look past any trailing
        // VT/FF for the pipe. Consume the pipe + that padding only if a (non-escaped) pipe is actually
        // there — otherwise trailing VT/FF is the last cell's content (`cmark_strbuf_trim` keeps VT/FF).
        var pipeEnd = e
        while pipeEnd > s && storage.strings[pipeEnd - 1].isExtensionScannerSpace {
            pipeEnd -= 1
        }
        if pipeEnd > s && storage.strings[pipeEnd - 1] == UInt8(ascii: "|") {
            // Don't strip a backslash-escaped pipe.
            if pipeEnd - 2 < s || storage.strings[pipeEnd - 2] != UInt8(ascii: "\\") {
                e = pipeEnd - 1
                hadClosingPipe = true
            }
        }
        var cells: [Range<Int>] = []
        var cellStart = s
        var i = s
        while i < e {
            // A `|` is a cell delimiter unless the byte directly before it is a backslash, which escapes it.
            // cmark's re2c cell scanner `table_cell = (escaped_char | [^|\r\n])+` takes the LONGEST match
            // (`ext_scanners.re`), so a backslash immediately before a `|` always pulls the pipe into the cell
            // as an escaped pipe — the backslashes ahead of that last one are always consumable, so parity
            // doesn't matter. `unescapePipes` later drops the one backslash sitting directly before the pipe.
            if storage.strings[i] == UInt8(ascii: "|")
                && (i == s || storage.strings[i - 1] != UInt8(ascii: "\\")) {
                cells.append(cellStart..<i)
                cellStart = i + 1
            }
            i += 1
        }
        // A lone leading pipe with only whitespace after it (`|`, or `|` + space/tab/VT/FF) is ZERO cells,
        // not one empty cell: cmark's `row_from_string` creates cells only inside its scan loop, and the
        // leading pipe's `scan_table_cell_end = [|] spacechar*` (spacechar = space/tab/VT/FF) consumes the
        // pipe and any trailing whitespace before the loop, which then finds nothing. Without this, `|`
        // counts as 1 column and a `|` header spuriously matches a 1-column delimiter (`|\n-|` → Table),
        // where cmark sees 0 vs 1 columns and keeps a paragraph. Space/tab were already trimmed from `e`
        // above; the `isExtensionScannerSpace` check additionally covers a trailing VT/FF (also `spacechar`,
        // and fuzzer-reachable via FF). A leading+trailing pipe (`||`) has `hadClosingPipe`, so its one
        // empty cell (appended below) is kept.
        if cells.isEmpty && hadLeadingPipe && !hadClosingPipe
            && (cellStart..<e).allSatisfy({ storage.strings[$0].isExtensionScannerSpace }) {
            return (cells, hadClosingPipe, hadLeadingPipe, leadingWhitespace)
        }
        cells.append(cellStart..<e)
        return (cells, hadClosingPipe, hadLeadingPipe, leadingWhitespace)
    }

    private func trimSpaceTabs(range: Range<Int>) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        while s < e && storage.strings[s].isSpaceOrTab {
            s += 1
        }
        while e > s && storage.strings[e - 1].isSpaceOrTab {
            e -= 1
        }
        return s..<e
    }

    /// Trim a table cell's RANGE down to the CONTENT cmark inline-parses. A PIPE-PRECEDED cell has its
    /// leading post-pipe `spacechar` run (space/tab/VT/FF) consumed by `scan_table_cell_end` (recorded as
    /// the cell's `internal_offset`), so pass `stripLeadingVTFF: true`; the row's FIRST cell when there
    /// is no leading pipe is not pipe-preceded, so its only leading trim is `cmark_strbuf_trim` (space/tab,
    /// VT/FF NOT trimmed) — pass `false`. The trailing edge is always `cmark_strbuf_trim` (space/tab only;
    /// a trailing VT/FF stays content). The cell NODE range is stamped from the untrimmed span (it includes
    /// the leading whitespace, as cmark's cell start_offset does); this range is the cell's content buffer
    /// (`cell->buf`), which cmark inline-parses and also tests for the lone rowspan marker.
    private func trimCellContent(range: Range<Int>, stripLeadingVTFF: Bool) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        if stripLeadingVTFF {
            while s < e && storage.strings[s].isExtensionScannerSpace {
                s += 1
            }
        } else {
            precondition(s == e || !storage.strings[s].isSpaceOrTab, "a row's first cell starts past the row's leading spaces and tabs")
        }
        while e > s && storage.strings[e - 1].isSpaceOrTab {
            e -= 1
        }
        return s..<e
    }

    /// Trim leading/trailing GFM delimiter-marker whitespace - space, tab, VT (0x0B), FF (0x0C) - from
    /// `range` (in `storage.strings`). This is `scan_table_start`'s `spacechar = [ \t\v\f]`, the padding
    /// around a delimiter marker (`:?-+:?`); used ONLY to validate the delimiter cell's shape, never for
    /// cell content or alignment (which follow cmark's `cmark_strbuf_trim`, excluding VT/FF).
    private func trimTableDelimiterSpace(range: Range<Int>) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        while s < e && storage.strings[s].isExtensionScannerSpace {
            s += 1
        }
        while e > s && storage.strings[e - 1].isExtensionScannerSpace {
            e -= 1
        }
        return s..<e
    }
}

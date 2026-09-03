/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// GFM-tables detection and transformation.
///
/// Called from `BlockParser.finalize` for `.paragraph` nodes when the `.tables` parse option is set. If the paragraph's content matches the GFM table pattern (header line containing `|` followed by a delimiter line of `:?-+:?` cells), the paragraph node is mutated in place into a `.table` node with `.tableRow` / `.tableCell` descendants.
extension BlockParser {

    /// Try to transform `node` (a `.paragraph`) and its content `chunk` into a `.table`.
    /// Only supports reading from the standard source (not materialized strings).
    /// Returns `true` on success (caller should skip inline-parsing the original paragraph since the cells were already inline-parsed). Returns `false` when the chunk doesn't match the table pattern.
    internal mutating func parseTable(node: DocumentStorage.Index, chunk inputChunk: Chunk, sourceMap: [ArenaRun]) throws(MarkdownDocument.Error) -> Bool {
        // The table machinery (line splitting, cell extraction, pipe-unescape) reads exclusively from `storage.strings`. Paragraph content is usually already materialized there, but the source-contiguity fast path can hand us an `inSource` chunk (a zero-copy multi-line source range). A table's delimiter (second) line must be a delimiter row - only `-`, `:`, `|`, and delimiter-marker whitespace (space, tab, VT, FF), with at least one `-` - so before paying for a copy we scan the chunk's second line directly in the source: any other character there means this paragraph can't be a table and we bail without materializing, which keeps the overwhelmingly common non-table paragraph zero-copy. (The header line need NOT contain a pipe: a single-column table like `a\n|-` or `a\n:-` has a pipe-less header. `parseDelimRow` + the column-count match below are the exact gate; this scan is only the cheap necessary condition that avoids the copy.) Only when the second line clears that gate do we copy into the arena so the rest of this function can address it uniformly. Only paid when `.tables` is enabled.
        let chunk: Chunk
        // How the flattened content maps back to source for stamping rows/cells/cell-text:
        //   - `.contiguous`: the arena copy below is a byte-for-byte image of an `inSource` range, so arena offset `A` maps to source `A + delta`. The common no-leading-whitespace table.
        //   - `.flattened`: a top-level row had leading whitespace, so the paragraph arrived as a non-contiguous segment list, flattened with a re-indent run map that re-bases each row's content to the table's content column (cmark's cell-column re-base; see `runParagraphMatchers`). A row nested in a block quote / list (also non-contiguous, but not enrolled here) keeps `.none`.
        //   - `.none`: materialized content with no source image (block-quote/list/CRLF tables) - positions are left unstamped, as before.
        let mode: TableSourceMode
        if inputChunk.inSource {
            if !sourceSecondLineCouldBeDelimiterRow(chunk: inputChunk) {
                return false
            }
            let offset = storage.strings.count
            for i in inputChunk.offset..<(inputChunk.offset + inputChunk.length) {
                storage.strings.append(sourceBytes[i])
            }
            chunk = Chunk(offset: offset, length: inputChunk.length, inSource: false)
            mode = positionsEnabled ? .contiguous(delta: inputChunk.offset - offset) : .none
        } else {
            chunk = inputChunk
            // A run map is threaded in only for a top-level flattened table (`runParagraphMatchers` gates on the parent); a nested/materialized table gets an empty map and stays unstamped.
            let topLevel = storage[node].parent.map { storage[$0].kind == .document } ?? false
            mode = (positionsEnabled && topLevel && !sourceMap.isEmpty) ? .flattened(sourceMap) : .none
        }
        let lines = splitLines(chunk: chunk)
        guard let alignments = tableOpenAlignments(lines: lines) else {
            return false
        }
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
        // Cell node indices for every row built so far, so a rowspan marker can find the cell above it. Only tracked when `.tableSpans` is on - otherwise it stays empty (no allocation) and the span machinery is skipped entirely, keeping the common table path identical to a span-free build.
        var previousRows: [[DocumentStorage.Index]] = []
        // Header row.
        let headerCellIndices = try appendRow(
            parent: node,
            line: header,
            alignments: alignments,
            isHeader: true,
            isLastLine: false,
            spansEnabled: spansEnabled,
            dittoEnabled: dittoEnabled,
            previousRows: previousRows,
            mode: mode,
            chunkOffset: chunk.offset
        )
        if spansEnabled {
            previousRows.append(headerCellIndices)
        }
        // Body rows. Each subsequent line becomes one `.tableRow`.
        for k in 2..<lines.count {
            let cells = try appendRow(
                parent: node,
                line: lines[k],
                alignments: alignments,
                isHeader: false,
                isLastLine: k == lines.count - 1,
                spansEnabled: spansEnabled,
                dittoEnabled: dittoEnabled,
                previousRows: previousRows,
                mode: mode,
                chunkOffset: chunk.offset
            )
            if spansEnabled {
                previousRows.append(cells)
            }
        }
        return true
    }

    /// The per-column alignments of the delimiter row if `lines` (a materialized paragraph's physical lines,
    /// as ranges into `storage.strings`) would open a GFM table, else `nil`. This is cmark's
    /// `try_opening_table_block` gate: at least two lines, a valid delimiter second line, and a header (first)
    /// line whose cell count equals the delimiter's column count. Shared by `parseTable` (which then builds
    /// the table from the returned alignments) and `chunkOpensTable`.
    private func tableOpenAlignments(lines: [Range<Int>]) -> [MarkdownNode.TableAlignment]? {
        if lines.count < 2 {
            return nil
        }
        guard let alignments = parseDelimRow(line: lines[1]), !alignments.isEmpty else {
            return nil
        }
        // GFM: header column count must equal delimiter column count, else not a table.
        if splitCells(line: lines[0]).cells.count != alignments.count {
            return nil
        }
        return alignments
    }

    /// Whether a materialized `chunk` (an `inSource == false` region of `storage.strings` holding a
    /// paragraph's accumulated header line + its just-arrived delimiter-candidate second line, separated by
    /// `\n`) would open a GFM table. Used by the block parser during parsing to mark a paragraph
    /// "table-pending" so a later LAZY continuation line breaks out of the table + its container instead of
    /// being absorbed as a body row — matching cmark, which opens the table while processing the delimiter
    /// line (`try_opening_table_block`) and therefore has a TABLE, not a paragraph, as the open block when
    /// the lazy line arrives.
    internal mutating func chunkOpensTable(chunk: Chunk) -> Bool {
        tableOpenAlignments(lines: splitLines(chunk: chunk)) != nil
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

    // MARK: - Row construction

    /// Build a `.tableRow` node + its cells under `parent`. Missing trailing cells are emitted as empty; extras beyond `columnCount` are dropped.
    ///
    /// When `spansEnabled`, each cell carries `.tableCell` span data: an empty `||` cell becomes a colspan filler (colspan 0) and grows the nearest preceding real cell's colspan (a leading filler has none, so it just carries colspan 0); a cell whose content is the lone rowspan marker (`^`, or `"` when `dittoEnabled`) becomes a rowspan filler (rowspan 0) and grows the matching cell in the nearest non-filler row above, with its marker text suppressed. Returns the row's cell node indices (for the next row's rowspan resolution).
    @discardableResult
    private mutating func appendRow(
        parent: DocumentStorage.Index,
        line: Range<Int>,
        alignments: [MarkdownNode.TableAlignment],
        isHeader: Bool,
        isLastLine: Bool,
        spansEnabled: Bool,
        dittoEnabled: Bool,
        previousRows: [[DocumentStorage.Index]],
        mode: TableSourceMode,
        chunkOffset: Int
    ) throws(MarkdownDocument.Error) -> [DocumentStorage.Index] {
        let rowIdx = storage.appendNode(NodeRecord(
            kind: .tableRow(isHeader: isHeader),
            parent: parent,
            data: nil
        ))
        storage.appendChild(rowIdx, to: parent)
        // The row spans its whole source line. cmark sets a table row's end column to the parent table's end column (`try_opening_table_row`): the full source line INCLUDING trailing whitespace. Interior rows already reach their line-terminating newline via `splitLines`, but the paragraph→table content chunk had its outermost whitespace trimmed (`runParagraphMatchers`), so the LAST line stops one or more bytes short of the source line end. Recover the untrimmed end from the table node's own end (the paragraph extent, stamped before this runs).
        // A row occupies a single physical source line, hence a single re-indent run, so ONE projection re-bases the whole row (start, end, and every cell). `nil` when the table isn't source-mapped, leaving the row unstamped as before.
        let proj = rowProjection(mode: mode, rowStartArena: line.lowerBound, chunkOffset: chunkOffset)
        // The untrimmed row-content extent as an arena offset, reused for the row end and the rightmost-no-closing-pipe cell.
        var rowContentEndArena = line.upperBound
        if let proj {
            // `sourceRanges` is populated only when positions are on, which `proj != nil` guarantees (an unmapped table yields `nil`).
            let tableEnd = storage.sourceRanges[parent].end
            stampStart(rowIdx, arena: line.lowerBound, proj)
            if isLastLine && tableEnd >= 0 {
                // Last row: the paragraph→table chunk trimmed this line's trailing whitespace, so recover the untrimmed extent from the table node's physical end. The row NODE ends at that physical end; `tableEnd - physDelta` is the arena offset it maps from, which the projection re-bases exactly as it would an interior row's trailing byte (so the rightmost cell below re-bases the same extent).
                rowContentEndArena = tableEnd - proj.physDelta
                storage.setSourceEnd(rowIdx, tableEnd)
            } else {
                stampEnd(rowIdx, arena: line.upperBound, proj)
            }
        }
        let (cells, hadClosingPipe, hadLeadingPipe) = splitCells(line: line)
        let columnCount = alignments.count

        // Span bookkeeping is only allocated/computed when `.tableSpans` is on. With spans off these stay empty (the empty `Array` is a non-allocating singleton) and every per-cell read below is guarded by `spansEnabled`, so the common table path does no extra allocation or work.
        var colspans: [Int] = []
        var rowspans: [Int] = []
        var skipContent: [Bool] = []
        var cellIndices: [DocumentStorage.Index] = []
        if spansEnabled {
            colspans = [Int](repeating: 1, count: columnCount)
            rowspans = [Int](repeating: 1, count: columnCount)
            skipContent = [Bool](repeating: false, count: columnCount)
            cellIndices.reserveCapacity(columnCount)
            let markerByte = dittoEnabled ? UInt8(ascii: "\"") : UInt8(ascii: "^")
            for col in 0..<min(columnCount, cells.count) {
                let raw = cells[col]
                // Colspan filler: a literally empty (`||`, zero-width) cell. cmark marks any zero-width cell colspan 0 (`row_from_string`: empty buf AND start_offset == end_offset), including the first column — its `n_columns > 0` guard is always satisfied because the cell was already appended. The nearest preceding real cell (if any) absorbs the span; a leading filler has none, so it just carries colspan 0.
                if raw.isEmpty {
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
                // Rowspan marker: the trimmed cell is exactly the marker byte.
                let trimmed = trimSpaceTabs(range: raw)
                if trimmed.count == 1 && storage.strings[trimmed.lowerBound] == markerByte {
                    rowspans[col] = 0
                }
            }
            // Resolve rowspan markers against the cell directly above (body rows only - the header has no row above). Scan upward past filler rows to the cell that owns the span and grow it.
            if !isHeader {
                for col in 0..<columnCount where rowspans[col] == 0 {
                    var r = previousRows.count - 1
                    var spanning: DocumentStorage.Index? = nil
                    while r >= 0 {
                        let prev = previousRows[r]
                        guard col < prev.count else { break }
                        let candidate = prev[col]
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

        // One pair of reusable inline-scratch stacks for all cells in this row.
        var delimiters = UniqueArray<DelimiterRecord>()
        var brackets = UniqueArray<BracketRecord>()
        // Reused content scratch for all cells in this row. Owned here so its borrow stays independent of the `storage` mutations `parseInline` performs. Cell chunks are always arena-backed (`inSource == false`).
        var scratch = UniqueArray<UInt8>()
        // Reused arena→source run map for a cell whose content is parsed from an arena copy (a `\|`-unescaped or a re-based/flattened cell): a single run mapping the whole cell content to source. Owned here alongside `scratch` so its borrow stays valid for the cell's `parseInline`.
        var runScratch = UniqueArray<ArenaRun>()
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
                    stampEnd(cellIdx, arena: rowContentEndArena, proj)
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
                    // No `\|` was present iff `unescapePipes` returned the range unchanged. For a contiguous source-mapped table with no escapes, the cell content is a contiguous source slice, so parse it through a source-backed `ContentSpan` and inline stamping lands real source positions on the cell's text/code/etc. A flattened (re-based) or escaped cell instead parses from an arena copy carrying an arena→source run map; a non-source-mapped table has no map (inline positions left unstamped).
                    let noEscape = cellChunk.offset == cellRange.lowerBound && cellChunk.length == cellRange.count
                    if case .contiguous(let sourceDelta) = mode, noEscape {
                        let srcLo = cellRange.lowerBound + sourceDelta
                        let srcHi = cellRange.upperBound + sourceDelta
                        try parseInline(
                            content: ContentSpan(span: sourceBytes.extracting(srcLo..<srcHi), base: srcLo, inSource: true),
                            into: cellIdx,
                            delimiters: &delimiters, brackets: &brackets
                        )
                    } else {
                        scratch.removeAll(keepingCapacity: true)
                        do {
                            let copyMe = storage.strings.span.extracting(cellChunk.range)
                            copyMe.withUnsafeBufferPointer { buffer in
                                scratch.append(copying: buffer)
                            }
                        }
                        // Hand the inline parser a linear arena→source mapping so the cell's inlines still get positions. cellChunk.offset (arena) images cellRange.lowerBound (source); cmark stamps cell inlines by their offset in the unescaped buffer added to the cell start, ignoring any stripped `\|` backslash, so a single constant-shift run (covering the whole cell content) reproduces its columns. A `.flattened` cell re-bases via the row projection (`rebasedDelta`). why: table-cell inline positions track the reference's escape-oblivious / re-based columns unconditionally - this is NOT enrolled in `.cmarkBugCompatibility` (there was no prior spec-correct behavior to protect: these inlines were unstamped before), so there is no flag split here. A non-source-mapped table (materialized content, no source image) has no mapping - leave `runScratch` empty so the cell stays unstamped as before.
                        runScratch.removeAll(keepingCapacity: true)
                        switch mode {
                        case .contiguous(let sourceDelta):
                            runScratch.append(ArenaRun(length: Int32(cellChunk.length), sourceOffset: Int32(cellRange.lowerBound + sourceDelta)))
                        case .flattened:
                            if let proj {
                                runScratch.append(ArenaRun(
                                    length: Int32(cellChunk.length),
                                    sourceOffset: Int32(cellRange.lowerBound + proj.rebasedDelta)))
                            }
                        case .none:
                            break
                        }
                        try parseInline(
                            content: ContentSpan(span: scratch.span, base: cellChunk.offset, inSource: cellChunk.inSource, arenaRuns: runScratch.span),
                            into: cellIdx,
                            delimiters: &delimiters, brackets: &brackets
                        )
                    }
                    // Coalesce adjacent `.text` children so bracket-literal / entity / smart-punct substitutions don't leave the cell content split across sibling text nodes. cmark runs `cmark_consolidate_text_nodes` over every node's inlines uniformly; the paragraph path does the same after its `parseInline` (see `BlockParser`), but a cell is inline-parsed here on the table path, so consolidate it here too.
                    consolidateTextNodes(cellIdx)
                }
            }
        }
        return cellIndices
    }

    // MARK: - Source projection

    /// How a source-mapped table projects flattened-content arena offsets back to source byte offsets.
    private enum TableSourceMode {
        /// Not source-mapped: materialized content with no contiguous source image (block-quote/list/CRLF tables). Positions are left unstamped, as before.
        case none
        /// A contiguous `inSource` range copied into the arena: arena offset `A` maps to source `A + delta` (physical == re-based). The common no-leading-whitespace table.
        case contiguous(delta: Int)
        /// A top-level row with leading whitespace: the paragraph arrived as a non-contiguous segment list, flattened with a content-relative arena→source run map that re-bases each row's content to the table's content column (cmark's cell-column re-base). Runs carry both the re-based `sourceOffset` and the physical byte-read `physicalOffset` (the latter places the row's content end on its true physical line).
        case flattened([ArenaRun])
    }

    /// A single row's constant arena→source shifts.
    ///
    /// A table row occupies one physical source line, which lies within a single run, so one constant delta re-bases every offset in the row: `rebased = arena + rebasedDelta` (the re-indented source offset, whose column is cmark's escape-oblivious / re-based column) and `physical = arena + physDelta` (the byte-read source offset on the row's true physical line, used to place the row's content end).
    private struct RowProjection {
        let rebasedDelta: Int
        let physDelta: Int
    }

    /// Build the projection for the row whose first content byte is at arena offset `rowStartArena`, or `nil` when the table isn't source-mapped (or the row's content didn't image source).
    private func rowProjection(mode: TableSourceMode, rowStartArena: Int, chunkOffset: Int) -> RowProjection? {
        let rebasedDelta: Int
        let physDelta: Int
        switch mode {
        case .none:
            return nil
        case .contiguous(let delta):
            rebasedDelta = delta
            physDelta = delta
        case .flattened(let runs):
            // Find the content run covering the row's first byte. A row's first content byte always lands inside a real content run (never a synthetic `\n` gap between rows), so a miss / gap means the content didn't image source - leave the row unstamped.
            let target = rowStartArena - chunkOffset
            var runStart = 0
            var matched: ArenaRun? = nil
            for run in runs {
                if target >= runStart && target < runStart + Int(run.length) {
                    matched = run
                    break
                }
                runStart += Int(run.length)
            }
            guard let run = matched, run.sourceOffset >= 0, run.physicalOffset >= 0 else { return nil }
            rebasedDelta = Int(run.sourceOffset) - runStart - chunkOffset
            physDelta = Int(run.physicalOffset) - runStart - chunkOffset
        }
        return RowProjection(rebasedDelta: rebasedDelta, physDelta: physDelta)
    }

    /// Stamp a node's start from an arena offset, re-basing via the row projection (`rebased = arena + rebasedDelta`, cmark's escape-oblivious / re-based column).
    private mutating func stampStart(_ node: DocumentStorage.Index, arena: Int, _ proj: RowProjection) {
        let rebased = arena + proj.rebasedDelta
        storage.setSourceStart(node, rebased)
    }

    /// Stamp a node's half-open end from an arena offset, re-basing via the row projection (see `stampStart`).
    private mutating func stampEnd(_ node: DocumentStorage.Index, arena: Int, _ proj: RowProjection) {
        let rebased = arena + proj.rebasedDelta
        storage.setSourceEnd(node, rebased)
    }

    /// Current rowspan of a `.tableCell` node (`1` if it carries no span data).
    private func cellRowspan(_ idx: DocumentStorage.Index) -> Int {
        if case .tableCell(_, _, let rowspan) = storage[idx].kind {
            return rowspan
        }
        return 1
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

    /// `true` if the SECOND line of an `inSource` `chunk` could be a table delimiter row, reading directly from `sourceBytes` without materializing. A delimiter row consists solely of `-`, `:`, `|`, and delimiter-marker whitespace (space, tab, VT, FF) and contains at least one `-`; any other byte on the second line means the paragraph can't be a table, so this is the cheap necessary-condition gate that keeps non-table paragraphs zero-copy. (`parseDelimRow` applies the exact rule once the chunk is materialized; the header line need not contain a pipe, so a single-column table like `a\n|-` or `a\n:-` still passes here.) This runs for every paragraph (when `.tables` is on): the header line (which may be long) is skipped to its newline with a vectorized scan like `LineReader` - 16 bytes per step - and the short delimiter line is then checked byte-by-byte, bailing at the first disqualifying character (a letter, for ordinary prose). Only LF endings reach an `inSource` chunk (CRLF/CR paragraphs are materialized), so `\n` is the sole line terminator.
    private func sourceSecondLineCouldBeDelimiterRow(chunk: Chunk) -> Bool {
        let endOff = chunk.offset + chunk.length
        return sourceBytes.withUnsafeBufferPointer { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            let nl = SIMD16<UInt8>(repeating: UInt8(ascii: "\n"))
            let lanes = SIMD16<UInt8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
            let noMatch = SIMD16<UInt8>(repeating: 16)
            // Skip the header (first) line: advance to its terminating newline.
            var i = chunk.offset
            var foundNewline = false
            while i < endOff {
                // Vectorized skip over the header bytes; stop at the first `\n`.
                if i + 16 <= endOff {
                    let c = UnsafeRawPointer(base + i).loadUnaligned(as: SIMD16<UInt8>.self)
                    let matched = c .== nl
                    if !any(matched) {
                        i += 16
                        continue
                    }
                    i += Int(lanes.replacing(with: noMatch, where: .!matched).min())
                }
                if base[i] == UInt8(ascii: "\n") {
                    foundNewline = true
                    break
                }
                i += 1
            }
            // A single-line paragraph has no delimiter row and is never a table.
            if !foundNewline {
                return false
            }
            i += 1
            // Scan the delimiter (second) line: only `-`, `:`, `|`, and spaces/tabs, with at least one `-`.
            var sawDash = false
            while i < endOff {
                let b = base[i]
                if b == UInt8(ascii: "\n") {
                    break
                }
                switch b {
                case UInt8(ascii: "-"):
                    sawDash = true
                // VT (0x0B) / FF (0x0C) are delimiter-marker whitespace (`scan_table_start`'s
                // `spacechar`), so admit them alongside space/tab; `parseDelimRow` applies the exact rule.
                case UInt8(ascii: ":"), UInt8(ascii: "|"), UInt8(ascii: " "), UInt8(ascii: "\t"),
                     0x0B, 0x0C:
                    break
                default:
                    return false
                }
                i += 1
            }
            return sawDash
        }
    }

    /// Parse the delimiter row into per-column alignments. Returns nil if the line isn't a valid delimiter row. After pipe splitting, each cell must be a valid GFM delimiter marker: `:?-+:?` bracketed by delimiter-marker whitespace (space, tab, VT, FF), with at least one column. Alignment colons are read from a space/tab-trimmed cell, reproducing cmark's alignment test on the `cmark_strbuf_trim`'d buffer (whose whitespace set excludes VT/FF), so a colon hidden behind a leading/trailing VT/FF does not set the column's alignment even though the marker stays valid.
    private func parseDelimRow(line: Range<Int>) -> [MarkdownNode.TableAlignment]? {
        let cells = splitCells(line: line).cells
        if cells.isEmpty {
            return nil
        }
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

    /// Split `line` into cells on unescaped `|`. Strips a single leading and trailing `|` if present (with optional surrounding whitespace). `hadClosingPipe` reports whether a trailing `|` was stripped, so the caller can tell a rightmost cell capped by a pipe from one that runs to the line end.
    private func splitCells(line: Range<Int>) -> (cells: [Range<Int>], hadClosingPipe: Bool, hadLeadingPipe: Bool) {
        var s = line.lowerBound
        var e = line.upperBound
        while s < e && storage.strings[s].isSpaceOrTab {
            s += 1
        }
        while e > s && storage.strings[e - 1].isSpaceOrTab {
            e -= 1
        }
        var hadLeadingPipe = false
        if s < e && storage.strings[s] == UInt8(ascii: "|") {
            s += 1
            hadLeadingPipe = true
        }
        var hadClosingPipe = false
        // A closing pipe may be followed by `spacechar*` (space/tab/VT/FF) per cmark's
        // `scan_table_cell_end = [|] spacechar*`. Space/tab were trimmed above; look past any trailing
        // VT/FF for the pipe. Consume the pipe + that padding only if a (non-escaped) pipe is actually
        // there — otherwise trailing VT/FF is the last cell's content (`cmark_strbuf_trim` keeps VT/FF).
        var pipeEnd = e
        while pipeEnd > s && storage.strings[pipeEnd - 1].isTableDelimiterSpace {
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
            let b = storage.strings[i]
            if b == UInt8(ascii: "\\") && i + 1 < e {
                i += 2
                continue
            }
            if b == UInt8(ascii: "|") {
                cells.append(cellStart..<i)
                cellStart = i + 1
            }
            i += 1
        }
        cells.append(cellStart..<e)
        return (cells, hadClosingPipe, hadLeadingPipe)
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
    /// the leading whitespace, as cmark's cell start_offset does); only the inline content uses this range.
    private func trimCellContent(range: Range<Int>, stripLeadingVTFF: Bool) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        if stripLeadingVTFF {
            while s < e && storage.strings[s].isTableDelimiterSpace {
                s += 1
            }
        } else {
            while s < e && storage.strings[s].isSpaceOrTab {
                s += 1
            }
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
        while s < e && storage.strings[s].isTableDelimiterSpace {
            s += 1
        }
        while e > s && storage.strings[e - 1].isTableDelimiterSpace {
            e -= 1
        }
        return s..<e
    }
}

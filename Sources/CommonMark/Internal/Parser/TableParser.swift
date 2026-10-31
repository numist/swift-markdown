/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Tables (extension): turns a table-pending paragraph into a `.table` with `.tableRow` and `.tableCell` descendants.
extension BlockParser {

    /// Turns table-pending `node` into a `.table` and queues its cells for inline parsing. A paragraph is table-pending only once `opensTable` held for its header and delimiter row.
    internal mutating func parseTable(node: DocumentStorage.Index, chunk inputChunk: Chunk, sourceMap: [ArenaRun]) {
        // The table machinery reads only `storage.strings`, so source-backed content is copied there.
        let chunk: Chunk
        // With positions on, `image` maps the content to the source. A copied contiguous table maps by the
        // constant `contiguousDelta`; arena content (rows not contiguous in the source, or NULs replaced)
        // carries its run map.
        var contiguousDelta: Int? = nil
        var runs: [ArenaRun] = []
        if inputChunk.inSource {
            let offset = storage.strings.count
            for i in inputChunk.offset..<(inputChunk.offset + inputChunk.length) {
                storage.strings.append(sourceBytes[i])
            }
            chunk = Chunk(offset: offset, length: inputChunk.length, inSource: false)
            if positionsEnabled {
                contiguousDelta = inputChunk.offset - offset
                runs = [ArenaRun(length: Int32(chunk.length), sourceOffset: Int32(inputChunk.offset))]
            }
        } else {
            chunk = inputChunk
            precondition(!positionsEnabled || !sourceMap.isEmpty, "with positions tracked, arena table content carries its run map to the source")
            runs = positionsEnabled ? sourceMap : []
        }
        let image = positionsEnabled ? ContentImage(base: chunk.offset, runs: runs) : nil
        let lines = splitLines(chunk: chunk)
        precondition(lines.count >= 2, "a table-pending paragraph holds its header and delimiter lines")
        let alignments = parseDelimRow(line: lines[1])
        precondition(splitCells(line: lines[0]).cells.count == alignments.count, "a table-pending paragraph's header has the delimiter row's column count")
        let columnCount = alignments.count
        storage[node].kind = .table
        storage[node].data = .table(columnCount: columnCount, alignmentsOffset: 0)
        // Per column, the cell a rowspan marker in the next row grows: the nearest cell above that isn't a rowspan filler. It is kept rather than searched for, so a long column of markers stays linear. Empty without `.tableSpans`.
        var rowspanOwners: [DocumentStorage.Index?] = storage.options.contains(.tableSpans) ? Array(repeating: nil, count: columnCount) : []
        // The delimiter row (line 1) is not a row.
        for k in lines.indices where k != 1 {
            appendRow(
                parent: node,
                line: lines[k],
                alignments: alignments,
                isHeader: k == 0,
                isLastLine: k == lines.count - 1,
                rowspanOwners: &rowspanOwners,
                contiguousDelta: contiguousDelta,
                image: image
            )
        }
    }

    /// Whether arena lines `header` and `delimiter` open a table: `delimiter` is a delimiter row and `header` has as
    /// many cells (Tables (extension)). The block parser then marks the paragraph table-pending, so the table, not a
    /// paragraph, is the open block for the next line.
    ///
    /// Every delimiter-shaped paragraph line asks this, so it counts cells without building arrays.
    // Non-mutating, it measured 8% slower on a paragraph of delimiter-shaped lines.
    internal mutating func opensTable(header: Range<Int>, delimiter: Range<Int>) -> Bool {
        var columns = 0
        var isDelimiterRow = true
        forEachCell(in: delimiter) { cell in
            columns += 1
            if isDelimiterRow && delimiterAlignment(of: cell) == nil {
                isDelimiterRow = false
            }
        }
        guard isDelimiterRow else {
            return false
        }
        precondition(columns > 0, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        var headerCells = 0
        forEachCell(in: header) { _ in headerCells += 1 }
        return headerCells == columns
    }

    /// Whether `sourceBytes[range]` holds only `-`, `:`, `|` and delimiter-row padding, with at least one `-`.
    /// This necessary condition for a delimiter row lets the block parser skip materializing ordinary prose.
    internal func couldBeDelimiterRow(range: Range<Int>) -> Bool {
        var sawDash = false
        for i in range {
            switch sourceBytes[i] {
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

    /// Whether body-row `sourceBytes[range]`, from its first non-space byte, is a lone `|` with only padding
    /// after it. Such a row has no cells (`splitCells`), so it closes the table.
    internal func isLonePipeRow(range: Range<Int>) -> Bool {
        var s = range.lowerBound
        var e = range.upperBound
        precondition(s == e || !sourceBytes[s].isSpaceOrTab, "a body-row candidate starts at the line's first non-space byte")
        while e > s && sourceBytes[e - 1].isSpaceOrTab { e -= 1 }
        // Must lead with a pipe, ...
        guard s < e && sourceBytes[s] == UInt8(ascii: "|") else { return false }
        s += 1
        // ... with nothing but padding after it: a second pipe or any content forms at least one cell.
        for i in s..<e where !sourceBytes[i].isExtensionScannerSpace {
            return false
        }
        return true
    }

    // MARK: - Row construction

    /// Appends a `.tableRow` and its cells under `parent`, padding missing cells and dropping extras.
    ///
    /// With `.tableSpans`, an empty `||` cell is a colspan filler (0) that grows the nearest real cell to its left, and a cell holding only the rowspan marker (`^`, or `"` with `.tableRowspanDitto`) is a rowspan filler (0) that grows its column's owner above and drops its text. Every other cell becomes its column's owner.
    private mutating func appendRow(
        parent: DocumentStorage.Index,
        line: Range<Int>,
        alignments: [MarkdownNode.TableAlignment],
        isHeader: Bool,
        isLastLine: Bool,
        rowspanOwners: inout [DocumentStorage.Index?],
        contiguousDelta: Int?,
        image: ContentImage?
    ) {
        let rowIdx = storage.appendNode(NodeRecord(
            kind: .tableRow(isHeader: isHeader),
            parent: parent,
            data: nil
        ))
        storage.appendChild(rowIdx, to: parent)
        // The source offset imaged by arena byte `arena`, or `nil` with positions off.
        func sourceStart(arena: Int) -> Int? {
            guard let image else { return nil }
            guard let offset = image.sourceOffset(ofArenaByte: arena) else {
                preconditionFailure("a table offset lies inside its content")
            }
            return offset
        }
        // Just past the source byte that the content's last byte images, so a range ending in a U+FFFD ends past its NUL.
        func sourceEnd(arena: Int) -> Int? {
            sourceStart(arena: arena - 1).map { $0 + 1 }
        }
        // A row covers its whole source line, trailing whitespace included. Paragraph content has its trailing whitespace trimmed, so the last row ends where the table node, already stamped with the paragraph's extent, ends. So does the rightmost cell of a row with no closing pipe.
        let rowEnd = isLastLine && image != nil ? Int(storage.sourceRanges[parent].end) : sourceEnd(arena: line.upperBound)
        storage.setSourceStart(rowIdx, sourceStart(arena: line.lowerBound))
        storage.setSourceEnd(rowIdx, rowEnd)
        let (cells, hadClosingPipe, hadLeadingPipe) = splitCells(line: line)
        let columnCount = alignments.count
        // The content that is inline-parsed and tested for the rowspan marker: a cell's range trimmed of padding.
        func content(_ col: Int) -> Range<Int> {
            trimCellContent(range: cells[col], stripLeadingVTFF: col > 0 || hadLeadingPipe)
        }

        // Empty without `.tableSpans`, so the common path does not allocate.
        let spansEnabled = storage.options.contains(.tableSpans)
        var colspans: [Int] = []
        var rowspans: [Int] = []
        var skipContent: [Bool] = []
        if spansEnabled {
            // Colspan accumulates over every cell, so empty cells past `columnCount`, which are dropped, still
            // grow the nearest real cell to their left, uncapped.
            colspans = [Int](repeating: 1, count: max(columnCount, cells.count))
            rowspans = [Int](repeating: 1, count: columnCount)
            skipContent = [Bool](repeating: false, count: columnCount)
            let markerByte = storage.options.contains(.tableRowspanDitto) ? UInt8(ascii: "\"") : UInt8(ascii: "^")
            // The nearest cell to the left that isn't a colspan filler, kept so a long run of fillers stays linear.
            var lastRealCell: Int? = nil
            for col in 0..<cells.count {
                // A zero-width cell (`||`) in any column is a colspan filler; a leading one has no cell to grow.
                if cells[col].isEmpty {
                    colspans[col] = 0
                    if let lastRealCell {
                        colspans[lastRealCell] += 1
                    }
                } else {
                    lastRealCell = col
                }
                // A cell whose content is exactly the marker byte is a rowspan marker.
                if col < columnCount {
                    let trimmed = content(col)
                    if trimmed.count == 1 && storage.strings[trimmed.lowerBound] == markerByte {
                        rowspans[col] = 0
                    }
                }
            }
            // The header has no row above to grow.
            if !isHeader {
                for col in 0..<columnCount where rowspans[col] == 0 {
                    if let spanning = rowspanOwners[col] {
                        growRowspan(spanning)
                        skipContent[col] = true
                    }
                }
            }
        }

        for col in 0..<columnCount {
            let cellIdx = storage.appendNode(NodeRecord(
                kind: .tableCell(
                    alignment: alignments[col],
                    columns: spansEnabled ? colspans[col] : 1,
                    rows: spansEnabled ? rowspans[col] : 1
                ),
                parent: rowIdx,
                data: nil
            ))
            storage.appendChild(cellIdx, to: rowIdx)
            if spansEnabled && rowspans[col] != 0 {
                rowspanOwners[col] = cellIdx
            }
            guard col < cells.count else { continue }
            // A cell covers its untrimmed span between pipes. A cell whose content trims to empty also covers its closing pipe, which it always has, because `splitCells` drops a trailing empty cell.
            let cr = cells[col]
            let cellRange = content(col)
            storage.setSourceStart(cellIdx, sourceStart(arena: cr.lowerBound))
            if col == cells.count - 1 && !hadClosingPipe {
                // With no closing pipe, the rightmost cell runs to the row's untrimmed end.
                storage.setSourceEnd(cellIdx, rowEnd)
            } else {
                storage.setSourceEnd(cellIdx, sourceEnd(arena: cellRange.isEmpty ? cr.upperBound + 1 : cr.upperBound))
            }
            if cellRange.isEmpty || (spansEnabled && skipContent[col]) { continue }
            // `\|` includes a pipe in a cell's content, even inside a code span (Tables (extension)), so it becomes `|` before inline parsing.
            let cellChunk = unescapePipes(range: cellRange)
            // Cell inlines parse after the block pass, so a reference in a cell resolves against definitions
            // anywhere in the document. A contiguous table's cell without `\|` is a source slice and is
            // queued source-backed; any other cell parses from the arena, with its run map in
            // `arenaSourceMaps` when positions are on.
            let noEscape = cellChunk.offset == cellRange.lowerBound && cellChunk.length == cellRange.count
            if let contiguousDelta, noEscape {
                pendingInlines.append((cellIdx, storage.intern(
                    Chunk(offset: cellRange.lowerBound + contiguousDelta, length: cellRange.count, inSource: true))))
            } else {
                // The table's map over the cell, less each stripped backslash for an escaped cell.
                if let image {
                    let cellMap = image.runs(from: cellRange.lowerBound, length: cellRange.count, in: self)
                    arenaSourceMaps[cellIdx] = noEscape
                        ? cellMap
                        : unescapedPipesMap(cellMap, of: Chunk(offset: cellRange.lowerBound, length: cellRange.count, inSource: false))
                }
                pendingInlines.append((cellIdx, storage.intern(cellChunk)))
            }
        }
    }

    private mutating func growRowspan(_ idx: DocumentStorage.Index) {
        guard case .tableCell(let alignment, let colspan, let rowspan) = storage[idx].kind else {
            preconditionFailure("a span row holds only table cells")
        }
        storage[idx].kind = .tableCell(alignment: alignment, columns: colspan, rows: rowspan + 1)
    }

    /// `range` with each `\|` replaced by `|`, copied only if it has one.
    private mutating func unescapePipes(range: Range<Int>) -> Chunk {
        let hasEscape = range.dropLast().contains { storage.strings[$0] == UInt8(ascii: "\\") && storage.strings[$0 + 1] == UInt8(ascii: "|") }
        if !hasEscape {
            return Chunk(offset: range.lowerBound, length: range.count, inSource: false)
        }
        let outOffset = storage.strings.count
        for j in range where !(storage.strings[j] == UInt8(ascii: "\\") && j + 1 < range.upperBound && storage.strings[j + 1] == UInt8(ascii: "|")) {
            storage.strings.append(storage.strings[j])
        }
        return Chunk(offset: outOffset, length: storage.strings.count - outOffset, inSource: false)
    }

    // MARK: - Line / cell splitting

    /// Splits arena `chunk` into lines.
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

    /// Delimiter row `line`'s column alignments.
    private func parseDelimRow(line: Range<Int>) -> [MarkdownNode.TableAlignment] {
        let cells = splitCells(line: line).cells
        precondition(!cells.isEmpty, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        return cells.map { cell in
            let alignment = delimiterAlignment(of: cell)
            precondition(alignment != nil, "a table-pending paragraph's delimiter line is a delimiter row")
            return alignment!
        }
    }

    /// A delimiter-row cell's alignment, or nil if `cell` isn't one. A cell is `:?-+:?` padded by spaces, tabs, line
    /// tabulations or form feeds. Colons are read inside spaces and tabs only, so a colon behind a line tabulation or
    /// form feed sets no alignment.
    private func delimiterAlignment(of cell: Range<Int>) -> MarkdownNode.TableAlignment? {
        let marker = trim(cell, leading: \.isExtensionScannerSpace, trailing: \.isExtensionScannerSpace)
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
        // `aligned` contains the non-empty `marker`, so it is non-empty.
        let aligned = trim(cell, leading: \.isSpaceOrTab, trailing: \.isSpaceOrTab)
        let leftColon = storage.strings[aligned.lowerBound] == UInt8(ascii: ":")
        let rightColon = storage.strings[aligned.upperBound - 1] == UInt8(ascii: ":")
        switch (leftColon, rightColon) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return MarkdownNode.TableAlignment.none
        }
    }

    /// `forEachCell`'s cells of `line`, collected.
    private func splitCells(line: Range<Int>) -> (cells: [Range<Int>], hadClosingPipe: Bool, hadLeadingPipe: Bool) {
        var cells: [Range<Int>] = []
        let pipes = forEachCell(in: line) { cells.append($0) }
        return (cells, pipes.hadClosingPipe, pipes.hadLeadingPipe)
    }

    /// Calls `body` with each cell of `line`, in order. Cells split on unescaped `|`, stripping a closing `|` and the
    /// padding after it, and a leading `|` only as the row's first byte.
    // Out of line, a table-heavy parse costs 0.7% more.
    @discardableResult @inline(__always)
    private func forEachCell(in line: Range<Int>, _ body: (Range<Int>) -> Void) -> (hadClosingPipe: Bool, hadLeadingPipe: Bool) {
        var s = line.lowerBound
        var e = line.upperBound
        while e > s && storage.strings[e - 1].isSpaceOrTab {
            e -= 1
        }
        // A pipe after leading whitespace closes an empty first cell: ` |` is one empty cell, not a lone-pipe row.
        var hadLeadingPipe = false
        if s < e && storage.strings[s] == UInt8(ascii: "|") {
            s += 1
            hadLeadingPipe = true
        }
        var hadClosingPipe = false
        // A closing pipe may be followed by line tabulations or form feeds; without one, they are the last
        // cell's content.
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
        var cellCount = 0
        var cellStart = s
        var i = s
        while i < e {
            // A `|` directly after a backslash is escaped, however many backslashes precede it;
            // `unescapePipes` drops that one backslash.
            if storage.strings[i] == UInt8(ascii: "|")
                && (i == s || storage.strings[i - 1] != UInt8(ascii: "\\")) {
                body(cellStart..<i)
                cellCount += 1
                cellStart = i + 1
            }
            i += 1
        }
        // A lone leading pipe with only padding after it is zero cells, so `|\n-|` is a paragraph. `||` has
        // a closing pipe, so its one empty cell is kept.
        if cellCount == 0 && hadLeadingPipe && !hadClosingPipe
            && (cellStart..<e).allSatisfy({ storage.strings[$0].isExtensionScannerSpace }) {
            return (hadClosingPipe, hadLeadingPipe)
        }
        body(cellStart..<e)
        return (hadClosingPipe, hadLeadingPipe)
    }

    private func trim(_ range: Range<Int>, leading: (UInt8) -> Bool, trailing: (UInt8) -> Bool) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        while s < e && leading(storage.strings[s]) {
            s += 1
        }
        while e > s && trailing(storage.strings[e - 1]) {
            e -= 1
        }
        return s..<e
    }

    /// A cell's content. A pipe-preceded cell drops all leading padding; a row's first cell without a leading
    /// pipe keeps a leading line tabulation or form feed. A trailing line tabulation or form feed is content.
    private func trimCellContent(range: Range<Int>, stripLeadingVTFF: Bool) -> Range<Int> {
        precondition(stripLeadingVTFF || range.isEmpty || !storage.strings[range.lowerBound].isSpaceOrTab, "a row's first cell starts past the row's leading spaces and tabs")
        return trim(range, leading: { stripLeadingVTFF && $0.isExtensionScannerSpace }, trailing: \.isSpaceOrTab)
    }
}

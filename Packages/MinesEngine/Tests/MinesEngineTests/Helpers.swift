@testable import MinesEngine

func cell(_ row: Int, _ column: Int) -> Int { MinesGrid.index(row: row, column: column) }

/// Mines drawn as rows of the board: `M` is a mine, anything else is not. Rows not given are empty.
func mines(_ rows: [String]) -> CellSet {
    var set = CellSet()
    for (row, line) in rows.enumerated() {
        for (column, character) in line.enumerated() where character == "M" { set.insert(cell(row, column)) }
    }
    return set
}

/// Three mines in a diagonal wall cut off the top-left corner: (0,0) shows 1, (0,1) and (1,0)
/// show 2, and none of them is opened by a first tap anywhere else.
let cornerPocket = mines([
    "..M.....",
    ".M......",
    "M.......",
])
let pocket = CellSet([cell(0, 0), cell(0, 1), cell(1, 0)])

/// A full row of mines across row 5 walls off the top five rows.
let wall = mines(["", "", "", "", "", "MMMMMMMM"])

/// Every square open except `covered`: for solver positions built by hand.
func everythingOpen(except covered: CellSet) -> CellSet {
    MinesGrid.all.subtracting(covered)
}

import XCTest
@testable import KlondikeEngine

final class DealTests: XCTestCase {
    func testDealHasStandardLayout() {
        let game = KlondikeGame(seed: 42)
        for (i, column) in game.tableau.enumerated() {
            XCTAssertEqual(column.hidden.count, i, "column \(i) face-down count")
            XCTAssertEqual(column.visible.count, 1, "column \(i) face-up count")
        }
        XCTAssertEqual(game.stock.count, 24)
        XCTAssertTrue(game.waste.isEmpty)
        XCTAssertTrue(game.foundations.allSatisfy(\.isEmpty))
        XCTAssertEqual(game.board.integrityProblems, [])
        XCTAssertEqual(game.moveCount, 0)
        XCTAssertFalse(game.isWon)
    }

    func testSameSeedGivesSameDeal() {
        XCTAssertEqual(KlondikeGame(seed: 7).board, KlondikeGame(seed: 7).board)
        XCTAssertEqual(KlondikeGame(seed: 7, drawMode: .three).board, KlondikeGame(seed: 7, drawMode: .one).board)
    }

    func testDifferentSeedsGiveDifferentDeals() {
        let signatures = Set((0..<200).map { KlondikeGame(seed: UInt64($0)).board.signature })
        XCTAssertEqual(signatures.count, 200)
    }

    /// Guards against accidental changes to the shuffle: saved games and shared deal numbers
    /// depend on a seed always producing the same deal on every platform.
    func testDealForSeedIsStableAcrossPlatformsAndReleases() {
        let board = KlondikeGame(seed: 1).board
        XCTAssertEqual(board.signature, DealTests.goldenSeed1Signature)
    }

    static let goldenSeed1Signature =
        "S:qs,4c,6s,7s,ac,5s,ad,kc,6d,qc,qd,qh,9h,3h,3c,as,4s,2d,8s,10s,3d,2c,9d,7c|W:|F0:|F1:|F2:|F3:|T0:7H|T1:9s,6H|T2:4h,9c,2H|T3:8d,js,jd,2S|T4:8h,5h,5d,ah,KD|T5:5c,kh,7d,6c,10d,JC|T6:jh,3s,4d,ks,10c,10h,8C"

    func testSplitMixMatchesReferenceSequence() {
        var generator = SeededGenerator(seed: 0)
        XCTAssertEqual(generator.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(generator.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(generator.next(), 0x06C4_5D18_8009_454F)
    }

    func testBoundedRandomStaysInRangeAndCoversIt() {
        var generator = SeededGenerator(seed: 99)
        var seen = Set<Int>()
        for _ in 0..<2000 {
            let value = generator.nextInt(below: 7)
            XCTAssertTrue((0..<7).contains(value))
            seen.insert(value)
        }
        XCTAssertEqual(seen.count, 7)
    }

    func testCardCodesAndNames() {
        XCTAssertEqual(Card(1, .spades).code, "AS")
        XCTAssertEqual(Card(10, .hearts).code, "10H")
        XCTAssertEqual(Card(12, .diamonds).name, "Queen of Diamonds")
        XCTAssertEqual(Set(Card.fullDeck.map(\.index)).count, 52)
        for card in Card.fullDeck { XCTAssertEqual(Card(index: card.index), card) }
        XCTAssertNil(Card(index: 52))
        XCTAssertTrue(Card(3, .hearts).isRed)
        XCTAssertTrue(Card(3, .diamonds).isRed)
        XCTAssertFalse(Card(3, .clubs).isRed)
        XCTAssertFalse(Card(3, .spades).isRed)
    }
}

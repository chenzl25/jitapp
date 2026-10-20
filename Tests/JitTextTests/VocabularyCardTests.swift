import XCTest
@testable import JitText

final class VocabularyCardTests: XCTestCase {
    func testParsesDefaultPromptFormat() throws {
        let text = """
        Headword: ephemeral
        Part of speech: adj.
        IPA: /ɪˈfem(ə)rəl/
        Meaning: 短暂的，转瞬即逝的 — lasting for a very short time
        Usage:
        - ephemeral storage
        - largely ephemeral — 大多是短暂的
        Examples:
        - Fame on social media is often ephemeral. | 社交媒体上的名气往往转瞬即逝。
        - The container writes logs to ephemeral storage. | 容器把日志写入临时存储。
        Notes: Formal; everyday synonym is "short-lived".
        """
        let card = try XCTUnwrap(VocabularyCard.parse(text))
        XCTAssertEqual(card.headword, "ephemeral")
        XCTAssertEqual(card.partOfSpeech, "adj")
        XCTAssertEqual(card.pronunciation, "/ɪˈfem(ə)rəl/")
        XCTAssertEqual(card.meaning, "短暂的，转瞬即逝的 — lasting for a very short time")
        XCTAssertEqual(card.usage, [
            .init(phrase: "ephemeral storage"),
            .init(phrase: "largely ephemeral", note: "大多是短暂的"),
        ])
        XCTAssertEqual(card.examples.count, 2)
        XCTAssertEqual(card.examples[0], .init(text: "Fame on social media is often ephemeral.", translation: "社交媒体上的名气往往转瞬即逝。"))
        XCTAssertEqual(card.notes, "Formal; everyday synonym is \"short-lived\".")
    }

    func testParsesLegacyNumberedFormatWithTranslationOnNextLine() throws {
        let text = """
        1) **Headword:** resilient (adj.) /rɪˈzɪliənt/
        2) Pronunciation: /rɪˈzɪliənt/, ri-ZIL-ee-uhnt
        3) Meaning: 有韧性的；能迅速恢复的
        4) Usage: resilient system; resilient to change
        5) Examples:
        1. The system is resilient to node failures.
        该系统能承受节点故障。
        2. Kids are remarkably resilient.
        孩子们的恢复能力非常强。
        """
        let card = try XCTUnwrap(VocabularyCard.parse(text))
        XCTAssertEqual(card.headword, "resilient")
        XCTAssertEqual(card.partOfSpeech, "adj")
        XCTAssertEqual(card.pronunciation, "/rɪˈzɪliənt/")
        XCTAssertEqual(card.usage.map(\.phrase), ["resilient system", "resilient to change"])
        XCTAssertEqual(card.examples, [
            .init(text: "The system is resilient to node failures.", translation: "该系统能承受节点故障。"),
            .init(text: "Kids are remarkably resilient.", translation: "孩子们的恢复能力非常强。"),
        ])
    }

    func testPartialStreamParsesWithHeadwordOnly() throws {
        let card = try XCTUnwrap(VocabularyCard.parse("Headword: ephemeral\nPart of sp"))
        XCTAssertEqual(card.headword, "ephemeral")
        XCTAssertNil(card.meaning)
    }

    func testNonCardOutputFallsBack() {
        XCTAssertNil(VocabularyCard.parse("Ephemeral means lasting a very short time."))
        XCTAssertNil(VocabularyCard.parse("Meaning: something\nUsage: a, b"))
        XCTAssertNil(VocabularyCard.parse(""))
    }

    func testChineseLabels() throws {
        let card = try XCTUnwrap(VocabularyCard.parse("单词：ubiquitous\n词性：adj\n释义：无处不在的\n例句：\n- Phones are ubiquitous. ｜ 手机无处不在。"))
        XCTAssertEqual(card.headword, "ubiquitous")
        XCTAssertEqual(card.meaning, "无处不在的")
        XCTAssertEqual(card.examples, [.init(text: "Phones are ubiquitous.", translation: "手机无处不在。")])
    }
}

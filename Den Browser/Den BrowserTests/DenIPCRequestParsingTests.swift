import Testing

@testable import Den_Browser

struct DenIPCRequestParsingTests {
    @Test func sheetGetParsesTypedInputs() throws {
        #expect(try DenSheetGetInput(args: ["text", "#title"]) == .text(target: "#title"))
        #expect(try DenSheetGetInput(args: ["value", "@e1"]) == .value(target: "@e1"))
        #expect(
            try DenSheetGetInput(args: ["attr", "#link", "href"])
                == .attribute(target: "#link", name: "href")
        )
        #expect(try DenSheetGetInput(args: ["count", ".item"]) == .count(selector: ".item"))
        #expect(try DenSheetGetInput(args: ["box", "#panel"]) == .box(target: "#panel"))
    }

    @Test func sheetIsParsesTypedInputs() throws {
        #expect(try DenSheetStateInput(args: ["visible", "#title"]) == .visible(target: "#title"))
        #expect(try DenSheetStateInput(args: ["enabled", "@e1"]) == .enabled(target: "@e1"))
        #expect(
            try DenSheetStateInput(args: ["checked", "input[type=checkbox]"])
                == .checked(target: "input[type=checkbox]"))
    }

    @Test func sheetGetRejectsUnknownTarget() {
        #expect(throws: DenIPCRequestParsingError.self) {
            _ = try DenSheetGetInput(args: ["html", "#title"])
        }
    }

    @Test func sheetIsRejectsUnknownState() {
        #expect(throws: DenIPCRequestParsingError.self) {
            _ = try DenSheetStateInput(args: ["selected", "#option"])
        }
    }
}

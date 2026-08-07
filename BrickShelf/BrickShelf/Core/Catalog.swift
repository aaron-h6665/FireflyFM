import Foundation

struct BrickSet: Identifiable, Hashable {
    var id: String { number }
    let number: String
    let name: String
    let year: Int
    let age: String
    let theme: String
    let partCount: Int

    var instructionsURL: URL {
        URL(string: "https://www.lego.com/en-us/service/buildinginstructions/\(number)")!
    }
}

enum SetCatalog {
    static let items: [BrickSet] = [
        BrickSet(number: "10316", name: "The Lord of the Rings: Rivendell", year: 2023, age: "18+", theme: "Icons", partCount: 6_167),
        BrickSet(number: "21338", name: "A-Frame Cabin", year: 2023, age: "18+", theme: "Ideas", partCount: 2_082),
        BrickSet(number: "75379", name: "R2-D2", year: 2024, age: "10+", theme: "Star Wars", partCount: 1_050),
        BrickSet(number: "31147", name: "Retro Camera", year: 2024, age: "8+", theme: "Creator 3-in-1", partCount: 261)
    ]

    static func item(number: String) -> BrickSet? {
        items.first { $0.number == number }
    }

    static func search(_ text: String) -> [BrickSet] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.number.localizedStandardContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.theme.localizedCaseInsensitiveContains(query)
        }
    }

    static func setNumber(fromScannedValue value: String) -> String? {
        if let direct = item(number: value)?.number { return direct }

        let candidates = value.split(whereSeparator: { !$0.isNumber })
            .map(String.init)
            .filter { (4...7).contains($0.count) }

        return candidates.first(where: { item(number: $0) != nil })
    }
}

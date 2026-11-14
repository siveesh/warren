import Foundation
import Testing
import RelayCore
import RelaySearch
@testable import RelayUI

@MainActor
@Suite("Palette favorites")
struct PaletteFavoritesTests {
    private func command(_ name: String, favorite: Bool = false) -> RelayCommand {
        RelayCommand(name: name, command: "echo \(name)", favorite: favorite)
    }

    @Test("Empty query lists favorites first")
    func favoritesLeadSuggestions() {
        let commands = [command("Alpha"), command("Beta", favorite: true), command("Gamma", favorite: true)]
        let model = CommandPaletteModel(commands: commands, search: FuzzySearchEngine())

        #expect(model.isShowingSuggestions)
        #expect(model.favoriteSuggestions.count == 2)
        #expect(model.results.prefix(2).allSatisfy { $0.favorite })
    }

    @Test("Toggling a favorite updates suggestions immediately")
    func togglingUpdatesResults() {
        let commands = [command("Alpha"), command("Beta")]
        let model = CommandPaletteModel(commands: commands, search: FuzzySearchEngine())
        #expect(model.favoriteSuggestions.isEmpty)

        model.setFavorite(true, for: commands[1].id)
        #expect(model.favoriteSuggestions.map(\.name) == ["Beta"])

        model.setFavorite(false, for: commands[1].id)
        #expect(model.favoriteSuggestions.isEmpty)
    }

    @Test("Searching shows normal results, not suggestions")
    func searchIgnoresSuggestionLayout() {
        let commands = [command("Alpha", favorite: true), command("Beta")]
        let model = CommandPaletteModel(commands: commands, search: FuzzySearchEngine())
        model.query = "bet"

        #expect(!model.isShowingSuggestions)
        #expect(model.favoriteSuggestions.isEmpty)
        #expect(model.results.first?.name == "Beta")
    }
}

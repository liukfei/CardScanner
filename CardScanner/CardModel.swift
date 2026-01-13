import Foundation
import UIKit

struct Card: Identifiable, Codable {
    let id: UUID
    let imageIdentifier: String
    var playerName: String
    var year: Int
    var team: String
    var scannedDate: Date
    
    init(id: UUID = UUID(), imageIdentifier: String, playerName: String, year: Int, team: String, scannedDate: Date = Date()) {
        self.id = id
        self.imageIdentifier = imageIdentifier
        self.playerName = playerName
        self.year = year
        self.team = team
        self.scannedDate = scannedDate
    }
}

struct CardFilter {
    var playerName: String = ""
    var year: Int? = nil
    var team: String = ""
    
    func matches(_ card: Card) -> Bool {
        if !playerName.isEmpty && !card.playerName.localizedCaseInsensitiveContains(playerName) {
            return false
        }
        if let year = year, card.year != year {
            return false
        }
        if !team.isEmpty && !card.team.localizedCaseInsensitiveContains(team) {
            return false
        }
        return true
    }
}


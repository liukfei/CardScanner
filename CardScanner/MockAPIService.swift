import Foundation
import UIKit

class MockAPIService {
    static let shared = MockAPIService()
    
    private let playerNames = [
        "LeBron James", "Michael Jordan", "Kobe Bryant", "Stephen Curry",
        "Kevin Durant", "Giannis Antetokounmpo", "Luka Dončić", "Jayson Tatum",
        "Joel Embiid", "Nikola Jokić", "Kawhi Leonard", "Damian Lillard",
        "Devin Booker", "Ja Morant", "Zion Williamson", "Anthony Edwards"
    ]
    
    private let teams = [
        "Los Angeles Lakers", "Chicago Bulls", "Golden State Warriors",
        "Boston Celtics", "Miami Heat", "Milwaukee Bucks", "Dallas Mavericks",
        "Denver Nuggets", "Phoenix Suns", "Philadelphia 76ers", "Brooklyn Nets",
        "Portland Trail Blazers", "Memphis Grizzlies", "New Orleans Pelicans",
        "Minnesota Timberwolves", "San Antonio Spurs"
    ]
    
    private let years = [2020, 2021, 2022, 2023, 2024, 2019, 2018, 2017]
    
    private init() {}
    
    func isCard(image: UIImage) -> Bool {
        return true
    }
    
    func getCardMetadata(image: UIImage) -> (playerName: String, year: Int, team: String) {
        let playerName = playerNames.randomElement() ?? "Unknown Player"
        let year = years.randomElement() ?? 2023
        let team = teams.randomElement() ?? "Unknown Team"
        
        return (playerName, year, team)
    }
}


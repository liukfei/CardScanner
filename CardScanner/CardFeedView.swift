import SwiftUI
import PhotosUI

struct CardFeedView: View {
    @ObservedObject var scannerService: CardScannerService
    @State private var filter = CardFilter()
    @State private var showPlayerFilter = false
    @State private var showYearFilter = false
    @State private var showTeamFilter = false
    
    var filteredCards: [Card] {
        scannerService.filteredCards(using: filter)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress bar at the top when scanning
                if scannerService.isScanning {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Scanning photo library...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(scannerService.scanProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 6)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
                                    .frame(width: geometry.size.width * scannerService.scanProgress, height: 6)
                                    .animation(.linear, value: scannerService.scanProgress)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .padding(.top, 8)
                    .background(Color(.systemBackground))
                }
                
                filterBar
                
                if filteredCards.isEmpty {
                    emptyStateView
                } else {
                    cardsList
                }
            }
            .navigationTitle("My Cards")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        scannerService.scanPhotoLibrary()
                    }) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                    }
                    .disabled(scannerService.isScanning)
                }
            }
        }
    }
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                FilterButton(
                    title: "Player",
                    value: filter.playerName.isEmpty ? "All" : filter.playerName,
                    isActive: !filter.playerName.isEmpty
                ) {
                    showPlayerFilter = true
                }
                
                FilterButton(
                    title: "Year",
                    value: filter.year == nil ? "All" : "\(filter.year!)",
                    isActive: filter.year != nil
                ) {
                    showYearFilter = true
                }
                
                FilterButton(
                    title: "Team",
                    value: filter.team.isEmpty ? "All" : filter.team,
                    isActive: !filter.team.isEmpty
                ) {
                    showTeamFilter = true
                }
                
                Spacer()
                
                if !filter.playerName.isEmpty || filter.year != nil || !filter.team.isEmpty {
                    Button("Clear") {
                        filter = CardFilter()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showPlayerFilter) {
            TextFieldFilterView(
                title: "Filter by Player",
                placeholder: "Enter player name",
                value: $filter.playerName
            )
        }
        .sheet(isPresented: $showYearFilter) {
            YearFilterView(year: $filter.year)
        }
        .sheet(isPresented: $showTeamFilter) {
            TextFieldFilterView(
                title: "Filter by Team",
                placeholder: "Enter team name",
                value: $filter.team
            )
        }
    }
    
    private var cardsList: some View {
        List {
            ForEach(filteredCards) { card in
                CardRowView(card: card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            scannerService.deleteCard(card)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Cards Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(scannerService.isScanning ? "Scanning your photo library..." : "Tap the camera icon to scan your photo library for cards")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if scannerService.isScanning {
                ProgressView(value: scannerService.scanProgress)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FilterButton: View {
    let title: String
    let value: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? .blue : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct CardRowView: View {
    let card: Card
    
    var body: some View {
        HStack(spacing: 16) {
            // Placeholder for card image
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 80)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(card.playerName)
                    .font(.headline)
                
                Text(card.team)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("\(card.year)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct TextFieldFilterView: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                TextField(placeholder, text: $value)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct YearFilterView: View {
    @Binding var year: Int?
    @Environment(\.dismiss) var dismiss
    @State private var selectedYear: Int?
    
    init(year: Binding<Int?>) {
        self._year = year
        self._selectedYear = State(initialValue: year.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Year", selection: $selectedYear) {
                    Text("All").tag(nil as Int?)
                    ForEach(2015...2024, id: \.self) { yearValue in
                        Text("\(yearValue)").tag(yearValue as Int?)
                    }
                }
            }
            .navigationTitle("Filter by Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        year = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        year = selectedYear
                        dismiss()
                    }
                }
            }
        }
    }
}


import SwiftUI

struct ContentView: View {
    @StateObject private var scannerService = CardScannerService()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CameraScannerView(scannerService: scannerService)
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(0)
            
            CardFeedView(scannerService: scannerService)
                .tabItem {
                    Label("My Cards", systemImage: "rectangle.stack")
                }
                .tag(1)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


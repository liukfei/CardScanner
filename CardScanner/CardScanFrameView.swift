import SwiftUI

struct CardScanFrameView: View {
    var detectedRectangles: [DetectedRectangle] = []
    @State private var viewSize: CGSize = .zero
    @State private var scanFrameRect: CGRect = .zero
    
    // Card dimensions - standard sports card size
    // Sports cards are typically 2.5" x 3.5" (portrait orientation: width < height)
    private let cardAspectRatio: CGFloat = 2.5 / 3.5 // Width/Height ratio for sports cards ≈ 0.714
    private var cardFrameWidth: CGFloat {
        min(viewSize.width * 0.75, 280) // 75% of screen width or 280pt max
    }
    private var cardFrameHeight: CGFloat {
        cardFrameWidth / cardAspectRatio
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed overlay
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .mask(
                        // Create a mask with a transparent hole for the scan frame
                        Rectangle()
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .frame(width: cardFrameWidth, height: cardFrameHeight)
                                    .blendMode(.destinationOut)
                            )
                    )
                
                // Scan frame border
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: cardFrameWidth, height: cardFrameHeight)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                // Corner guides
                VStack {
                    HStack {
                        // Top-left corner
                        CornerGuide()
                            .offset(x: -(cardFrameWidth/2 + 15), y: -(cardFrameHeight/2 + 15))
                        
                        Spacer()
                        
                        // Top-right corner
                        CornerGuide(flipped: true)
                            .offset(x: cardFrameWidth/2 + 15, y: -(cardFrameHeight/2 + 15))
                    }
                    
                    Spacer()
                    
                    HStack {
                        // Bottom-left corner
                        CornerGuide(flipped: true, vertical: true)
                            .offset(x: -(cardFrameWidth/2 + 15), y: cardFrameHeight/2 + 15)
                        
                        Spacer()
                        
                        // Bottom-right corner
                        CornerGuide(vertical: true)
                            .offset(x: cardFrameWidth/2 + 15, y: cardFrameHeight/2 + 15)
                    }
                }
                .frame(width: cardFrameWidth, height: cardFrameHeight)
                
                // Detected rectangles within scan frame
                if !detectedRectangles.isEmpty && scanFrameRect != .zero {
                    DetectedRectanglesOverlay(
                        rectangles: detectedRectangles,
                        scanFrameRect: scanFrameRect
                    )
                }
            }
            .onAppear {
                let frameWidth = min(geometry.size.width * 0.75, 280)
                let frameHeight = frameWidth / cardAspectRatio
                viewSize = geometry.size
                scanFrameRect = CGRect(
                    x: (geometry.size.width - frameWidth) / 2,
                    y: (geometry.size.height - frameHeight) / 2,
                    width: frameWidth,
                    height: frameHeight
                )
            }
            .onChange(of: geometry.size) { newSize in
                let frameWidth = min(newSize.width * 0.75, 280)
                let frameHeight = frameWidth / cardAspectRatio
                viewSize = newSize
                scanFrameRect = CGRect(
                    x: (newSize.width - frameWidth) / 2,
                    y: (newSize.height - frameHeight) / 2,
                    width: frameWidth,
                    height: frameHeight
                )
            }
    }
    }
}

// Corner guide lines
struct CornerGuide: View {
    var flipped: Bool = false
    var vertical: Bool = false
    
    var body: some View {
        Group {
            if vertical {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 20)
            } else {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 20, height: 2)
            }
        }
    }
}

// Overlay for detected rectangles within scan frame
struct DetectedRectanglesOverlay: View {
    let rectangles: [DetectedRectangle]
    let scanFrameRect: CGRect
    
    var body: some View {
        // Show green frame matching scan frame when card is detected
        if !rectangles.isEmpty {
            DetectedRectangleView(scanFrameRect: scanFrameRect)
        }
    }
}

// Individual detected rectangle view - matches scan frame exactly
struct DetectedRectangleView: View {
    let scanFrameRect: CGRect
    
    var body: some View {
        // Green rectangle matching scan frame exactly
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.green, lineWidth: 3)
            .frame(width: scanFrameRect.width, height: scanFrameRect.height)
            .position(x: scanFrameRect.midX, y: scanFrameRect.midY)
    }
}

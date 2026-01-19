import SwiftUI
import UIKit

struct RectangleOverlayView: UIViewRepresentable {
    let rectangles: [DetectedRectangle]
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove old rectangle layers
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // Add new rectangle layers
        let viewSize = uiView.bounds.size
        guard viewSize.width > 0 && viewSize.height > 0 else { return }
        
        for rectangle in rectangles {
            let rect = rectangle.boundingBoxInView(viewSize: viewSize)
            
            // Skip if rectangle is invalid
            guard rect.width > 0 && rect.height > 0 else { continue }
            
            // Create rectangle path with rounded corners
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            
            // Create shape layer for rectangle border
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.strokeColor = UIColor.green.cgColor
            shapeLayer.lineWidth = 3.0
            shapeLayer.lineDashPattern = [10, 5]
            uiView.layer.addSublayer(shapeLayer)
            
            // Add confidence label above rectangle
            let confidenceText = String(format: "%.0f%%", rectangle.confidence * 100)
            let labelRect = CGRect(
                x: rect.origin.x,
                y: max(0, rect.origin.y - 25),
                width: rect.width,
                height: 20
            )
            
            let textLayer = CATextLayer()
            textLayer.string = confidenceText
            textLayer.fontSize = 14
            textLayer.foregroundColor = UIColor.green.cgColor
            textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
            textLayer.frame = labelRect
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.cornerRadius = 4
            uiView.layer.addSublayer(textLayer)
        }
    }
}

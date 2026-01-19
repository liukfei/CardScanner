import Foundation
import Vision
import UIKit
import CoreImage

class CardDetectionService {
    static let shared = CardDetectionService()
    
    private init() {}
    
    /// Detect rectangles in the image and identify if any contains a card
    /// - Parameters:
    ///   - image: The image to detect rectangles in
    ///   - imageSize: The actual size of the captured image (for coordinate conversion)
    ///   - scanFrameRect: The scan frame rectangle in view coordinates (optional)
    ///   - viewSize: The view size for coordinate conversion
    ///   - completion: Callback with detected rectangles and whether any contains a card
    func detectRectanglesAndCards(in image: UIImage, 
                                  imageSize: CGSize? = nil,
                                  scanFrameRect: CGRect? = nil,
                                  viewSize: CGSize? = nil,
                                  completion: @escaping ([DetectedRectangle], Bool) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([], false)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Request to detect rectangles
        let rectangleRequest = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self,
                  let observations = request.results as? [VNRectangleObservation],
                  error == nil else {
                DispatchQueue.main.async {
                    completion([], false)
                }
                return
            }
            
            // Convert observations to our model
            // Filter rectangles by aspect ratio to focus on card-like shapes
            var detectedRectangles = observations
                .filter { observation in
                    // Filter by aspect ratio - cards are typically 0.5-0.8 (width/height)
                    let aspectRatio = observation.boundingBox.width / observation.boundingBox.height
                    return aspectRatio >= 0.45 && aspectRatio <= 0.85 && observation.confidence >= 0.6
                }
                .map { observation in
                    DetectedRectangle(
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        topLeft: observation.topLeft,
                        topRight: observation.topRight,
                        bottomLeft: observation.bottomLeft,
                        bottomRight: observation.bottomRight,
                        imageSize: imageSize ?? CGSize(width: cgImage.width, height: cgImage.height),
                        viewSize: viewSize
                    )
                }
            
            // Filter rectangles to only include those within scan frame
            // If scan frame is provided, only process rectangles that overlap with it
            if let scanFrame = scanFrameRect, let viewSize = viewSize {
                detectedRectangles = detectedRectangles.filter { rectangle in
                    let rectInView = rectangle.boundingBoxInView(viewSize: viewSize)
                    
                    // Check if rectangle center is within scan frame
                    let centerX = rectInView.midX
                    let centerY = rectInView.midY
                    
                    // Also check if rectangle overlaps with scan frame (more lenient)
                    let intersection = rectInView.intersection(scanFrame)
                    let overlapArea = intersection.width * intersection.height
                    let rectArea = rectInView.width * rectInView.height
                    let scanArea = scanFrame.width * scanFrame.height
                    
                    // Accept if center is in scan frame OR if overlap is significant
                    let overlapRatio = rectArea > 0 ? overlapArea / rectArea : 0
                    let scanOverlapRatio = scanArea > 0 ? overlapArea / scanArea : 0
                    
                    return scanFrame.contains(CGPoint(x: centerX, y: centerY)) || overlapRatio > 0.3 || scanOverlapRatio > 0.3
                }
            }
            
            // Check if any rectangle contains a card
            self.checkCardsInRectangles(rectangles: detectedRectangles, image: image) { hasCard in
                DispatchQueue.main.async {
                    completion(detectedRectangles, hasCard)
                }
            }
        }
        
        // Configure rectangle detection for sports cards
        // Sports cards typically have aspect ratio around 0.6-0.7 (width/height)
        rectangleRequest.minimumAspectRatio = 0.4  // Minimum width/height ratio
        rectangleRequest.maximumAspectRatio = 0.85  // Maximum width/height ratio
        rectangleRequest.minimumSize = 0.15  // Minimum size as fraction of image
        rectangleRequest.minimumConfidence = 0.6  // Higher confidence threshold
        rectangleRequest.maximumObservations = 5  // Limit to 5 rectangles
        rectangleRequest.quadratureTolerance = 30  // Allow slight non-rectangular shapes (degrees)
        
        // Perform the request
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([rectangleRequest])
            } catch {
                DispatchQueue.main.async {
                    completion([], false)
                }
            }
        }
    }
    
    /// Check if any detected rectangle contains a card
    private func checkCardsInRectangles(rectangles: [DetectedRectangle], image: UIImage, completion: @escaping (Bool) -> Void) {
        guard !rectangles.isEmpty,
              let cgImage = image.cgImage else {
            completion(false)
            return
        }
        
        // Crop each rectangle and check if it's a card
        var foundCard = false
        
        let group = DispatchGroup()
        
        for rectangle in rectangles {
            group.enter()
            
            // Crop the rectangle region from the image
            if let croppedImage = cropImage(image: image, rectangle: rectangle) {
                // Check if the cropped region is a card
                // For now, we'll use a simple heuristic based on aspect ratio and size
                // In a real app, you'd use a YOLO model or Core ML model here
                let isCard = self.isLikelyCard(image: croppedImage)
                
                if isCard {
                    foundCard = true
                }
            }
            
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(foundCard)
        }
    }
    
    /// Crop image based on detected rectangle
    private func cropImage(image: UIImage, rectangle: DetectedRectangle) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // Convert normalized coordinates to pixel coordinates
        let boundingBox = rectangle.boundingBox
        let x = boundingBox.origin.x * imageSize.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height // Flip Y coordinate
        let width = boundingBox.width * imageSize.width
        let height = boundingBox.height * imageSize.height
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height).integral
        
        guard cropRect.width > 0, cropRect.height > 0,
              cropRect.origin.x >= 0, cropRect.origin.y >= 0,
              cropRect.maxX <= imageSize.width, cropRect.maxY <= imageSize.height,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    /// Simple heuristic to check if an image is likely a card
    /// In a real app, this would use a YOLO or Core ML model
    private func isLikelyCard(image: UIImage) -> Bool {
        // Check aspect ratio - cards are typically rectangular (around 0.6-0.7 aspect ratio)
        let aspectRatio = image.size.width / image.size.height
        let isCardAspectRatio = aspectRatio >= 0.45 && aspectRatio <= 0.85
        
        // Check size - cards should be reasonably sized (more lenient)
        let minSize: CGFloat = 50  // Reduced from 100 to be more lenient
        let hasReasonableSize = image.size.width >= minSize && image.size.height >= minSize
        
        // If aspect ratio and size match, consider it a card
        // Also use mock API as fallback for testing
        if isCardAspectRatio && hasReasonableSize {
            return true
        }
        
        // Fallback to mock API (for testing purposes)
        return MockAPIService.shared.isCard(image: image)
    }
}

// Model for detected rectangle
struct DetectedRectangle: Identifiable {
    let id = UUID()
    let boundingBox: CGRect // Normalized coordinates (0.0 to 1.0)
    let confidence: Float
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let imageSize: CGSize // Actual image size for coordinate conversion
    let viewSize: CGSize? // Actual image size for coordinate conversion
    
    /// Convert normalized bounding box to view coordinates
    /// Vision uses normalized coordinates with origin at bottom-left
    /// This handles the coordinate system conversion and aspect ratio differences
    func boundingBoxInView(viewSize: CGSize? = nil) -> CGRect {
        let targetViewSize = viewSize ?? self.viewSize ?? CGSize(width: 375, height: 812) // Default iPhone size
        // Vision coordinates are normalized (0-1) with origin at bottom-left
        // Convert to pixel coordinates based on actual image size
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height
        
        // Calculate image aspect ratio vs view aspect ratio
        let imageAspect = imageWidth / imageHeight
        let viewAspect = targetViewSize.width / targetViewSize.height
        
        // Convert normalized coordinates to image pixel coordinates
        let pixelX = boundingBox.origin.x * imageWidth
        let pixelWidth = boundingBox.width * imageWidth
        // Vision Y is from bottom, convert to top-left origin
        let visionY = boundingBox.origin.y * imageHeight
        let pixelHeight = boundingBox.height * imageHeight
        let pixelY = imageHeight - visionY - pixelHeight
        
        // Handle aspect ratio difference (resizeAspectFill crops image)
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        
        if imageAspect > viewAspect {
            // Image is wider - will be cropped on sides (vertical fill)
            scaleY = targetViewSize.height / imageHeight
            scaleX = scaleY
            let scaledImageWidth = imageWidth * scaleX
            offsetX = (targetViewSize.width - scaledImageWidth) / 2
        } else {
            // Image is taller - will be cropped on top/bottom (horizontal fill)
            scaleX = targetViewSize.width / imageWidth
            scaleY = scaleX
            let scaledImageHeight = imageHeight * scaleY
            offsetY = (targetViewSize.height - scaledImageHeight) / 2
        }
        
        // Apply scaling and offset
        return CGRect(
            x: pixelX * scaleX + offsetX,
            y: pixelY * scaleY + offsetY,
            width: pixelWidth * scaleX,
            height: pixelHeight * scaleY
        )
    }
}

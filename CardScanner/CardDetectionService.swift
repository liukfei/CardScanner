import Foundation
import Vision
import UIKit
import CoreImage

class CardDetectionService {
    static let shared = CardDetectionService()
    
    // Allow external access to extractCardInfo for YOLO integration
    func extractCardInfo(from image: UIImage, completion: @escaping (CardInfo?) -> Void) {
        self.extractCardInfoPrivate(from: image, completion: completion)
    }
    
    private init() {}
    
    /// Detect rectangles in the image and identify if any contains a card
    /// - Parameters:
    ///   - image: The image to detect rectangles in
    ///   - imageSize: The actual size of the captured image (for coordinate conversion)
    ///   - scanFrameRect: The scan frame rectangle in view coordinates (optional)
    ///   - viewSize: The view size for coordinate conversion
    ///   - completion: Callback with detected rectangles and detected card information (if any)
    func detectRectanglesAndCards(in image: UIImage, 
                                  imageSize: CGSize? = nil,
                                  scanFrameRect: CGRect? = nil,
                                  viewSize: CGSize? = nil,
                                  completion: @escaping ([DetectedRectangle], CardInfo?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([], nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Request to detect rectangles
        let rectangleRequest = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self,
                  let observations = request.results as? [VNRectangleObservation],
                  error == nil else {
                DispatchQueue.main.async {
                    completion([], nil)
                }
                return
            }
            
            // Convert observations to our model
            // Filter rectangles by aspect ratio to focus on card-like shapes
            var detectedRectangles = observations
                .filter { observation in
                    // Filter by aspect ratio - cards are typically 0.5-0.8 (width/height)
                    let aspectRatio = observation.boundingBox.width / observation.boundingBox.height
                    return aspectRatio >= 0.45 && aspectRatio <= 0.85 && observation.confidence >= 0.5
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
                    // More lenient: accept if rectangle overlaps with scan frame at all, or center is close
                    let overlapRatio = rectArea > 0 ? overlapArea / rectArea : 0
                    let scanOverlapRatio = scanArea > 0 ? overlapArea / scanArea : 0
                    
                    // Check if center is within scan frame (with some margin)
                    let margin: CGFloat = 20
                    let expandedFrame = scanFrame.insetBy(dx: -margin, dy: -margin)
                    let centerInFrame = expandedFrame.contains(CGPoint(x: centerX, y: centerY))
                    
                    // Accept if center is in expanded frame OR if there's any overlap
                    return centerInFrame || overlapRatio > 0.1 || scanOverlapRatio > 0.1
                }
            }
            
            // Check if any rectangle contains a card and extract card info
            self.checkCardsInRectangles(rectangles: detectedRectangles, image: image) { cardInfo in
                DispatchQueue.main.async {
                    completion(detectedRectangles, cardInfo)
                }
            }
        }
        
        // Configure rectangle detection for sports cards
        // Sports cards typically have aspect ratio around 0.6-0.7 (width/height)
        rectangleRequest.minimumAspectRatio = 0.4  // Minimum width/height ratio
        rectangleRequest.maximumAspectRatio = 0.85  // Maximum width/height ratio
        rectangleRequest.minimumSize = 0.05  // Lower minimum size to detect cards at closer distances (was 0.15)
        rectangleRequest.minimumConfidence = 0.5  // Slightly lower confidence to catch more cards (was 0.6)
        rectangleRequest.maximumObservations = 5  // Limit to 5 rectangles
        rectangleRequest.quadratureTolerance = 30  // Allow slight non-rectangular shapes (degrees)
        
        // Perform the request
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([rectangleRequest])
            } catch {
                DispatchQueue.main.async {
                    completion([], nil)
                }
            }
        }
    }
    
    /// Card information extracted from OCR and face detection
    struct CardInfo {
        let playerName: String?
        let year: Int?
        let team: String?
        let allText: String
        let hasFace: Bool  // Whether a face was detected on the card
        let faceBounds: CGRect?  // Normalized face bounding box (0.0 to 1.0)
    }
    
    /// Check if any detected rectangle contains a card and extract card information using OCR
    private func checkCardsInRectangles(rectangles: [DetectedRectangle], image: UIImage, completion: @escaping (CardInfo?) -> Void) {
        guard !rectangles.isEmpty,
              let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        // Crop each rectangle and check if it's a card, then extract text using OCR
        var foundCardInfo: CardInfo? = nil
        
        let group = DispatchGroup()
        
        for rectangle in rectangles {
            group.enter()
            
            // Crop the rectangle region from the image
            if let croppedImage = cropImage(image: image, rectangle: rectangle) {
                // Check if the cropped region is a card
                let isCard = self.isLikelyCard(image: croppedImage)
                
                if isCard {
                    // Use OCR to extract text from the card
                    self.extractCardInfoPrivate(from: croppedImage) { cardInfo in
                        // Use the first valid card info found
                        if foundCardInfo == nil, let info = cardInfo {
                            foundCardInfo = info
                        }
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(foundCardInfo)
        }
    }
    
    /// Extract card information using OCR and face detection
    private func extractCardInfoPrivate(from image: UIImage, completion: @escaping (CardInfo?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Create OCR request
        let ocrRequest = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  error == nil else {
                completion(nil)
                return
            }
            
            // Extract all text from observations
            var allText = ""
            var recognizedStrings: [String] = []
            
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                let text = topCandidate.string
                allText += text + "\n"
                recognizedStrings.append(text)
            }
            
            // Parse card information from text
            let textInfo = self.parseCardInfo(from: recognizedStrings, allText: allText)
            
            // Also detect faces in the card image
            self.detectFace(in: image) { hasFace, faceBounds in
                let cardInfo = CardInfo(
                    playerName: textInfo.playerName,
                    year: textInfo.year,
                    team: textInfo.team,
                    allText: textInfo.allText,
                    hasFace: hasFace,
                    faceBounds: faceBounds
                )
                completion(cardInfo)
            }
        }
        
        // Configure OCR for better accuracy
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.recognitionLanguages = ["en-US", "en-GB"]
        ocrRequest.usesLanguageCorrection = true
        
        // Perform OCR
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([ocrRequest])
            } catch {
                completion(nil)
            }
        }
    }
    
    /// Detect faces in the card image using Vision framework
    /// Note: This detects faces but cannot identify specific players
    /// For identifying specific players, you would need a custom-trained model or external API
    private func detectFace(in image: UIImage, completion: @escaping (Bool, CGRect?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(false, nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Create face detection request
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            guard let observations = request.results as? [VNFaceObservation],
                  error == nil,
                  let firstFace = observations.first else {
                completion(false, nil)
                return
            }
            
            // Return if face was detected and its bounding box (normalized coordinates)
            let faceBounds = firstFace.boundingBox
            completion(true, faceBounds)
        }
        
        // Perform face detection
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([faceRequest])
            } catch {
                completion(false, nil)
            }
        }
    }
    
    /// Parse card information from recognized text
    private func parseCardInfo(from recognizedStrings: [String], allText: String) -> CardInfo {
        var playerName: String? = nil
        var year: Int? = nil
        var team: String? = nil
        
        // Common NBA team names (abbreviations and full names)
        let teamNames = [
            "Lakers", "Bulls", "Warriors", "Celtics", "Heat", "Bucks", "Mavericks",
            "Nuggets", "Suns", "76ers", "Nets", "Trail Blazers", "Grizzlies",
            "Pelicans", "Timberwolves", "Spurs", "Rockets", "Clippers", "Kings",
            "Jazz", "Thunder", "Magic", "Pistons", "Hornets", "Wizards",
            "Hawks", "Knicks", "Pacers", "Cavaliers", "Raptors",
            "Los Angeles Lakers", "Chicago Bulls", "Golden State Warriors",
            "Boston Celtics", "Miami Heat", "Milwaukee Bucks", "Dallas Mavericks",
            "Denver Nuggets", "Phoenix Suns", "Philadelphia 76ers", "Brooklyn Nets",
            "Portland Trail Blazers", "Memphis Grizzlies", "New Orleans Pelicans",
            "Minnesota Timberwolves", "San Antonio Spurs", "Houston Rockets",
            "LA Clippers", "Sacramento Kings", "Utah Jazz", "Oklahoma City Thunder",
            "Orlando Magic", "Detroit Pistons", "Charlotte Hornets", "Washington Wizards",
            "Atlanta Hawks", "New York Knicks", "Indiana Pacers", "Cleveland Cavaliers",
            "Toronto Raptors"
        ]
        
        // Look for player name (usually the longest capitalized string or contains common name patterns)
        for text in recognizedStrings {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract year (4-digit number between 1900-2030)
            if year == nil {
                let yearPattern = #"\b(19\d{2}|20[0-3]\d)\b"#
                if let yearRange = trimmed.range(of: yearPattern, options: .regularExpression) {
                    let yearString = String(trimmed[yearRange])
                    year = Int(yearString)
                }
            }
            
            // Extract team name
            if team == nil {
                for teamName in teamNames {
                    if trimmed.localizedCaseInsensitiveContains(teamName) {
                        team = teamName
                        break
                    }
                }
            }
            
            // Extract player name (usually longer text that might contain first and last name)
            // Look for text with 2+ words, capitalized, and doesn't match year/team patterns
            if playerName == nil {
                let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if words.count >= 2 {
                    let isCapitalized = words.allSatisfy { word in
                        word.first?.isUppercase == true || word.count <= 1
                    }
                    let hasYear = trimmed.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
                    let isTeam = teamNames.contains { teamName in
                        trimmed.localizedCaseInsensitiveContains(teamName)
                    }
                    
                    if isCapitalized && !hasYear && !isTeam {
                        playerName = trimmed
                    }
                }
            }
        }
        
        // Return text info only (face detection is done separately)
        return CardInfo(
            playerName: playerName,
            year: year,
            team: team,
            allText: allText.trimmingCharacters(in: .whitespacesAndNewlines),
            hasFace: false,  // Will be updated by face detection
            faceBounds: nil
        )
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

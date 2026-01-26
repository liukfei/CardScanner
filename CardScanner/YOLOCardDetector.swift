import Foundation
import CoreML
import Vision
import UIKit
import CoreImage

/// Service for detecting baseball cards using a custom-trained YOLO model
/// 
/// Usage:
/// 1. Convert your YOLO model to Core ML format (.mlmodel or .mlpackage)
///    - Use coremltools: `coremltools.converters.convert(yolo_model, source='pytorch'/'tensorflow'/'onnx')`
///    - Or use Apple's converter tools
/// 2. Add the .mlmodel file to your Xcode project
/// 3. Replace "YourYOLOModel" with your actual model name
/// 4. Configure the model input/output in this file based on your model's specifications
class YOLOCardDetector {
    static let shared = YOLOCardDetector()
    
    private var model: VNCoreMLModel?
    private let modelQueue = DispatchQueue(label: "yolo.model.queue", qos: .userInitiated)
    
    private init() {
        loadModel()
    }
    
    /// Load the YOLO Core ML model
    /// Replace "YourYOLOModel" with your actual model name
    private func loadModel() {
        modelQueue.async { [weak self] in
            // TODO: Replace "YourYOLOModel" with your actual model name
            // Example: "BaseballCardYOLOv8", "CardDetector_v5", etc.
            guard let modelURL = Bundle.main.url(forResource: "YourYOLOModel", withExtension: "mlmodel") ??
                                 Bundle.main.url(forResource: "YourYOLOModel", withExtension: "mlpackage") else {
                print("⚠️ YOLO Model not found. Please add your .mlmodel or .mlpackage file to the project.")
                print("📝 Steps to add:")
                print("   1. Convert your YOLO model to Core ML format")
                print("   2. Drag the .mlmodel/.mlpackage file into Xcode project")
                print("   3. Update 'YourYOLOModel' in YOLOCardDetector.swift to match your model name")
                return
            }
            
            do {
                // Load Core ML model
                let mlModel = try MLModel(contentsOf: modelURL)
                
                // Create Vision request with Core ML model
                if let coreMLModel = try? VNCoreMLModel(for: mlModel) {
                    DispatchQueue.main.async {
                        self?.model = coreMLModel
                        print("✅ YOLO Model loaded successfully: \(modelURL.lastPathComponent)")
                    }
                } else {
                    print("⚠️ Failed to create VNCoreMLModel from MLModel")
                }
            } catch {
                print("❌ Error loading YOLO model: \(error.localizedDescription)")
            }
        }
    }
    
    /// Detect cards in image using YOLO model
    /// - Parameters:
    ///   - image: Image to detect cards in
    ///   - completion: Callback with detected cards and their information
    func detectCards(in image: UIImage, completion: @escaping ([YOLODetection], CardDetectionService.CardInfo?) -> Void) {
        guard let model = model,
              let cgImage = image.cgImage else {
            completion([], nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Create Vision request with YOLO model
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self,
                  error == nil else {
                completion([], nil)
                return
            }
            
            // Parse YOLO model output
            // Note: The output format depends on your YOLO model version
            // YOLOv5/v8 typically outputs: [confidence, x_center, y_center, width, height, class_scores...]
            let detections = self.parseYOLOOutput(from: request)
            
            // If cards detected, extract card info using OCR
            if let bestDetection = detections.first {
                // Crop the detected card region
                if let croppedImage = self.cropImage(image: image, detection: bestDetection) {
                    // Extract card information using OCR
                    CardDetectionService.shared.extractCardInfo(from: croppedImage) { cardInfo in
                        completion(detections, cardInfo)
                    }
                } else {
                    completion(detections, nil)
                }
            } else {
                completion([], nil)
            }
        }
        
        // Configure request
        request.imageCropAndScaleOption = .scaleFill  // or .scaleFit, .centerCrop based on your model
        
        // Perform detection
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("❌ Error performing YOLO detection: \(error.localizedDescription)")
                completion([], nil)
            }
        }
    }
    
    /// Parse YOLO model output
    /// This needs to be customized based on your specific YOLO model's output format
    private func parseYOLOOutput(from request: VNRequest) -> [YOLODetection] {
        var detections: [YOLODetection] = []
        
        // Get observations from Vision request
        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            // If using custom output, parse MLFeatureValue directly
            // Example for YOLO output:
            /*
            guard let featureValue = request.results?.first as? MLFeatureValue,
                  let multiArray = featureValue.multiArrayValue else {
                return detections
            }
            
            // Parse YOLO output format: [batch, detections, features]
            // features: [x_center, y_center, width, height, confidence, class_scores...]
            let detectionCount = multiArray.shape[1].intValue
            let featureCount = multiArray.shape[2].intValue
            
            for i in 0..<detectionCount {
                let confidenceIndex = i * featureCount + 4
                let confidence = Double(truncating: multiArray[confidenceIndex])
                
                // Filter by confidence threshold
                if confidence > 0.5 {
                    let x = Double(truncating: multiArray[i * featureCount])
                    let y = Double(truncating: multiArray[i * featureCount + 1])
                    let width = Double(truncating: multiArray[i * featureCount + 2])
                    let height = Double(truncating: multiArray[i * featureCount + 3])
                    
                    // Find class with highest score
                    var maxScore: Double = 0
                    var classIndex = 0
                    for j in 5..<featureCount {
                        let score = Double(truncating: multiArray[i * featureCount + j])
                        if score > maxScore {
                            maxScore = score
                            classIndex = j - 5
                        }
                    }
                    
                    let boundingBox = CGRect(
                        x: (x - width/2),
                        y: (y - height/2),
                        width: width,
                        height: height
                    )
                    
                    detections.append(YOLODetection(
                        boundingBox: boundingBox,
                        confidence: Float(confidence),
                        classIndex: classIndex,
                        className: "Card_\(classIndex)"
                    ))
                }
            }
            */
            return detections
        }
        
        // Parse VNRecognizedObjectObservation (if model outputs recognized objects)
        for observation in observations {
            // Filter by confidence threshold
            guard observation.confidence > 0.5 else { continue }
            
            let boundingBox = observation.boundingBox
            
            // Get top label (VNClassificationObservation has identifier & confidence only, no index)
            let topLabel = observation.labels.first
            let className = topLabel?.identifier ?? "Unknown"
            let classIndex = topLabel.flatMap { label in
                observation.labels.firstIndex(where: { $0.identifier == label.identifier })
            } ?? 0
            
            detections.append(YOLODetection(
                boundingBox: boundingBox,
                confidence: observation.confidence,
                classIndex: classIndex,
                className: className
            ))
        }
        
        // Sort by confidence (highest first)
        detections.sort { $0.confidence > $1.confidence }
        
        return detections
    }
    
    /// Crop image based on detection bounding box
    private func cropImage(image: UIImage, detection: YOLODetection) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // Convert normalized coordinates to pixel coordinates
        let x = detection.boundingBox.origin.x * imageSize.width
        let y = (1 - detection.boundingBox.origin.y - detection.boundingBox.height) * imageSize.height // Flip Y
        let width = detection.boundingBox.width * imageSize.width
        let height = detection.boundingBox.height * imageSize.height
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    /// Check if model is loaded and ready
    var isModelLoaded: Bool {
        return model != nil
    }
}

/// Represents a detection from YOLO model
struct YOLODetection {
    let boundingBox: CGRect  // Normalized coordinates (0.0 to 1.0)
    let confidence: Float
    let classIndex: Int
    let className: String
    
    /// Convert to DetectedRectangle format for compatibility
    func toDetectedRectangle(imageSize: CGSize, viewSize: CGSize?) -> DetectedRectangle {
        return DetectedRectangle(
            boundingBox: boundingBox,
            confidence: confidence,
            topLeft: CGPoint(x: boundingBox.minX, y: boundingBox.maxY),
            topRight: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY),
            bottomLeft: CGPoint(x: boundingBox.minX, y: boundingBox.minY),
            bottomRight: CGPoint(x: boundingBox.maxX, y: boundingBox.minY),
            imageSize: imageSize,
            viewSize: viewSize
        )
    }
}

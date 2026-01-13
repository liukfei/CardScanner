import Foundation
import Photos
import UIKit
import Combine

class CardScannerService: ObservableObject {
    @Published var cards: [Card] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    
    private let mockAPIService = MockAPIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Store processed image identifiers to avoid duplicates
    private var processedImageIdentifiers = Set<String>()
    
    init() {
        loadCards()
    }
    
    /// Scan photo library for cards
    func scanPhotoLibrary() {
        guard !isScanning else { return }
        
        isScanning = true
        scanProgress = 0.0
        
        // Request photo library access
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .authorized {
            performScan()
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        self?.performScan()
                    } else {
                        self?.isScanning = false
                    }
                }
            }
        } else {
            isScanning = false
        }
    }
        
    private func processImage(_ asset: PHAsset) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        
        let imageIdentifier = asset.localIdentifier
        
        // Skip if already processed
        guard !processedImageIdentifiers.contains(imageIdentifier) else {
            return
        }
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            guard let self = self,
                  let image = image else {
                return
            }
            
            // Check if image is a card using mock API
            if self.mockAPIService.isCard(image: image) {
                // Get card metadata
                let metadata = self.mockAPIService.getCardMetadata(image: image)
                
                // Create card object
                let card = Card(
                    imageIdentifier: imageIdentifier,
                    playerName: metadata.playerName,
                    year: metadata.year,
                    team: metadata.team
                )
                
                DispatchQueue.main.async {
                    // Add to cards array if not already present
                    if !self.cards.contains(where: { $0.imageIdentifier == imageIdentifier }) {
                        self.cards.append(card)
                        self.processedImageIdentifiers.insert(imageIdentifier)
                        self.saveCards()
                    }
                }
            }
        }
    }
    
    private func performScan() {
        // Fetch all images from photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let totalCount = assets.count
        
        guard totalCount > 0 else {
            isScanning = false
            return
        }
        
        // Process images in batches to avoid blocking
        let batchSize = 10
        var processedCount = 0
        
        var processBatch: ((Int) -> Void)?
        processBatch = { [weak self] (startIndex: Int) in
            guard let self = self else { return }
            
            let endIndex = min(startIndex + batchSize, totalCount)
            
            for i in startIndex..<endIndex {
                let asset = assets.object(at: i)
                self.processImage(asset)
                processedCount += 1
                
                DispatchQueue.main.async {
                    self.scanProgress = Double(processedCount) / Double(totalCount)
                }
            }
            
            // Continue with next batch
            if endIndex < totalCount {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
                    processBatch?(endIndex)
                }
            } else {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.scanProgress = 1.0
                }
            }
        }
        
        // Start processing
        DispatchQueue.global(qos: .userInitiated).async {
            processBatch?(0)
        }
    }
    
    /// Filter cards based on filter criteria
    func filteredCards(using filter: CardFilter) -> [Card] {
        if filter.playerName.isEmpty && filter.year == nil && filter.team.isEmpty {
            return cards
        }
        return cards.filter { filter.matches($0) }
    }
    
    /// Save cards to UserDefaults
    private func saveCards() {
        if let encoded = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(encoded, forKey: "SavedCards")
        }
    }
    
    /// Load cards from UserDefaults
    private func loadCards() {
        if let data = UserDefaults.standard.data(forKey: "SavedCards"),
           let decoded = try? JSONDecoder().decode([Card].self, from: data) {
            cards = decoded
            processedImageIdentifiers = Set(decoded.map { $0.imageIdentifier })
        }
    }
    
    /// Scan a single image captured from camera
    func scanImage(_ image: UIImage, completion: @escaping (Card?) -> Void) {
        guard !isScanning else {
            completion(nil)
            return
        }
        
        isScanning = true
        
        // Generate a unique identifier for this camera-captured image
        let imageIdentifier = "camera_\(UUID().uuidString)_\(Date().timeIntervalSince1970)"
        
        // Skip if somehow already processed (unlikely for camera captures)
        guard !processedImageIdentifiers.contains(imageIdentifier) else {
            isScanning = false
            completion(nil)
            return
        }
        
        // Process the image in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Check if image is a card using mock API
            if self.mockAPIService.isCard(image: image) {
                // Get card metadata
                let metadata = self.mockAPIService.getCardMetadata(image: image)
                
                // Create card object
                let card = Card(
                    imageIdentifier: imageIdentifier,
                    playerName: metadata.playerName,
                    year: metadata.year,
                    team: metadata.team
                )
                
                DispatchQueue.main.async {
                    // Add to cards array if not already present
                    if !self.cards.contains(where: { $0.imageIdentifier == imageIdentifier }) {
                        self.cards.append(card)
                        self.processedImageIdentifiers.insert(imageIdentifier)
                        self.saveCards()
                    }
                    
                    self.isScanning = false
                    completion(card)
                }
            } else {
                DispatchQueue.main.async {
                    self.isScanning = false
                    completion(nil)
                }
            }
        }
    }
    
    /// Delete a card
    func deleteCard(_ card: Card) {
        cards.removeAll { $0.id == card.id }
        processedImageIdentifiers.remove(card.imageIdentifier)
        saveCards()
    }
}


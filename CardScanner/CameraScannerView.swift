import SwiftUI
import AVFoundation
import UIKit
import Combine
import CoreVideo
import CoreImage

struct CameraScannerView: View {
    @ObservedObject var scannerService: CardScannerService
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var scanningState = ScanningState()
    @State private var showingCardFeed = false
    @State private var scannedCard: Card?
    @State private var showingSuccessAlert = false
    @State private var isScanningModeOn = false
    
    var body: some View {
        ZStack {
            // Camera preview
            if cameraManager.isSessionRunning {
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }
            
            // Permission denied view
            if !cameraManager.permissionGranted && !cameraManager.isSessionRunning {
                permissionDeniedView
            }
            
            // Overlay UI
            if cameraManager.permissionGranted {
                VStack {
                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 20) {
                        // Scanning indicator (continuous scanning mode)
                        if scannerService.isScanning {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Scanning...")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                }
                                Spacer()
                            }
                        }
                        
                        // Scan mode toggle button
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                isScanningModeOn.toggle()
                                cameraManager.isScanningEnabled = isScanningModeOn
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(isScanningModeOn ? Color.red : Color.white)
                                        .frame(width: 70, height: 70)
                                    
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear {
            cameraManager.checkPermission()
            // Set up continuous scanning callback
            setupScanningCallback()
        }
        .onDisappear {
            cameraManager.onFrameCaptured = nil
        }
        .sheet(isPresented: $showingCardFeed) {
            CardFeedView(scannerService: scannerService)
        }
        .onChange(of: scanningState.shouldShowAlert) { shouldShow in
            if shouldShow {
                scannedCard = scanningState.scannedCard
                showingSuccessAlert = true
                scanningState.shouldShowAlert = false
            }
        }
        .alert("Card Scanned!", isPresented: $showingSuccessAlert) {
            Button("OK", role: .cancel) { }
            if scannedCard != nil {
                Button("View Card") {
                    showingCardFeed = true
                }
            }
        } message: {
            if let card = scannedCard {
                Text("Found: \(card.playerName) - \(card.team) (\(card.year))")
            } else {
                Text("Card has been scanned and saved!")
            }
        }
    }
    
    var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
            
            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Please enable camera access in Settings to scan cards")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }) {
                Text("Open Settings")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
    
    private func setupScanningCallback() {
        cameraManager.onFrameCaptured = { [scannerService, scanningState] image in
            // Process the captured frame
            scannerService.scanImage(image) { card in
                DispatchQueue.main.async {
                    if let card = card {
                        scanningState.scannedCard = card
                        scanningState.shouldShowAlert = true
                    }
                }
            }
        }
    }
}

// Helper class to hold scanning state for callbacks
class ScanningState: ObservableObject {
    @Published var scannedCard: Card?
    @Published var shouldShowAlert: Bool = false
}

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var session = AVCaptureSession()
    @Published var isSessionRunning = false
    @Published var permissionGranted = false
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var lastScanTime: Date = Date.distantPast
    private let scanInterval: TimeInterval = 1.0 // Scan every 1 second
    var onFrameCaptured: ((UIImage) -> Void)?
    var isScanningEnabled: Bool = false
    
    override init() {
        super.init()
    }
    
    func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            DispatchQueue.main.async { [weak self] in
                self?.permissionGranted = true
                self?.setupSession()
            }
        case .notDetermined:
            print("Camera permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print("📝 Permission request result: \(granted)")
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        case .denied, .restricted:
            print("Camera permission denied or restricted")
            DispatchQueue.main.async { [weak self] in
                self?.permissionGranted = false
            }
        @unknown default:
            print("Unknown permission status")
            DispatchQueue.main.async { [weak self] in
                self?.permissionGranted = false
            }
        }
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prevent duplicate setup
            guard !self.session.isRunning else {
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
                return
            }
            
            // Remove existing inputs if any
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            
            // Add video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentCameraPosition) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
                return
            }
            
            do {
                let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                guard self.session.canAddInput(videoDeviceInput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                    }
                    return
                }
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                print("Video input added successfully")
            } catch {
                print("Error creating video input: \(error)")
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
                return
            }
            
            // Add video output for continuous scanning
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.output.queue"))
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                print("📱 Updated isSessionRunning: \(self.isSessionRunning)")
            }
        }
    }
    
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            if let existingInput = self.videoDeviceInput {
                self.session.removeInput(existingInput)
            }
            
            // Switch camera position
            self.currentCameraPosition = self.currentCameraPosition == .back ? .front : .back
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentCameraPosition),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(videoDeviceInput) else {
                self.session.commitConfiguration()
                return
            }
            
            self.session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            self.session.commitConfiguration()
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only process frames when scanning is enabled
        guard isScanningEnabled else {
            return
        }
        
        // Only process frames at the specified interval
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= scanInterval else {
            return
        }
        lastScanTime = now
        
        // Convert sample buffer to UIImage
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        
        // Notify the view to process the frame
        DispatchQueue.main.async { [weak self] in
            self?.onFrameCaptured?(image)
        }
    }
}


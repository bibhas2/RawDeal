//
//  CameraController.swift
//  RawDeal
//
//  Created by Bibhas Bhattacharya on 3/12/18.
//  Copyright © 2018 Bibhas Bhattacharya. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class CameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    let captureSession = AVCaptureSession()
    let capturePhotoOutput = AVCapturePhotoOutput()
    @IBOutlet weak var previewView: VideoPreviewView!
    private let sessionQueue = DispatchQueue(label: "session queue")
    var rawSampleBuffer: CMSampleBuffer?
    var rawPreviewPhotoSampleBuffer: CMSampleBuffer?
    @IBOutlet weak var snapButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.checkCameraAuthorization {authorized in
            NSLog("Camera authorized: %@", authorized ? "TRUE" : "FLASE")
            if authorized {
                self.previewView.session = self.captureSession
                
                self.sessionQueue.async {
                    self.configureCaptureSession({ success in
                        guard success else { return }
                        
                        self.captureSession.startRunning()
                        
                        DispatchQueue.main.async {
                            self.previewView.updateVideoOrientationForDeviceOrientation()

                            self.snapButton.isEnabled =
                                !self.capturePhotoOutput.availableRawPhotoPixelFormatTypes.isEmpty
                        }
                    })
                }
                
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    func checkCameraAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            //The user has previously granted access to the camera.
            completionHandler(true)
            
        case .notDetermined:
            // The user has not yet been presented with the option to grant video access so request access.
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { success in
                completionHandler(success)
            })
            
        case .denied:
            // The user has previously denied access.
            completionHandler(false)
            
        case .restricted:
            // The user doesn't have the authority to request access e.g. parental restriction.
            completionHandler(false)
        }
    }
    
    func defaultDevice() -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDualCamera,
                                                for: AVMediaType.video,
                                                      position: .back) {
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: AVMediaType.video,
                                                             position: .back) {
            return device // use default back facing camera otherwise
        } else {
            fatalError("All supported devices are expected to have at least one of the queried capture devices.")
        }
    }
    
    func configureCaptureSession(_ completionHandler: ((_ success: Bool) -> Void)) {
        var success = false
        defer { completionHandler(success) } // Ensure all exit paths call completion handler.
        
        // Get video input for the default camera.
        let videoCaptureDevice = defaultDevice()
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            print("Unable to obtain video input for default camera.")
            return
        }
        
        // Create and configure the photo output.
        
        capturePhotoOutput.isHighResolutionCaptureEnabled = true
        capturePhotoOutput.isLivePhotoCaptureEnabled = capturePhotoOutput.isLivePhotoCaptureSupported
        
        // Make sure inputs and output can be added to session.
        guard self.captureSession.canAddInput(videoInput) else { return }
        guard self.captureSession.canAddOutput(capturePhotoOutput) else { return }
        
        // Configure the session.
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = AVCaptureSession.Preset.photo
        self.captureSession.addInput(videoInput)
        self.captureSession.addOutput(capturePhotoOutput)
        self.captureSession.commitConfiguration()
        
        success = true
    }
    
    func snapPhoto() {
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        self.sessionQueue.async {
            // Update the photo output's connection to match the video orientation of the video preview layer.
            if let photoOutputConnection = self.capturePhotoOutput.connection(with: AVMediaType.video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            
            let photoSettings = self.createPhotoSettings()
            
            self.capturePhotoOutput.capturePhoto(with: photoSettings, delegate: self as! AVCapturePhotoCaptureDelegate)
        }
    }

    @IBAction func takePhoto(_ sender: Any) {
        self.snapPhoto()
    }

    func checkPhotoLibraryAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            // The user has previously granted access to the photo library.
            completionHandler(true)
            
        case .notDetermined:
            // The user has not yet been presented with the option to grant photo library access so request access.
            PHPhotoLibrary.requestAuthorization({ status in
                completionHandler((status == .authorized))
            })
            
        case .denied:
            // The user has previously denied access.
            completionHandler(false)
            
        case .restricted:
            // The user doesn't have the authority to request access e.g. parental restriction.
            completionHandler(false)
        }
    }
    
    func createPhotoSettings() -> AVCapturePhotoSettings {
        let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: self.capturePhotoOutput.availableRawPhotoPixelFormatTypes.first!)
        
        photoSettings.isAutoStillImageStabilizationEnabled = false //Must be far RAW
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.flashMode = .auto
        
        let desiredPreviewPixelFormat = NSNumber(value: kCVPixelFormatType_32BGRA)
        if photoSettings.availablePreviewPhotoPixelFormatTypes.contains(OSType(truncating: desiredPreviewPixelFormat)) {
            photoSettings.previewPhotoFormat = [
                kCVPixelBufferPixelFormatTypeKey as String : desiredPreviewPixelFormat,
                kCVPixelBufferWidthKey as String : NSNumber(value: 512),
                kCVPixelBufferHeightKey as String : NSNumber(value: 512)
            ]
        }
        
        return photoSettings
    }
    
    func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                     didFinishProcessingRawPhoto rawSampleBuffer: CMSampleBuffer?,
                     previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                 resolvedSettings: AVCaptureResolvedPhotoSettings,
                 bracketSettings: AVCaptureBracketedStillImageSettings?,
                 error: Error?) {
        guard error == nil, let rawSampleBuffer = rawSampleBuffer else {
            NSLog("Error capturing RAW photo: %@", String(describing: error))
            
            return
        }
        
        self.rawSampleBuffer = rawSampleBuffer
        self.rawPreviewPhotoSampleBuffer = previewPhotoSampleBuffer
    }
    
    func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        guard error == nil else {
            NSLog("Error in capture process: %@", String(describing: error))
            
            return
        }
        
        if let _ = self.rawSampleBuffer, let _ = self.rawPreviewPhotoSampleBuffer {
            
            self.saveRAWPlusJPEGPhotoLibrary { success, error in
                if success {
                    NSLog("Added RAW+JPEG photo to library.")
                } else {
                    NSLog("Error adding RAW+JPEG photo to library: %@", String(describing: error))
                }
                
                self.rawPreviewPhotoSampleBuffer = nil
                self.rawSampleBuffer = nil
            }
        } else {
            NSLog("Raw buffers are missing")
        }
    }
    
    func saveRAWPlusJPEGPhotoLibrary(completionHandler: ((_ success: Bool, _ error: Error?) -> Void)?) {
        self.checkPhotoLibraryAuthorization({ authorized in
            guard authorized else {
                print("Permission to access photo library denied.")
                completionHandler?(false, nil)
                return
            }
            
            guard let dngData = AVCapturePhotoOutput.dngPhotoDataRepresentation(
                forRawSampleBuffer: self.rawSampleBuffer!,
                previewPhotoSampleBuffer: self.rawPreviewPhotoSampleBuffer!)
                else {
                    NSLog("Unable to create DNG data.")
                    completionHandler?(false, nil)
                    
                    return
            }
            
            let dngFileURL = self.makeUniqueTempFileURL()
            
            do {
                try dngData.write(to: dngFileURL, options: [])
            } catch let error as NSError {
                NSLog("Unable to write DNG file.")
                completionHandler?(false, error)
                
                return
            }
            
            PHPhotoLibrary.shared().performChanges( {
                let creationRequest = PHAssetCreationRequest.forAsset()
                let creationOptions = PHAssetResourceCreationOptions()
                
                creationOptions.shouldMoveFile = true
                
                creationRequest.addResource(with: .photo, fileURL: dngFileURL, options: creationOptions)
            }, completionHandler: completionHandler)
        })
    }

    func makeUniqueTempFileURL() -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("raw.dng")
    }
}

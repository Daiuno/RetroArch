/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2025      - Joseph Mattiello
 *
 *  RetroArch is free software: you can redistribute it and/or modify it under the terms
 *  of the GNU General Public License as published by the Free Software Found-
 *  ation, either version 3 of the License, or (at your option) any later version.
 *
 *  RetroArch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 *  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 *  PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with RetroArch.
 *  If not, see <http://www.gnu.org/licenses/>.
 */

#include <TargetConditionals.h>
#include <Foundation/Foundation.h>
#include <AVFoundation/AVFoundation.h>
#include <libretro.h>
#include "../camera/camera_driver.h"
#include "../verbosity.h"
/// For image scaling and color space DSP
#import <Accelerate/Accelerate.h>
#if TARGET_OS_IOS
/// For camera rotation detection
#import <UIKit/UIKit.h>
#endif

// TODO: Add an API to retroarch to allow selection of camera
#ifndef CAMERA_PREFER_FRONTFACING
#define CAMERA_PREFER_FRONTFACING 1  /// Default to front camera
#endif

#ifndef CAMERA_MIRROR_FRONT_CAMERA
#define CAMERA_MIRROR_FRONT_CAMERA 1
#endif

@interface AVCameraManager : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDeviceInput *input;
@property (strong, nonatomic) AVCaptureVideoDataOutput *output;
@property (strong, nonatomic) dispatch_queue_t sessionQueue;  // Background queue for session operations
@property (strong, nonatomic) dispatch_queue_t outputQueue;   // Queue for frame processing
@property (assign) uint32_t *frameBuffer;
@property (assign) size_t width;
@property (assign) size_t height;
@property (assign) BOOL preferFrontCamera;
@property (assign) BOOL cameraPreferenceSet;  // Track if preference was explicitly set
@property (assign) BOOL enableFrontCameraMirrored;
@property (assign) BOOL fixFrontCameraRotation;

- (bool)setupCameraSession;
- (bool)switchCamera:(BOOL)useFrontCamera;
- (void)startSession;
- (void)stopSession;
@end

@implementation AVCameraManager

+ (AVCameraManager *)sharedInstance {
    static AVCameraManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AVCameraManager alloc] init];
        // Create dedicated queues for camera operations
        instance.sessionQueue = dispatch_queue_create("com.retroarch.camera.session", DISPATCH_QUEUE_SERIAL);
        instance.outputQueue = dispatch_queue_create("com.retroarch.camera.output", DISPATCH_QUEUE_SERIAL);
    });
    return instance;
}

- (void)startSession {
    // Use dispatch_async to ensure session is started before returning
    // This is safe because we're on the main thread and sessionQueue is a serial queue
    dispatch_async(self.sessionQueue, ^{
        if (!self.session.isRunning) {
            AVCaptureConnection * connection = [self.output connectionWithMediaType:AVMediaTypeVideo];
            if (connection) {
                connection.videoOrientation = AVCaptureVideoOrientationPortrait;
                if (connection.isVideoMirroringSupported) {
                    BOOL preferFront = self.cameraPreferenceSet ? self.preferFrontCamera : CAMERA_PREFER_FRONTFACING;
                    connection.videoMirrored = self.enableFrontCameraMirrored ? (preferFront ? YES : NO) : NO;
                }
            }
            [self.session startRunning];
            RARCH_LOG("[Camera]: Camera session started on background thread\n");
        }
    });
}

- (void)stopSession {
    dispatch_async(self.sessionQueue, ^{
        if (self.session.isRunning) {
            [self.session stopRunning];
            RARCH_LOG("[Camera]: Camera session stopped on background thread\n");
        }
    });
}

- (void)requestCameraAuthorizationWithCompletion:(void (^)(BOOL granted))completion {
    RARCH_LOG("[Camera]: Checking camera authorization status\n");

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    switch (status) {
        case AVAuthorizationStatusAuthorized: {
            RARCH_LOG("[Camera]: Camera access already authorized\n");
            completion(YES);
            break;
        }

        case AVAuthorizationStatusNotDetermined: {

            RARCH_LOG("[Camera]: Requesting camera authorization...\n");
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                     completionHandler:^(BOOL granted) {
                RARCH_LOG("[Camera]: Authorization %s\n", granted ? "granted" : "denied");
                completion(granted);
            }];
            break;
        }

        case AVAuthorizationStatusDenied: {
            RARCH_ERR("[Camera]: Camera access denied by user\n");
            completion(NO);
            break;
        }

        case AVAuthorizationStatusRestricted: {
            RARCH_ERR("[Camera]: Camera access restricted (parental controls?)\n");
            completion(NO);
            break;
        }

        default: {
            RARCH_ERR("[Camera]: Unknown authorization status\n");
            completion(NO);
            break;
        }
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    @autoreleasepool {
        if (!self.frameBuffer)
            return;

        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) {
            RARCH_ERR("[Camera]: Failed to get image buffer\n");
            return;
        }

        CVPixelBufferLockBaseAddress(imageBuffer, 0);

        size_t sourceWidth = CVPixelBufferGetWidth(imageBuffer);
        size_t sourceHeight = CVPixelBufferGetHeight(imageBuffer);
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);

        BOOL isFrontCam = (self.input.device.position == AVCaptureDevicePositionFront);
        // Create intermediate buffer for full-size converted image
        uint32_t *intermediateBuffer = (uint32_t*)malloc(sourceWidth * sourceHeight * 4);
        if (!intermediateBuffer) {
            RARCH_ERR("[Camera]: Failed to allocate intermediate buffer\n");
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        }

        vImage_Buffer srcBuffer = {}, intermediateVBuffer = {}, dstBuffer = {};
        vImage_Error err = kvImageNoError;

        // Setup intermediate buffer
        intermediateVBuffer.data = intermediateBuffer;
        intermediateVBuffer.width = sourceWidth;
        intermediateVBuffer.height = sourceHeight;
        intermediateVBuffer.rowBytes = sourceWidth * 4;

        // Setup destination buffer
        dstBuffer.data = self.frameBuffer;
        dstBuffer.width = self.width;
        dstBuffer.height = self.height;
        dstBuffer.rowBytes = self.width * 4;

        // Process based on pixel format
        switch (pixelFormat) {
            case kCVPixelFormatType_32BGRA: {
                srcBuffer.data = CVPixelBufferGetBaseAddress(imageBuffer);
                srcBuffer.width = sourceWidth;
                srcBuffer.height = sourceHeight;
                srcBuffer.rowBytes = CVPixelBufferGetBytesPerRow(imageBuffer);

                if (isFrontCam) {
                    // Front camera: Swap R and B channels to fix color
                    // BGRA: [B, G, R, A] -> [R, G, B, A] (swap B and R)
                    uint8_t *srcData = (uint8_t *)srcBuffer.data;
                    uint8_t *dstData = (uint8_t *)intermediateVBuffer.data;

                    for (size_t y = 0; y < sourceHeight; y++) {
                        for (size_t x = 0; x < sourceWidth; x++) {
                            size_t srcOffset = y * srcBuffer.rowBytes + x * 4;
                            size_t dstOffset = y * intermediateVBuffer.rowBytes + x * 4;

                            // Swap B and R, keep G and A
                            dstData[dstOffset + 0] = srcData[srcOffset + 2]; // B <- R
                            dstData[dstOffset + 1] = srcData[srcOffset + 1]; // G <- G
                            dstData[dstOffset + 2] = srcData[srcOffset + 0]; // R <- B
                            dstData[dstOffset + 3] = srcData[srcOffset + 3]; // A <- A
                        }
                    }
                    err = kvImageNoError;
                } else {
                    // Back camera: Keep BGRA format - just copy directly
                    if (srcBuffer.rowBytes == intermediateVBuffer.rowBytes) {
                        memcpy(intermediateVBuffer.data, srcBuffer.data, sourceHeight * srcBuffer.rowBytes);
                        err = kvImageNoError;
                    } else {
                        for (size_t y = 0; y < sourceHeight; y++) {
                            memcpy((uint8_t*)intermediateVBuffer.data + y * intermediateVBuffer.rowBytes,
                                   (uint8_t*)srcBuffer.data + y * srcBuffer.rowBytes,
                                   sourceWidth * 4);
                        }
                        err = kvImageNoError;
                    }
                }
                break;
            }

            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: {
                // YUV to RGB conversion
                vImage_Buffer srcY = {}, srcCbCr = {};

                srcY.data = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
                srcY.width = sourceWidth;
                srcY.height = sourceHeight;
                srcY.rowBytes = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);

                srcCbCr.data = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
                srcCbCr.width = sourceWidth / 2;
                srcCbCr.height = sourceHeight / 2;
                srcCbCr.rowBytes = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);

                vImage_YpCbCrToARGB info;
                vImage_YpCbCrPixelRange pixelRange =
                    (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) ?
                        (vImage_YpCbCrPixelRange){16, 128, 235, 240} :
                        (vImage_YpCbCrPixelRange){0, 128, 255, 255};

                err = vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
                                                                   &pixelRange,
                                                                   &info,
                                                                   kvImage420Yp8_CbCr8,
                                                                   kvImageARGB8888,
                                                                   kvImageNoFlags);

                if (err == kvImageNoError) {
                    vImage_Buffer argbBuffer = {};
                    argbBuffer.data = malloc(sourceWidth * sourceHeight * 4);
                    if (!argbBuffer.data) {
                        err = kvImageMemoryAllocationError;
                        break;
                    }
                    argbBuffer.width = sourceWidth;
                    argbBuffer.height = sourceHeight;
                    argbBuffer.rowBytes = sourceWidth * 4;

                    err = vImageConvert_420Yp8_CbCr8ToARGB8888(&srcY,
                                                              &srcCbCr,
                                                              &argbBuffer,
                                                              &info,
                                                              NULL,
                                                              255,
                                                              kvImageNoFlags);

                    if (err == kvImageNoError) {
                        // Convert ARGB to BGRA: [A, R, G, B] -> [B, G, R, A]
                        uint8_t permuteMap[4] = {3, 2, 1, 0};
                        err = vImagePermuteChannels_ARGB8888(&argbBuffer, &intermediateVBuffer, permuteMap, kvImageNoFlags);
                    }
                    free(argbBuffer.data);
                }
                break;
            }

            default:
                RARCH_ERR("[Camera]: Unsupported pixel format: %u\n", (unsigned int)pixelFormat);
                free(intermediateBuffer);
                CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
                return;
        }

        if (err != kvImageNoError) {
            RARCH_ERR("[Camera]: Error converting color format: %ld\n", err);
            free(intermediateBuffer);
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        }

        // Determine rotation based on platform and camera type
#if TARGET_OS_OSX
        int rotationDegrees = 0;
#else
        int rotationDegrees = 0;

        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
        BOOL preferFront = self.cameraPreferenceSet ? self.preferFrontCamera : CAMERA_PREFER_FRONTFACING;
        switch (orientation) {
            case UIDeviceOrientationPortrait:
                rotationDegrees = 0;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                rotationDegrees = 0;
                break;
            case UIDeviceOrientationLandscapeLeft:
                rotationDegrees = self.fixFrontCameraRotation && preferFront ? 270 : 90;
                break;
            case UIDeviceOrientationLandscapeRight:
                rotationDegrees = self.fixFrontCameraRotation && preferFront ? 90 : 270;
                break;
            default:
                rotationDegrees = 0;
                break;
        }
#endif

        // Rotate image
        vImage_Buffer rotatedBuffer = {};
        rotatedBuffer.data = malloc(sourceWidth * sourceHeight * 4);
        if (!rotatedBuffer.data) {
            RARCH_ERR("[Camera]: Failed to allocate rotation buffer\n");
            free(intermediateBuffer);
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        }

        // Set dimensions based on rotation angle
        if (rotationDegrees == 90 || rotationDegrees == 270) {
            rotatedBuffer.width = sourceHeight;
            rotatedBuffer.height = sourceWidth;
        } else {
            rotatedBuffer.width = sourceWidth;
            rotatedBuffer.height = sourceHeight;
        }
        rotatedBuffer.rowBytes = rotatedBuffer.width * 4;

        const Pixel_8888 backgroundColor = {0, 0, 0, 255};

        err = vImageRotate90_ARGB8888(&intermediateVBuffer,
                                     &rotatedBuffer,
                                     rotationDegrees / 90,
                                     backgroundColor,
                                     kvImageNoFlags);

        if (err != kvImageNoError) {
            RARCH_ERR("[Camera]: Error rotating image: %ld\n", err);
            free(rotatedBuffer.data);
            free(intermediateBuffer);
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        }

        // Mirror the image if needed
        //Mirroring messes up the front camera's colors, and I have no idea how to fix it. Let's just turn off mirroring.
//        if (shouldMirror) {
//            vImage_Buffer mirroredBuffer = {};
//            mirroredBuffer.data = malloc(rotatedBuffer.height * rotatedBuffer.rowBytes);
//            if (!mirroredBuffer.data) {
//                RARCH_ERR("[Camera]: Failed to allocate mirror buffer\n");
//                free(rotatedBuffer.data);
//                free(intermediateBuffer);
//                CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//                return;
//            }
//
//            mirroredBuffer.width = rotatedBuffer.width;
//            mirroredBuffer.height = rotatedBuffer.height;
//            mirroredBuffer.rowBytes = rotatedBuffer.rowBytes;
//
//            err = vImageHorizontalReflect_ARGB8888(&rotatedBuffer, &mirroredBuffer, kvImageNoFlags);
//
//            if (err == kvImageNoError) {
//                // Free rotated buffer and use mirrored buffer for scaling
//                free(rotatedBuffer.data);
//                rotatedBuffer = mirroredBuffer;
//            } else {
//                RARCH_ERR("[Camera]: Error mirroring image: %ld\n", err);
//                free(mirroredBuffer.data);
//            }
//        }

        // Calculate aspect fill scaling
        float sourceAspect = (float)rotatedBuffer.width / rotatedBuffer.height;
        float targetAspect = (float)self.width / self.height;

        vImage_Buffer scaledBuffer = {};
        size_t scaledWidth, scaledHeight;

        if (sourceAspect > targetAspect) {
            // Source is wider - scale to match height
            scaledHeight = self.height;
            scaledWidth = (size_t)(self.height * sourceAspect);
        } else {
            // Source is taller - scale to match width
            scaledWidth = self.width;
            scaledHeight = (size_t)(self.width / sourceAspect);
        }

        scaledBuffer.data = malloc(scaledWidth * scaledHeight * 4);
        if (!scaledBuffer.data) {
            RARCH_ERR("[Camera]: Failed to allocate scaled buffer\n");
            free(rotatedBuffer.data);
            free(intermediateBuffer);
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        }

        scaledBuffer.width = scaledWidth;
        scaledBuffer.height = scaledHeight;
        scaledBuffer.rowBytes = scaledWidth * 4;

        err = vImageScale_ARGB8888(&rotatedBuffer, &scaledBuffer, NULL, kvImageHighQualityResampling);

        if (err != kvImageNoError) {
            RARCH_ERR("[Camera]: Error scaling image: %ld\n", err);
            free(scaledBuffer.data);
            free(rotatedBuffer.data);
            free(intermediateBuffer);
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            return;
        }

        // Center crop the scaled image into the destination buffer
        size_t xOffset = (scaledWidth > self.width) ? (scaledWidth - self.width) / 2 : 0;
        size_t yOffset = (scaledHeight > self.height) ? (scaledHeight - self.height) / 2 : 0;

        uint32_t *scaledPtr = (uint32_t *)scaledBuffer.data;
        uint32_t *dstPtr = (uint32_t *)self.frameBuffer;

        for (size_t y = 0; y < self.height; y++) {
            memcpy(dstPtr + y * self.width,
                   scaledPtr + (y + yOffset) * scaledWidth + xOffset,
                   self.width * 4);
        }

        // Clean up
        free(scaledBuffer.data);
        free(rotatedBuffer.data);
        free(intermediateBuffer);
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    } // End of autorelease pool
}

- (AVCaptureDevice *)selectCameraDevice {
    RARCH_LOG("[Camera]: Selecting camera device\n");

    NSArray<AVCaptureDevice *> *devices;

#if TARGET_OS_OSX
    // On macOS, use default discovery method
    // Could probably due the same as iOS but need to test.
    devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
#else
    // On iOS/tvOS use modern discovery session
    NSArray<AVCaptureDeviceType> *deviceTypes;
    if (@available(iOS 17.0, *)) {
        deviceTypes = @[
            AVCaptureDeviceTypeExternal,
            AVCaptureDeviceTypeBuiltInWideAngleCamera,
            AVCaptureDeviceTypeBuiltInTelephotoCamera,
            AVCaptureDeviceTypeBuiltInUltraWideCamera,
            //        AVCaptureDeviceTypeBuiltInDualCamera,
            //        AVCaptureDeviceTypeBuiltInDualWideCamera,
            //        AVCaptureDeviceTypeBuiltInTripleCamera,
            //        AVCaptureDeviceTypeBuiltInTrueDepthCamera,
            //        AVCaptureDeviceTypeBuiltInLiDARDepthCamera,
            //        AVCaptureDeviceTypeContinuityCamera,
        ];
    } else {
        deviceTypes = @[
            AVCaptureDeviceTypeBuiltInWideAngleCamera,
            AVCaptureDeviceTypeBuiltInTelephotoCamera,
            AVCaptureDeviceTypeBuiltInUltraWideCamera,
            //        AVCaptureDeviceTypeBuiltInDualCamera,
            //        AVCaptureDeviceTypeBuiltInDualWideCamera,
            //        AVCaptureDeviceTypeBuiltInTripleCamera,
            //        AVCaptureDeviceTypeBuiltInTrueDepthCamera,
            //        AVCaptureDeviceTypeBuiltInLiDARDepthCamera,
            //        AVCaptureDeviceTypeContinuityCamera,
        ];
    }
    AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                         discoverySessionWithDeviceTypes:deviceTypes
                                                         mediaType:AVMediaTypeVideo
                                                         position:AVCaptureDevicePositionUnspecified];

    devices = discoverySession.devices;
#endif

    if (devices.count == 0) {
        RARCH_ERR("[Camera]: No camera devices found\n");
        return nil;
    }

    // Log available devices
    for (AVCaptureDevice *device in devices) {
        RARCH_LOG("[Camera]: Found device: %s - Position: %d\n",
                  [device.localizedName UTF8String],
                  (int)device.position);
    }

#if TARGET_OS_OSX
    // macOS: Just use the first available camera if only one exists
    if (devices.count == 1) {
        RARCH_LOG("[Camera]: Using only available camera: %s\n",
                  [devices.firstObject.localizedName UTF8String]);
        return devices.firstObject;
    }

    // Use preferFrontCamera property if explicitly set, otherwise use default
    BOOL preferFront = self.cameraPreferenceSet ? self.preferFrontCamera : CAMERA_PREFER_FRONTFACING;

    // Try to match by name for built-in cameras
    for (AVCaptureDevice *device in devices) {
        BOOL isFrontFacing = [device.localizedName containsString:@"FaceTime"] ||
                            [device.localizedName containsString:@"Front"];
        if (preferFront == isFrontFacing) {
            RARCH_LOG("[Camera]: Selected macOS camera: %s\n",
                      [device.localizedName UTF8String]);
            return device;
        }
    }
#else
    // iOS: Use position property
    // Use preferFrontCamera property if explicitly set, otherwise use default
    BOOL preferFront = self.cameraPreferenceSet ? self.preferFrontCamera : CAMERA_PREFER_FRONTFACING;

    AVCaptureDevicePosition preferredPosition = preferFront ?
        AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;

    // Try to find preferred camera
    for (AVCaptureDevice *device in devices) {
        if (device.position == preferredPosition) {
            RARCH_LOG("[Camera]: Selected iOS camera position: %d (preferFront: %d)\n",
                      (int)preferredPosition, preferFront);
            return device;
        }
    }
#endif

    // Fallback to first available camera
    RARCH_LOG("[Camera]: Using fallback camera: %s\n",
              [devices.firstObject.localizedName UTF8String]);
    return devices.firstObject;
}

- (bool)setupCameraSession {
    // Initialize capture session
    self.session = [[AVCaptureSession alloc] init];

    // Get camera device
    AVCaptureDevice *device = [self selectCameraDevice];
    if (!device) {
        RARCH_ERR("[Camera]: No camera device found\n");
        return false;
    }

    // Create device input
    NSError *error = nil;
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (error) {
        RARCH_ERR("[Camera]: Failed to create device input: %s\n",
                  [error.localizedDescription UTF8String]);
        return false;
    }

    if ([self.session canAddInput:self.input]) {
        [self.session addInput:self.input];
        RARCH_LOG("[Camera]: Added camera input to session\n");
    }

    // Create and configure video output
    self.output = [[AVCaptureVideoDataOutput alloc] init];
    self.output.videoSettings = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    // Use dedicated output queue instead of main queue for frame processing
    [self.output setSampleBufferDelegate:self queue:self.outputQueue];

    if ([self.session canAddOutput:self.output]) {
        [self.session addOutput:self.output];
        RARCH_LOG("[Camera]: Added video output to session\n");
    }

    return true;
}

- (bool)switchCamera:(BOOL)useFrontCamera {
    if (!self.session) {
        RARCH_ERR("[Camera]: Cannot switch camera - session not initialized\n");
        return false;
    }

    // Update preference
    self.preferFrontCamera = useFrontCamera;
    self.cameraPreferenceSet = YES;

    // Perform camera switch on session queue to avoid blocking main thread
    dispatch_async(self.sessionQueue, ^{
        BOOL wasRunning = self.session.isRunning;
        if (wasRunning) {
            [self.session stopRunning];
        }

        // Remove current input
        if (self.input) {
            [self.session removeInput:self.input];
        }

        // Find and add new camera
        NSArray<AVCaptureDevice *> *devices;
#if TARGET_OS_OSX
        devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
#else
        NSArray<AVCaptureDeviceType> *deviceTypes;
        if (@available(iOS 17.0, *)) {
            deviceTypes = @[
                AVCaptureDeviceTypeExternal,
                AVCaptureDeviceTypeBuiltInWideAngleCamera,
            ];
        } else {
            deviceTypes = @[
                AVCaptureDeviceTypeBuiltInWideAngleCamera,
            ];
        }
        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                             discoverySessionWithDeviceTypes:deviceTypes
                                                             mediaType:AVMediaTypeVideo
                                                             position:AVCaptureDevicePositionUnspecified];
        devices = discoverySession.devices;
#endif

        AVCaptureDevice *newDevice = nil;
#if TARGET_OS_OSX
        for (AVCaptureDevice *device in devices) {
            BOOL isFront = [device.localizedName containsString:@"FaceTime"] ||
                          [device.localizedName containsString:@"Front"];
            if (isFront == useFrontCamera) {
                newDevice = device;
                break;
            }
        }
#else
        AVCaptureDevicePosition targetPosition = useFrontCamera ?
            AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        for (AVCaptureDevice *device in devices) {
            if (device.position == targetPosition) {
                newDevice = device;
                break;
            }
        }
#endif

        if (!newDevice && devices.count > 0) {
            newDevice = devices.firstObject;
        }

        if (!newDevice) {
            RARCH_ERR("[Camera]: No camera device found for switch\n");
            return;
        }

        NSError *error = nil;
        self.input = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&error];
        if (error) {
            RARCH_ERR("[Camera]: Failed to create device input: %s\n",
                      [error.localizedDescription UTF8String]);
            return;
        }

        // Begin configuration to make atomic changes
        [self.session beginConfiguration];

        if ([self.session canAddInput:self.input]) {
            [self.session addInput:self.input];
            RARCH_LOG("[Camera]: Switched to camera: %s (front: %d)\n",
                      [newDevice.localizedName UTF8String], useFrontCamera);
        }

        // Re-apply video output settings to ensure consistent pixel format
        if (self.output) {
            self.output.videoSettings = @{
                (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
            };
            RARCH_LOG("[Camera]: Re-applied BGRA pixel format after camera switch\n");
        }

        // Commit configuration
        [self.session commitConfiguration];

        if (wasRunning) {
            [self.session startRunning];
        }
    });

    return true;
}

@end

typedef struct
{
    AVCameraManager *manager;
    unsigned width;
    unsigned height;
} avfoundation_t;

static void *avfoundation_init(const char *device, uint64_t caps,
                             unsigned width, unsigned height)
{
    RARCH_LOG("[Camera]: Initializing AVFoundation camera %ux%u\n", width, height);

    avfoundation_t *avf = (avfoundation_t*)calloc(1, sizeof(avfoundation_t));
    if (!avf) {
        RARCH_ERR("[Camera]: Failed to allocate avfoundation_t\n");
        return NULL;
    }

    avf->manager = [AVCameraManager sharedInstance];
    avf->manager.enableFrontCameraMirrored = YES;
    avf->manager.preferFrontCamera = YES;
    avf->width = width;
    avf->height = height;
    avf->manager.width = width;
    avf->manager.height = height;

    // Allocate frame buffer first - always needed for black screen fallback
    avf->manager.frameBuffer = (uint32_t*)calloc(width * height, sizeof(uint32_t));
    if (!avf->manager.frameBuffer) {
        RARCH_ERR("[Camera]: Failed to allocate frame buffer\n");
        free(avf);
        return NULL;
    }

    // Check authorization status without blocking
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (status == AVAuthorizationStatusAuthorized) {
        // Already authorized, setup camera session
        RARCH_LOG("[Camera]: Camera access authorized, setting up session\n");
        
        __block bool setupSuccess = false;
        @autoreleasepool {
            setupSuccess = [avf->manager setupCameraSession];
        }

        if (!setupSuccess) {
            RARCH_WARN("[Camera]: Failed to setup camera, will return black frames\n");
            // Don't fail - continue with black frame fallback
        }
    } else if (status == AVAuthorizationStatusNotDetermined) {
        // Request permission asynchronously - don't block main thread
        RARCH_LOG("[Camera]: Requesting camera authorization asynchronously\n");
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                RARCH_LOG("[Camera]: Camera access granted, setting up session\n");
                @autoreleasepool {
                    [avf->manager setupCameraSession];
                }
            } else {
                RARCH_WARN("[Camera]: Camera access denied, will return black frames\n");
            }
        }];
    } else {
        // Denied or Restricted - log warning but continue with black frames
        RARCH_WARN("[Camera]: Camera access not authorized (status: %d), will return black frames\n", (int)status);
    }

    // Don't start camera session here - wait for avfoundation_start() to be called
    // This allows cores to control when the camera actually starts capturing
    // which saves battery and resources when camera is not needed

    RARCH_LOG("[Camera]: AVFoundation camera initialized (not started yet)\n");
    return avf;
}

static void avfoundation_free(void *data)
{
    avfoundation_t *avf = (avfoundation_t*)data;
    if (!avf)
        return;

    RARCH_LOG("[Camera]: Freeing AVFoundation camera\n");

    if (avf->manager) {
        if (avf->manager.session) {
            // Stop session on background queue
            [avf->manager stopSession];
            // Wait a bit for session to stop
            usleep(50000); // 50ms
        }

        if (avf->manager.frameBuffer) {
            free(avf->manager.frameBuffer);
            avf->manager.frameBuffer = NULL;
        }
    }

    free(avf);
    RARCH_LOG("[Camera]: AVFoundation camera freed\n");
}

static bool avfoundation_start(void *data)
{
    avfoundation_t *avf = (avfoundation_t*)data;
    if (!avf) {
        RARCH_ERR("[Camera]: Cannot start - invalid data\n");
        return false;
    }

    // If session is not available (permission denied), still return true
    // to allow the game to continue with black frames
    if (!avf->manager.session) {
        RARCH_WARN("[Camera]: No camera session available, will return black frames\n");
        return true;
    }

    RARCH_LOG("[Camera]: Starting AVFoundation camera\n");

    // Start session synchronously on background queue
    [avf->manager startSession];
    
    // Give the session a moment to start
    usleep(100000); // 100ms

    bool isRunning = avf->manager.session.isRunning;
    RARCH_LOG("[Camera]: Camera session running: %s\n", isRunning ? "YES" : "NO");
    return true; // Always return true to allow game to continue
}

static void avfoundation_stop(void *data)
{
    avfoundation_t *avf = (avfoundation_t*)data;
    if (!avf || !avf->manager || !avf->manager.session)
        return;

    RARCH_LOG("[Camera]: Stopping AVFoundation camera\n");

    // Stop session on dedicated background queue
    [avf->manager stopSession];
}

static bool avfoundation_poll(void *data,
      retro_camera_frame_raw_framebuffer_t frame_raw_cb,
      retro_camera_frame_opengl_texture_t frame_gl_cb)
{
    avfoundation_t *avf = (avfoundation_t*)data;
    if (!avf || !frame_raw_cb) {
        return false;
    }

    // Always provide the frame buffer - it will contain:
    // - Actual camera data if session is running
    // - Black/empty frame if session hasn't started yet or permission denied
    // This avoids log spam and unnecessary allocations
    if (avf->manager && avf->manager.frameBuffer) {
        frame_raw_cb(avf->manager.frameBuffer, avf->width, avf->height, avf->width * 4);
    }
    
    return true;
}

bool avfoundation_switch_camera(void *data, bool use_front_camera)
{
    avfoundation_t *avf = (avfoundation_t*)data;
    if (!avf || !avf->manager) {
        RARCH_ERR("[Camera]: Cannot switch camera - invalid data\n");
        return false;
    }

    avf->manager.enableFrontCameraMirrored = NO;
    avf->manager.fixFrontCameraRotation = YES;
    
    RARCH_LOG("[Camera]: Switching camera to %s\n", use_front_camera ? "front" : "back");
    return [avf->manager switchCamera:use_front_camera];
}

camera_driver_t camera_avfoundation = {
   avfoundation_init,
   avfoundation_free,
   avfoundation_start,
   avfoundation_stop,
   avfoundation_poll,
   "avfoundation"
};

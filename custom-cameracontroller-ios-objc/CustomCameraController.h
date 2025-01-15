/**
 * @file CustomCameraController.h
 * @brief Contains the @link CustomCameraController @endlink helper class that controls the camera device.
 * @copyright Copyright (c) 2021 DeepAR.ai
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <DeepAR/DeepAR.h>



/**
 * @brief Helper class that wraps <a href="https://developer.apple.com/documentation/avfoundation?language=objc">AVFoundation</a> to handle camera-related logic like starting camera preview, choosing resolution, front or back camera, and video orientation.
 * @details @link CustomCameraController @endlink works with DeepAR @endlink, just make sure to set it as a property on @link CustomCameraController @endlink instance. Check Github <a href="https://github.com/DeepARSDK/quickstart-ios-objc">example</a> for detailed usage example.
 */
@interface CustomCameraController : NSObject

/**
 * @brief The @link DeepAR @endlink instance.
 * @details Must be set manually if using @link DeepAR @endlink. See @link init @endlink for more details.
 */
@property (nonatomic, weak) DeepAR* deepAR;

/**
 * @brief The currently selected camera.
 * @details Options:
 * - <i>AVCaptureDevicePositionBack</i>
 * - <i>AVCaptureDevicePositionFront</i>
 * @details Changing this parameter in real-time causes the preview to switch to the given camera device.
 */
@property (nonatomic, assign) AVCaptureDevicePosition position;

/**
 * @brief Represents camera resolution currently used. Can be changed in real-time.
 */
@property (nonatomic, strong) AVCaptureSessionPreset preset;

/**
 * @brief Represents currently used video orientation. Should be called with right orientation when the device rotates.
 */
@property (nonatomic, assign) AVCaptureVideoOrientation videoOrientation;

/**
 * @brief Initializes a new @link CustomCameraController @endlink instance.
 * @details Initialization example:
 * @code
 * ...
 * self.cameraController = [[CustomCameraController alloc] init];
 * self.cameraController.deepAR = self.deepAR;
 * ...
 * @endcode
 */
- (instancetype)init;

/**
 * @brief Checks camera permissions.
 */
- (void)checkCameraPermission;

/**
 * @brief Checks microphone permissions.
 */
- (void)checkMicrophonePermission;

/**
 * @brief Starts camera preview using <a href="https://developer.apple.com/documentation/avfoundation?language=objc">AVFoundation</a>.
 * @details Checks camera permissions and asks if none has been given.
 */
- (void)startCamera;

/**
 * @brief Stops camera preview.
 */
- (void)stopCamera;

/**
 * @brief Starts capturing audio samples using <a href="https://developer.apple.com/documentation/avfoundation?language=objc">AVFoundation</a>.
 * @details Checks permissions and asks if none has been given. Must be called if @link DeepAR::startVideoRecordingWithOutputWidth:outputHeight: startVideoRecordingWithOutputWidth @endlink has been called with <i>recordAudio</i> parameter set to true.
 */
- (void)startAudio;

/**
 * @brief Stops capturing audio samples.
 */
- (void)stopAudio;

/**
 Custom methods
 */

/**
 * @brief Toggle torch if the current device has one. Only the back camera has a torch.
 */
- (void)toggleTorch:(BOOL)on;

@end

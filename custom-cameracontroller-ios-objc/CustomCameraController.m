#import "CustomCameraController.h"
#import <DeepAR/ARView.h>

@interface CustomCameraController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate> {
    AVCaptureSession* _captureSession;

    AVCaptureDevice* _videoCaptureDevice;
    AVCaptureDeviceInput* _videoCaptureInput;

    AVCaptureDevice* _audioCaptureDevice;
    AVCaptureDeviceInput* _audioCaptureInput;

    AVCaptureVideoDataOutput* _videoOutput;
    AVCaptureAudioDataOutput* _audioOutput;

    AVCaptureConnection* _audioConnection;
    AVCaptureConnection* _videoConnection;

    dispatch_queue_t _sessionQueue;
    dispatch_queue_t _videoDataOutputQueue;
    dispatch_queue_t _audioCaptureQueue;
    
    BOOL _hasCameraPermission;
    BOOL _hasMicrophonePermission;
    
    NSDictionary* _recommendedAudioSettings;

    BOOL _mirrorCamera;
}

@end

@implementation CustomCameraController

- (instancetype)init {
    self = [super init];
    if (self) {
        _deepAR = nil;
        [self setup];
    }
    return self;
}

- (void)setup {
    _hasCameraPermission = NO;
    _hasMicrophonePermission = NO;
    _preset = AVCaptureSessionPreset1280x720;
    _position = AVCaptureDevicePositionBack;
    _videoOrientation = AVCaptureVideoOrientationPortrait;
    _mirrorCamera = NO;
    _captureSession = [[AVCaptureSession alloc] init];

    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
    _sessionQueue = dispatch_queue_create( "ai.deepar.sessionqueue", attr );

    _videoDataOutputQueue = dispatch_queue_create( "ai.deepar.videoqueue", DISPATCH_QUEUE_SERIAL );
    dispatch_set_target_queue( _videoDataOutputQueue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
    
    _audioCaptureQueue = dispatch_queue_create( "com.deepar.audio", attr );
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startAudio) name:@"deepar_start_audio" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopAudio) name:@"deepar_stop_audio" object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)checkCameraPermission {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized) {
        _hasCameraPermission = YES;
    } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
        dispatch_suspend(_sessionQueue);
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            self->_hasCameraPermission = granted;
            dispatch_resume(self->_sessionQueue);
        }];

    } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusDenied) {
        _hasCameraPermission = NO;
    }
}

- (void)checkMicrophonePermission {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized) {
        _hasMicrophonePermission = YES;
    } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusNotDetermined) {
        dispatch_suspend(_sessionQueue);
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            self->_hasMicrophonePermission = granted;
            dispatch_resume(self->_sessionQueue);
        }];

    } else if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusDenied) {
        _hasMicrophonePermission = NO;
    }
}

- (AVCaptureDevice*)findDeviceWithPosition:(AVCaptureDevicePosition) position {
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice* device in devices) {
        if (device.position == position) {
            return device;
        }
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

- (void)setPosition:(AVCaptureDevicePosition)position {
    _position = position;
    _mirrorCamera = _position == AVCaptureDevicePositionFront;
    if (_captureSession.isRunning && _videoCaptureDevice && _videoCaptureDevice.position != position) {
        // switch position
        __weak CustomCameraController* weakSelf = self;
        dispatch_async(_sessionQueue, ^{
            [weakSelf switchDevice];
        });
    }
}

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    _videoOrientation = videoOrientation;
    if (_videoConnection) {
        _videoConnection.videoOrientation = videoOrientation;
    }
}

- (void)setPreset:(AVCaptureSessionPreset)preset {
    if (_captureSession.isRunning && _preset != preset) {
        _preset = preset;
        __weak CustomCameraController* weakSelf = self;
        dispatch_async(_sessionQueue, ^{
            [weakSelf switchPreset];
        });
        return;
    }
    _preset = preset;
}

- (void)switchPreset {
    [_captureSession beginConfiguration];
    if ([_captureSession canSetSessionPreset:_preset]) {
        [_captureSession setSessionPreset:_preset];
    } else {
        // try setting default preset
        if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
            [_captureSession setSessionPreset:AVCaptureSessionPreset640x480];
            NSLog(@"Preset not supported, using default");
        } else {
            NSLog(@"Unable to set session preset");
            [_captureSession commitConfiguration];
            return;
        }
    }
    [_captureSession commitConfiguration];
}

- (void)switchDevice {
    [_captureSession beginConfiguration];
    [_captureSession removeInput:_videoCaptureInput];
    _videoCaptureDevice = [self findDeviceWithPosition:_position];
    _videoCaptureInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoCaptureDevice error:nil];
    if ([_captureSession canAddInput:_videoCaptureInput]) {
        [_captureSession addInput:_videoCaptureInput];
    } else {
        [_captureSession commitConfiguration];
        NSLog(@"Unable to add input");
        return;
    }

    // configure orientation
    _videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    _videoConnection.videoOrientation = _videoOrientation;

    [_captureSession commitConfiguration];
}

- (void)startCamera {
    [self checkCameraPermission];
    __weak CustomCameraController* weakSelf = self;
    dispatch_async(_sessionQueue, ^{
        [weakSelf startCameraInternal];
    });
}

- (void)startCameraInternal {
    if (_captureSession.isRunning) {
        return;
    }
    
    if (!_hasCameraPermission) {
        return;
    }

    [_captureSession beginConfiguration];

    // configure input
    _videoCaptureDevice = [self findDeviceWithPosition:_position];
    _videoCaptureInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoCaptureDevice error:nil];
    if ([_captureSession canAddInput:_videoCaptureInput]) {
        [_captureSession addInput:_videoCaptureInput];
    } else {
        [_captureSession commitConfiguration];
        NSLog(@"Unable to add input");
        return;
    }

    // configure output
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    _videoOutput.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    [_videoOutput setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)self queue:_videoDataOutputQueue];
    
    if ([_captureSession canAddOutput:_videoOutput]) {
        [_captureSession addOutput:_videoOutput];
    } else {
        NSLog(@"Unable to add output");
        [_captureSession commitConfiguration];
        return;
    }
    
    // configure preset
    if ([_captureSession canSetSessionPreset:_preset]) {
        [_captureSession setSessionPreset:_preset];
    } else {
        // try setting default preset
        if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
            [_captureSession setSessionPreset:AVCaptureSessionPreset640x480];
            NSLog(@"Preset not supported, using default");
        } else {
            NSLog(@"Unable to set session preset");
            [_captureSession commitConfiguration];
            return;
        }
    }

    // configure framerate
    //todo

    // configure orientation
    _videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    _videoConnection.videoOrientation = _videoOrientation;

    [_captureSession commitConfiguration];
    [_captureSession startRunning];
}

- (void)stopCamera {
    __weak CustomCameraController* weakSelf = self;
    dispatch_async(_sessionQueue, ^{
        [weakSelf stopCameraInternal];
    });
}

- (void)stopCameraInternal {
    [_captureSession removeInput:_videoCaptureInput];
    [_captureSession removeOutput:_videoOutput];
    [_captureSession stopRunning];
}

- (void)stopAudio {
    __weak CustomCameraController* weakSelf = self;
    dispatch_async(_sessionQueue, ^{
        [weakSelf stopAudioInternal];
    });
}

- (void)stopAudioInternal {
    NSLog(@"stopAudioInternal");
    [_captureSession removeInput:_audioCaptureInput];
    _audioCaptureInput = nil;
    [_captureSession removeOutput:_audioOutput];
    _audioOutput = nil;
    _audioConnection = nil;
}

- (void)startAudio {
    [self checkMicrophonePermission];
    __weak CustomCameraController* weakSelf = self;
    dispatch_async(_sessionQueue, ^{
        [weakSelf startAudioInternal];
    });
}

- (void)startAudioInternal {
    if (!_hasMicrophonePermission) {
        return;
    }

    [_captureSession beginConfiguration];

    // configure input
    _audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    _audioCaptureInput = [[AVCaptureDeviceInput alloc] initWithDevice:_audioCaptureDevice error:nil];
    if ([_captureSession canAddInput:_audioCaptureInput]) {
        [_captureSession addInput:_audioCaptureInput];
    } else {
        NSLog(@"Unable to add audio input");
        [_captureSession commitConfiguration];
        return;
    }

    // configure output
    _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    [_audioOutput setSampleBufferDelegate:self queue:_audioCaptureQueue];
    if ([_captureSession canAddOutput:_audioOutput]) {
        [_captureSession addOutput:_audioOutput];
    } else {
        NSLog(@"Unable to add audio output");
        [_captureSession commitConfiguration];
        return;
    }

    // get audio connection
    _audioConnection = [_audioOutput connectionWithMediaType:AVMediaTypeAudio];
    
    [_captureSession commitConfiguration];
    
    _recommendedAudioSettings = [[_audioOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeQuickTimeMovie] copy];

    if (self.deepAR) {
        self.deepAR.audioCompressionSettings = _recommendedAudioSettings;
    }
}

- (bool)changeDeviceFocusPointOfInterest:(CGPoint)pointOfInterest {
    if(pointOfInterest.x <= 1 && pointOfInterest.y <= 1 && pointOfInterest.x >=0 && pointOfInterest.y >= 0){
        AVCaptureDevice* captureDevice = _videoCaptureDevice;
        if (captureDevice){
            if([captureDevice isFocusModeSupported: AVCaptureFocusModeContinuousAutoFocus] && [captureDevice isFocusPointOfInterestSupported]){
                NSError *error;
                if ([captureDevice lockForConfiguration:&error]) {
                    [captureDevice setFocusPointOfInterest:pointOfInterest];
                    [captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                    [captureDevice unlockForConfiguration];
                    return true;
                }
            }
        }
    }
    return false;
}

- (bool)changeDeviceExposurePointOfInterest:(CGPoint)pointOfInterest {
    if(pointOfInterest.x <= 1 && pointOfInterest.y <= 1 && pointOfInterest.x >=0 && pointOfInterest.y >= 0){
        AVCaptureDevice* captureDevice = _videoCaptureDevice;
        if (captureDevice){
            if([captureDevice isExposureModeSupported: AVCaptureExposureModeContinuousAutoExposure] && [captureDevice isExposurePointOfInterestSupported]){
                NSError *error;
                if ([captureDevice lockForConfiguration:&error]) {
                    [captureDevice setExposurePointOfInterest:pointOfInterest];
                    [captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                    [captureDevice unlockForConfiguration];
                    return true;
                }
            }
        }
    }
    return false;
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!self.deepAR && !self.arview) {
        return;
    }
    if (self.deepAR) {
        if (connection == _videoConnection) {
            [self.deepAR enqueueCameraFrame:sampleBuffer mirror:_mirrorCamera];
        } else {
            [self.deepAR enqueueAudioSample:sampleBuffer];
        }
    } else if (self.arview) {
        if (connection == _videoConnection) {
            [self.arview enqueueCameraFrame:sampleBuffer mirror:_mirrorCamera];
        } else {
            [self.arview enqueueAudioSample:sampleBuffer];
        }
    }
}

- (void)toggleTorch:(BOOL)on {
    // check if flashlight available
    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
    if (captureDeviceClass != nil) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]){
            [device lockForConfiguration:nil];
            if (on) {
                [device setTorchMode:AVCaptureTorchModeOn];
            } else {
                [device setTorchMode:AVCaptureTorchModeOff];
            }
            [device unlockForConfiguration];
        }
    } }

@end

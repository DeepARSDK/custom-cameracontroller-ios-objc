# custom-cameracontroller-ios-objc

How to add functionalities to the CameraController. This example has a CustomCameraController class which starts in back camera mode and implements a toggleTorch method, The toggleTorch method will only work if the current device (camera) has a torch. Only the back camera has a torch.

To run the example
* Go to https://developer.deepar.ai, sign up, create the project and the iOS app, copy the license key and paste it to ViewController.m (instead of your_license_key_goes_here string)
* Download the SDK from https://developer.deepar.ai and copy the DeepAR.DeepAR.xcframework into custom-cameracontroller-ios-objc
* In the project settings select custom-cameracontroller-ios-objc under Targets and:
  * Frameworks, Libararies and Embedded content add DeepAR.framework with Embed & Sign option selected
  * Go to Build Phases and make sure DeepAR.framework is included in Link Binary With libraries and Embeded Frameworks sections

Run the project

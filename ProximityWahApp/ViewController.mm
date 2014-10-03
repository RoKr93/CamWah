//
//  ViewController.m
//  ProximityWahApp
//
//  Created by Roshan Krishnan on 6/28/14.
//  Copyright (c) 2014 Roshan Krishnan. All rights reserved.
//

#import "ViewController.h"
#import <math.h>

@interface ViewController ()

@property (nonatomic, assign) RingBuffer *ringBuffer;

@end

@implementation ViewController

- (void)dealloc{
    delete self.ringBuffer;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    
    // Hide the post-calibration UI.
    sweepParams.hidden = YES;
    LF.hidden = YES;
    HF.hidden = YES;
    CF.hidden = YES;
    CFValue.hidden = YES;
    LFvalue.hidden = YES;
    HFvalue.hidden = YES;
    LFSlider.hidden = YES;
    HFSlider.hidden = YES;
    
    // Set up calibration info.
    _val = 0;
    _calibratedLumVal = 0;
    calibrationLuminance = [[NSMutableArray alloc] initWithCapacity:1];
    calibrationTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                target:self
                                selector:@selector(finishCalibrating)
                                userInfo:nil
                                repeats:NO];
    isCalibrating = true;
    
    //Set up the video capture session.
    NSLog(@"Setting up the capture session...\n");
    captureSession = [[AVCaptureSession alloc] init];
    
    //Add input.
    NSLog(@"Adding video input...\n");
    AVCaptureDevice *captureDevice = [self frontFacingCameraIfAvailable];
    if(captureDevice){
        NSError *error;
        videoInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
        if(!error){
            if([captureSession canAddInput:videoInputDevice])
                [captureSession addInput:videoInputDevice];
            else
                NSLog(@"Couldn't add video input.\n");
                    
        }else{
            NSLog(@"Couldn't create video input.\n");
        }
    }else{
        NSLog(@"Couldn't create capture device.\n");
    }
    
    //Add output.
    NSLog(@"Adding video data output...\n");
    vidOutput = [[AVCaptureVideoDataOutput alloc] init];
    vidOutput.alwaysDiscardsLateVideoFrames = YES;
    if([captureSession canAddOutput:vidOutput])
        [captureSession addOutput:vidOutput];
    else
        NSLog(@"Couldn't add video output.\n");
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber numberWithInt:kCVPixelFormatType_32BGRA];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    [vidOutput setVideoSettings:videoSettings];
    dispatch_queue_t queue = dispatch_queue_create("MyQueue", NULL);
    [vidOutput setSampleBufferDelegate:self queue:queue];
    [captureSession startRunning];
    
}

- (void)viewDidUnload{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    // Create a weak instance of the view controller to use within the block.
    __weak ViewController * wself = self;
    
    // Create the Novocaine RingBuffer and AudioManager.
    self.ringBuffer = new RingBuffer(32768, 2);
    self.audioManager = [Novocaine audioManager];
    
    // Get the audio input and the center frequency.
    __block float centerFreq = 0.0;
    [self.audioManager setInputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels){
         wself.ringBuffer->AddNewInterleavedFloatData(data, numFrames, numChannels);
         centerFreq = wself.val;
     }];
    
    // Get the sampling rate.
    float samplingRate = wself.audioManager.samplingRate;
    
    // Establish filter coefficients.
    __block float f;                // f is the center frequency
    float Qvalue = 0.707;           // Q value
    __block float yH = 0.0;         // High-pass result
    __block float yB = 0.0;         // Band-pass result
    __block float yL = 0.0;         // Low-pass result
    
    [self.audioManager setOutputBlock:^(float *data, UInt32 numFrames, UInt32 numChannels){
         wself.ringBuffer->FetchInterleavedData(data, numFrames, numChannels);
         f	= 2 * M_PI * centerFreq/samplingRate;
         printf("Center Frequency: %f\n", centerFreq);
        
         // Hop back to the main thread to update the UI
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             ViewController *strongSelf = wself;
             if(strongSelf){
                 strongSelf->CFValue.text = [NSString stringWithFormat:@"%.2f Hz", centerFreq];
             }else{
                 NSLog(@"Oh dear.");
             }
         }];
        
         for (int i=0; i < numFrames; ++i){
             for (int iChannel = 0; iChannel < numChannels; ++iChannel){
                 // State-variable filter to produce wah wah effect.
                 yH = data[i*numChannels + iChannel] - yL - Qvalue*yB;
                 yB = f*yH + yB;
                 yL = f*yB + yL;
                 // Use the band-passed signal.
                 data[i*numChannels + iChannel] = yB;
             }
         }
     }];
    
    [self.audioManager play];
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return YES;
    }
}

-(AVCaptureDevice *)frontFacingCameraIfAvailable{
    // Look for the front-facing camera first
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices){
        if (device.position == AVCaptureDevicePositionFront){
            captureDevice = device;
            break;
        }
    }
    
    // Couldn't find one on the front, so just get the default video device
    if (!captureDevice){
        captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    return captureDevice;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection: (AVCaptureConnection *)connection{
    // Create autorelease pool because we are not in the main_queue
    @autoreleasepool {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // Lock the imagebuffer
        CVPixelBufferLockBaseAddress(imageBuffer,0);
        
        // Get the image
        UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
        
        // Convert it to a CGImage so we can get the data
        CGImageRef cgImage = [image CGImage];
        CGDataProviderRef provider = CGImageGetDataProvider(cgImage);
        CFDataRef bitmapData = CGDataProviderCopyData(provider);
        const UInt8* data = CFDataGetBytePtr(bitmapData);
        
        // Get the information about the CGImage
        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        size_t bytesPerRow = CGImageGetBytesPerRow(cgImage);
        size_t bitsPerPixel = CGImageGetBitsPerPixel(cgImage);
        size_t bitsPerComponent = CGImageGetBitsPerComponent(cgImage);
        size_t bytesPerPixel = bitsPerPixel/bitsPerComponent;
        
        size_t trimmedHeight = height/4;
        size_t trimmedWidth = width/4;
        
        
        // Calculate the average luminance
        float avgLuminance = 0.0;
        
        // We want to use trimmedWidth and trimmedHeight because the camera sees a wide image.
        // We only care about what's directly above it, so this will improve proximity sensing (and speed)
        // by only checking an area of the image concentrated in the center.
        for(int row = (int)trimmedHeight; row < (height-trimmedHeight); row++){
            for(int col = (int)trimmedWidth; col < (width-trimmedWidth); col++){
                const UInt8* pixel = &data[row*bytesPerRow + col*bytesPerPixel];
                avgLuminance += (pixel[0]*0.299) + (pixel[1]*0.587) + (pixel[2]*0.114);
            }
        }
        avgLuminance /= (4*trimmedWidth*trimmedHeight);
        
        // Release the CF data reference
        CFRelease(bitmapData);
        //NSLog(@"Average Luminance: %f\n", avgLuminance);
        
        if(isCalibrating){
            [calibrationLuminance addObject:[NSNumber numberWithFloat:avgLuminance]];
        }else{
            // sliderValsToInts updates the UI, so jump to the main thread
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self sliderValsToInts];
            }];
            _val = [self luminanceToFrequency:avgLuminance withMax:_calibratedLumVal
                                     andUpper:HFSlider.value andLower:LFSlider.value];
        }
        
    }
}

-(UIImage *)imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
}

-(float)luminanceToFrequency:(float)lum withMax:(float)maxVal
                                        andUpper:(int)upperBound
                                        andLower:(int)lowerBound{

    // Get the frequency bandwidth.
    const int bandwidth = upperBound - lowerBound;
    
    // Make sure we don't go above the calibrated maximum.
    if(lum > maxVal)
        lum = maxVal;
    
    // Scale the luminance value to our frequency boundaries.
    float scaled = lum/maxVal;
    scaled = pow(scaled, 4);
    scaled = upperBound - scaled*bandwidth;

    return scaled;
}

-(void)finishCalibrating{
    // Get out of the calibration process.
    [calibrationTimer invalidate];
    calibrationTimer = nil;
    isCalibrating = false;
    calibrationTitle.text = @"Finished!";
    titleTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                   target:self
                                   selector:@selector(createDisplay)
                                   userInfo:nil
                                   repeats:NO];
    calibrationMessage.hidden = YES;
    int count = 0;
    for(NSNumber *currentVal in calibrationLuminance){
        _calibratedLumVal += [currentVal floatValue];
        count++;
    }
    _calibratedLumVal = _calibratedLumVal/count;
}

-(void)sliderValsToInts{
    // Convert frequency slider values to integers and update the UI.
    int outputLF = (int)LFSlider.value;
    int outputHF = (int)HFSlider.value;
    LFSlider.value = outputLF;
    HFSlider.value = outputHF;
    LFvalue.text = [NSString stringWithFormat:@"%i Hz", outputLF];
    HFvalue.text = [NSString stringWithFormat:@"%i Hz", outputHF];
    [LFvalue setNeedsDisplay];
    [HFvalue setNeedsDisplay];
}

-(void)createDisplay{
    // Hide the calibration UI.
    [titleTimer invalidate];
    titleTimer = nil;
    calibrationTitle.hidden = YES;
    
    // Reveal the post-calibration UI.
    sweepParams.hidden = NO;
    LF.hidden = NO;
    HF.hidden = NO;
    CF.hidden = NO;
    CFValue.hidden = NO;
    LFvalue.hidden = NO;
    HFvalue.hidden = NO;
    LFSlider.hidden = NO;
    HFSlider.hidden = NO;
}


@end

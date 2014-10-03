//
//  ViewController.h
//  ProximityWahApp
//
//  Created by Roshan Krishnan on 6/28/14.
//  Copyright (c) 2014 Roshan Krishnan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "Novocaine.h"
#import "RingBuffer.h"
#import "AudioFileReader.h"
#import "AudioFileWriter.h"
#import "Endian.h"

#define CAPTURE_FPS = 20;

@interface ViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate>{
    IBOutlet UILabel *calibrationTitle;
    IBOutlet UILabel *sweepParams;
    IBOutlet UILabel *LF;
    IBOutlet UILabel *LFvalue;
    IBOutlet UILabel *HF;
    IBOutlet UILabel *HFvalue;
    IBOutlet UILabel *CF;
    IBOutlet UILabel *CFValue;
    IBOutlet UISlider *LFSlider;
    IBOutlet UISlider *HFSlider;
    IBOutlet UITextView *calibrationMessage;
    NSTimer *calibrationTimer;
    NSTimer *titleTimer;
    AVCaptureSession *captureSession;
    AVCaptureVideoDataOutput *vidOutput;
    AVCaptureDeviceInput *videoInputDevice;
    NSMutableArray *calibrationLuminance;
    bool isCalibrating;
}

@property (nonatomic, strong) Novocaine *audioManager;
@property (nonatomic, strong) AudioFileReader *fileReader;
@property (nonatomic, strong) AudioFileWriter *fileWriter;
@property float val;
@property float calibratedLumVal;

-(AVCaptureDevice *)frontFacingCameraIfAvailable;
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection: (AVCaptureConnection *)connection;
-(UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer;
-(float)luminanceToFrequency:(float)lum withMax:(float)maxVal andUpper:(int)upperBound andLower:(int)lowerBound;
-(void)sliderValsToInts;
-(void)finishCalibrating;
-(void)createDisplay;

@end


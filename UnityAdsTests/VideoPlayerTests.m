#import <XCTest/XCTest.h>
#import "UnityAdsTests-Bridging-Header.h"
#import "UADSWebViewApp.h"
#import "UADSAVPlayer.h"
#import "UADSVideoView.h"
#import "UADSViewController.h"

@interface VideoPlayerTestsWebApp : UADSWebViewApp
@property (nonatomic, strong) XCTestExpectation *expectation;
@property (nonatomic, strong) NSString *fulfillingEvent;
@property (nonatomic, strong) NSString *collectEvents;
@property (nonatomic, strong) NSMutableArray *collectedEvents;
@end

@implementation VideoPlayerTestsWebApp
@synthesize expectation = _expectation;
@synthesize fulfillingEvent = _fulfillingEvent;
@synthesize collectEvents = _collectEvents;
@synthesize collectedEvents = _collectedEvents;

- (id)init {
    self = [super init];
    if (self) {
    }
    
    return self;
}

- (BOOL)invokeCallback:(UADSInvocation *)invocation {
    return true;
}

- (BOOL)sendEvent:(NSString *)eventId category:(NSString *)category params:(NSArray *)params {
    return true;
}

- (BOOL)sendEvent:(NSString *)eventId category:(NSString *)category param1:(id)param1, ... {
    NSLog(@"GOT_EVENT=%@", eventId);
    if (self.fulfillingEvent && [self.fulfillingEvent isEqualToString:eventId]) {
        NSLog(@"FULFILLING=%@", eventId);
        if (self.expectation) {
            [self.expectation fulfill];
        }
        else {
        }
    }
    
    if (self.collectEvents && [self.collectEvents isEqualToString:eventId]) {
        NSLog(@"COLLECTING=%@", eventId);
        if (!self.collectedEvents) {
            self.collectedEvents = [[NSMutableArray alloc] init];
        }
        
        long currentTimeMS = ([[NSDate date] timeIntervalSince1970] * 1000);
        [self.collectedEvents addObject:[NSNumber numberWithLong:currentTimeMS]];
    }

    return true;
}

- (BOOL)invokeMethod:(NSString *)methodName className:(NSString *)className receiverClass:(NSString *)receiverClass callback:(NSString *)callback params:(NSArray *)params {
    return true;
}

@end


@interface VideoPlayerTests : XCTestCase
@property (nonatomic, strong) UADSAVPlayer *videoPlayer;
@property (nonatomic, strong) UADSVideoView *videoView;
@property (nonatomic, strong) UADSViewController *viewController;
@end

@implementation VideoPlayerTests
@synthesize videoView = _videoView;
@synthesize videoPlayer = _videoPlayer;
@synthesize viewController = _viewController;

static NSString *validVideoUrl = @"https://static.applifier.com/impact/11017/blue_test_trailer.mp4";
static NSString *invalidVideoUrl = @"https://static.applifier.com/impact/11017/invalid_video_url.mp4";

- (BOOL)waitForViewControllerStart {
    self.viewController = [[UADSViewController alloc] init];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:self.viewController animated:true completion:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    __block BOOL success = true;
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_sync(queue, ^{
        [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"VIEW_CONTROLLER_DID_APPEAR"];
        [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:expectation];
        [self waitForExpectationsWithTimeout:60 handler:^(NSError * _Nullable error) {
            if (error) {
                success = false;
            }
        }];
    });
    
    return success;
}

- (BOOL)waitForViewControllerExit {
    [self.viewController dismissViewControllerAnimated:true completion:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    __block BOOL success = true;
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_sync(queue, ^{
        [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"VIEW_CONTROLLER_DID_DISAPPEAR"];
        [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:expectation];
        [self waitForExpectationsWithTimeout:60 handler:^(NSError * _Nullable error) {
            if (error) {
                success = false;
            }
        }];
    });
    
    return success;
}

- (void)setUp {
    [super setUp];
    
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping setUp");
        return;
    }
    
    VideoPlayerTestsWebApp *webViewApp = [[VideoPlayerTestsWebApp alloc] init];
    [UADSWebViewApp setCurrentApp:webViewApp];
    [[UADSWebViewApp getCurrentApp] setWebAppLoaded:true];
    [[UADSWebViewApp getCurrentApp] setWebAppInitialized:true];
    
    [self setVideoView:[[UADSVideoView alloc] initWithFrame:CGRectMake(0, 0, 400, 400)]];
    [self.videoView setVideoFillMode:AVLayerVideoGravityResizeAspect];
    
    AVURLAsset *asset = nil;
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    [self setVideoPlayer:[[UADSAVPlayer alloc] initWithPlayerItem:item]];
    [self.videoView setPlayer:self.videoPlayer];
}

- (void)tearDown {
    [super tearDown];
    
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping tearDown");
        return;
    }
    
    [self.videoPlayer stop];
    [self.videoPlayer stopObserving];
    self.videoPlayer = NULL;
    [self.videoView removeFromSuperview];
    self.videoView = NULL;
}

- (void)testConstruct {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }
    
    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    XCTAssertNotNil(self.videoPlayer, @"VideoPlayer should not be NULL");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    XCTAssertNotNil(self.videoView, @"VideoView should not be NULL");
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
    [self.videoView removeFromSuperview];
}

- (void)testPrepare {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];

    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:expectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)testPrepareAndPlay {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    
    XCTestExpectation *playExpectation = [self expectationWithDescription:@"playExpectation"];
    [self.videoPlayer play];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:playExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"COMPLETED"];

    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];

    XCTAssertTrue(success, @"Play expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)testPrepareAndPlayNonExistingUrl {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:invalidVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"GENERIC_ERROR"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)testPreparePlaySeekToPause {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    
    [self.videoPlayer play];

    XCTestExpectation *seekExpectation = [self expectationWithDescription:@"seekExpectation"];
    [self performSelector:@selector(seekVideoPlayerTo4080) withObject:self afterDelay:1];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:seekExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"SEEKTO"];
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    [self.videoPlayer pause];
    
    int diff = abs(4080 - [self.videoPlayer getCurrentPosition]);
    
    XCTAssertTrue(diff < 100, @"Seek threshold exceeded!");
    XCTAssertTrue(success, @"Seekto expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)seekVideoPlayerTo4080 {
    [self.videoPlayer seekTo:4080];
}

- (void)testPreparePlayStop {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:NULL];
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    
    [self.videoPlayer play];
    
    XCTestExpectation *stopExpectation = [self expectationWithDescription:@"stopExpectation"];
    [self performSelector:@selector(stopVideoPlayer) withObject:self afterDelay:2];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:stopExpectation];

    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Stop expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)stopVideoPlayer {
    [self.videoPlayer stop];
    [[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] expectation] fulfill];
}

- (void)testPreparePlaySetVolumePause {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:NULL];
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    
    [self.videoPlayer play];
    
    XCTestExpectation *volumeExpectation = [self expectationWithDescription:@"volumeExpectation"];
    [self performSelector:@selector(setVideoPlayerVolumeTo0666) withObject:self afterDelay:2];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:volumeExpectation];
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Volume expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    XCTAssertEqual(0.666f, [self.videoPlayer volume], @"Volume is not what was expected");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)setVideoPlayerVolumeTo0666 {
    [self.videoPlayer setVolume:0.666f];
    [self.videoPlayer pause];
    [[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] expectation] fulfill];
}

- (void)testSetProgressInterval {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer setProgressEventInterval:333];
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:NULL];
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    
    XCTestExpectation *playExpectation = [self expectationWithDescription:@"playExpectation"];
    [self.videoPlayer play];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:playExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setCollectEvents:@"PROGRESS"];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"COMPLETED"];
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    double totalDiff = 0;
    double totalValueCount = [[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] collectedEvents] count];
    double baseValue = [[[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] collectedEvents] objectAtIndex:0] longLongValue];
    for (int idx = 1; idx < [[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] collectedEvents] count]; idx++) {
        double current = [[[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] collectedEvents] objectAtIndex:idx] longLongValue];
        double currentDiff = baseValue - current;
        totalDiff += currentDiff;
        baseValue = [[[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] collectedEvents] objectAtIndex:idx] longLongValue];
    }
    
    XCTAssertTrue(success, @"Play expectation was not opened properly or an error occurred!");
    XCTAssertTrue(333 - (int)abs((int)roundf(fabs(totalDiff / totalValueCount))) < 70, @"Event approximate threshold should be less than 70ms");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)testPreparePlayPause {
    if ([UADSDevice isSimulator]) {
        NSLog(@"Device is simulator, Skipping a videoview test");
        return;
    }

    XCTAssertTrue([self waitForViewControllerStart], @"Couldn't start viewController properly");
    [self.viewController.view addSubview:self.videoView];
    
    XCTestExpectation *prepareExpectation = [self expectationWithDescription:@"prepareExpectation"];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        [self.videoPlayer prepare:validVideoUrl initialVolume:1.0f timeout:10000];
    });
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:prepareExpectation];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:@"PREPARED"];
    
    __block BOOL success = true;
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setFulfillingEvent:NULL];
    XCTAssertTrue(success, @"Prepare expectation was not opened properly or an error occurred!");
    
    [self.videoPlayer play];
    
    XCTestExpectation *pauseExpectation = [self expectationWithDescription:@"pauseExpectation"];
    [self performSelector:@selector(pauseVideoPlayer) withObject:self afterDelay:2];
    [(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] setExpectation:pauseExpectation];
    
    [self waitForExpectationsWithTimeout:30 handler:^(NSError * _Nullable error) {
        if (error) {
            success = false;
        }
    }];
    
    XCTAssertTrue(success, @"Pause expectation was not opened properly or an error occurred!");
    XCTAssertFalse(self.videoPlayer.isPlaying, @"VideoPlayer should not be in isPlaying -state");
    XCTAssertTrue([self.videoPlayer getCurrentPosition] > 300, @"Videoplayer current position should be over 300ms");
    [self.videoView removeFromSuperview];
    XCTAssertTrue([self waitForViewControllerExit], @"Couldn't exit viewController properly");
}

- (void)pauseVideoPlayer {
    [self.videoPlayer pause];
    [[(VideoPlayerTestsWebApp *)[UADSWebViewApp getCurrentApp] expectation] fulfill];
}

@end

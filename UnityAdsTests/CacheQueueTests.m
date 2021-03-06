#import <XCTest/XCTest.h>
#import "UnityAdsTests-Bridging-Header.h"

static long kVideoSize = 1445875;
static long kMinFileSize = 5000;
static NSString *videoUrl = @"https://static.applifier.com/impact/11017/blue_test_trailer.mp4";



@interface MockWebViewApp : UADSWebViewApp
@property (nonatomic, strong) XCTestExpectation *expectation;
@property (nonatomic, strong) XCTestExpectation *progressExpectation;
@property (nonatomic, strong) XCTestExpectation *resumeEndExpectation;


@end

@implementation MockWebViewApp

- (BOOL)sendEvent:(NSString *)eventId category:(NSString *)category param1:(id)param1, ... {
    if (eventId && [eventId isEqualToString:@"DOWNLOAD_END"]) {
        NSLog(@"DOWNLOAD_END");
        if (self.expectation) {
            [self.expectation fulfill];
            self.expectation = nil;
        }
        
        if (self.resumeEndExpectation) {
            [self.resumeEndExpectation fulfill];
            self.resumeEndExpectation = nil;
        }
    }
    if (eventId && [eventId isEqualToString:@"DOWNLOAD_PROGRESS"]) {
        
        va_list args;
        va_start(args, param1);
        
        NSMutableArray *params = [[NSMutableArray alloc] init];
        
        __unsafe_unretained id arg = nil;
        
        if (param1) {
            [params addObject:param1];
            
            while ((arg = va_arg(args, id)) != nil) {
                [params addObject:arg];
            }
            
            va_end(args);
        }
        NSLog(@"DOWNLOAD_PROGRESS %li", (long)[[params objectAtIndex:1] integerValue]);
        if ([[params objectAtIndex:1] integerValue] > kMinFileSize) {
            if (self.progressExpectation) {
                [self.progressExpectation fulfill];
                self.progressExpectation = nil;
            }
        }
        
    }
    
    return true;
}

- (BOOL)invokeCallback:(UADSInvocation *)invocation {
    return true;
}
@end

@interface CacheQueueTests : XCTestCase
@end

@implementation CacheQueueTests

- (void)setUp {
    [super setUp];
    MockWebViewApp *webApp = [[MockWebViewApp alloc] init];
    [UADSWebViewApp setCurrentApp:webApp];
    [UADSCacheQueue start];
}

- (void)testDownloadFile {
    XCTestExpectation *expectation = [self expectationWithDescription:@"downloadFinishExpectation"];
    MockWebViewApp *mockApp = (MockWebViewApp *)[UADSWebViewApp getCurrentApp];
    [mockApp setExpectation:expectation];
    NSString *fileName = [NSString stringWithFormat:@"%@/%@", [UADSSdkProperties getCacheDirectory], @"test.mp4"];
    [[NSFileManager defaultManager]removeItemAtPath:fileName error:nil];
    
    [UADSCacheQueue download:@"https://static.applifier.com/impact/videos/41566/a8d822f017e100c5/adcap-trailer-badge-logo-1280x720/m31-1000.mp4" target:fileName];
    [self waitForExpectationsWithTimeout:60 handler:^(NSError * _Nullable error) {
    }];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    XCTAssertTrue([fileManager fileExistsAtPath:fileName], "File should exist after downloading");
}

- (void)testSetConnectTimeout {
    [UADSCacheQueue setConnectTimeout:15000];
    XCTAssertEqual([UADSCacheQueue getConnectTimeout], 15000, "Connect timeout was not the same as expected");
}

- (void)testResumeDownload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"downloadProgressExpectation"];
    MockWebViewApp *mockApp = (MockWebViewApp *)[UADSWebViewApp getCurrentApp];
    [mockApp setProgressExpectation:expectation];
    NSString *fileName = [NSString stringWithFormat:@"%@/%@", [UADSSdkProperties getCacheDirectory], @"resume_test.mp4"];
    [[NSFileManager defaultManager] removeItemAtPath:fileName error:nil];
    
    [UADSCacheQueue setProgressInterval:50];
    [UADSCacheQueue download:videoUrl target:fileName];
    [self waitForExpectationsWithTimeout:60 handler:^(NSError * _Nullable error) {
        [mockApp setProgressExpectation:nil];
    }];
    
    [UADSCacheQueue cancelAllDownloads];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:fileName], "File should exist");

    XCTestExpectation *delayExpectation  = [self expectationWithDescription:@"delayEndExpectation"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [delayExpectation fulfill];
    });
    
    [self waitForExpectationsWithTimeout:2 handler:^(NSError * _Nullable error) {
    }];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:fileName];
    unsigned long long fileSize = [fileHandle seekToEndOfFile];
    XCTAssertTrue(fileSize > kMinFileSize, "File size should be over 5000 %llu", fileSize);
    XCTAssertTrue(fileSize < kVideoSize, "File size should be less than kVideoSize (1445875)");
        
    XCTestExpectation *endExpectation  = [self expectationWithDescription:@"downloadEndExpectation"];
    [mockApp setResumeEndExpectation:endExpectation];

    [UADSCacheQueue download:videoUrl target:fileName];
        
    [self waitForExpectationsWithTimeout:60 handler:^(NSError * _Nullable error) {
    }];

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:fileName], "File should exist");
    NSFileHandle *fileHandle2 = [NSFileHandle fileHandleForUpdatingAtPath:fileName];
    unsigned long long fileSize2 = [fileHandle2 seekToEndOfFile];
    XCTAssertEqual(fileSize2, kVideoSize, "File size should be same as kVideoSize");
}


- (void)testSetProgressInterval {
    [UADSCacheQueue setProgressInterval:500];
    XCTAssertEqual(500, [UADSCacheQueue getProgressInterval], @"Progress interval should be equal to 500");
}
@end

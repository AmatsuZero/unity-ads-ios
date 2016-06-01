#import "UADSInitialize.h"
#import "UADSWebViewApp.h"
#import "UADSSdkProperties.h"
#import "UADSURLProtocol.h"
#import "UADSStorageManager.h"
#import "UADSWebRequest.h"
#import "UADSWebRequestQueue.h"
#import "UADSCacheQueue.h"
#import "UADSApiPlacement.h"
#import "NSString+Hash.h"

@implementation UADSInitialize

static NSOperationQueue *initializeQueue;
static UADSConfiguration *currentConfiguration;
static dispatch_once_t onceToken;

+ (void)initialize:(UADSConfiguration *)configuration {
    dispatch_once(&onceToken, ^{
        if (!initializeQueue) {
            initializeQueue = [[NSOperationQueue alloc] init];
            initializeQueue.maxConcurrentOperationCount = 1;
        }
    });

    if (initializeQueue && initializeQueue.operationCount == 0) {
        currentConfiguration = configuration;
        id state = [[UADSInitializeStateReset alloc] initWithConfiguration:currentConfiguration];
        [state setQueue:initializeQueue];
        [initializeQueue addOperation:state];
    }
}

@end

/* STATE CLASSES */

// BASE STATE

@implementation UADSInitializeState

- (void)main {
    id nextState = [self execute];
    if (nextState && self.queue) {
        [self.queue addOperation:nextState];
    }
}

- (instancetype)execute {
    return NULL;
}

- (instancetype)initWithConfiguration:(UADSConfiguration *)configuration {
    self = [super init];
    
    if (self) {
        [self setConfiguration:configuration];
    }
    
    return self;
}

@end

// RESET

@implementation UADSInitializeStateReset : UADSInitializeState

- (instancetype)execute {
    [UADSCacheQueue start];
    [UADSWebRequestQueue start];    
    UADSWebViewApp *currentWebViewApp = [UADSWebViewApp getCurrentApp];
    
    if (currentWebViewApp != NULL) {
        [currentWebViewApp setWebAppLoaded:false];
        [currentWebViewApp setWebAppInitialized:false];
        NSCondition *blockCondition = [[NSCondition alloc] init];
        
        if ([currentWebViewApp webView] != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([[currentWebViewApp webView] superview]) {
                    [[currentWebViewApp webView] removeFromSuperview];
                }

                [blockCondition lock];
                [blockCondition signal];
                [blockCondition unlock];
            });
            
            [currentWebViewApp setWebView:NULL];
        }
        
        [blockCondition lock];
        BOOL success = [blockCondition waitUntilDate:[[NSDate alloc] initWithTimeIntervalSinceNow:10]];
        [blockCondition unlock];
        
        if (!success) {
            UADSLog(@"WIERD ERROR, DISPATCH ASYNC DID NOT RUN THROUGH WHILE RESETTING SDK")
            return NULL;
        }

        [UADSWebViewApp setCurrentApp:NULL];
    }
    
    [UADSSdkProperties setInitialized:false];
    [UADSApiPlacement reset];
    [UADSCacheQueue cancelAllDownloads];
    [UADSConnectivityMonitor stopAll];
    [UADSStorageManager init];
    
    id nextState = [[UADSInitializeStateConfig alloc] initWithConfiguration:self.configuration retries:0];
    [nextState setQueue:self.queue];
    return nextState;
}

@end

// CONFIG

@implementation UADSInitializeStateConfig : UADSInitializeState

- (instancetype)initWithConfiguration:(UADSConfiguration *)configuration retries:(int)retries {
    self = [super initWithConfiguration:configuration];
    
    if (self) {
        [self setRetries:retries];
        [self setMaxRetries:2];
        [self setRetryDelay:10];
    }
    
    return self;
}

- (instancetype)execute {
    [self.configuration setConfigUrl:[UADSSdkProperties getConfigUrl]];
    [self.configuration makeRequest];
    
    if (!self.configuration.error) {
        id nextState = [[UADSInitializeStateLoadCache alloc] initWithConfiguration:self.configuration];
        [nextState setQueue:self.queue];
        return nextState;
    }
    else if (self.configuration.error && self.retries < self.maxRetries) {
        self.retries++;
        id retryState = [[UADSInitializeStateConfig alloc] initWithConfiguration:self.configuration retries:self.retries];
        id nextState = [[UADSInitializeStateRetry alloc] initWithConfiguration:self.configuration retryState:retryState retryDelay:self.retryDelay];
        [nextState setQueue:self.queue];
        return nextState;
    }
    else {
        id erroredState = [[UADSInitializeStateConfig alloc] initWithConfiguration:self.configuration retries:self.retries];
        id nextState = [[UADSInitializeStateNetworkError alloc] initWithConfiguration:self.configuration erroredState:erroredState];
        [nextState setQueue:self.queue];
        return nextState;
    }
}

@end

// LOAD CACHE

@implementation UADSInitializeStateLoadCache : UADSInitializeState

- (instancetype)execute {
    NSString *localWebViewFile = [UADSSdkProperties getLocalWebViewFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:localWebViewFile]) {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:localWebViewFile];
        NSData *fileData = [fileHandle readDataToEndOfFile];
        NSString *fileString = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
        NSString *localWebViewHash = [fileString sha256];
        
        if (!localWebViewHash || (localWebViewHash && [localWebViewHash isEqualToString:self.configuration.webViewHash])) {
            UADSLog(@"Loaded WebView from Cache");
            id nextState = [[UADSInitializeStateCreate alloc] initWithConfiguration:self.configuration webViewData:fileString];
            [nextState setQueue:self.queue];
            return nextState;
        }
    }
    
    id nextState = [[UADSInitializeStateLoadWeb alloc] initWithConfiguration:self.configuration retries:0];
    [nextState setQueue:self.queue];
    return nextState;
}

@end

// LOAD NETWORK

@implementation UADSInitializeStateLoadWeb : UADSInitializeState

- (instancetype)initWithConfiguration:(UADSConfiguration *)configuration retries:(int)retries {
    self = [super initWithConfiguration:configuration];
    
    if (self) {
        [self setRetries:retries];
        [self setMaxRetries:2];
        [self setRetryDelay:10];
    }
    
    return self;
}

- (instancetype)execute {
    NSString *urlString = [NSString stringWithFormat:@"%@", [self.configuration webViewUrl]];
    UADSWebRequest *webRequest = [[UADSWebRequest alloc] initWithUrl:urlString requestType:@"GET" headers:NULL connectTimeout:30000];
    NSData *responseData = [webRequest makeRequest];

    if (!webRequest.error) {
        [responseData writeToFile:[UADSSdkProperties getLocalWebViewFile] atomically:YES];
    }
    else if (webRequest.error && self.retries < self.maxRetries) {
        self.retries++;
        id retryState = [[UADSInitializeStateLoadWeb alloc] initWithConfiguration:self.configuration retries:self.retries];
        id nextState = [[UADSInitializeStateRetry alloc] initWithConfiguration:self.configuration retryState:retryState retryDelay:self.retryDelay];
        [nextState setQueue:self.queue];
        return nextState;
    }
    else if (webRequest.error) {
        id erroredState = [[UADSInitializeStateLoadWeb alloc] initWithConfiguration:self.configuration retries:self.retries];
        id nextState = [[UADSInitializeStateNetworkError alloc] initWithConfiguration:self.configuration erroredState:erroredState];
        [nextState setQueue:self.queue];
        return nextState;
    }

    NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
    id nextState = [[UADSInitializeStateCreate alloc] initWithConfiguration:self.configuration webViewData:responseString];
    [nextState setQueue:self.queue];
    return nextState;
}

@end

// CREATE

@implementation UADSInitializeStateCreate : UADSInitializeState

- (instancetype)execute {
    [NSURLProtocol registerClass:[UADSURLProtocol class]];
    [self.configuration setWebViewData:[self webViewData]];
    [UADSWebViewApp create:self.configuration];

    id nextState = [[UADSInitializeStateComplete alloc] initWithConfiguration:self.configuration];
    [nextState setQueue:self.queue];
    return nextState;
}

- (instancetype)initWithConfiguration:(UADSConfiguration *)configuration webViewData:(NSString *)webViewData {
    self = [super initWithConfiguration:configuration];

    if (self) {
        [self setWebViewData:webViewData];
    }

    return self;
}

@end

// COMPLETE

@implementation UADSInitializeStateComplete : UADSInitializeState
- (instancetype)execute {
    UADSLog(@"COMPLETE");
    return NULL;
}
@end

// ERROR

@implementation UADSInitializeStateError : UADSInitializeState

- (instancetype)initWithConfiguration:(UADSConfiguration *)configuration erroredState:(id)erroredState {
    self = [super initWithConfiguration:configuration];
    
    if (self) {
        [self setErroredState:erroredState];
    }
    
    return self;
}

- (instancetype)execute {
    return NULL;
}
@end

// NETWORK ERROR

@implementation UADSInitializeStateNetworkError : UADSInitializeStateError

- (void)connected {
    self.receivedConnectedEvents++;
    
    if ([self shouldHandleConnectedEvent]) {
        [self.blockCondition lock];
        [self.blockCondition signal];
        [self.blockCondition unlock];
    }
    
    self.lastConnectedEventTimeMs = [[NSDate date] timeIntervalSince1970] * 1000;
}

- (void)disconnected {
    UADSLog(@"GOT DISCONNECTED EVENT");
}

- (instancetype)execute {
    [UADSConnectivityMonitor startListening:self];
    
    self.blockCondition = [[NSCondition alloc] init];
    [self.blockCondition lock];
    BOOL success = [self.blockCondition waitUntilDate:[[NSDate alloc] initWithTimeIntervalSinceNow:10000 * 60]];
    
    if (success) {
        [UADSConnectivityMonitor stopListening:self];
        return self.erroredState;
    }
    else {
        [UADSConnectivityMonitor stopListening:self];
    }

    [self.blockCondition unlock];
    return NULL;
}

- (BOOL)shouldHandleConnectedEvent {
    long currentTimeMs = [[NSDate date] timeIntervalSince1970] * 1000;
    if (currentTimeMs - self.lastConnectedEventTimeMs >= 10000 && self.receivedConnectedEvents < 500) {
        return true;
    }

    return false;
}

@end

// RETRY

@implementation UADSInitializeStateRetry:  UADSInitializeState

- (instancetype)initWithConfiguration:(UADSConfiguration *)configuration retryState:(id)retryState retryDelay:(int)retryDelay {
    self = [super initWithConfiguration:configuration];
    
    if (self) {
        [self setRetryState:retryState];
        [self setRetryDelay:retryDelay];
    }
    
    return self;
}

- (instancetype)execute {
    NSCondition *blockCondition = [[NSCondition alloc] init];
    [blockCondition lock];
    [blockCondition waitUntilDate:[[NSDate alloc] initWithTimeIntervalSinceNow:self.retryDelay]];
    [blockCondition unlock];
    
    return self.retryState;
}
@end
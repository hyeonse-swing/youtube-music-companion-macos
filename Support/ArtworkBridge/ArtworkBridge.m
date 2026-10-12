#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "NowPlayingSelection.h"
#include <stdio.h>

/// Loaded by Apple's `perl` process. MediaRemote permits that platform-signed
/// host to request the bytes but denies the same request from a third-party app.
/// Returning base64 keeps the process boundary simple and avoids temporary files.
__attribute__((visibility("default")))
void YTMCPrintNowPlayingArtworkBase64(void) {
    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC);
    // Reserve time for the targeted artwork request within the same four
    // seconds as the metadata selection.
    YTMCNowPlayingSelection *selection = YTMCSelectPreferredNowPlaying(2.5);
    if (!selection) return;

    Class requestClass = NSClassFromString(@"MRNowPlayingRequest");
    id path = YTMCPlayerPathForClient(selection.client);
    if (!path || ![requestClass instancesRespondToSelector:@selector(initWithPlayerPath:)])
        return;

    id request;
    @try {
        id (*initWithPath)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
        request = initWithPath([requestClass alloc], @selector(initWithPlayerPath:), path);
    } @catch (NSException *exception) {
        return;
    }
    if (!request) return;
    SEL selector = NSSelectorFromString(
        @"requestNowPlayingItemArtworkOnQueue:completion:"
    );
    if (![request respondsToSelector:selector]) {
        return;
    }

    __block NSData *imageData = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    void (^completion)(id, NSError *) = ^(id artwork, NSError *error) {
        if (artwork != nil && error == nil) {
            SEL imageDataSelector = NSSelectorFromString(@"imageData");
            if ([artwork respondsToSelector:imageDataSelector]) {
                NSData *(*sendImageData)(id, SEL) =
                    (NSData *(*)(id, SEL))objc_msgSend;
                id data = sendImageData(artwork, imageDataSelector);
                if ([data isKindOfClass:NSData.class]) imageData = [data copy];
            }
        }
        dispatch_semaphore_signal(semaphore);
    };

    void (*sendRequest)(id, SEL, dispatch_queue_t, id) =
        (void (*)(id, SEL, dispatch_queue_t, id))objc_msgSend;
    @try {
        sendRequest(request, selector, queue, completion);
    } @catch (NSException *exception) {
        return;
    }

    if (dispatch_semaphore_wait(semaphore, deadline) != 0 || imageData.length == 0) {
        return;
    }
    NSString *base64 = [imageData base64EncodedStringWithOptions:0];
    fprintf(stdout, "%s\n", base64.UTF8String);
}

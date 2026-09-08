#import <Foundation/Foundation.h>
#include <dlfcn.h>

@interface NSObject (YTMCNowPlaying)
+ (id)localOrigin;
- (id)initWithOrigin:(id)origin client:(id)client player:(id)player;
- (id)initWithPlayerPath:(id)path;
- (void)requestNowPlayingInfoOnQueue:(dispatch_queue_t)queue
                        completion:(void (^)(NSDictionary *, NSError *))completion;
@end

// Query the installed player directly, independently of macOS's elected source.
// Like the artwork bridge this must run in the platform-signed Perl host.
__attribute__((visibility("default")))
void YTMCPrintYouTubeMusicNowPlaying(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        void (*getClients)(dispatch_queue_t, void (^)(NSArray *)) =
            handle ? dlsym(handle, "MRMediaRemoteGetNowPlayingClients") : NULL;
        Class originClass = NSClassFromString(@"MROrigin");
        Class pathClass = NSClassFromString(@"MRPlayerPath");
        Class requestClass = NSClassFromString(@"MRNowPlayingRequest");
        if (!getClients || ![originClass respondsToSelector:@selector(localOrigin)] ||
            ![pathClass instancesRespondToSelector:@selector(initWithOrigin:client:player:)] ||
            ![requestClass instancesRespondToSelector:@selector(initWithPlayerPath:)] ||
            ![requestClass instancesRespondToSelector:@selector(requestNowPlayingInfoOnQueue:completion:)]) {
            puts("{\"error\":\"unsupported\"}");
            return;
        }
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSDictionary *output = nil;
        getClients(queue, ^(NSArray *clients) {
            id selected = nil;
            // Stable choice if more than one Chromium installation is registered.
            NSArray *sorted = [clients sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                return [[a valueForKey:@"bundleIdentifier"] compare:[b valueForKey:@"bundleIdentifier"]];
            }];
            for (id client in sorted) {
                NSString *bundle = [client valueForKey:@"bundleIdentifier"];
                if ([bundle hasSuffix:@".cinhimbnkkaeohfgghhklpknlkffjgod"]) {
                    selected = client;
                    break;
                }
            }
            if (!selected) {
                output = @{@"error": @"no preferred client"};
                dispatch_semaphore_signal(semaphore);
                return;
            }
            id path = [[pathClass alloc] initWithOrigin:[originClass localOrigin] client:selected player:nil];
            id request = [[requestClass alloc] initWithPlayerPath:path];
            [request requestNowPlayingInfoOnQueue:queue completion:^(NSDictionary *info, NSError *error) {
                if (!error && info) {
                    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
                    [info enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                        NSString *name = [key stringByReplacingOccurrencesOfString:@"kMRMediaRemoteNowPlayingInfo" withString:@""];
                        if ([value isKindOfClass:NSDate.class]) snapshot[name] = @([value timeIntervalSince1970]);
                        else if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) snapshot[name] = value;
                    }];
                    snapshot[@"Bundle"] = [selected valueForKey:@"bundleIdentifier"];
                    snapshot[@"SourcePID"] = [selected valueForKey:@"processIdentifier"];
                    snapshot[@"isPlaying"] = @([snapshot[@"PlaybackRate"] doubleValue] > 0);
                    output = snapshot;
                }
                dispatch_semaphore_signal(semaphore);
            }];
        });
        if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) != 0 || !output) {
            puts("{\"error\":\"query failed\"}");
            return;
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:output options:0 error:nil];
        if (data) fwrite(data.bytes, 1, data.length, stdout);
    }
}

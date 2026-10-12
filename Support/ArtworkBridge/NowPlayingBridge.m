#import "NowPlayingSelection.h"
#include <dlfcn.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>

@interface NSObject (YTMCNowPlaying)
+ (id)localOrigin;
- (id)initWithOrigin:(id)origin client:(id)client player:(id)player;
- (id)initWithPlayerPath:(id)path;
- (void)requestNowPlayingInfoOnQueue:(dispatch_queue_t)queue
                        completion:(void (^)(NSDictionary *, NSError *))completion;
@end

@implementation YTMCNowPlayingSelection
- (instancetype)initWithSnapshot:(NSDictionary *)snapshot client:(id)client {
    if ((self = [super init])) {
        _snapshot = [snapshot copy];
        _client = client;
    }
    return self;
}
@end

@interface YTMCQueryState : NSObject
@property (nonatomic, strong) NSMutableArray *snapshots;
@property (nonatomic, strong) NSMutableIndexSet *completed;
@property (nonatomic, strong) dispatch_group_t group;
@end

@implementation YTMCQueryState
@end

static id YTMCSafeValue(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

static NSString *YTMCSafeString(id object, NSString *key) {
    id value = YTMCSafeValue(object, key);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL YTMCIsPWAIdentifier(NSString *bundle) {
    return [bundle isKindOfClass:NSString.class] &&
        [bundle hasSuffix:@".cinhimbnkkaeohfgghhklpknlkffjgod"];
}

static BOOL YTMCIsLegacyYouTubeMusicProcess(pid_t pid) {
    if (pid <= 0) return NO;
    // KERN_PROCARGS2 returns argc, the executable path, padding, then argv.
    // Limit the kernel copy and inspect argv only; environment variables must
    // not make a generic loader appear to be the YouTube Music app.
    enum { kMaximumArguments = 1024 * 1024 };
    NSMutableData *data = [NSMutableData dataWithLength:kMaximumArguments];
    size_t length = data.length;
    int mib[] = {CTL_KERN, KERN_PROCARGS2, pid};
    if (sysctl(mib, 3, data.mutableBytes, &length, NULL, 0) != 0 ||
        length <= sizeof(int) || length > data.length) {
        return NO;
    }
    const char *cursor = data.bytes;
    const char *end = cursor + length;
    int argc = 0;
    memcpy(&argc, cursor, sizeof(argc));
    if (argc < 1 || argc > 4096) return NO;
    cursor += sizeof(argc);
    const char *pathEnd = memchr(cursor, '\0', (size_t)(end - cursor));
    if (!pathEnd) return NO;
    cursor = pathEnd + 1;
    while (cursor < end && *cursor == '\0') cursor++;
    for (int index = 0; index < argc; index++) {
        if (cursor >= end) return NO;
        const char *argumentEnd = memchr(cursor, '\0', (size_t)(end - cursor));
        if (!argumentEnd) return NO;
        NSString *argument = [[NSString alloc] initWithBytes:cursor
            length:(NSUInteger)(argumentEnd - cursor) encoding:NSUTF8StringEncoding];
        if (argument && [argument rangeOfString:@"youtube music.app"
                                        options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
        cursor = argumentEnd + 1;
    }
    return NO;
}

static NSDictionary *YTMCCandidate(id client, NSUInteger index) {
    NSString *bundle = YTMCSafeString(client, @"bundleIdentifier");
    NSString *parent = YTMCSafeString(client, @"parentApplicationBundleIdentifier");
    BOOL modern = YTMCIsPWAIdentifier(bundle) || YTMCIsPWAIdentifier(parent);
    BOOL legacy = [bundle isEqualToString:@"app_mode_loader"];
    if (!modern && !legacy) return nil;
    id pid = YTMCSafeValue(client, @"processIdentifier");
    double pidNumber = [pid isKindOfClass:NSNumber.class] ? [pid doubleValue] : 0;
    BOOL validPID = isfinite(pidNumber) && pidNumber > 0 && pidNumber <= INT_MAX &&
        pidNumber == floor(pidNumber);
    if (legacy && !modern && !validPID) return nil;
    return @{
        @"client": client,
        @"bundle": bundle ?: @"",
        @"parent": parent ?: @"",
        @"pid": validPID ? @((pid_t)pidNumber) : @0,
        @"legacy": @(legacy && !modern),
        @"index": @(index),
    };
}

static NSComparisonResult YTMCCompareCandidates(NSDictionary *a, NSDictionary *b) {
    NSString *aIdentity = YTMCIsPWAIdentifier(a[@"parent"]) ? a[@"parent"] : a[@"bundle"];
    NSString *bIdentity = YTMCIsPWAIdentifier(b[@"parent"]) ? b[@"parent"] : b[@"bundle"];
    NSComparisonResult result = [aIdentity compare:bIdentity];
    if (result != NSOrderedSame) return result;
    result = [a[@"bundle"] compare:b[@"bundle"]];
    if (result != NSOrderedSame) return result;
    result = [a[@"pid"] compare:b[@"pid"]];
    if (result != NSOrderedSame) return result;
    return [a[@"index"] compare:b[@"index"]];
}

static NSDictionary *YTMCSnapshot(NSDictionary *info, NSDictionary *candidate) {
    if (![info isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    [info enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:NSString.class]) return;
        NSString *name = [key stringByReplacingOccurrencesOfString:
            @"kMRMediaRemoteNowPlayingInfo" withString:@""];
        if ([value isKindOfClass:NSDate.class]) {
            snapshot[name] = @([value timeIntervalSince1970]);
        } else if ([value isKindOfClass:NSString.class] ||
                   [value isKindOfClass:NSNumber.class]) {
            snapshot[name] = value;
        }
    }];

    NSString *title = snapshot[@"Title"];
    NSString *artist = snapshot[@"Artist"];
    if (![title isKindOfClass:NSString.class] || ![artist isKindOfClass:NSString.class] ||
        [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0 ||
        [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return nil;
    }

    // The Swift source filter uses ParentBundle ahead of Bundle. Include it
    // only when it is the matching installed PWA identity.
    snapshot[@"Bundle"] = candidate[@"bundle"];
    if (YTMCIsPWAIdentifier(candidate[@"parent"])) {
        snapshot[@"ParentBundle"] = candidate[@"parent"];
    }
    id pid = candidate[@"pid"];
    if ([pid isKindOfClass:NSNumber.class]) snapshot[@"SourcePID"] = pid;
    snapshot[@"isPlaying"] = @([snapshot[@"PlaybackRate"] doubleValue] > 0);
    return snapshot;
}

static void YTMCFinishCandidate(YTMCQueryState *state, NSUInteger index,
                                NSDictionary *snapshot) {
    BOOL shouldLeave = NO;
    @synchronized (state) {
        if (![state.completed containsIndex:index]) {
            if (snapshot) state.snapshots[index] = snapshot;
            [state.completed addIndex:index];
            shouldLeave = YES;
        }
    }
    if (shouldLeave) dispatch_group_leave(state.group);
}

static void YTMCRequestCandidate(YTMCQueryState *state, NSDictionary *candidate,
                                 NSUInteger index, NSUInteger attempt,
                                 YTMCRequestInfo requestInfo, dispatch_queue_t queue,
                                 dispatch_time_t deadline) {
    if (dispatch_time(DISPATCH_TIME_NOW, 0) >= deadline) {
        YTMCFinishCandidate(state, index, nil);
        return;
    }
    NSObject *oneShot = [NSObject new];
    __block BOOL handled = NO;
    @try {
        requestInfo(candidate[@"client"], queue, ^(NSDictionary *info, NSError *error) {
            @synchronized (oneShot) {
                if (handled) return;
                handled = YES;
            }
            NSDictionary *snapshot = error ? nil : YTMCSnapshot(info, candidate);
            // One retry can recover an empty/transient response. It shares the
            // original deadline and never delays another candidate's request.
            if (!snapshot && attempt == 0 &&
                dispatch_time(DISPATCH_TIME_NOW, 0) < deadline) {
                YTMCRequestCandidate(state, candidate, index, 1, requestInfo, queue, deadline);
            } else {
                YTMCFinishCandidate(state, index, snapshot);
            }
        });
    } @catch (NSException *exception) {
        @synchronized (oneShot) { handled = YES; }
        YTMCFinishCandidate(state, index, nil);
    }
}

YTMCNowPlayingSelection *YTMCSelectNowPlayingWithProviders(
    YTMCGetClients getClients, YTMCRequestInfo requestInfo,
    YTMCLegacyIdentity isLegacyYouTubeMusic, NSTimeInterval timeout) {
    if (!getClients || !requestInfo || timeout <= 0) return nil;
    dispatch_time_t deadline = dispatch_time(
        DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_semaphore_t clientSemaphore = dispatch_semaphore_create(0);
    NSObject *clientOneShot = [NSObject new];
    __block BOOL clientsReceived = NO;
    __block NSArray *clients = nil;
    @try {
        getClients(queue, ^(NSArray *received) {
            @synchronized (clientOneShot) {
                if (clientsReceived) return;
                clientsReceived = YES;
                clients = [received isKindOfClass:NSArray.class] ? [received copy] : nil;
            }
            dispatch_semaphore_signal(clientSemaphore);
        });
    } @catch (NSException *exception) {
        return nil;
    }
    if (dispatch_semaphore_wait(clientSemaphore, deadline) != 0 || !clients) {
        return nil;
    }

    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableArray *verifiedLegacy = [NSMutableArray array];
    dispatch_group_t identityGroup = dispatch_group_create();
    [clients enumerateObjectsUsingBlock:^(id client, NSUInteger index, BOOL *stop) {
        if (dispatch_time(DISPATCH_TIME_NOW, 0) >= deadline) {
            *stop = YES;
            return;
        }
        NSDictionary *candidate = YTMCCandidate(client, index);
        if (!candidate) return;
        if (![candidate[@"legacy"] boolValue]) {
            [candidates addObject:candidate];
        } else if (isLegacyYouTubeMusic) {
            dispatch_group_enter(identityGroup);
            dispatch_async(queue, ^{
                BOOL verified = NO;
                if (dispatch_time(DISPATCH_TIME_NOW, 0) < deadline) {
                    @try {
                        verified = isLegacyYouTubeMusic(
                            [candidate[@"pid"] intValue]);
                    } @catch (NSException *exception) {
                        verified = NO;
                    }
                }
                if (verified) {
                    @synchronized (verifiedLegacy) {
                        [verifiedLegacy addObject:candidate];
                    }
                }
                dispatch_group_leave(identityGroup);
            });
        }
    }];
    // A slow/denied process lookup must leave time to query already-known PWA
    // clients and to retain their completed now-playing snapshots.
    dispatch_time_t identityDeadline = dispatch_time(
        DISPATCH_TIME_NOW, NSEC_PER_SEC / 2);
    dispatch_group_wait(identityGroup,
        identityDeadline < deadline ? identityDeadline : deadline);
    @synchronized (verifiedLegacy) {
        [candidates addObjectsFromArray:verifiedLegacy];
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return YTMCCompareCandidates(a, b);
    }];
    if (candidates.count == 0) return nil;

    YTMCQueryState *state = [YTMCQueryState new];
    state.snapshots = [NSMutableArray arrayWithCapacity:candidates.count];
    state.completed = [NSMutableIndexSet indexSet];
    state.group = dispatch_group_create();
    for (NSUInteger index = 0; index < candidates.count; index++) {
        [state.snapshots addObject:NSNull.null];
        dispatch_group_enter(state.group);
    }
    // Callbacks can arrive while requests are still being dispatched, so the
    // array must be fully populated before any callback may replace a slot.
    for (NSUInteger index = 0; index < candidates.count; index++) {
        YTMCRequestCandidate(state, candidates[index], index, 0, requestInfo, queue, deadline);
    }
    dispatch_group_wait(state.group, deadline);
    NSArray *snapshots;
    @synchronized (state) { snapshots = [state.snapshots copy]; }
    NSUInteger selected = NSNotFound;
    for (NSUInteger index = 0; index < snapshots.count; index++) {
        NSDictionary *snapshot = snapshots[index];
        if (![snapshot isKindOfClass:NSDictionary.class]) continue;
        if (selected == NSNotFound) {
            selected = index;
            continue;
        }
        NSDictionary *current = snapshots[selected];
        BOOL playing = [snapshot[@"isPlaying"] boolValue];
        BOOL currentPlaying = [current[@"isPlaying"] boolValue];
        double timestamp = [snapshot[@"Timestamp"] doubleValue];
        double currentTimestamp = [current[@"Timestamp"] doubleValue];
        if (!isfinite(timestamp)) timestamp = 0;
        if (!isfinite(currentTimestamp)) currentTimestamp = 0;
        if ((playing && !currentPlaying) ||
            (playing == currentPlaying && timestamp > currentTimestamp)) {
            selected = index;
        }
    }
    if (selected == NSNotFound) return nil;
    return [[YTMCNowPlayingSelection alloc] initWithSnapshot:snapshots[selected]
                                                     client:candidates[selected][@"client"]];
}

id YTMCPlayerPathForClient(id client) {
    Class originClass = NSClassFromString(@"MROrigin");
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    if (!client || ![originClass respondsToSelector:@selector(localOrigin)] ||
        ![pathClass instancesRespondToSelector:@selector(initWithOrigin:client:player:)]) {
        return nil;
    }
    @try {
        id origin = [originClass localOrigin];
        return origin ? [[pathClass alloc] initWithOrigin:origin client:client player:nil] : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

YTMCNowPlayingSelection *YTMCSelectPreferredNowPlaying(NSTimeInterval timeout) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                          RTLD_LAZY);
    void (*getClients)(dispatch_queue_t, void (^)(NSArray *)) =
        handle ? dlsym(handle, "MRMediaRemoteGetNowPlayingClients") : NULL;
    Class requestClass = NSClassFromString(@"MRNowPlayingRequest");
    if (!getClients || ![requestClass instancesRespondToSelector:@selector(initWithPlayerPath:)] ||
        ![requestClass instancesRespondToSelector:
            @selector(requestNowPlayingInfoOnQueue:completion:)]) {
        return nil;
    }
    return YTMCSelectNowPlayingWithProviders(
        ^(dispatch_queue_t queue, void (^completion)(NSArray *)) {
            getClients(queue, completion);
        },
        ^(id client, dispatch_queue_t queue,
          void (^completion)(NSDictionary *, NSError *)) {
            id path = YTMCPlayerPathForClient(client);
            if (!path) { completion(nil, nil); return; }
            @try {
                id request = [[requestClass alloc] initWithPlayerPath:path];
                if (!request) { completion(nil, nil); return; }
                [request requestNowPlayingInfoOnQueue:queue completion:completion];
            } @catch (NSException *exception) {
                completion(nil, nil);
            }
        },
        ^BOOL(pid_t pid) { return YTMCIsLegacyYouTubeMusicProcess(pid); },
        timeout);
}

// Query the installed player directly, independently of macOS's elected source.
// This must run in the platform-signed Perl host.
__attribute__((visibility("default")))
void YTMCPrintYouTubeMusicNowPlaying(void) {
    @autoreleasepool {
        YTMCNowPlayingSelection *selection = YTMCSelectPreferredNowPlaying(4.0);
        NSDictionary *output = selection.snapshot ?: @{@"error": @"query failed"};
        NSData *data = [NSJSONSerialization dataWithJSONObject:output options:0 error:nil];
        if (data) fwrite(data.bytes, 1, data.length, stdout);
    }
}

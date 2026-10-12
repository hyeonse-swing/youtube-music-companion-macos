#import <Foundation/Foundation.h>
#import "../Support/ArtworkBridge/NowPlayingSelection.h"
#include <unistd.h>

static NSString *const kPWA = @".cinhimbnkkaeohfgghhklpknlkffjgod";

@interface FixtureClient : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *parentApplicationBundleIdentifier;
@property (nonatomic, strong) NSNumber *processIdentifier;
+ (instancetype)bundle:(NSString *)bundle parent:(NSString *)parent pid:(NSInteger)pid;
@end

@implementation FixtureClient
+ (instancetype)bundle:(NSString *)bundle parent:(NSString *)parent pid:(NSInteger)pid {
    FixtureClient *client = [FixtureClient new];
    client.bundleIdentifier = bundle;
    client.parentApplicationBundleIdentifier = parent;
    client.processIdentifier = @(pid);
    return client;
}
@end

static NSDictionary *Info(NSString *title, NSString *artist, double rate, double timestamp) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (title) info[@"kMRMediaRemoteNowPlayingInfoTitle"] = title;
    if (artist) info[@"kMRMediaRemoteNowPlayingInfoArtist"] = artist;
    info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] = @(rate);
    info[@"kMRMediaRemoteNowPlayingInfoTimestamp"] = @(timestamp);
    return info;
}

static YTMCNowPlayingSelection *SelectWithIdentity(
    NSArray *clients, YTMCRequestInfo request,
    YTMCLegacyIdentity legacyIdentity, double timeout) {
    return YTMCSelectNowPlayingWithProviders(
        ^(dispatch_queue_t queue, void (^completion)(NSArray *)) { completion(clients); },
        request, legacyIdentity, timeout);
}

static YTMCNowPlayingSelection *Select(NSArray *clients, YTMCRequestInfo request, double timeout) {
    return SelectWithIdentity(clients, request, nil, timeout);
}

static void Check(BOOL condition, NSString *caseName) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", caseName.UTF8String);
        exit(1);
    }
    printf("PASS: %s\n", caseName.UTF8String);
}

int main(void) {
    @autoreleasepool {
        FixtureClient *other = [FixtureClient bundle:@"com.spotify.client" parent:nil pid:1];
        FixtureClient *pwa = [FixtureClient bundle:
            [@"com.google.Chrome.app" stringByAppendingString:kPWA] parent:nil pid:2];
        __block NSInteger queriedOther = 0;
        YTMCNowPlayingSelection *selection = Select(@[other, pwa],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                if (client == other) queriedOther++;
                completion(Info(@"YouTube", @"Artist", 1, 1), nil);
            }, 0.1);
        Check(selection.client == pwa && queriedOther == 0, @"other audio apps ignored");

        FixtureClient *first = [FixtureClient bundle:
            [@"a.browser.app" stringByAppendingString:kPWA] parent:nil pid:3];
        FixtureClient *second = [FixtureClient bundle:
            [@"z.browser.app" stringByAppendingString:kPWA] parent:nil pid:4];
        selection = Select(@[second, first],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(client == first ? Info(@"Partial", nil, 1, 3) :
                    Info(@"Complete", @"Artist", 0, 2), nil);
            }, 0.1);
        Check(selection.client == second && [selection.snapshot[@"Title"] isEqual:@"Complete"],
              @"incomplete first client skipped");

        selection = Select(@[second, first],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(client == first ? Info(@"Paused", @"Artist", 0, 20) :
                    Info(@"Playing", @"Artist", 1, 10), nil);
            }, 0.1);
        Check(selection.client == second && [selection.snapshot[@"isPlaying"] boolValue],
              @"playing client outranks paused client");

        FixtureClient *parentPWA = [FixtureClient bundle:@"com.google.Chrome"
            parent:[@"com.google.Chrome.app" stringByAppendingString:kPWA] pid:5];
        selection = Select(@[parentPWA],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(Info(@"Parent", @"Artist", 1, 1), nil);
            }, 0.1);
        Check(selection.client == parentPWA &&
              [selection.snapshot[@"ParentBundle"] isEqual:parentPWA.parentApplicationBundleIdentifier],
              @"parent PWA identity accepted");

        FixtureClient *legacy = [FixtureClient bundle:@"app_mode_loader"
            parent:@"com.google.Chrome" pid:77];
        selection = SelectWithIdentity(@[other, legacy],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(Info(@"Legacy", @"Artist", 1, 1), nil);
            },
            ^BOOL(pid_t pid) { return pid == 77; }, 0.2);
        Check(selection.client == legacy &&
              [selection.snapshot[@"Bundle"] isEqual:@"app_mode_loader"] &&
              [selection.snapshot[@"SourcePID"] intValue] == 77 &&
              selection.snapshot[@"ParentBundle"] == nil,
              @"PID-verified legacy loader accepted without generic parent override");

        FixtureClient *genericLoader = [FixtureClient bundle:@"app_mode_loader"
            parent:nil pid:78];
        __block NSInteger genericQueries = 0;
        selection = SelectWithIdentity(@[genericLoader, pwa],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                if (client == genericLoader) genericQueries++;
                completion(Info(@"Known", @"Artist", 1, 1), nil);
            },
            ^BOOL(pid_t pid) { return NO; }, 0.2);
        Check(selection.client == pwa && genericQueries == 0,
              @"generic loader rejected before metadata request");

        FixtureClient *unknownLoader = [FixtureClient bundle:@"app_mode_loader"
            parent:nil pid:0];
        __block NSInteger unknownLookups = 0;
        selection = SelectWithIdentity(@[unknownLoader, pwa],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(Info(@"Known", @"Artist", 1, 1), nil);
            },
            ^BOOL(pid_t pid) { unknownLookups++; return YES; }, 0.2);
        Check(selection.client == pwa && unknownLookups == 0,
              @"unknown legacy PID rejected without lookup");

        CFAbsoluteTime identityStart = CFAbsoluteTimeGetCurrent();
        selection = SelectWithIdentity(@[legacy, pwa],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(Info(@"Known", @"Artist", 1, 1), nil);
            },
            ^BOOL(pid_t pid) { usleep(1000000); return YES; }, 0.8);
        Check(selection.client == pwa &&
              CFAbsoluteTimeGetCurrent() - identityStart < 0.8,
              @"slow legacy lookup leaves time for known PWA");

        // A valid response must survive another candidate never invoking its completion.
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        selection = Select(@[first, second],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                if (client == second) completion(Info(@"Complete", @"Artist", 1, 1), nil);
            }, 0.08);
        Check(selection.client == second && CFAbsoluteTimeGetCurrent() - start < 0.3,
              @"valid result retained despite another timeout");

        NSMutableArray *concurrentClients = [NSMutableArray array];
        for (NSInteger pid = 1; pid <= 64; pid++) {
            NSString *bundle = [NSString stringWithFormat:@"com.browser.%03ld.app%@",
                                (long)pid, kPWA];
            [concurrentClients addObject:[FixtureClient bundle:bundle parent:nil pid:pid]];
        }
        selection = Select(concurrentClients,
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                dispatch_async(queue, ^{
                    FixtureClient *fixture = client;
                    completion(Info(@"Concurrent", @"Artist", 1,
                                    fixture.processIdentifier.doubleValue), nil);
                });
                // Let early callbacks overlap the remaining request dispatches.
                usleep(1000);
            }, 2.0);
        Check(selection.client == concurrentClients.lastObject,
              @"immediate concurrent callbacks select deterministically");

        selection = Select(@[first, second],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(client == first ? Info(@"Old", @"Artist", 1, 1) :
                    Info(@"Recent", @"Artist", 1, 2), nil);
            }, 0.1);
        Check(selection.client == second, @"newer timestamp wins among playing clients");

        __block NSInteger attempts = 0;
        selection = Select(@[pwa],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                attempts++;
                completion(attempts == 1 ? @{} : Info(@"Retry", @"Artist", 1, 1), nil);
            }, 0.1);
        Check(selection.client == pwa && attempts == 2, @"one retry recovers empty response");

        selection = Select(@[[NSObject new], other], nil, 0.1);
        Check(selection == nil, @"unavailable request API returns no selection");
        selection = Select(@[[NSObject new], other],
            ^(id client, dispatch_queue_t queue, void (^completion)(NSDictionary *, NSError *)) {
                completion(Info(@"Ignored", @"Artist", 1, 1), nil);
            }, 0.1);
        Check(selection == nil, @"missing client accessors safely ignored");
    }
    return 0;
}

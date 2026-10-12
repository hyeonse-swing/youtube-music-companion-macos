#import <Foundation/Foundation.h>

@interface YTMCNowPlayingSelection : NSObject
@property (nonatomic, readonly) NSDictionary *snapshot;
@property (nonatomic, readonly) id client;
- (instancetype)initWithSnapshot:(NSDictionary *)snapshot client:(id)client;
@end

typedef void (^YTMCGetClients)(dispatch_queue_t queue, void (^completion)(NSArray *clients));
typedef void (^YTMCRequestInfo)(id client, dispatch_queue_t queue,
                                void (^completion)(NSDictionary *info, NSError *error));
typedef BOOL (^YTMCLegacyIdentity)(pid_t pid);

// The provider form permits deterministic native fixtures without MediaRemote.
YTMCNowPlayingSelection *YTMCSelectNowPlayingWithProviders(
    YTMCGetClients getClients, YTMCRequestInfo requestInfo,
    YTMCLegacyIdentity isLegacyYouTubeMusic, NSTimeInterval timeout);

YTMCNowPlayingSelection *YTMCSelectPreferredNowPlaying(NSTimeInterval timeout);
id YTMCPlayerPathForClient(id client);

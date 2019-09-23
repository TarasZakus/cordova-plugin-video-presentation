#import "VideoPresentation.h"
#import "WebSocketAdvanced.h"
#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import "LandscapeVideo.h"

@interface VideoPresentation()
- (void)startPlayer:(NSString*)uri;
- (void)moviePlayBackDidFinish:(NSNotification*)notification;
- (void)cleanup;
@end

@implementation VideoPresentation {
    NSString* callbackId;
    NSString* mediaUrl;
    AVPlayerViewController *moviePlayer;
    AVPlayer *movie;
    NSTimer* playbackTimer;
}

- (void)pluginInitialize {
    webSockets = [[NSMutableDictionary alloc] init];
}

- (void)wsConnect:(CDVInvokedUrlCommand*)command {
    NSLog(@"Establishing WS connection.");

    NSDictionary* wsOptions = [command argumentAtIndex:0];
    WebSocketAdvanced* ws = [[WebSocketAdvanced alloc] initWithOptions:wsOptions
                                                       commandDelegate:self.commandDelegate
                                                       callbackId:command.callbackId];
    [webSockets setObject:ws forKey:ws.webSocketId];
}

-(void)start:(CDVInvokedUrlCommand *)command {
    NSLog(@"Connection established.\nPrepare for the playback.");

    callbackId = command.callbackId;
    mediaUrl = [command.arguments objectAtIndex:0];

    [self ignoreMute];

    // Setup WS listener.
    NSString* webSocketId = [command argumentAtIndex:1];
    WebSocketAdvanced* ws = [webSockets valueForKey:webSocketId];
    if (ws != nil) {
        SEL listenerSel = @selector(onWsReceive:);
        [ws wsAddListener:self listenerSel:listenerSel];
    }
}

-(void)onWsReceive:(NSMutableDictionary*)data {
    NSString* message = [data valueForKey:@"message"];
    if (message != nil) {
        message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        message = [message stringByReplacingOccurrencesOfString:@"\"" withString:@""];

        if ([message isEqualToString:@"t"]) {
            if (moviePlayer) {
                NSLog(@"Resume video presentation.");
                [self schedulePlayback];
            } else {
                NSLog(@"Start video presentation.");
                [self.commandDelegate runInBackground:^{
                    [self startPlayer:mediaUrl completion:^(void){
                        [self schedulePlayback];
                    }];
                }];
            }
            return;
        } else if ([message isEqualToString:@"m"]) {
            NSLog(@"Pause video presentation.");
            if (moviePlayer) {
                [moviePlayer.player pause];
            }
            return;
        } else if ([message hasPrefix: @"playback:"]) {
            // TODO: use the /synced-playback request.
            return;
        } else {
            NSLog(@"%@", message);
        }
    }

    [self _closeAllSockets];
    [self cleanup];
}

-(void)ignoreMute {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
}

-(void)startPlayer:(NSString*)uri completion:(void(^)(void))completion {
    NSURL *url  =  [NSURL URLWithString:uri];
    movie       =  [AVPlayer playerWithURL:url];
    moviePlayer =  [[LandscapeAVPlayerViewController alloc] init];

    [self handleGestures];

    [moviePlayer setPlayer:movie];
    [moviePlayer setShowsPlaybackControls:NO];
    [moviePlayer setUpdatesNowPlayingInfoCenter:YES];
    [moviePlayer setEntersFullScreenWhenPlaybackBegins:YES];

    dispatch_async(dispatch_get_main_queue(), ^(void){
        [self.viewController presentViewController:moviePlayer animated:NO completion:completion];
    });

    [self handleListeners];
}

- (void) schedulePlayback {
    // Schedule playback with timer (note that for all users system clock must be synchronized).
    double maxDelay = 3.0;
    double delay = fmod([[NSDate date] timeIntervalSince1970], maxDelay);
    if (delay == 0) {
        delay = maxDelay;
    }
    playbackTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                             target:moviePlayer.player
                             selector:@selector(play)
                             userInfo:nil repeats:NO];
}

- (void) handleListeners {
    // Listen for playback finishing.
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(moviePlayBackDidFinish:)
        name:AVPlayerItemDidPlayToEndTimeNotification
        object:moviePlayer.player.currentItem];

    // Listen for errors.
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(moviePlayBackDidFinish:)
        name:AVPlayerItemFailedToPlayToEndTimeNotification
        object:moviePlayer.player.currentItem];
}

- (void) handleGestures {
    // Get nested view.
    UIView *contentView = [moviePlayer.view valueForKey:@"contentView"];

    // Loop through gestures, remove swipes.
    for (UIGestureRecognizer *recognizer in contentView.gestureRecognizers) {
        if ([recognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
            [contentView removeGestureRecognizer:recognizer];
        }
        if ([recognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
            [contentView removeGestureRecognizer:recognizer];
        }
        if ([recognizer isKindOfClass:[UIRotationGestureRecognizer class]]) {
            [contentView removeGestureRecognizer:recognizer];
        }
        if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [contentView removeGestureRecognizer:recognizer];
        }
        if ([recognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
            [contentView removeGestureRecognizer:recognizer];
        }
        if ([recognizer isKindOfClass:[UISwipeGestureRecognizer class]]) {
            [contentView removeGestureRecognizer:recognizer];
        }
    }
}

- (void) moviePlayBackDidFinish:(NSNotification*)notification {
    NSDictionary *notificationUserInfo = [notification userInfo];
    NSNumber *errorValue = [notificationUserInfo objectForKey:AVPlayerItemFailedToPlayToEndTimeErrorKey];
    NSString *errorMsg;
    if (errorValue) {
        NSError *mediaPlayerError = [notificationUserInfo objectForKey:@"error"];
        if (mediaPlayerError) {
            errorMsg = [mediaPlayerError localizedDescription];
        } else {
            errorMsg = @"Unknown error.";
        }
    }

    [self cleanup];
    if ([errorMsg length] != 0) {
        CDVPluginResult* pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMsg];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
}

- (void)cleanup {
    // Remove playback finished listener.
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
        name:AVPlayerItemDidPlayToEndTimeNotification
        object:moviePlayer.player.currentItem];

    // Remove playback finished error listener.
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
        name:AVPlayerItemFailedToPlayToEndTimeNotification
        object:moviePlayer.player.currentItem];

    if (moviePlayer) {
        [moviePlayer.player pause];
        [moviePlayer dismissViewControllerAnimated:NO completion:nil];
        moviePlayer = nil;
    }

    if (playbackTimer != nil) {
        [playbackTimer invalidate];
        playbackTimer = nil;
    }
}

- (void)dealloc {
    [self _closeAllSockets];
    [self cleanup];
}

- (void)_closeAllSockets {
    for(id wsId in webSockets) {
        WebSocketAdvanced* ws = [webSockets objectForKey:wsId];
        [ws wsClose];
    }
    [webSockets removeAllObjects];
}

@end

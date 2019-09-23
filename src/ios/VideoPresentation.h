#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <Cordova/CDVPlugin.h>
#import <AVFoundation/AVFoundation.h>
#import <SocketRocket/SocketRocket.h>

@interface VideoPresentation : CDVPlugin {
    NSMutableDictionary* webSockets;
}

- (void)wsConnect:(CDVInvokedUrlCommand*)command;
- (void)start:(CDVInvokedUrlCommand*)command;

@end

#import <Cordova/CDV.h>
#import "WebSocketAdvanced.h"

@implementation WebSocketAdvanced

- (instancetype)initWithOptions:(NSDictionary*)wsOptions 
                commandDelegate:(id<CDVCommandDelegate>)commandDelegate
                callbackId:(NSString*)callbackId;
{
    NSString* wsUrl =           [wsOptions valueForKey:@"url"];
    NSNumber* timeout =         [wsOptions valueForKey:@"timeout"];
    NSDictionary* wsHeaders =   [wsOptions valueForKey:@"headers"];
    BOOL acceptAllCerts =       [wsOptions valueForKey:@"acceptAllCerts"];

    NSTimeInterval timeoutInterval = timeout ? (timeout.doubleValue / 1000) : 0;
    
    self.webSocketId = [[NSUUID UUID] UUIDString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:wsUrl]
                                                        cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                        timeoutInterval:timeoutInterval];

    for(id key in wsHeaders) {
        [request addValue:[wsHeaders objectForKey:key] forHTTPHeaderField:key];
    }

    _webSocket = [[SRWebSocket alloc] initWithURLRequest:request
                                      protocols:nil
                                      allowsUntrustedSSLCertificates:acceptAllCerts];
    
    _webSocket.delegate = self;
    _commandDelegate = commandDelegate;
    _callbackId = callbackId;

    [_commandDelegate runInBackground:^{
        [_webSocket open];
    }];
    return self;
}

- (void)wsAddListener:(id)listenerObj listenerSel:(SEL)listenerSel {
    _listenerObj = listenerObj;
    _listenerSel = listenerSel;
}

- (void)wsSendMessage:(NSString*)message {
    if (_webSocket != nil) {
        [_webSocket send:message];
    }
}

- (void)wsClose {
    if (_webSocket != nil) {
        [_webSocket close];
    }
}

- (void)wsClose:(NSInteger)code reason:(NSString*)reason {
    if (_webSocket != nil) {
        [_webSocket closeWithCode:code reason:reason];
    }
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket*)webSocket {
    NSMutableDictionary* successResult = [[NSMutableDictionary alloc] init];
    NSNumber* code = [NSNumber numberWithInteger:SRStatusCodeNormal];

    [successResult setValue:self.webSocketId forKey:@"webSocketId"];
    [successResult setValue:code             forKey:@"code"];

    CDVPluginResult* pluginResult =[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:successResult];
    [_commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
}

- (void)webSocket:(SRWebSocket*)webSocket didFailWithError:(NSError*)error {
    NSMutableDictionary* errorResult = [[NSMutableDictionary alloc] init];
    NSNumber* code = [NSNumber numberWithInteger:SRStatusCodeAbnormal];
    
    [errorResult setValue:self.webSocketId           forKey:@"webSocketId"];
    [errorResult setValue:code                       forKey:@"code"];
    [errorResult setValue:error.localizedDescription forKey:@"exception"];

    @try {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:errorResult];
        [_commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
    }
    @catch (NSException *exception) {
        // Swallow exception
    }

    if (_listenerObj != nil) {
        [errorResult setValue:@"onFail" forKey:@"callbackMethod"];
        [_listenerObj performSelector:_listenerSel withObject:errorResult];
    }

    _webSocket = nil;
}

- (void)webSocket:(SRWebSocket*)webSocket didReceiveMessage:(id)message {
    NSMutableDictionary* callbackResult = [[NSMutableDictionary alloc] init];
    [callbackResult setValue:@"onMessage"     forKey:@"callbackMethod"];
    [callbackResult setValue:self.webSocketId forKey:@"webSocketId"];
    [callbackResult setValue:message          forKey:@"message"];

    if (_listenerObj != nil) {
        [_listenerObj performSelector:_listenerSel withObject:callbackResult];
    }
}

- (void)webSocket:(SRWebSocket*)webSocket didCloseWithCode:(NSInteger)code reason:(NSString*)reason wasClean:(BOOL)wasClean {
    NSMutableDictionary* callbackResult = [[NSMutableDictionary alloc] init];
    NSNumber* c = [NSNumber numberWithInteger:code];

    [callbackResult setValue:self.webSocketId forKey:@"webSocketId"];
    [callbackResult setValue:c                forKey:@"code"];
    [callbackResult setValue:reason           forKey:@"reason"];

    @try {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:callbackResult];
        [_commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
    }
    @catch (NSException *exception) {
        // Swallow exception
    }
    
    if (_listenerObj != nil) {
        [callbackResult setValue:@"onClose" forKey:@"callbackMethod"];
        [_listenerObj performSelector:_listenerSel withObject:callbackResult];
    }

    _webSocket = nil;
}

- (void)webSocket:(SRWebSocket*)webSocket didReceivePong:(nullable NSData*)pongData {
    NSLog(@"WebSocket received pong");
}

- (BOOL)webSocketShouldConvertTextFrameToString:(SRWebSocket*)webSocket {
    return YES;
}

@end

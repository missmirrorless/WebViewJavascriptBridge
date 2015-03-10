//
//  WebViewJavascriptBridge.m
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import "WebViewJavascriptBridge.h"

#define WVJB_WEAK __weak

typedef NSDictionary WVJBMessage;

@implementation WebViewJavascriptBridge {
  WVJB_WEAK UIWebView* _webView;
  WVJB_WEAK WKWebView* _WKWebView;
  WVJB_WEAK id<UIWebViewDelegate> _webViewDelegate;
  WVJB_WEAK id<WKNavigationDelegate> _WKWebViewDelegate;
  NSMutableArray* _startupMessageQueue;
  NSMutableDictionary* _responseCallbacks;
  NSMutableDictionary* _messageHandlers;
  long _uniqueId;
  WVJBHandler _messageHandler;
  
  NSBundle *_resourceBundle;
  NSUInteger _numRequestsLoading;
}

/* API
 *****/

static bool logging = false;
+ (void)enableLogging { logging = true; }

+ (instancetype)bridgeForWebView:(UIWebView*)webView handler:(WVJBHandler)handler {
  return [self bridgeForWebView:webView webViewDelegate:nil handler:handler];
}

+ (instancetype)bridgeForWebView:(UIWebView*)webView webViewDelegate:(NSObject<UIWebViewDelegate>*)webViewDelegate handler:(WVJBHandler)messageHandler {
  return [self bridgeForWebView:webView webViewDelegate:webViewDelegate handler:messageHandler resourceBundle:nil];
}

+ (instancetype)bridgeForWebView:(UIWebView*)webView webViewDelegate:(NSObject<UIWebViewDelegate>*)webViewDelegate handler:(WVJBHandler)messageHandler resourceBundle:(NSBundle*)bundle
{
  WebViewJavascriptBridge* bridge = [[WebViewJavascriptBridge alloc] init];
  [bridge _UIWebViewSetup:webView webViewDelegate:webViewDelegate handler:messageHandler resourceBundle:bundle];
  return bridge;
}

+ (instancetype)bridgeForWKWebView:(WKWebView*)webView handler:(WVJBHandler)handler
{
  return [self bridgeForWKWebView:webView webViewDelegate:nil handler:handler];
}
+ (instancetype)bridgeForWKWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)handler
{
  return [self bridgeForWKWebView:webView webViewDelegate:webViewDelegate handler:handler resourceBundle:nil];
}
+ (instancetype)bridgeForWKWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)handler resourceBundle:(NSBundle*)bundle
{
  WebViewJavascriptBridge* bridge = [[WebViewJavascriptBridge alloc] init];
  [bridge _WKWebViewSetup:webView webViewDelegate:webViewDelegate handler:handler resourceBundle:bundle];
  return bridge;
}

- (void)send:(id)data {
  [self send:data responseCallback:nil];
}

- (void)send:(id)data responseCallback:(WVJBResponseCallback)responseCallback {
  [self _sendData:data responseCallback:responseCallback handlerName:nil];
}

- (void)callHandler:(NSString *)handlerName {
  [self callHandler:handlerName data:nil responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data {
  [self callHandler:handlerName data:data responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback {
  [self _sendData:data responseCallback:responseCallback handlerName:handlerName];
}

- (void)registerHandler:(NSString *)handlerName handler:(WVJBHandler)handler {
  _messageHandlers[handlerName] = [handler copy];
}

/* Platform agnostic internals
 *****************************/

- (id)init {
  if (self = [super init]) {
    _startupMessageQueue = [NSMutableArray array];
    _responseCallbacks = [NSMutableDictionary dictionary];
    _uniqueId = 0;
  }
  return self;
}

- (void)dealloc {
  [self _platformSpecificDealloc];
  
  _webView = nil;
  _webViewDelegate = nil;
  _startupMessageQueue = nil;
  _responseCallbacks = nil;
  _messageHandlers = nil;
  _messageHandler = nil;
}

- (void)_sendData:(id)data responseCallback:(WVJBResponseCallback)responseCallback handlerName:(NSString*)handlerName {
  NSMutableDictionary* message = [NSMutableDictionary dictionary];
  
  if (data) {
    message[@"data"] = data;
  }
  
  if (responseCallback) {
    NSString* callbackId = [NSString stringWithFormat:@"objc_cb_%ld", ++_uniqueId];
    _responseCallbacks[callbackId] = [responseCallback copy];
    message[@"callbackId"] = callbackId;
  }
  
  if (handlerName) {
    message[@"handlerName"] = handlerName;
  }
  [self _queueMessage:message];
}

- (void)_queueMessage:(WVJBMessage*)message {
  if (_startupMessageQueue) {
    [_startupMessageQueue addObject:message];
  } else {
    [self _dispatchMessage:message];
  }
}

- (void)_dispatchMessage:(WVJBMessage*)message {
  NSString *messageJSON = [self _serializeMessage:message];
  [self _log:@"SEND" json:messageJSON];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\'" withString:@"\\\'"];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\f" withString:@"\\f"];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
  messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
  
  NSString* javascriptCommand = [NSString stringWithFormat:@"WebViewJavascriptBridge._handleMessageFromObjC('%@');", messageJSON];
  [self _evaluatingJavaScriptFromString:javascriptCommand handler:NULL];
}

- (void)_flushMessageQueue
{
  [self _evaluatingJavaScriptFromString:@"WebViewJavascriptBridge._fetchQueue();" handler:^(NSString *messageQueueString, NSError *error) {
    id messages = [self _deserializeMessageJSON:messageQueueString];
    if (![messages isKindOfClass:[NSArray class]]) {
      NSLog(@"WebViewJavascriptBridge: WARNING: Invalid %@ received: %@", [messages class], messages);
      return;
    }
    for (WVJBMessage* message in messages) {
      if (![message isKindOfClass:[WVJBMessage class]]) {
        NSLog(@"WebViewJavascriptBridge: WARNING: Invalid %@ received: %@", [message class], message);
        continue;
      }
      [self _log:@"RCVD" json:message];
      
      NSString* responseId = message[@"responseId"];
      if (responseId) {
        WVJBResponseCallback responseCallback = _responseCallbacks[responseId];
        responseCallback(message[@"responseData"]);
        [_responseCallbacks removeObjectForKey:responseId];
      } else {
        WVJBResponseCallback responseCallback = NULL;
        NSString* callbackId = message[@"callbackId"];
        if (callbackId) {
          responseCallback = ^(id responseData) {
            if (responseData == nil) {
              responseData = [NSNull null];
            }
            
            WVJBMessage* msg = @{ @"responseId":callbackId, @"responseData":responseData };
            [self _queueMessage:msg];
          };
        } else {
          responseCallback = ^(id ignoreResponseData) {
            // Do nothing
          };
        }
        
        WVJBHandler handler;
        if (message[@"handlerName"]) {
          handler = _messageHandlers[message[@"handlerName"]];
        } else {
          handler = _messageHandler;
        }
        
        if (!handler) {
          [NSException raise:@"WVJBNoHandlerException" format:@"No handler for message from JS: %@", message];
        }
        
        handler(message[@"data"], responseCallback);
      }
    }
  }];
}

- (NSString *)_serializeMessage:(id)message {
  return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] encoding:NSUTF8StringEncoding];
}

- (NSArray*)_deserializeMessageJSON:(NSString *)messageJSON {
  return [NSJSONSerialization JSONObjectWithData:[messageJSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:nil];
}

- (void)_log:(NSString *)action json:(id)json {
  if (!logging) { return; }
  if (![json isKindOfClass:[NSString class]]) {
    json = [self _serializeMessage:json];
  }
  if ([json length] > 500) {
    NSLog(@"WVJB %@: %@ [...]", action, [json substringToIndex:500]);
  } else {
    NSLog(@"WVJB %@: %@", action, json);
  }
}


- (void) _UIWebViewSetup:(UIWebView*)webView webViewDelegate:(id<UIWebViewDelegate>)webViewDelegate handler:(WVJBHandler)messageHandler resourceBundle:(NSBundle*)bundle{
  _messageHandler = messageHandler;
  _webView = webView;
  _webViewDelegate = webViewDelegate;
  _messageHandlers = [NSMutableDictionary dictionary];
  _webView.delegate = self;
  _resourceBundle = bundle;
}

- (void) _WKWebViewSetup:(WKWebView *)webView webViewDelegate:(id<WKNavigationDelegate>)webViewDelegate handler:(WVJBHandler)messageHandler resourceBundle:(NSBundle*)bundle{
  _messageHandler = messageHandler;
  _WKWebView = webView;
  _WKWebViewDelegate = webViewDelegate;
  _messageHandlers = [NSMutableDictionary dictionary];
  [_WKWebView setNavigationDelegate:self];
  _resourceBundle = bundle;
}


- (void) _platformSpecificDealloc {
  _webView.delegate = nil;
  [_WKWebView setNavigationDelegate:nil];
}

- (void)_evaluatingJavaScriptFromString:(NSString *)javascriptCommand handler:(void (^)(id, NSError *))completionHandler
{
  if (_webView != nil) {
    if ([[NSThread currentThread] isMainThread]) {
      NSString *returnString = [_webView stringByEvaluatingJavaScriptFromString:javascriptCommand];
      if (completionHandler != NULL) {
        completionHandler(returnString, nil);
      }
    } else {
      __strong UIWebView* strongWebView = _webView;
      dispatch_sync(dispatch_get_main_queue(), ^{
        NSString *returnString = [strongWebView stringByEvaluatingJavaScriptFromString:javascriptCommand];
        if (completionHandler != NULL) {
          completionHandler(returnString, nil);
        }
      });
    }
  } else {
    [_WKWebView evaluateJavaScript:javascriptCommand completionHandler:completionHandler];
  }
}


#pragma mark - delegate common hanlder
- (void)bridge_webViewDidFinishLoad
{
  _numRequestsLoading--;
  
  if (_numRequestsLoading == 0) {
    [self _evaluatingJavaScriptFromString:@"typeof WebViewJavascriptBridge == 'object'" handler:^(id returnValue, NSError *error) {
      if (([returnValue isKindOfClass:[NSString class]] && ![(NSString *)returnValue isEqualToString:@"true"])
          || ([returnValue isKindOfClass:[NSNumber class]] && [(NSNumber *)returnValue boolValue] == NO)) {
        NSBundle *bundle = _resourceBundle ? _resourceBundle : [NSBundle mainBundle];
        NSString *filePath = [bundle pathForResource:@"WebViewJavascriptBridge.js" ofType:@"txt"];
        NSString *js = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        [self _evaluatingJavaScriptFromString:js handler:^(id r, NSError *err) {
          if (error) {
            NSLog(@"WebViewJavascriptBridge: ERROR: failed to inject WebViewJavascriptBridge.js, %@", err);
          }
          if (_startupMessageQueue) {
            for (id queuedMessage in _startupMessageQueue) {
              [self _dispatchMessage:queuedMessage];
            }
            _startupMessageQueue = nil;
          }
        }];
      }
    }];
  }
}

#pragma mark - UIWebViewDelegate
- (void)webViewDidFinishLoad:(UIWebView *)webView {
  if (webView != _webView) { return; }
  
  [self bridge_webViewDidFinishLoad];
  
  __strong id<UIWebViewDelegate> strongDelegate = _webViewDelegate;
  if (strongDelegate && [strongDelegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
    [strongDelegate webViewDidFinishLoad:webView];
  }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
  if (webView != _webView) { return; }
  
  _numRequestsLoading--;
  
  __strong id<UIWebViewDelegate> strongDelegate = _webViewDelegate;
  if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
    [strongDelegate webView:webView didFailLoadWithError:error];
  }
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
  if (webView != _webView) { return YES; }
  NSURL *url = [request URL];
  __strong id<UIWebViewDelegate> strongDelegate = _webViewDelegate;
  if ([[url scheme] isEqualToString:kCustomProtocolScheme]) {
    if ([[url host] isEqualToString:kQueueHasMessage]) {
      [self _flushMessageQueue];
    } else {
      NSLog(@"WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command %@://%@", kCustomProtocolScheme, [url path]);
    }
    return NO;
  } else if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
    return [strongDelegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
  } else {
    return YES;
  }
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
  if (webView != _webView) { return; }
  
  _numRequestsLoading++;
  
  __strong id<UIWebViewDelegate> strongDelegate = _webViewDelegate;
  if (strongDelegate && [strongDelegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
    [strongDelegate webViewDidStartLoad:webView];
  }
}

#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
  if (webView != _WKWebView) { return; }
  
  [self bridge_webViewDidFinishLoad];
  
  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didFinishNavigation:)]) {
    [_WKWebViewDelegate webView:webView didFinishNavigation:navigation];
  }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
  _numRequestsLoading--;
  
  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didFailNavigation:withError:)]) {
    [_WKWebViewDelegate webView:webView didFailNavigation:navigation withError:error];
  }
}


- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
  _numRequestsLoading--;

  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didFailProvisionalNavigation:withError:)]) {
    [_WKWebViewDelegate webView:webView didFailProvisionalNavigation:navigation withError:error];
  }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
  if (_WKWebView != webView) {
    decisionHandler(WKNavigationActionPolicyAllow);
    return;
  }
  NSURLRequest *request = navigationAction.request;
  NSURL *url = [request URL];
  if ([[url scheme] isEqualToString:kCustomProtocolScheme]) {
    if ([[url host] isEqualToString:kQueueHasMessage]) {
      [self _flushMessageQueue];
    } else {
      NSLog(@"WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command %@://%@", kCustomProtocolScheme, [url path]);
    }
    decisionHandler(WKNavigationActionPolicyCancel);
  } else if ([_WKWebViewDelegate respondsToSelector:@selector(webView:decidePolicyForNavigationAction:decisionHandler:)]) {
    [_WKWebViewDelegate webView:webView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
  } else {
    decisionHandler(WKNavigationActionPolicyAllow);
  }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
  if (_WKWebView != webView) { return; }
  
  _numRequestsLoading++;

  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didStartProvisionalNavigation:)]) {
    [_WKWebViewDelegate webView:webView didStartProvisionalNavigation:navigation];
  }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:decidePolicyForNavigationResponse:decisionHandler:)]) {
    [_WKWebViewDelegate webView:webView decidePolicyForNavigationResponse:navigationResponse decisionHandler:decisionHandler];
  } else {
    decisionHandler(WKNavigationResponsePolicyAllow);
  }
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation
{
  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didReceiveServerRedirectForProvisionalNavigation:)]) {
    [_WKWebViewDelegate webView:webView didReceiveServerRedirectForProvisionalNavigation:navigation];
  }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didCommitNavigation:)]) {
    [_WKWebViewDelegate webView:webView didCommitNavigation:navigation];
  }
}


- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
  if ([_WKWebViewDelegate respondsToSelector:@selector(webView:didReceiveAuthenticationChallenge:completionHandler:)]) {
    [_WKWebViewDelegate webView:webView didReceiveAuthenticationChallenge:challenge completionHandler:completionHandler];
  } else {
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NSURLCredentialPersistenceNone);
  }
}


@end

//
//  WebViewJavascriptBridge.h
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>

#define kCustomProtocolScheme @"wvjbscheme"
#define kQueueHasMessage      @"__WVJB_QUEUE_MESSAGE__"

typedef void (^WVJBResponseCallback)(id responseData);
typedef void (^WVJBHandler)(id data, WVJBResponseCallback responseCallback);

@interface WebViewJavascriptBridge : NSObject <UIWebViewDelegate, WKNavigationDelegate>

+ (instancetype)bridgeForWebView:(UIWebView*)webView handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWebView:(UIWebView*)webView webViewDelegate:(NSObject<UIWebViewDelegate>*)webViewDelegate handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWebView:(UIWebView*)webView webViewDelegate:(NSObject<UIWebViewDelegate>*)webViewDelegate handler:(WVJBHandler)handler resourceBundle:(NSBundle*)bundle;

+ (instancetype)bridgeForWKWebView:(WKWebView*)webView handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWKWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWKWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)handler resourceBundle:(NSBundle*)bundle;

+ (void)enableLogging;

- (void)send:(id)message;
- (void)send:(id)message responseCallback:(WVJBResponseCallback)responseCallback;
- (void)registerHandler:(NSString*)handlerName handler:(WVJBHandler)handler;
- (void)callHandler:(NSString*)handlerName;
- (void)callHandler:(NSString*)handlerName data:(id)data;
- (void)callHandler:(NSString*)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback;

@end

#import "TVWebEngine.h"
#import <dlfcn.h>
#import <objc/message.h>

@interface TVWebEngine ()
@property (nonatomic, strong, readwrite) UIView *webView;
@property (nonatomic, assign, readwrite) BOOL isUsingWKWebView;
@end

@implementation TVWebEngine

+ (NSString *)desktopUserAgent {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15";
}

+ (void)loadWebKitIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Register desktop User-Agent for UIWebView fallback as well
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            @"UserAgent": [TVWebEngine desktopUserAgent]
        }];

        const char *paths[] = {
            "/System/Library/Frameworks/WebKit.framework/WebKit",
            "/System/Library/PrivateFrameworks/WebKit.framework/WebKit"
        };
        for (int i = 0; i < 2; i++) {
            if (dlopen(paths[i], RTLD_NOW) != NULL) {
                break;
            }
        }
    });
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        [TVWebEngine loadWebKitIfNeeded];

        Class wkClass = NSClassFromString(@"WKWebView");
        Class wkConfigClass = NSClassFromString(@"WKWebViewConfiguration");

        if (wkClass && wkConfigClass) {
            id config = [[wkConfigClass alloc] init];

            if ([config respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(config, @selector(setAllowsInlineMediaPlayback:), YES);
            }
            if ([config respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) {
                ((void (*)(id, SEL, NSUInteger))objc_msgSend)(config, @selector(setMediaTypesRequiringUserActionForPlayback:), 0);
            }

            // Ensure persistent cookies/sessions for Google Sign-In
            Class dataStoreClass = NSClassFromString(@"WKWebsiteDataStore");
            if (dataStoreClass && [dataStoreClass respondsToSelector:@selector(defaultDataStore)] &&
                [config respondsToSelector:@selector(setWebsiteDataStore:)]) {
                id store = ((id (*)(id, SEL))objc_msgSend)(dataStoreClass, @selector(defaultDataStore));
                ((void (*)(id, SEL, id))objc_msgSend)(config, @selector(setWebsiteDataStore:), store);
            }

            // Enable JS & window opening for OAuth flows
            if ([config respondsToSelector:@selector(preferences)]) {
                id prefs = ((id (*)(id, SEL))objc_msgSend)(config, @selector(preferences));
                if ([prefs respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(prefs, @selector(setJavaScriptCanOpenWindowsAutomatically:), YES);
                }
            }

            id allocView = [wkClass alloc];
            UIView *wkView = ((id (*)(id, SEL, CGRect, id))objc_msgSend)(allocView, @selector(initWithFrame:configuration:), frame, config);
            wkView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            wkView.backgroundColor = [UIColor blackColor];

            if ([wkView respondsToSelector:@selector(setNavigationDelegate:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(wkView, @selector(setNavigationDelegate:), self);
            }
            if ([wkView respondsToSelector:@selector(setUIDelegate:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(wkView, @selector(setUIDelegate:), self);
            }
            if ([wkView respondsToSelector:@selector(setCustomUserAgent:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(wkView, @selector(setCustomUserAgent:), [TVWebEngine desktopUserAgent]);
            }

            _webView = wkView;
            _isUsingWKWebView = YES;
        } else {
            Class uiWebClass = NSClassFromString(@"UIWebView");
            if (uiWebClass) {
                UIView *uiWeb = [[uiWebClass alloc] initWithFrame:frame];
                uiWeb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                uiWeb.backgroundColor = [UIColor blackColor];
                if ([uiWeb respondsToSelector:@selector(setDelegate:)]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(uiWeb, @selector(setDelegate:), self);
                }
                if ([uiWeb respondsToSelector:@selector(setScalesPageToFit:)]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(uiWeb, @selector(setScalesPageToFit:), YES);
                }
                _webView = uiWeb;
                _isUsingWKWebView = NO;
            } else {
                _webView = [[UIView alloc] initWithFrame:frame];
                _webView.backgroundColor = [UIColor darkGrayColor];
                _isUsingWKWebView = NO;
            }
        }
    }
    return self;
}

- (UIScrollView *)scrollView {
    if ([_webView respondsToSelector:@selector(scrollView)]) {
        return ((UIScrollView *(*)(id, SEL))objc_msgSend)(_webView, @selector(scrollView));
    }
    return nil;
}

- (BOOL)canGoBack {
    if ([_webView respondsToSelector:@selector(canGoBack)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(_webView, @selector(canGoBack));
    }
    return NO;
}

- (BOOL)canGoForward {
    if ([_webView respondsToSelector:@selector(canGoForward)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(_webView, @selector(canGoForward));
    }
    return NO;
}

- (NSURL *)currentURL {
    if (_isUsingWKWebView && [_webView respondsToSelector:@selector(URL)]) {
        return ((NSURL *(*)(id, SEL))objc_msgSend)(_webView, @selector(URL));
    }
    if ([_webView respondsToSelector:@selector(request)]) {
        NSURLRequest *req = ((NSURLRequest *(*)(id, SEL))objc_msgSend)(_webView, @selector(request));
        return req.URL;
    }
    return nil;
}

- (NSString *)currentTitle {
    if (_isUsingWKWebView && [_webView respondsToSelector:@selector(title)]) {
        return ((NSString *(*)(id, SEL))objc_msgSend)(_webView, @selector(title));
    }
    return nil;
}

- (void)loadURL:(NSURL *)url {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:30.0];
    [request setValue:[TVWebEngine desktopUserAgent] forHTTPHeaderField:@"User-Agent"];
    if ([_webView respondsToSelector:@selector(loadRequest:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(_webView, @selector(loadRequest:), request);
    }
}

- (void)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL {
    if ([_webView respondsToSelector:@selector(loadHTMLString:baseURL:)]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(_webView, @selector(loadHTMLString:baseURL:), html, baseURL);
    }
}

- (void)goBack {
    if (self.canGoBack && [_webView respondsToSelector:@selector(goBack)]) {
        ((void (*)(id, SEL))objc_msgSend)(_webView, @selector(goBack));
    }
}

- (void)goForward {
    if (self.canGoForward && [_webView respondsToSelector:@selector(goForward)]) {
        ((void (*)(id, SEL))objc_msgSend)(_webView, @selector(goForward));
    }
}

- (void)reload {
    if ([_webView respondsToSelector:@selector(reload)]) {
        ((void (*)(id, SEL))objc_msgSend)(_webView, @selector(reload));
    }
}

- (void)stopLoading {
    if ([_webView respondsToSelector:@selector(stopLoading)]) {
        ((void (*)(id, SEL))objc_msgSend)(_webView, @selector(stopLoading));
    }
}

- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(id _Nullable, NSError * _Nullable))completion {
    if (_isUsingWKWebView && [_webView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
        ((void (*)(id, SEL, id, void (^)(id, NSError *)))objc_msgSend)(_webView, @selector(evaluateJavaScript:completionHandler:), script, completion);
    } else if ([_webView respondsToSelector:@selector(stringByEvaluatingJavaScriptFromString:)]) {
        NSString *res = ((NSString *(*)(id, SEL, id))objc_msgSend)(_webView, @selector(stringByEvaluatingJavaScriptFromString:), script);
        if (completion) {
            completion(res, nil);
        }
    } else if (completion) {
        completion(nil, nil);
    }
}

#pragma mark - WKNavigationDelegate (Dynamic)

- (void)webView:(id)webView decidePolicyForNavigationAction:(id)navigationAction decisionHandler:(void (^)(NSInteger))decisionHandler {
    NSURL *url = nil;
    @try {
        url = [navigationAction valueForKeyPath:@"request.URL"];
    } @catch (NSException *exception) {
        url = nil;
    }

    BOOL allow = YES;
    if (url && [self.delegate respondsToSelector:@selector(webEngine:shouldAllowURL:)]) {
        allow = [self.delegate webEngine:self shouldAllowURL:url];
    }

    if (decisionHandler) {
        decisionHandler(allow ? 1 : 0);
    }
}

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    if ([self.delegate respondsToSelector:@selector(webEngineDidStartLoading:)]) {
        [self.delegate webEngineDidStartLoading:self];
    }
}

- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    if ([self.delegate respondsToSelector:@selector(webEngineDidFinishLoading:)]) {
        [self.delegate webEngineDidFinishLoading:self];
    }
    if ([self.delegate respondsToSelector:@selector(webEngine:didUpdateURL:title:)]) {
        [self.delegate webEngine:self didUpdateURL:self.currentURL title:self.currentTitle];
    }
}

- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(webEngine:didFailWithError:)]) {
        [self.delegate webEngine:self didFailWithError:error];
    }
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(webEngine:didFailWithError:)]) {
        [self.delegate webEngine:self didFailWithError:error];
    }
}

#pragma mark - WKUIDelegate (Dynamic - Pop-up & Google OAuth handling)

- (id)webView:(id)webView createWebViewWithConfiguration:(id)configuration forNavigationAction:(id)navigationAction windowFeatures:(id)windowFeatures {
    NSURL *url = nil;
    @try {
        url = [navigationAction valueForKeyPath:@"request.URL"];
    } @catch (NSException *exception) {
        url = nil;
    }
    if (url) {
        BOOL allow = YES;
        if ([self.delegate respondsToSelector:@selector(webEngine:shouldAllowURL:)]) {
            allow = [self.delegate webEngine:self shouldAllowURL:url];
        }
        if (allow) {
            [self loadURL:url];
        }
    }
    return nil;
}

#pragma mark - UIWebViewDelegate (Fallback)

- (BOOL)webView:(id)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    if (request.URL && [self.delegate respondsToSelector:@selector(webEngine:shouldAllowURL:)]) {
        return [self.delegate webEngine:self shouldAllowURL:request.URL];
    }
    return YES;
}

- (void)webViewDidStartLoad:(id)webView {
    if ([self.delegate respondsToSelector:@selector(webEngineDidStartLoading:)]) {
        [self.delegate webEngineDidStartLoading:self];
    }
}

- (void)webViewDidFinishLoad:(id)webView {
    if ([self.delegate respondsToSelector:@selector(webEngineDidFinishLoading:)]) {
        [self.delegate webEngineDidFinishLoading:self];
    }
    if ([self.delegate respondsToSelector:@selector(webEngine:didUpdateURL:title:)]) {
        [self.delegate webEngine:self didUpdateURL:self.currentURL title:self.currentTitle];
    }
}

- (void)webView:(id)webView didFailLoadWithError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(webEngine:didFailWithError:)]) {
        [self.delegate webEngine:self didFailWithError:error];
    }
}

@end

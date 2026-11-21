#import "TVWebEngine.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static void *kTVWebEngineKVOContext = &kTVWebEngineKVOContext;
static char kTVUCCRouterAttachedKey;
static char kTVBridgeScriptInstalledKey;
static NSString * const kTVBridgeMessageName = @"tvbrowser";
static NSString * const kTVContentRuleListIdentifier = @"tvbrowser_adblock_rules_v1";

static NSInteger TVPrivacyStanceUnknown(__unused id self, __unused SEL _cmd) {
    return 0;
}

static void TVInstallWebCoreShims(void) {
    Class metricsClass = objc_getClass("WebCoreNSURLSessionTaskTransactionMetrics");
    if (metricsClass == Nil) {
        return;
    }
    const char *typeEncoding = "q@:";
    SEL privateSelector = NSSelectorFromString(@"_privacyStance");
    SEL publicSelector = NSSelectorFromString(@"privacyStance");
    if (class_getInstanceMethod(metricsClass, privateSelector) == NULL) {
        class_addMethod(metricsClass, privateSelector, (IMP)TVPrivacyStanceUnknown, typeEncoding);
    }
    if (class_getInstanceMethod(metricsClass, publicSelector) == NULL) {
        class_addMethod(metricsClass, publicSelector, (IMP)TVPrivacyStanceUnknown, typeEncoding);
    }
}

@interface TVScriptMessageRouter : NSObject
@end

@implementation TVScriptMessageRouter

+ (NSMapTable<UIView *, TVWebEngine *> *)engineMap {
    static NSMapTable<UIView *, TVWebEngine *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = [NSMapTable weakToWeakObjectsMapTable];
    });
    return map;
}

+ (instancetype)sharedRouter {
    static TVScriptMessageRouter *router = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        router = [[TVScriptMessageRouter alloc] init];
    });
    return router;
}

+ (void)registerEngine:(TVWebEngine *)engine forWebView:(UIView *)webView {
    if (!engine || !webView) return;
    @synchronized (self) {
        [[self engineMap] setObject:engine forKey:webView];
    }
}

+ (void)unregisterWebView:(UIView *)webView {
    if (!webView) return;
    @synchronized (self) {
        [[self engineMap] removeObjectForKey:webView];
    }
}

- (void)userContentController:(id)userContentController didReceiveScriptMessage:(id)message {
    (void)userContentController;
    if (!message) return;

    UIView *sourceWebView = nil;
    NSString *name = nil;
    id body = nil;
    @try {
        sourceWebView = [message valueForKey:@"webView"];
        name = [message valueForKey:@"name"];
        body = [message valueForKey:@"body"];
    } @catch (NSException *exception) {
        return;
    }

    if (!sourceWebView || !name) return;
    TVWebEngine *engine = nil;
    @synchronized ([TVScriptMessageRouter class]) {
        engine = [[TVScriptMessageRouter engineMap] objectForKey:sourceWebView];
    }
    if (!engine) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([engine.delegate respondsToSelector:@selector(webEngine:didReceiveScriptMessageName:body:)]) {
            [engine.delegate webEngine:engine didReceiveScriptMessageName:name body:body];
        }
    });
}

@end

@interface TVWebEngine ()
@property (nonatomic, strong, readwrite) UIView *webView;
@property (nonatomic, assign, readwrite) BOOL isUsingWKWebView;
@property (nonatomic, assign, readwrite) NSUInteger mainFrameNavigationCount;
@property (nonatomic, assign) BOOL isObservingKVO;
@property (nonatomic, strong, nullable) id userContentController;
@property (nonatomic, copy, nullable) NSString *lastReportedURLString;
@property (nonatomic, copy, nullable) NSString *lastReportedTitle;
@end

static BOOL TVIsIgnorableError(NSError *error) {
    // NSURLErrorCancelled (-999): a new navigation replaced the previous one.
    // WebKitErrorFrameLoadInterruptedByPolicyChange (102): blocked/handled by policy.
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return YES;
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return YES;
    return NO;
}

static NSString *TVBridgeUserScriptSource(void) {
    return @"(function(){"
        "if (window.__tvBrowserBridgeInstalled) return;"
        "window.__tvBrowserBridgeInstalled = true;"
        "function postMsg(payload) {"
            "try {"
                "if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tvbrowser) {"
                    "window.webkit.messageHandlers.tvbrowser.postMessage(payload);"
                "}"
            "} catch (e) {}"
        "}"
        "var nonTextTypes = ['submit','button','checkbox','radio','reset','file','image','range','color','hidden'];"
        "function isEditable(el) {"
            "if (!el || !el.tagName) return false;"
            "var tag = el.tagName.toLowerCase();"
            "if (tag === 'textarea') return !el.disabled && !el.readOnly;"
            "if (tag === 'input') {"
                "var t = (el.getAttribute('type') || 'text').toLowerCase();"
                "return nonTextTypes.indexOf(t) === -1 && !el.disabled && !el.readOnly;"
            "}"
            "if (el.isContentEditable) return true;"
            "return false;"
        "}"
        "document.addEventListener('focusin', function(e) {"
            "var t = e.target;"
            "if (isEditable(t)) {"
                "window.__tvBrowserActiveInput = t;"
                "var itype = (t.getAttribute && t.getAttribute('type') || 'text').toLowerCase();"
                "postMsg({ type: 'inputFocus', focused: true, isPassword: itype === 'password' });"
            "}"
        "}, true);"
        "document.addEventListener('focusout', function(e) {"
            "setTimeout(function() {"
                "var active = document.activeElement;"
                "if (!isEditable(active)) {"
                    "postMsg({ type: 'inputFocus', focused: false });"
                "}"
            "}, 40);"
        "}, true);"
        "function notifyVideo(v) {"
            "if (!v) return;"
            "var src = v.currentSrc || v.src || '';"
            "if (!src) {"
                "var s = v.querySelector && v.querySelector('source[src]');"
                "if (s) src = s.src || '';"
            "}"
            "if (src && src.indexOf('blob:') !== 0) {"
                "postMsg({ type: 'videoDetected', src: src });"
            "}"
        "}"
        "document.addEventListener('play', function(e) {"
            "if (e && e.target && e.target.tagName && e.target.tagName.toLowerCase() === 'video') {"
                "notifyVideo(e.target);"
            "}"
        "}, true);"
        "document.addEventListener('loadedmetadata', function(e) {"
            "if (e && e.target && e.target.tagName && e.target.tagName.toLowerCase() === 'video') {"
                "notifyVideo(e.target);"
            "}"
        "}, true);"
        "function tvDeepHit(x, y) {"
            "var el = document.elementFromPoint(x, y);"
            "while (el && el.shadowRoot && typeof el.shadowRoot.elementFromPoint === 'function') {"
                "var inner = el.shadowRoot.elementFromPoint(x, y);"
                "if (!inner || inner === el) break;"
                "el = inner;"
            "}"
            "return el;"
        "}"
        "function tvClosest(el, sel) {"
            "var cur = el;"
            "while (cur) {"
                "if (cur.matches && cur.matches(sel)) return cur;"
                "if (cur.parentElement) { cur = cur.parentElement; continue; }"
                "var root = cur.getRootNode ? cur.getRootNode() : null;"
                "cur = (root && root.host) ? root.host : null;"
            "}"
            "return null;"
        "}"
        "window.addEventListener('message', function(ev) {"
            "var d = ev && ev.data;"
            "if (!d || d.__tvBrowserBridge !== true) return;"
            "var rx = Number(d.rx), ry = Number(d.ry);"
            "if (!isFinite(rx) || !isFinite(ry)) return;"
            "var el = tvDeepHit(rx, ry);"
            "if (!el) return;"
            "if (d.action === 'click') {"
                "window.__tvBrowserLastClick = Date.now();"
                "if (el.tagName && el.tagName.toLowerCase() === 'iframe') {"
                    "try {"
                        "var r = el.getBoundingClientRect();"
                        "if (el.contentWindow) {"
                            "el.contentWindow.postMessage({ __tvBrowserBridge: true, action: 'click', rx: rx - r.left, ry: ry - r.top }, '*');"
                        "}"
                    "} catch (e) {}"
                    "return;"
                "}"
                "var target = tvClosest(el, 'a[href], a, button, input, select, textarea, label, summary, [role=\"button\"], [role=\"link\"], [role=\"tab\"], [role=\"menuitem\"], [onclick], [tabindex]') || el;"
                "var opts = { bubbles: true, cancelable: true, view: window, clientX: rx, clientY: ry, screenX: rx, screenY: ry, button: 0, buttons: 1 };"
                "try { if (typeof PointerEvent === 'function') { var p = Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, opts); target.dispatchEvent(new PointerEvent('pointerover', p)); target.dispatchEvent(new PointerEvent('pointerdown', p)); } } catch (e) {}"
                "target.dispatchEvent(new MouseEvent('mouseover', opts));"
                "target.dispatchEvent(new MouseEvent('mousedown', opts));"
                "try { target.focus && target.focus(); } catch (e) {}"
                "try { if (typeof PointerEvent === 'function') { target.dispatchEvent(new PointerEvent('pointerup', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, opts, { buttons: 0 }))); } } catch (e) {}"
                "target.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, opts, { buttons: 0 })));"
                "target.dispatchEvent(new MouseEvent('click', Object.assign({}, opts, { buttons: 0, detail: 1 })));"
            "}"
        "});"
    "})();";
}

@implementation TVWebEngine

+ (NSString *)userAgentStringForMode:(TVUserAgentMode)mode {
    switch (mode) {
        case TVUserAgentModeIPad:
            return @"Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1";
        case TVUserAgentModeIPhone:
            return @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1";
        case TVUserAgentModeDesktopMac:
        default:
            return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15";
    }
}

+ (void)loadWebKitIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            @"UserAgent": [TVWebEngine userAgentStringForMode:TVUserAgentModeDesktopMac]
        }];

        if (NSClassFromString(@"WKWebView") == Nil) {
            const char *paths[] = {
                "/System/Library/Frameworks/WebKit.framework/WebKit",
                "/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
                "/System/Library/StagedFrameworks/Safari/WebKit.framework/WebKit"
            };
            for (int i = 0; i < 3; i++) {
                if (dlopen(paths[i], RTLD_NOW | RTLD_GLOBAL) != NULL && NSClassFromString(@"WKWebView") != Nil) {
                    break;
                }
            }
        }
        TVInstallWebCoreShims();
    });
}

+ (void)clearCacheAndCookiesWithCompletion:(void (^)(void))completion {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSHTTPCookieStorage *sharedCookies = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [sharedCookies.cookies copy]) {
        [sharedCookies deleteCookie:cookie];
    }

    [self loadWebKitIfNeeded];
    Class dataStoreClass = NSClassFromString(@"WKWebsiteDataStore");
    SEL defaultStoreSel = NSSelectorFromString(@"defaultDataStore");
    SEL allTypesSel = NSSelectorFromString(@"allWebsiteDataTypes");
    SEL removeSel = NSSelectorFromString(@"removeDataOfTypes:modifiedSince:completionHandler:");

    if (dataStoreClass &&
        [dataStoreClass respondsToSelector:defaultStoreSel] &&
        [dataStoreClass respondsToSelector:allTypesSel]) {
        id store = ((id (*)(id, SEL))objc_msgSend)(dataStoreClass, defaultStoreSel);
        id types = ((id (*)(id, SEL))objc_msgSend)(dataStoreClass, allTypesSel);
        if (store && types && [store respondsToSelector:removeSel]) {
            NSDate *since = [NSDate dateWithTimeIntervalSince1970:0];
            ((void (*)(id, SEL, id, id, void (^)(void)))objc_msgSend)(store, removeSel, types, since, ^{
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), completion);
                }
            });
            return;
        }
    }

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), completion);
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame runtimeConfiguration:nil];
}

- (instancetype)initWithFrame:(CGRect)frame runtimeConfiguration:(id)runtimeConfiguration {
    self = [super init];
    if (self) {
        _userAgentMode = TVUserAgentModeDesktopMac;
        [TVWebEngine loadWebKitIfNeeded];

        Class wkClass = NSClassFromString(@"WKWebView");
        Class wkConfigClass = NSClassFromString(@"WKWebViewConfiguration");

        if (wkClass && wkConfigClass) {
            id config = runtimeConfiguration ?: [[wkConfigClass alloc] init];

            if ([config respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(config, @selector(setAllowsInlineMediaPlayback:), YES);
            }
            if ([config respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) {
                ((void (*)(id, SEL, NSUInteger))objc_msgSend)(config, @selector(setMediaTypesRequiringUserActionForPlayback:), 0);
            }

            // Ensure persistent cookies/sessions for logins
            Class dataStoreClass = NSClassFromString(@"WKWebsiteDataStore");
            if (!runtimeConfiguration && dataStoreClass &&
                [dataStoreClass respondsToSelector:@selector(defaultDataStore)] &&
                [config respondsToSelector:@selector(setWebsiteDataStore:)]) {
                id store = ((id (*)(id, SEL))objc_msgSend)(dataStoreClass, @selector(defaultDataStore));
                ((void (*)(id, SEL, id))objc_msgSend)(config, @selector(setWebsiteDataStore:), store);
            }

            // Enable JS, window opening & private MSE/video playback preferences when present
            if ([config respondsToSelector:@selector(preferences)]) {
                id prefs = ((id (*)(id, SEL))objc_msgSend)(config, @selector(preferences));
                if ([prefs respondsToSelector:@selector(setJavaScriptCanOpenWindowsAutomatically:)]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(prefs, @selector(setJavaScriptCanOpenWindowsAutomatically:), YES);
                }
                SEL mseSel = NSSelectorFromString(@"_setMediaSourceEnabled:");
                if ([prefs respondsToSelector:mseSel]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(prefs, mseSel, YES);
                }
                SEL managedMseSel = NSSelectorFromString(@"_setManagedMediaSourceEnabled:");
                if ([prefs respondsToSelector:managedMseSel]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(prefs, managedMseSel, YES);
                }
            }

            [self configureUserContentControllerForConfig:config];

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
                ((void (*)(id, SEL, id))objc_msgSend)(wkView, @selector(setCustomUserAgent:), [TVWebEngine userAgentStringForMode:_userAgentMode]);
            }

            _webView = wkView;
            _isUsingWKWebView = YES;
            UIScrollView *sv = self.scrollView;
            if (sv && [sv respondsToSelector:@selector(setContentInsetAdjustmentBehavior:)]) {
                sv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
            }
            [TVScriptMessageRouter registerEngine:self forWebView:wkView];
            [self startObservingWKWebView:wkView];
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
                UIScrollView *sv = self.scrollView;
                if (sv && [sv respondsToSelector:@selector(setContentInsetAdjustmentBehavior:)]) {
                    sv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
                }
            } else {
                _webView = [[UIView alloc] initWithFrame:frame];
                _webView.backgroundColor = [UIColor darkGrayColor];
                _isUsingWKWebView = NO;
            }
        }
    }
    return self;
}

- (void)dealloc {
    [self stopObservingWKWebView];
    if (_webView) {
        [TVScriptMessageRouter unregisterWebView:_webView];
    }
}

- (void)configureUserContentControllerForConfig:(id)config {
    SEL getUCCSel = NSSelectorFromString(@"userContentController");
    SEL setUCCSel = NSSelectorFromString(@"setUserContentController:");
    id ucc = nil;
    if ([config respondsToSelector:getUCCSel]) {
        ucc = ((id (*)(id, SEL))objc_msgSend)(config, getUCCSel);
    }
    if (!ucc) {
        Class uccClass = NSClassFromString(@"WKUserContentController");
        if (uccClass && [config respondsToSelector:setUCCSel]) {
            ucc = [[uccClass alloc] init];
            ((void (*)(id, SEL, id))objc_msgSend)(config, setUCCSel, ucc);
        }
    }
    if (!ucc) return;
    self.userContentController = ucc;

    if (!objc_getAssociatedObject(ucc, &kTVUCCRouterAttachedKey)) {
        SEL addHandlerSel = NSSelectorFromString(@"addScriptMessageHandler:name:");
        if ([ucc respondsToSelector:addHandlerSel]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(ucc, addHandlerSel, [TVScriptMessageRouter sharedRouter], kTVBridgeMessageName);
            objc_setAssociatedObject(ucc, &kTVUCCRouterAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if (!objc_getAssociatedObject(ucc, &kTVBridgeScriptInstalledKey)) {
        Class userScriptClass = NSClassFromString(@"WKUserScript");
        SEL addUserScriptSel = NSSelectorFromString(@"addUserScript:");
        SEL initScriptSel = NSSelectorFromString(@"initWithSource:injectionTime:forMainFrameOnly:");
        if (userScriptClass &&
            [ucc respondsToSelector:addUserScriptSel] &&
            [userScriptClass instancesRespondToSelector:initScriptSel]) {
            id scriptAlloc = [userScriptClass alloc];
            id script = ((id (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(scriptAlloc, initScriptSel, TVBridgeUserScriptSource(), 0, NO);
            if (script) {
                ((void (*)(id, SEL, id))objc_msgSend)(ucc, addUserScriptSel, script);
                objc_setAssociatedObject(ucc, &kTVBridgeScriptInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

- (NSArray<NSString *> *)observedKeyPaths {
    return @[@"URL", @"title", @"canGoBack", @"canGoForward", @"loading", @"estimatedProgress"];
}

- (void)startObservingWKWebView:(UIView *)wkView {
    if (_isObservingKVO || !wkView) return;
    _isObservingKVO = YES;
    for (NSString *keyPath in [self observedKeyPaths]) {
        [wkView addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:kTVWebEngineKVOContext];
    }
}

- (void)stopObservingWKWebView {
    if (!_isObservingKVO || !_webView) return;
    _isObservingKVO = NO;
    for (NSString *keyPath in [self observedKeyPaths]) {
        @try {
            [_webView removeObserver:self forKeyPath:keyPath context:kTVWebEngineKVOContext];
        } @catch (NSException *exception) {}
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != kTVWebEngineKVOContext || object != _webView) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    dispatch_block_t notifyBlock = ^{
        if ([keyPath isEqualToString:@"estimatedProgress"]) {
            if ([self.delegate respondsToSelector:@selector(webEngine:didUpdateProgress:)]) {
                [self.delegate webEngine:self didUpdateProgress:self.estimatedProgress];
            }
        } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"] || [keyPath isEqualToString:@"loading"]) {
            if ([self.delegate respondsToSelector:@selector(webEngine:didUpdateNavigationStateCanGoBack:canGoForward:isLoading:)]) {
                [self.delegate webEngine:self didUpdateNavigationStateCanGoBack:self.canGoBack canGoForward:self.canGoForward isLoading:self.isLoading];
            }
        } else if ([keyPath isEqualToString:@"URL"] || [keyPath isEqualToString:@"title"]) {
            [self emitURLAndTitleUpdateIfNeeded];
        }
    };

    if ([NSThread isMainThread]) {
        notifyBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), notifyBlock);
    }
}

- (void)emitURLAndTitleUpdateIfNeeded {
    NSURL *url = self.currentURL;
    NSString *title = self.currentTitle;
    NSString *urlStr = url.absoluteString ?: @"";
    NSString *titleStr = title ?: @"";

    if ([urlStr isEqualToString:self.lastReportedURLString ?: @""] &&
        [titleStr isEqualToString:self.lastReportedTitle ?: @""]) {
        return;
    }
    self.lastReportedURLString = urlStr;
    self.lastReportedTitle = titleStr;

    if ([self.delegate respondsToSelector:@selector(webEngine:didUpdateURL:title:)]) {
        [self.delegate webEngine:self didUpdateURL:url title:title];
    }
}

- (void)setUserAgentMode:(TVUserAgentMode)userAgentMode {
    _userAgentMode = userAgentMode;
    NSString *ua = [TVWebEngine userAgentStringForMode:userAgentMode];
    if (_isUsingWKWebView && [_webView respondsToSelector:@selector(setCustomUserAgent:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(_webView, @selector(setCustomUserAgent:), ua);
    }
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

- (BOOL)isLoading {
    if ([_webView respondsToSelector:@selector(isLoading)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(_webView, @selector(isLoading));
    }
    return NO;
}

- (double)estimatedProgress {
    if (_isUsingWKWebView && [_webView respondsToSelector:@selector(estimatedProgress)]) {
        return ((double (*)(id, SEL))objc_msgSend)(_webView, @selector(estimatedProgress));
    }
    return self.isLoading ? 0.5 : 1.0;
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
    [request setValue:[TVWebEngine userAgentStringForMode:_userAgentMode] forHTTPHeaderField:@"User-Agent"];
    if ([_webView respondsToSelector:@selector(loadRequest:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(_webView, @selector(loadRequest:), request);
    }
}

- (BOOL)applyNativePageZoom:(CGFloat)zoom {
    if (!_isUsingWKWebView || !_webView) return NO;
    SEL pageZoomSel = NSSelectorFromString(@"setPageZoom:");
    if ([_webView respondsToSelector:pageZoomSel]) {
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(_webView, pageZoomSel, zoom);
        return YES;
    }
    SEL privateZoomSel = NSSelectorFromString(@"_setPageZoomFactor:");
    if ([_webView respondsToSelector:privateZoomSel]) {
        ((void (*)(id, SEL, double))objc_msgSend)(_webView, privateZoomSel, (double)zoom);
        return YES;
    }
    return NO;
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

- (void)installContentRuleListWithJSON:(NSString *)jsonString {
    if (!_isUsingWKWebView || !self.userContentController) return;
    id ucc = self.userContentController;
    SEL removeAllSel = NSSelectorFromString(@"removeAllContentRuleLists");
    SEL addRuleListSel = NSSelectorFromString(@"addContentRuleList:");

    if (jsonString.length == 0) {
        if ([ucc respondsToSelector:removeAllSel]) {
            ((void (*)(id, SEL))objc_msgSend)(ucc, removeAllSel);
        }
        return;
    }

    Class storeClass = NSClassFromString(@"WKContentRuleListStore");
    SEL defaultStoreSel = NSSelectorFromString(@"defaultStore");
    SEL compileSel = NSSelectorFromString(@"compileContentRuleListForIdentifier:encodedContentRuleList:completionHandler:");
    if (!storeClass || ![storeClass respondsToSelector:defaultStoreSel]) return;
    id store = ((id (*)(id, SEL))objc_msgSend)(storeClass, defaultStoreSel);
    if (!store || ![store respondsToSelector:compileSel]) return;

    __weak typeof(self) weakSelf = self;
    ((void (*)(id, SEL, id, id, void (^)(id, NSError *)))objc_msgSend)(
        store, compileSel, kTVContentRuleListIdentifier, jsonString, ^(id ruleList, NSError *error) {
            (void)error;
            if (!ruleList) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || !strongSelf.userContentController) return;
                if ([strongSelf.userContentController respondsToSelector:removeAllSel]) {
                    ((void (*)(id, SEL))objc_msgSend)(strongSelf.userContentController, removeAllSel);
                }
                if ([strongSelf.userContentController respondsToSelector:addRuleListSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(strongSelf.userContentController, addRuleListSel, ruleList);
                }
            });
        }
    );
}

#pragma mark - WKNavigationDelegate (Dynamic)

- (void)webView:(id)webView decidePolicyForNavigationAction:(id)navigationAction decisionHandler:(void (^)(NSInteger))decisionHandler {
    (void)webView;
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

    if (allow) {
        BOOL isMain = YES;
        @try {
            id frame = [navigationAction valueForKey:@"targetFrame"];
            if (frame) {
                isMain = [[frame valueForKey:@"mainFrame"] boolValue];
            }
        } @catch (NSException *exception) {
            isMain = YES;
        }
        if (isMain) {
            self.mainFrameNavigationCount += 1;
        }
    }

    if (decisionHandler) {
        decisionHandler(allow ? 1 : 0);
    }
}

- (void)webView:(id)webView decidePolicyForNavigationResponse:(id)navigationResponse decisionHandler:(void (^)(NSInteger))decisionHandler {
    (void)webView;
    (void)navigationResponse;
    if (decisionHandler) {
        decisionHandler(1);
    }
}

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    (void)webView;
    (void)navigation;
    if ([self.delegate respondsToSelector:@selector(webEngineDidStartLoading:)]) {
        [self.delegate webEngineDidStartLoading:self];
    }
}

- (void)webView:(id)webView didCommitNavigation:(id)navigation {
    (void)webView;
    (void)navigation;
    [self emitURLAndTitleUpdateIfNeeded];
}

- (void)webView:(id)webView didFinishNavigation:(id)navigation {
    (void)webView;
    (void)navigation;
    if ([self.delegate respondsToSelector:@selector(webEngineDidFinishLoading:)]) {
        [self.delegate webEngineDidFinishLoading:self];
    }
    [self emitURLAndTitleUpdateIfNeeded];
}

- (void)webView:(id)webView didFailNavigation:(id)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    if (TVIsIgnorableError(error)) return;
    NSURL *failingURL = nil;
    NSString *failingStr = error.userInfo[NSURLErrorFailingURLStringErrorKey];
    if (failingStr) failingURL = [NSURL URLWithString:failingStr];
    if ([self.delegate respondsToSelector:@selector(webEngine:didFailWithError:failingURL:)]) {
        [self.delegate webEngine:self didFailWithError:error failingURL:failingURL ?: self.currentURL];
    }
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    if (TVIsIgnorableError(error)) return;
    NSURL *failingURL = nil;
    NSString *failingStr = error.userInfo[NSURLErrorFailingURLStringErrorKey];
    if (failingStr) failingURL = [NSURL URLWithString:failingStr];
    if ([self.delegate respondsToSelector:@selector(webEngine:didFailWithError:failingURL:)]) {
        [self.delegate webEngine:self didFailWithError:error failingURL:failingURL ?: self.currentURL];
    }
}

- (void)webViewWebContentProcessDidTerminate:(id)webView {
    (void)webView;
    if ([self.delegate respondsToSelector:@selector(webEngineWebContentProcessDidTerminate:)]) {
        [self.delegate webEngineWebContentProcessDidTerminate:self];
    }
}

#pragma mark - WKUIDelegate (Dynamic - Pop-up, OAuth & JS Panels)

- (id)webView:(id)webView createWebViewWithConfiguration:(id)configuration forNavigationAction:(id)navigationAction windowFeatures:(id)windowFeatures {
    (void)webView;
    (void)windowFeatures;
    NSURL *url = nil;
    @try {
        url = [navigationAction valueForKeyPath:@"request.URL"];
    } @catch (NSException *exception) {
        url = nil;
    }

    if (url && [self.delegate respondsToSelector:@selector(webEngine:shouldAllowURL:)]) {
        if (![self.delegate webEngine:self shouldAllowURL:url]) {
            return nil;
        }
    }

    if ([self.delegate respondsToSelector:@selector(webEngine:createPopupEngineWithConfiguration:forURL:)]) {
        TVWebEngine *popupEngine = [self.delegate webEngine:self createPopupEngineWithConfiguration:configuration forURL:url];
        if (popupEngine && popupEngine.isUsingWKWebView) {
            return popupEngine.webView;
        }
    }

    if (url) {
        [self loadURL:url];
    }
    return nil;
}

- (void)webViewDidClose:(id)webView {
    (void)webView;
    if ([self.delegate respondsToSelector:@selector(webEngineDidRequestClose:)]) {
        [self.delegate webEngineDidRequestClose:self];
    }
}

- (void)webView:(id)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(id)frame completionHandler:(void (^)(void))completionHandler {
    (void)webView;
    (void)frame;
    if ([self.delegate respondsToSelector:@selector(webEngine:runJavaScriptAlert:completion:)]) {
        [self.delegate webEngine:self runJavaScriptAlert:message ?: @"" completion:^{
            if (completionHandler) completionHandler();
        }];
    } else if (completionHandler) {
        completionHandler();
    }
}

- (void)webView:(id)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(id)frame completionHandler:(void (^)(BOOL))completionHandler {
    (void)webView;
    (void)frame;
    if ([self.delegate respondsToSelector:@selector(webEngine:runJavaScriptConfirm:completion:)]) {
        [self.delegate webEngine:self runJavaScriptConfirm:message ?: @"" completion:^(BOOL result) {
            if (completionHandler) completionHandler(result);
        }];
    } else if (completionHandler) {
        completionHandler(NO);
    }
}

- (void)webView:(id)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(id)frame completionHandler:(void (^)(NSString * _Nullable))completionHandler {
    (void)webView;
    (void)frame;
    if ([self.delegate respondsToSelector:@selector(webEngine:runJavaScriptPrompt:defaultText:completion:)]) {
        [self.delegate webEngine:self runJavaScriptPrompt:prompt ?: @"" defaultText:defaultText completion:^(NSString * _Nullable result) {
            if (completionHandler) completionHandler(result);
        }];
    } else if (completionHandler) {
        completionHandler(nil);
    }
}

#pragma mark - UIWebViewDelegate (Fallback)

- (BOOL)webView:(id)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(NSInteger)navigationType {
    (void)webView;
    (void)navigationType;
    BOOL allow = YES;
    if (request.URL && [self.delegate respondsToSelector:@selector(webEngine:shouldAllowURL:)]) {
        allow = [self.delegate webEngine:self shouldAllowURL:request.URL];
    }
    if (allow && (request.mainDocumentURL == nil || [request.mainDocumentURL isEqual:request.URL])) {
        self.mainFrameNavigationCount += 1;
    }
    return allow;
}

- (void)webViewDidStartLoad:(id)webView {
    (void)webView;
    if ([self.delegate respondsToSelector:@selector(webEngineDidStartLoading:)]) {
        [self.delegate webEngineDidStartLoading:self];
    }
}

- (void)webViewDidFinishLoad:(id)webView {
    (void)webView;
    if ([self.delegate respondsToSelector:@selector(webEngineDidFinishLoading:)]) {
        [self.delegate webEngineDidFinishLoading:self];
    }
    if ([self.delegate respondsToSelector:@selector(webEngine:didUpdateURL:title:)]) {
        __weak typeof(self) weakSelf = self;
        [self evaluateJavaScript:@"document.title" completion:^(id _Nullable result, NSError * _Nullable error) {
            (void)error;
            NSString *jsTitle = [result isKindOfClass:[NSString class]] ? (NSString *)result : nil;
            [weakSelf.delegate webEngine:weakSelf didUpdateURL:weakSelf.currentURL title:jsTitle];
        }];
    }
}

- (void)webView:(id)webView didFailLoadWithError:(NSError *)error {
    (void)webView;
    if (TVIsIgnorableError(error)) return;
    NSURL *failingURL = nil;
    NSString *failingStr = error.userInfo[NSURLErrorFailingURLStringErrorKey];
    if (failingStr) failingURL = [NSURL URLWithString:failingStr];
    if ([self.delegate respondsToSelector:@selector(webEngine:didFailWithError:failingURL:)]) {
        [self.delegate webEngine:self didFailWithError:error failingURL:failingURL ?: self.currentURL];
    }
}

@end

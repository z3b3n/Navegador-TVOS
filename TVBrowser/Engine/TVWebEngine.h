#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TVUserAgentMode) {
    TVUserAgentModeDesktopMac = 0,
    TVUserAgentModeIPad = 1,
    TVUserAgentModeIPhone = 2
};

@class TVWebEngine;

@protocol TVWebEngineDelegate <NSObject>
@optional
- (void)webEngineDidStartLoading:(TVWebEngine *)engine;
- (void)webEngineDidFinishLoading:(TVWebEngine *)engine;
- (void)webEngine:(TVWebEngine *)engine didFailWithError:(NSError *)error failingURL:(nullable NSURL *)failingURL;
- (void)webEngine:(TVWebEngine *)engine didUpdateURL:(nullable NSURL *)url title:(nullable NSString *)title;
- (void)webEngine:(TVWebEngine *)engine didUpdateProgress:(double)progress;
- (void)webEngine:(TVWebEngine *)engine didUpdateNavigationStateCanGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward isLoading:(BOOL)isLoading;
- (BOOL)webEngine:(TVWebEngine *)engine shouldAllowURL:(NSURL *)url;
- (nullable TVWebEngine *)webEngine:(TVWebEngine *)engine createPopupEngineWithConfiguration:(nullable id)configuration forURL:(nullable NSURL *)url;
- (void)webEngineDidRequestClose:(TVWebEngine *)engine;
- (void)webEngineWebContentProcessDidTerminate:(TVWebEngine *)engine;
- (void)webEngine:(TVWebEngine *)engine runJavaScriptAlert:(NSString *)message completion:(void (^)(void))completion;
- (void)webEngine:(TVWebEngine *)engine runJavaScriptConfirm:(NSString *)message completion:(void (^)(BOOL result))completion;
- (void)webEngine:(TVWebEngine *)engine runJavaScriptPrompt:(NSString *)prompt defaultText:(nullable NSString *)defaultText completion:(void (^)(NSString * _Nullable result))completion;
- (void)webEngine:(TVWebEngine *)engine didReceiveScriptMessageName:(NSString *)name body:(nullable id)body;
@end

@interface TVWebEngine : NSObject

@property (nonatomic, weak, nullable) id<TVWebEngineDelegate> delegate;
@property (nonatomic, strong, readonly) UIView *webView;
@property (nonatomic, strong, readonly, nullable) UIScrollView *scrollView;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) double estimatedProgress;
@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly, nullable) NSString *currentTitle;
@property (nonatomic, readonly) BOOL isUsingWKWebView;
/// Incremented every time a main-frame navigation is allowed to start.
@property (nonatomic, readonly) NSUInteger mainFrameNavigationCount;
@property (nonatomic, assign) TVUserAgentMode userAgentMode;

+ (NSString *)userAgentStringForMode:(TVUserAgentMode)mode;
+ (void)clearCacheAndCookiesWithCompletion:(nullable void (^)(void))completion;

/// Applies native page zoom (WKWebView.pageZoom). Returns NO if unsupported.
- (BOOL)applyNativePageZoom:(CGFloat)zoom;

- (instancetype)initWithFrame:(CGRect)frame;
- (instancetype)initWithFrame:(CGRect)frame runtimeConfiguration:(nullable id)configuration;
- (void)loadURL:(NSURL *)url;
- (void)loadHTMLString:(NSString *)html baseURL:(nullable NSURL *)baseURL;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)evaluateJavaScript:(NSString *)script completion:(nullable void (^)(id _Nullable result, NSError * _Nullable error))completion;
- (void)installContentRuleListWithJSON:(nullable NSString *)jsonString;

@end

NS_ASSUME_NONNULL_END

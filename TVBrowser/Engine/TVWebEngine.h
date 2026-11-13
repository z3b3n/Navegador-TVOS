#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TVWebEngine;

@protocol TVWebEngineDelegate <NSObject>
@optional
- (void)webEngineDidStartLoading:(TVWebEngine *)engine;
- (void)webEngineDidFinishLoading:(TVWebEngine *)engine;
- (void)webEngine:(TVWebEngine *)engine didFailWithError:(NSError *)error;
- (void)webEngine:(TVWebEngine *)engine didUpdateURL:(nullable NSURL *)url title:(nullable NSString *)title;
- (BOOL)webEngine:(TVWebEngine *)engine shouldAllowURL:(NSURL *)url;
- (void)webEngine:(TVWebEngine *)engine didRequestTextInputWithTitle:(NSString *)title currentValue:(NSString *)value elementId:(NSString *)elementId;
@end

@interface TVWebEngine : NSObject

@property (nonatomic, weak, nullable) id<TVWebEngineDelegate> delegate;
@property (nonatomic, strong, readonly) UIView *webView;
@property (nonatomic, strong, readonly, nullable) UIScrollView *scrollView;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly, nullable) NSString *currentTitle;
@property (nonatomic, readonly) BOOL isUsingWKWebView;
/// Incremented every time a main-frame navigation is allowed to start.
@property (nonatomic, readonly) NSUInteger mainFrameNavigationCount;

/// Applies native page zoom (WKWebView.pageZoom). Returns NO if unsupported.
- (BOOL)applyNativePageZoom:(CGFloat)zoom;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)loadURL:(NSURL *)url;
- (void)loadHTMLString:(NSString *)html baseURL:(nullable NSURL *)baseURL;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)evaluateJavaScript:(NSString *)script completion:(nullable void (^)(id _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

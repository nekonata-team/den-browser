#import <WebKit/WKWebView.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKWebView (DenPrivateProcessActivity)

@property (nonatomic, readonly) pid_t _webProcessIdentifier;
@property (nonatomic, readonly) BOOL _webProcessIsResponsive;

@end

NS_ASSUME_NONNULL_END

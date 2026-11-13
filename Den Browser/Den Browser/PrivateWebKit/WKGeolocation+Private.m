#import "WKGeolocation+Private.h"
#import <WebKit/WebKit.h>

NSObject *DenGeolocationContext(WKWebView *webView) {
    // The private geolocation provider API is scoped to the process pool, even on macOS 27.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return webView.configuration.processPool;
#pragma clang diagnostic pop
}

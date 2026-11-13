#import <Foundation/Foundation.h>
#import <WebKit/WKWebView.h>

NS_ASSUME_NONNULL_BEGIN

typedef const struct OpaqueWKContext *WKContextRef;
typedef const struct OpaqueWKGeolocationManager *WKGeolocationManagerRef;
typedef const struct OpaqueWKGeolocationPosition *WKGeolocationPositionRef;

typedef struct {
    int version;
    const void *clientInfo;
} WKGeolocationProviderBase;

typedef struct {
    WKGeolocationProviderBase base;
    void (*startUpdating)(WKGeolocationManagerRef, const void *);
    void (*stopUpdating)(WKGeolocationManagerRef, const void *);
    void (*setEnableHighAccuracy)(WKGeolocationManagerRef, bool, const void *);
} WKGeolocationProviderV1;

// WebKit's C context is toll-free bridged to WKProcessPool. Keep it alive while using its manager.
NSObject *DenGeolocationContext(WKWebView *webView);
WKGeolocationManagerRef WKContextGetGeolocationManager(WKContextRef context);
void WKGeolocationManagerSetProvider(WKGeolocationManagerRef manager, const WKGeolocationProviderBase * _Nullable provider);
void WKGeolocationManagerProviderDidChangePosition(WKGeolocationManagerRef manager, WKGeolocationPositionRef position);
void WKGeolocationManagerProviderDidFailToDeterminePosition(WKGeolocationManagerRef manager);
WKGeolocationPositionRef WKGeolocationPositionCreate(double timestamp, double latitude, double longitude, double accuracy);
void WKRelease(const void *object);

NS_ASSUME_NONNULL_END

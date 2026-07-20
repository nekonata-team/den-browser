#import <WebKit/WKPreferences.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKPreferences (DenPrivatePictureInPicture)

@property (
    nonatomic,
    setter=_setAllowsPictureInPictureMediaPlayback:
) BOOL _allowsPictureInPictureMediaPlayback;

@end

NS_ASSUME_NONNULL_END

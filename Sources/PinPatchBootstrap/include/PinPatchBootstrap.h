#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PPShakeHandler)(UIWindow *window, UIEvent * _Nullable event);

@interface PPShakeHook : NSObject
+ (BOOL)installWithHandler:(PPShakeHandler)handler;
@end

NS_ASSUME_NONNULL_END

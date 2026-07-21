#import "PinPatchBootstrap.h"
#import <objc/message.h>
#import <objc/runtime.h>

static PPShakeHandler PinPatchShakeHandler = nil;
static BOOL PinPatchShakeInstalled = NO;

@implementation UIWindow (PinPatchShake)

- (void)pp_motionEnded:(UIEventSubtype)motion withEvent:(UIEvent * _Nullable)event {
    [self pp_motionEnded:motion withEvent:event];
    if (motion == UIEventSubtypeMotionShake && PinPatchShakeHandler != nil) {
        PinPatchShakeHandler(self, event);
    }
}

@end

@implementation PPShakeHook

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class runtimeClass = NSClassFromString(@"PPBootstrapRuntime");
        SEL selector = NSSelectorFromString(@"start");
        if (runtimeClass != Nil && [runtimeClass respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(runtimeClass, selector);
        }
    });
}

+ (BOOL)installWithHandler:(PPShakeHandler)handler {
    @synchronized(self) {
        if (PinPatchShakeInstalled) {
            return YES;
        }

        Method original = class_getInstanceMethod(UIWindow.class, @selector(motionEnded:withEvent:));
        Method replacement = class_getInstanceMethod(UIWindow.class, @selector(pp_motionEnded:withEvent:));
        if (original == NULL || replacement == NULL) {
            return NO;
        }
        const char *originalTypes = method_getTypeEncoding(original);
        const char *replacementTypes = method_getTypeEncoding(replacement);
        if (originalTypes == NULL || replacementTypes == NULL || strcmp(originalTypes, replacementTypes) != 0) {
            return NO;
        }

        PinPatchShakeHandler = [handler copy];
        method_exchangeImplementations(original, replacement);
        PinPatchShakeInstalled = YES;
        return YES;
    }
}

@end

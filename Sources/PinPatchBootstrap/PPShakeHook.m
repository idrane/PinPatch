#import "PinPatchBootstrap.h"
#import <objc/message.h>
#import <objc/runtime.h>

static PPShakeHandler PinPatchShakeHandler = nil;
static BOOL PinPatchShakeInstalled = NO;
typedef void (*PPMotionEndedImplementation)(UIWindow *, SEL, UIEventSubtype, UIEvent * _Nullable);
static PPMotionEndedImplementation PinPatchOriginalMotionEnded = NULL;

static void PinPatchMotionEnded(UIWindow *window, SEL _cmd, UIEventSubtype motion, UIEvent * _Nullable event) {
    if (PinPatchOriginalMotionEnded != NULL) {
        PinPatchOriginalMotionEnded(window, @selector(motionEnded:withEvent:), motion, event);
    }
    if (motion == UIEventSubtypeMotionShake && PinPatchShakeHandler != nil) {
        PinPatchShakeHandler(window, event);
    }
}

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
        if (original == NULL) {
            return NO;
        }
        const char *originalTypes = method_getTypeEncoding(original);
        if (originalTypes == NULL) {
            return NO;
        }

        IMP originalImplementation = method_getImplementation(original);
        BOOL addedToWindow = class_addMethod(
            UIWindow.class,
            @selector(motionEnded:withEvent:),
            (IMP)PinPatchMotionEnded,
            originalTypes
        );
        if (addedToWindow) {
            PinPatchOriginalMotionEnded = (PPMotionEndedImplementation)originalImplementation;
        } else {
            IMP replaced = method_setImplementation(original, (IMP)PinPatchMotionEnded);
            if (replaced == NULL) {
                return NO;
            }
            PinPatchOriginalMotionEnded = (PPMotionEndedImplementation)replaced;
        }

        PinPatchShakeHandler = [handler copy];
        PinPatchShakeInstalled = YES;
        return YES;
    }
}

@end

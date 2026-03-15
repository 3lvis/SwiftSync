#import "ObjCExceptionCatcher.h"

NSString * const SwiftSyncObjCExceptionCatcherErrorDomain = @"SwiftSync.ObjCException";
NSString * const SwiftSyncObjCExceptionNameKey = @"exceptionName";
NSString * const SwiftSyncObjCExceptionReasonKey = @"exceptionReason";

@implementation SwiftSyncObjCExceptionCatcher

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[SwiftSyncObjCExceptionNameKey] = exception.name;
            if (exception.reason != nil) {
                userInfo[SwiftSyncObjCExceptionReasonKey] = exception.reason;
                userInfo[NSLocalizedDescriptionKey] = exception.reason;
            } else {
                userInfo[NSLocalizedDescriptionKey] = exception.name;
            }

            *error = [NSError errorWithDomain:SwiftSyncObjCExceptionCatcherErrorDomain code:1 userInfo:userInfo];
        }
        return NO;
    }
}

@end

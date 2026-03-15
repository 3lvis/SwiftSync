#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SwiftSyncObjCExceptionCatcher : NSObject
+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error;
@end

FOUNDATION_EXPORT NSString * const SwiftSyncObjCExceptionCatcherErrorDomain;
FOUNDATION_EXPORT NSString * const SwiftSyncObjCExceptionNameKey;
FOUNDATION_EXPORT NSString * const SwiftSyncObjCExceptionReasonKey;

NS_ASSUME_NONNULL_END

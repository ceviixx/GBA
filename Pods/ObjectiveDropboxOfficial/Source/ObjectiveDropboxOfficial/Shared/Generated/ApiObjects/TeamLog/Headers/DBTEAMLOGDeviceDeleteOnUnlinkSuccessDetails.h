///
/// Copyright (c) 2016 Dropbox, Inc. All rights reserved.
///
/// Auto-generated by Stone, do not modify.
///

#import <Foundation/Foundation.h>

#import "DBSerializableProtocol.h"

@class DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails;
@class DBTEAMLOGDeviceLogInfo;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - API Object

///
/// The `DeviceDeleteOnUnlinkSuccessDetails` struct.
///
/// Deleted all files from an unlinked device.
///
/// This class implements the `DBSerializable` protocol (serialize and
/// deserialize instance methods), which is required for all Obj-C SDK API route
/// objects.
///
@interface DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails : NSObject <DBSerializable, NSCopying>

#pragma mark - Instance fields

/// Device information.
@property (nonatomic, readonly) DBTEAMLOGDeviceLogInfo *deviceInfo;

#pragma mark - Constructors

///
/// Full constructor for the struct (exposes all instance variables).
///
/// @param deviceInfo Device information.
///
/// @return An initialized instance.
///
- (instancetype)initWithDeviceInfo:(DBTEAMLOGDeviceLogInfo *)deviceInfo;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Serializer Object

///
/// The serialization class for the `DeviceDeleteOnUnlinkSuccessDetails` struct.
///
@interface DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetailsSerializer : NSObject

///
/// Serializes `DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails` instances.
///
/// @param instance An instance of the
/// `DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails` API object.
///
/// @return A json-compatible dictionary representation of the
/// `DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails` API object.
///
+ (nullable NSDictionary *)serialize:(DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails *)instance;

///
/// Deserializes `DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails` instances.
///
/// @param dict A json-compatible dictionary representation of the
/// `DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails` API object.
///
/// @return An instantiation of the
/// `DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails` object.
///
+ (DBTEAMLOGDeviceDeleteOnUnlinkSuccessDetails *)deserialize:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END

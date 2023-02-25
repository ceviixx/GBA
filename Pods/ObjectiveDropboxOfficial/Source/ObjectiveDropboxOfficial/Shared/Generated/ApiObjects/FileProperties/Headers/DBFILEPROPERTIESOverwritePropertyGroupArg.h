///
/// Copyright (c) 2016 Dropbox, Inc. All rights reserved.
///
/// Auto-generated by Stone, do not modify.
///

#import <Foundation/Foundation.h>

#import "DBSerializableProtocol.h"

@class DBFILEPROPERTIESOverwritePropertyGroupArg;
@class DBFILEPROPERTIESPropertyGroup;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - API Object

///
/// The `OverwritePropertyGroupArg` struct.
///
/// This class implements the `DBSerializable` protocol (serialize and
/// deserialize instance methods), which is required for all Obj-C SDK API route
/// objects.
///
@interface DBFILEPROPERTIESOverwritePropertyGroupArg : NSObject <DBSerializable, NSCopying>

#pragma mark - Instance fields

/// A unique identifier for the file or folder.
@property (nonatomic, readonly, copy) NSString *path;

/// The property groups "snapshot" updates to force apply.
@property (nonatomic, readonly) NSArray<DBFILEPROPERTIESPropertyGroup *> *propertyGroups;

#pragma mark - Constructors

///
/// Full constructor for the struct (exposes all instance variables).
///
/// @param path A unique identifier for the file or folder.
/// @param propertyGroups The property groups "snapshot" updates to force apply.
///
/// @return An initialized instance.
///
- (instancetype)initWithPath:(NSString *)path propertyGroups:(NSArray<DBFILEPROPERTIESPropertyGroup *> *)propertyGroups;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Serializer Object

///
/// The serialization class for the `OverwritePropertyGroupArg` struct.
///
@interface DBFILEPROPERTIESOverwritePropertyGroupArgSerializer : NSObject

///
/// Serializes `DBFILEPROPERTIESOverwritePropertyGroupArg` instances.
///
/// @param instance An instance of the
/// `DBFILEPROPERTIESOverwritePropertyGroupArg` API object.
///
/// @return A json-compatible dictionary representation of the
/// `DBFILEPROPERTIESOverwritePropertyGroupArg` API object.
///
+ (nullable NSDictionary *)serialize:(DBFILEPROPERTIESOverwritePropertyGroupArg *)instance;

///
/// Deserializes `DBFILEPROPERTIESOverwritePropertyGroupArg` instances.
///
/// @param dict A json-compatible dictionary representation of the
/// `DBFILEPROPERTIESOverwritePropertyGroupArg` API object.
///
/// @return An instantiation of the `DBFILEPROPERTIESOverwritePropertyGroupArg`
/// object.
///
+ (DBFILEPROPERTIESOverwritePropertyGroupArg *)deserialize:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END

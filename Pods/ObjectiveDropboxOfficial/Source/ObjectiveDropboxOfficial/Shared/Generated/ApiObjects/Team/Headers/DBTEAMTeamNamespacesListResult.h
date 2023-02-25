///
/// Copyright (c) 2016 Dropbox, Inc. All rights reserved.
///
/// Auto-generated by Stone, do not modify.
///

#import <Foundation/Foundation.h>

#import "DBSerializableProtocol.h"

@class DBTEAMNamespaceMetadata;
@class DBTEAMTeamNamespacesListResult;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - API Object

///
/// The `TeamNamespacesListResult` struct.
///
/// Result for `namespacesList`.
///
/// This class implements the `DBSerializable` protocol (serialize and
/// deserialize instance methods), which is required for all Obj-C SDK API route
/// objects.
///
@interface DBTEAMTeamNamespacesListResult : NSObject <DBSerializable, NSCopying>

#pragma mark - Instance fields

/// List of all namespaces the team can access.
@property (nonatomic, readonly) NSArray<DBTEAMNamespaceMetadata *> *namespaces;

/// Pass the cursor into `namespacesListContinue` to obtain additional
/// namespaces. Note that duplicate namespaces may be returned.
@property (nonatomic, readonly, copy) NSString *cursor;

/// Is true if there are additional namespaces that have not been returned yet.
@property (nonatomic, readonly) NSNumber *hasMore;

#pragma mark - Constructors

///
/// Full constructor for the struct (exposes all instance variables).
///
/// @param namespaces List of all namespaces the team can access.
/// @param cursor Pass the cursor into `namespacesListContinue` to obtain
/// additional namespaces. Note that duplicate namespaces may be returned.
/// @param hasMore Is true if there are additional namespaces that have not been
/// returned yet.
///
/// @return An initialized instance.
///
- (instancetype)initWithNamespaces:(NSArray<DBTEAMNamespaceMetadata *> *)namespaces
                            cursor:(NSString *)cursor
                           hasMore:(NSNumber *)hasMore;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Serializer Object

///
/// The serialization class for the `TeamNamespacesListResult` struct.
///
@interface DBTEAMTeamNamespacesListResultSerializer : NSObject

///
/// Serializes `DBTEAMTeamNamespacesListResult` instances.
///
/// @param instance An instance of the `DBTEAMTeamNamespacesListResult` API
/// object.
///
/// @return A json-compatible dictionary representation of the
/// `DBTEAMTeamNamespacesListResult` API object.
///
+ (nullable NSDictionary *)serialize:(DBTEAMTeamNamespacesListResult *)instance;

///
/// Deserializes `DBTEAMTeamNamespacesListResult` instances.
///
/// @param dict A json-compatible dictionary representation of the
/// `DBTEAMTeamNamespacesListResult` API object.
///
/// @return An instantiation of the `DBTEAMTeamNamespacesListResult` object.
///
+ (DBTEAMTeamNamespacesListResult *)deserialize:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END

/*
	This file is part of the PolKit library.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <dirent.h>
#import <sys/stat.h>
#import <sys/attr.h>
#import <sys/xattr.h>

#import "DirectoryScanner.h"
#import "NSData+GZip.h"

#define kDataVersion						1
#define kDataMinVersion						1
#define kDataMaxVersion						kDataVersion

#define kPropertyListVersion				3
#define kPropertyListMinVersion				1
#define kPropertyListMaxVersion				kPropertyListVersion

#define kExtendedAttributesBufferSize		(128 * (XATTR_MAXNAMELEN + 1))

enum {
	kArray_Added = 0,
	kArray_Removed,
	kArray_Missing, //Must be (kArray_Removed + 1)
	kArray_ModifiedData,
	kArray_ModifiedMetadata,
	kArray_Moved,
	kArrayCount
};

typedef struct {
	uint16_t				mode;
	uint16_t				flags; //Only non-zero if "scanMetadata" is YES
	uint32_t				uid; //Only non-zero if "scanMetadata" is YES
	uint32_t				gid; //Only non-zero if "scanMetadata" is YES
	uint32_t				nodeID;
	uint32_t				revision;
	uint32_t				resourceSize; //Always zero for anything but regular files with a resource fork
	NSData*					userInfo;
	const char*				aclString; //Only non-NULL if "scanMetadata" is YES
	CFMutableDictionaryRef	extendedAttributes; //Only non-NULL if "scanMetadata" is YES
	uint64_t				dataSize; //Always zero for directories
	double					newDate, //Seconds since 1970
							modDate; //Seconds since 1970
} DirectoryItemData;

#pragma pack(push, 1)
typedef struct {
	uint16_t				mode;
	uint16_t				flags;
	uint32_t				uid;
	uint32_t				gid;
	uint32_t				nodeID;
	uint32_t				revision;
	uint32_t				resourceSize;
	uint32_t				userInfoPtr;
	uint32_t				aclStringPtr;
	uint32_t				extendedAttributesPtr;
	uint64_t				dataSize;
	double					newDate,
							modDate;
} DirectoryItemData32;
#pragma pack(pop)

#define IS_DIRECTORY(__DATA__) S_ISDIR((__DATA__)->mode)

#define ADD_PATH_TO_ARRAY(__ARRAY__, __PATH__) \
{ \
	CFStringRef string = CFStringCreateWithCString(kCFAllocatorDefault, (__PATH__), kCFStringEncodingUTF8); \
	[(__ARRAY__) addObject:(id)string]; \
	CFRelease(string); \
}

@interface DirectoryItem ()
@property(nonatomic, readonly) uint32_t nodeID;
- (id) initWithPath:(const char*)string data:(DirectoryItemData*)data;
- (void) setPath:(NSString*)path;
@end

@interface DirectoryScanner ()
@property(nonatomic, readonly, nonatomic) CFMutableDictionaryRef _directories;
- (NSInteger) _scanSubdirectory:(const char*)subPath fromRootDirectory:(const char*)rootDirectory directories:(CFMutableDictionaryRef)directories excludedPaths:(NSMutableArray*)excludedPaths errorPaths:(NSMutableArray*)errorPaths;
- (NSDictionary*) _scanRootDirectory:(BOOL)compare bumpRevision:(BOOL)bumpRevision detectMovedItems:(BOOL)detectMovedItems reportAllRemovedItems:(BOOL)reportAllRemovedItems;
@end

static void _DirectoryItemDataReleaseCallback(CFAllocatorRef allocator, const void* value)
{
	DirectoryItemData*		data = (DirectoryItemData*)value;
	
	if(data->aclString)
	free((void*)data->aclString);
	
	if(data->extendedAttributes)
	CFRelease(data->extendedAttributes);
	
	if(data->userInfo)
	[data->userInfo release];
	
	free((void*)value);
}

static void _FreeReleaseCallBack(CFAllocatorRef allocator, const void* value)
{
	free((void*)value);
}

static Boolean _XATTREqualCallBack(const void* value1, const void* value2)
{
	unsigned int			size1 = *((unsigned int*)value1),
							size2 = *((unsigned int*)value2);
	
	return ((size1 == size2) && (memcmp((char*)value1 + sizeof(unsigned int), (char*)value2 + sizeof(unsigned int), size1) == 0));
}

static inline char* _CopyCString(const char* string)
{
	size_t					length;
	void*					buffer;
	
	length = strlen(string) + 1;
	buffer = malloc(length);
	bcopy(string, buffer, length);
	
	return buffer;
}

static const void* _UTF8StringRetainCallBack(CFAllocatorRef allocator, const void* value)
{
	return _CopyCString(value);
}

static CFStringRef _UTF8StringCopyDescriptionCallBack(const void* value)
{
	return CFStringCreateWithBytes(kCFAllocatorDefault, value, strlen(value), kCFStringEncodingUTF8, false);
}

static Boolean _UTF8StringCaseSensitiveEqualCallBack(const void *value1, const void *value2)
{
	return (strcmp(value1, value2) == 0);
}

/* djb2 C string hash function */
static CFHashCode _UTF8StringHashCallBack(const void* value)
{
	const unsigned char* str = value;
	CFHashCode hash = 5381;
	int c;
	
	while((c = *str++))
	hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

	return hash;
}

static const CFDictionaryKeyCallBacks _UTF8KeyCallbacks = {0, _UTF8StringRetainCallBack, _FreeReleaseCallBack, _UTF8StringCopyDescriptionCallBack, _UTF8StringCaseSensitiveEqualCallBack, _UTF8StringHashCallBack};
static const CFDictionaryValueCallBacks	_XATTRValueCallbacks = {0, NULL, _FreeReleaseCallBack, NULL, _XATTREqualCallBack};

static DirectoryItemData* _CreateDirectoryItemData(const char* fullPath, const struct stat* stats, BOOL includeMetadata, NSUInteger revision, char* xattrBuffer)
{
	DirectoryItemData*			data = malloc(sizeof(DirectoryItemData));
	char						buffer[sizeof(uint32_t) + sizeof(struct timespec)];
	acl_t						acls;
	char*						aclString;
	ssize_t						xattrLength,
								xattrSize,
								xattrOffset;
	void*						xattrValue;
	ssize_t						resourceSize;
	struct attrlist				list;
	const struct timespec*		time;
	
	data->mode = stats->st_mode;
	data->nodeID = stats->st_ino;
	data->modDate = (double)stats->st_mtimespec.tv_sec + (double)stats->st_mtimespec.tv_nsec / 1000000000.0;
	data->dataSize = (S_ISDIR(stats->st_mode) ? 0 : stats->st_size);
	data->revision = revision;
	data->userInfo = nil;
	
	bzero(&list, sizeof(struct attrlist));
	list.bitmapcount = ATTR_BIT_MAP_COUNT;
	list.commonattr = ATTR_CMN_CRTIME;
	if(getattrlist(fullPath, &list, buffer, sizeof(buffer), FSOPT_NOFOLLOW) == 0)
	time = (const struct timespec*)&buffer[sizeof(uint32_t)];
	else {
		NSLog(@"%s: getattrlist() for 'ATTR_CMN_CRTIME' on \"%s\" failed with error \"%s\"", __FUNCTION__, fullPath, strerror(errno));
		time = &stats->st_ctimespec;
	}
	data->newDate = (double)time->tv_sec + (double)time->tv_nsec / 1000000000.0;
	
	if(S_ISREG(stats->st_mode)) {
		resourceSize = getxattr(fullPath, XATTR_RESOURCEFORK_NAME, NULL, 0, 0, XATTR_NOFOLLOW);
		if(resourceSize >= 0)
		data->resourceSize = resourceSize;
		else {
			if(errno != ENOATTR)
			NSLog(@"%s: getxattr() for 'XATTR_RESOURCEFORK_NAME' on \"%s\" failed with error \"%s\"", __FUNCTION__, fullPath, strerror(errno));
			data->resourceSize = 0;
		}
	}
	else
	data->resourceSize = 0;
	
	if(includeMetadata) {
		data->uid = stats->st_uid;
		data->gid = stats->st_gid;
		data->flags = stats->st_flags & UF_SETTABLE;
		
		if((acls = acl_get_file(fullPath, ACL_TYPE_EXTENDED))) {
			aclString = acl_to_text(acls, NULL);
			if(aclString) {
				data->aclString = _CopyCString(aclString);
				acl_free(aclString);
			}
			else {
				NSLog(@"%s: acl_to_text() on \"%s\" failed with error \"%s\"", __FUNCTION__, fullPath, strerror(errno));
				free(data);
				data = NULL;
			}
			acl_free(acls);
		}
		else {
			if(errno != ENOENT) {
				NSLog(@"%s: acl_get_file() on \"%s\" failed with error \"%s\"", __FUNCTION__, fullPath, strerror(errno));
				free(data);
				data = NULL;
			}
			else
			data->aclString = NULL;
		}
		
		if(data) {
			xattrLength = listxattr(fullPath, xattrBuffer, kExtendedAttributesBufferSize, XATTR_NOFOLLOW);
			if(xattrLength > 0) {
				data->extendedAttributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &_XATTRValueCallbacks);
				xattrOffset = 0;
				while(xattrOffset < xattrLength) {
					if((strcmp(&xattrBuffer[xattrOffset], XATTR_RESOURCEFORK_NAME) != 0) && (strncmp(&xattrBuffer[xattrOffset], "_kTimeMachine", 13) != 0)) { //HACK: Ignore resource fork and Time Machine attributes
						xattrSize = getxattr(fullPath, &xattrBuffer[xattrOffset], NULL, 0, 0, XATTR_NOFOLLOW);
						if(xattrSize >= 0) {
							xattrValue = malloc(sizeof(unsigned int) + xattrSize);
							*((unsigned int*)xattrValue) = xattrSize;
							xattrSize = getxattr(fullPath, &xattrBuffer[xattrOffset], (char*)xattrValue + sizeof(unsigned int), xattrSize, 0, XATTR_NOFOLLOW);
							if(xattrSize == *((unsigned int*)xattrValue))
							CFDictionarySetValue(data->extendedAttributes, &xattrBuffer[xattrOffset], xattrValue);
							else
							free(xattrValue);
						}
						if(xattrSize < 0) {
							NSLog(@"%s: getxattr() for '%s' on \"%s\" failed with error \"%s\"", __FUNCTION__, &xattrBuffer[xattrOffset], fullPath, strerror(errno));
							CFRelease(data->extendedAttributes);
							if(data->aclString)
							free((void*)data->aclString);
							free(data);
							data = NULL;
							break;
						}
					}
					xattrOffset += strlen(&xattrBuffer[xattrOffset]) + 1;
				}
			}
			else if(xattrLength < 0) {
				NSLog(@"%s: listxattr() on \"%s\" failed with error \"%s\"", __FUNCTION__, fullPath, strerror(errno));
				if(data->aclString)
				free((void*)data->aclString);
				free(data);
				data = NULL;
			}
			else
			data->extendedAttributes = NULL;
		}
	}
	else {
		data->mode &= ~ALLPERMS;
		data->uid = 0;
		data->gid = 0;
		data->flags = 0;
		data->aclString = NULL;
		data->extendedAttributes = NULL;
	}
	
	return data;
}

@implementation DirectoryItem

@synthesize path=_path, revision=_revision, creationDate=_creationDate, modificationDate=_modificationDate, dataSize=_dataSize, resourceSize=_resourceSize, nodeID=_nodeID, userInfo=_userInfo, userID=_userID, groupID=_groupID, userFlags=_flags, ACLText=_aclString, extendedAttributes=_attributes;

static NSComparisonResult _SortFunction_Paths(NSString* path1, NSString* path2, void* context)
{
	return [path1 compare:path2 options:(NSCaseInsensitiveSearch | NSNumericSearch | NSForcedOrderingSearch)];
}

static NSComparisonResult _SortFunction_DirectoryItem(DirectoryItem* item1, DirectoryItem* item2, void* context)
{
	return [item1->_path compare:item2->_path options:(NSCaseInsensitiveSearch | NSNumericSearch | NSForcedOrderingSearch)];
}

static void _DictionaryApplierFunction_ConvertExtendedAttributes(const void* key, const void* value, void* context)
{
	unsigned int				size = *((unsigned int*)value);
	CFStringRef					keyString;
	NSData*						data;
	
	keyString = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
	data = [[NSData alloc] initWithBytes:((char*)value + sizeof(unsigned int)) length:size];
	[(NSMutableDictionary*)context setObject:data forKey:(id)keyString];
	[data release];
	CFRelease(keyString);
}

- (id) initWithPath:(const char*)string data:(DirectoryItemData*)data
{
	if((self = [super init])) {
		_nodeID = data->nodeID;
		_mode = data->mode;
		_flags = data->flags;
		_userID = data->uid;
		_groupID = data->gid;
		_path = [[NSString alloc] initWithUTF8String:string];
		_revision = data->revision;
		_resourceSize = data->resourceSize;
		_creationDate = data->newDate - kCFAbsoluteTimeIntervalSince1970;
		_modificationDate = data->modDate - kCFAbsoluteTimeIntervalSince1970;
		_dataSize = data->dataSize;
		_userInfo = [data->userInfo retain];
		
		if(data->aclString)
		_aclString = [[NSString alloc] initWithUTF8String:data->aclString];
		
		if(data->extendedAttributes) {
			_attributes = [NSMutableDictionary new];
			CFDictionaryApplyFunction(data->extendedAttributes, _DictionaryApplierFunction_ConvertExtendedAttributes, _attributes);
		}
	}
	
	return self;
}

- (void) dealloc
{
	[_userInfo release];
	[_attributes release];
	[_aclString release];
	[_path release];
	
	[super dealloc];
}

- (void) setPath:(NSString*)path
{
	if(path != _path) {
		[_path release];
		_path = [path copy];
	}
}

- (BOOL) isDirectory
{
	return S_ISDIR(_mode);
}

- (BOOL) isSymbolicLink
{
	return S_ISLNK(_mode);
}

- (unsigned short) permissions
{
	return (_mode & ALLPERMS);
}

- (BOOL) isEqual:(id)object
{
	return ([object isKindOfClass:[DirectoryItem class]] && [_path isEqual:((DirectoryItem*)object)->_path]);
}

- (NSUInteger) hash
{
	return [_path hash];
}

- (BOOL) isEqualToDirectoryItem:(DirectoryItem*)otherItem compareMetadata:(BOOL)flag
{
	if(_nodeID != otherItem->_nodeID)
	return NO;
	
	if((_modificationDate != otherItem->_modificationDate) || (_creationDate != otherItem->_creationDate))
	return NO;
	
	if(flag) {
		if((_userID != otherItem->_userID) || (_groupID != otherItem->_groupID) || (_mode != otherItem->_mode) || (_flags != otherItem->_flags))
		return NO;
		
		if((_aclString && !otherItem->_aclString) || (!_aclString && otherItem->_aclString) || (_aclString && otherItem->_aclString && ![_aclString isEqualToString:otherItem->_aclString]))
		return NO;
		
		if((_attributes && !otherItem->_attributes) || (!_attributes && otherItem->_attributes) || (_attributes && otherItem->_attributes && ![_attributes isEqualToDictionary:otherItem->_attributes]))
		return NO;
	}
	
	return YES;
}

- (unsigned long long) totalSize
{
	unsigned long long			size = _dataSize + _resourceSize;
	NSString*					key;
	
	for(key in _attributes)
	size += [[_attributes objectForKey:key] length];
	
	return size;
}

- (NSString*) description
{
	return ([self isDirectory] ? [NSString stringWithFormat:@"[%i - %p] %@/", _revision, _userInfo, _path] : [NSString stringWithFormat:@"[%i - %p] %@ (%qu:%i bytes)", _revision, _userInfo, _path, _dataSize, _resourceSize]);
}

@end

@implementation DirectoryScanner

@synthesize rootDirectory=_rootDirectory, scanningMetadata=_scanMetadata, sortPaths=_sortPaths, reportExcludedHiddenItems=_reportHidden, excludeHiddenItems=_excludeHidden, excludeDSStoreFiles=_excludeDSStore, exclusionPredicate=_exclusionPredicate, revision=_revision, _directories=_directories, delegate=_delegate;

+ (NSPredicate*) exclusionPredicateWithPaths:(NSArray*)paths names:(NSArray*)names
{
	NSMutableArray*				predicates = [NSMutableArray array];
	NSExpression*				expression;
	NSString*					string;
	NSMutableArray*				array;
	
	if(![paths count] && ![names count])
	return nil;
	
	if([paths count]) {
		expression = [NSExpression expressionForVariable:@"PATH"];
		for(string in paths) {
			array = [NSMutableArray new];
			[array addObject:[NSComparisonPredicate predicateWithLeftExpression:expression rightExpression:[NSExpression expressionForConstantValue:string] modifier:NSDirectPredicateModifier type:NSInPredicateOperatorType options:NSCaseInsensitivePredicateOption]];
			[array addObject:[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:string] rightExpression:expression modifier:NSDirectPredicateModifier type:NSInPredicateOperatorType options:NSCaseInsensitivePredicateOption]];
			[predicates addObject:[NSCompoundPredicate andPredicateWithSubpredicates:array]];
			[array release];
		}
	}
	
	if([names count]) {
		expression = [NSExpression expressionForVariable:@"NAME"];
		for(string in names) {
			array = [NSMutableArray new];
			[array addObject:[NSComparisonPredicate predicateWithLeftExpression:expression rightExpression:[NSExpression expressionForConstantValue:string] modifier:NSDirectPredicateModifier type:NSInPredicateOperatorType options:NSCaseInsensitivePredicateOption]];
			[array addObject:[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:string] rightExpression:expression modifier:NSDirectPredicateModifier type:NSInPredicateOperatorType options:NSCaseInsensitivePredicateOption]];
			[predicates addObject:[NSCompoundPredicate andPredicateWithSubpredicates:array]];
			[array release];
		}
	}
	
	return [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
}

+ (DirectoryItem*) directoryItemAtPath:(NSString*)path includeMetadata:(BOOL)includeMetadata
{
	DirectoryItemData*			data;
	const char*					fullPath;
	struct stat					stats;
	char*						buffer;
	DirectoryItem*				item;
	
	path = [path stringByStandardizingPath];
	fullPath = [path UTF8String];
	if(fullPath == NULL)
	return nil;
	
	if(lstat(fullPath, &stats) != 0) {
		NSLog(@"%s: lstat() on \"%s\" failed with error \"%s\"", __FUNCTION__, fullPath, strerror(errno));
		return nil;
	}
	
	buffer = malloc(kExtendedAttributesBufferSize);
	data = _CreateDirectoryItemData(fullPath, &stats, includeMetadata, 0, buffer);
	free(buffer);
	if(data == NULL)
	return nil;
	item = [[DirectoryItem alloc] initWithPath:fullPath data:data];
	_DirectoryItemDataReleaseCallback(NULL, data);
	
	return [item autorelease];
}

- (id) initWithRootDirectory:(NSString*)rootDirectory scanMetadata:(BOOL)scanMetadata
{
	if(rootDirectory == nil) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_rootDirectory = [rootDirectory copy];
		_scanMetadata = scanMetadata;
		
		_root = NULL;
		_directories = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &kCFTypeDictionaryValueCallBacks);
		_info = [NSMutableDictionary new];
		if(_scanMetadata)
		_xattrBuffer = malloc(kExtendedAttributesBufferSize);
		_revision = 0;
	}
	
	return self;
}

- (void) _cleanUp_DirectoryScanner
{
	if(_xattrBuffer)
	free(_xattrBuffer);
	if(_directories)
	CFRelease(_directories);
	if(_root)
	_DirectoryItemDataReleaseCallback(NULL, _root);
}

- (void) finalize
{
	[self _cleanUp_DirectoryScanner];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_DirectoryScanner];
	
	[_exclusionPredicate release];
	[_info release];
	[_rootDirectory release];
	
	[super dealloc];
}

- (void) setUserInfo:(id)info forKey:(NSString*)key
{
	[_info setValue:info forKey:key];
}

- (id) userInfoForKey:(NSString*)key
{
	return [_info valueForKey:key];
}

static void _DictionaryApplierFunction_DescriptionLeaf(const void* key, const void* value, void* context)
{
	DirectoryItemData*			data = (DirectoryItemData*)value;
	NSString*					string;
	CFStringRef					keyString;
	
	keyString = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
	if(IS_DIRECTORY(data))
	string = [[NSString alloc] initWithFormat:@"[%i - %p] %@/", data->revision, data->userInfo, keyString];
	else
	string = [[NSString alloc] initWithFormat:@"[%i - %p] %@ (%qu:%i bytes)", data->revision, data->userInfo, keyString, data->dataSize, data->resourceSize];
	
	[(NSMutableArray*)context addObject:string];
	
	[string release];
	CFRelease(keyString);
}

static void _DictionaryApplierFunction_DescriptionTrunk(const void* key, const void* value, void* context)
{
	CFDictionaryRef				entries = (CFDictionaryRef)value;
	NSMutableArray*				array;
	CFStringRef					keyString;
	
	keyString = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
	array = [[NSMutableArray alloc] initWithCapacity:CFDictionaryGetCount(entries)];
	
	CFDictionaryApplyFunction(entries, _DictionaryApplierFunction_DescriptionLeaf, array);
	[(NSMutableDictionary*)context setObject:array forKey:(id)keyString];
	
	[array release];
	CFRelease(keyString);
}

- (NSString*) description
{
	NSMutableDictionary*		items = [NSMutableDictionary dictionary];
	
	CFDictionaryApplyFunction(_directories, _DictionaryApplierFunction_DescriptionTrunk, items);
	
	return [items description];
}

- (NSInteger) _scanSubdirectory:(const char*)subPath fromRootDirectory:(const char*)rootDirectory directories:(CFMutableDictionaryRef)directories excludedPaths:(NSMutableArray*)excludedPaths errorPaths:(NSMutableArray*)errorPaths
{
	CFDictionaryValueCallBacks	itemValueCallbacks = {0, NULL, _DirectoryItemDataReleaseCallback, NULL, NULL};
	NSMutableDictionary*		variables = nil;
	NSInteger					result = 0;
	CFMutableDictionaryRef		dictionary;
	char						buffer[PATH_MAX];
	char*						fullPath;
	size_t						rootLength,
								fullLength;
	struct dirent				storage;
	struct dirent*				dirent;
	struct stat					stats;
	DirectoryItemData*			data;
	size_t						nameLength;
	DIR*						dir;
	CFTypeRef					value;
	int							type;
	CFNumberRef					typeNumbers[3];
	
	if(_delegate && [_delegate shouldAbortScanning:self])
	return -1;
	
	rootLength = strlen(rootDirectory);
	if(subPath[0] != 0) {
		fullLength = rootLength + strlen(subPath) + 1;
		fullPath = malloc(fullLength + __DARWIN_MAXNAMLEN + 3);
		bcopy(rootDirectory, fullPath, rootLength);
		fullPath[rootLength] = '/';
		bcopy(subPath, &fullPath[rootLength + 1], fullLength - rootLength);
	}
	else {
		fullLength = rootLength;
		fullPath = malloc(fullLength + __DARWIN_MAXNAMLEN + 2);
		bcopy(rootDirectory, fullPath, rootLength + 1);
	}
	
	if((dir = opendir(fullPath))) {
		fullPath[fullLength++] = '/';
		
		if(_exclusionPredicate) {
			variables = [NSMutableDictionary new];
			type = 0;
			typeNumbers[0] =  CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &type);
			type = 1;
			typeNumbers[1] =  CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &type);
			type = 2;
			typeNumbers[2] =  CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &type);
		}
		
		dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &itemValueCallbacks);
		while(1) {
			if(readdir_r(dir, &storage, &dirent) != 0) {
				CFRelease(dictionary);
				dictionary = NULL;
				break;
			}
			if(dirent == NULL)
			break;
			if((dirent->d_name[0] == '.') && (dirent->d_name[1] == 0))
			continue;
			if((dirent->d_name[0] == '.') && (dirent->d_name[1] == '.') && (dirent->d_name[2] == 0))
			continue;
			
			nameLength = strlen(dirent->d_name);
			bcopy(dirent->d_name, &fullPath[fullLength], nameLength + 1);
			
			if(dirent->d_name[0] == '.') {
				do {
					if(dirent->d_name[1] == '_') { //NOTE: Ignore AppleDouble system files
						dirent->d_name[0] = 0;
						break;
					}
					if(strncmp(dirent->d_name, ".afpDeleted", 11) == 0) { //NOTE: Ignore "open-delete" files on AFP servers
						dirent->d_name[0] = 0;
						break;
					}
					if(_excludeHidden) {
						dirent->d_name[0] = 0;
						break;
					}
					if(_excludeDSStore && (strcmp(dirent->d_name, ".DS_Store") == 0)) {
						dirent->d_name[0] = 0;
						break;
					}
				} while(0);
				if(dirent->d_name[0] == 0) {
					if(_reportHidden)
					ADD_PATH_TO_ARRAY(excludedPaths, &fullPath[rootLength + 1]);
					continue;
				}
			}
			
			if(lstat(fullPath, &stats) == 0) {
				if(!S_ISDIR(stats.st_mode) && !S_ISREG(stats.st_mode) && !S_ISLNK(stats.st_mode)) {
					ADD_PATH_TO_ARRAY(errorPaths, &fullPath[rootLength + 1]);
					continue;
				}
				
				if(_excludeHidden && (stats.st_flags & UF_HIDDEN)) {
					ADD_PATH_TO_ARRAY(excludedPaths, &fullPath[rootLength + 1]);
					continue;
				}
				
				if(_exclusionPredicate) {
					value = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, &fullPath[rootLength + 1], kCFStringEncodingUTF8, kCFAllocatorNull);
					[variables setObject:(id)value forKey:@"PATH"];
					CFRelease(value);
					value = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, dirent->d_name, kCFStringEncodingUTF8, kCFAllocatorNull);
					[variables setObject:(id)value forKey:@"NAME"];
					CFRelease(value);
					type = (S_ISDIR(stats.st_mode) ? 0 : (S_ISREG(stats.st_mode) ? 1 : 2));
					[variables setObject:(id)typeNumbers[type] forKey:@"TYPE"];
					if(S_ISREG(stats.st_mode))
					value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &stats.st_size); //FIXME: This is only data fork size
					else
					value = CFRetain(kCFNumberNaN); //FIXME: -[NSPredicate -evaluateWithObject:substitutionVariables:] can return invalid result for NAN variable (radr://6755236)
					[variables setObject:(id)value forKey:@"FILE_SIZE"];
					CFRelease(value);
					value = CFDateCreate(kCFAllocatorDefault, (double)stats.st_ctimespec.tv_sec + (double)stats.st_ctimespec.tv_nsec / 1000000000.0 - kCFAbsoluteTimeIntervalSince1970);
					[variables setObject:(id)value forKey:@"DATE_MODIFIED"];
					CFRelease(value);
					value = CFDateCreate(kCFAllocatorDefault, (double)stats.st_mtimespec.tv_sec + (double)stats.st_mtimespec.tv_nsec / 1000000000.0 - kCFAbsoluteTimeIntervalSince1970);
					[variables setObject:(id)value forKey:@"DATE_CREATED"];
					CFRelease(value);
					if([_exclusionPredicate evaluateWithObject:nil substitutionVariables:variables]) {
						ADD_PATH_TO_ARRAY(excludedPaths, &fullPath[rootLength + 1]);
						continue;
					}
				}
				
				if(S_ISDIR(stats.st_mode)) {
					result = [self _scanSubdirectory:&fullPath[rootLength + 1] fromRootDirectory:rootDirectory directories:directories excludedPaths:excludedPaths errorPaths:errorPaths];
					if(result < 0) {
						CFRelease(dictionary);
						dictionary = NULL;
						break;
					}
					if(result == 0)
					continue;
				}
				else if(_scanMetadata) {
					if(!S_ISLNK(stats.st_mode) && (access(fullPath, R_OK) != 0)) {
						ADD_PATH_TO_ARRAY(errorPaths, &fullPath[rootLength + 1]);
						continue;
					}
					else if(S_ISLNK(stats.st_mode) && (readlink(fullPath, buffer, PATH_MAX) < 0)) { //FIXME: Is this the best to emulate laccess()?
						ADD_PATH_TO_ARRAY(errorPaths, &fullPath[rootLength + 1]);
						continue;
					}
				}
				
				data = _CreateDirectoryItemData(fullPath, &stats, _scanMetadata, _revision, _xattrBuffer);
				if(data)
				CFDictionarySetValue(dictionary, dirent->d_name, data);
				else
				ADD_PATH_TO_ARRAY(errorPaths, &fullPath[rootLength + 1]);
			}
			else
			ADD_PATH_TO_ARRAY(errorPaths, &fullPath[rootLength + 1]);
		}
		if(dictionary) {
			CFDictionarySetValue(directories, subPath, dictionary);
			CFRelease(dictionary);
			result = 1;
		}
		
		if(_exclusionPredicate) {
			CFRelease(typeNumbers[0]);
			CFRelease(typeNumbers[1]);
			CFRelease(typeNumbers[2]);
			[variables release];
		}
		
		closedir(dir);
	}
	
	if(result == 0)
	ADD_PATH_TO_ARRAY(errorPaths, subPath);
	
	free(fullPath);
	
	return result;
}

static void _DictionaryApplierFunction_Subprune(const void* key, const void* value, void* context)
{
	void**							params = (void**)context;
	DirectoryItem*					info;
	
	bcopy(key, (char*)params[1] + (long)params[2], strlen(key) + 1);
	
	info = [[DirectoryItem alloc] initWithPath:params[1] data:(DirectoryItemData*)value];
	[(NSMutableArray*)params[0] addObject:info];
	[info release];
}

static void _DictionaryApplierFunction_Prune(const void* key, const void* value, void* context)
{
	void**							params = (void**)context;
	void*							subParams[3];
	char*							buffer;
	size_t							length;
	
	if(!CFSetContainsValue(params[0], key)) {
		length = strlen(key);
		buffer = malloc(length + __DARWIN_MAXNAMLEN + 2);
		bcopy(key, buffer, length);
		buffer[length++] = '/';
		
		subParams[0] = params[1];
		subParams[1] = buffer;
		subParams[2] = (void*)(long)length;
		CFDictionaryApplyFunction(value, _DictionaryApplierFunction_Subprune, subParams);
		
		free(buffer);
	}
}

static void _DictionaryApplierFunction_Subadd(const void* key, const void* value, void* context)
{
	void**							params = (void**)context;
	DirectoryItemData*				data = (DirectoryItemData*)value;
	DirectoryItem*					info;
	
	if(params[3])
	data->revision = (long)params[3];
	
	bcopy(key, (char*)params[1] + (long)params[2], strlen(key) + 1);
	
	info = [[DirectoryItem alloc] initWithPath:params[1] data:data];
	[(NSMutableArray*)params[0] addObject:info];
	[info release];
}

static void _DictionaryApplierFunction_Subremove(const void* key, const void* value, void* context)
{
	void**							params = (void**)context;
	DirectoryItem*					info;
	
	if(!CFSetContainsValue(params[1], key)) {
		bcopy(key, (char*)params[2] + (long)params[3], strlen(key) + 1);
		
		info = [[DirectoryItem alloc] initWithPath:params[2] data:(DirectoryItemData*)value];
		[(NSMutableArray*)params[0] addObject:info];
		[info release];
	}
}

static inline BOOL _ItemContentsWasModified(DirectoryItemData* oldData, DirectoryItemData* newData)
{
	if((newData->mode & S_IFMT) != (oldData->mode & S_IFMT))
	return YES;
	
	if(!IS_DIRECTORY(newData) && (round(newData->modDate * 1000.0) != round(oldData->modDate * 1000.0))) //NOTE: Use a 1ms tolerance
	return YES;
	
	return NO;
}

static inline BOOL _ItemMetadataHasChanged(DirectoryItemData* oldData, DirectoryItemData* newData)
{
	if(round(newData->newDate * 1000.0) != round(oldData->newDate * 1000.0)) //NOTE: Use a 1ms tolerance
	return YES;
	
	if(((newData->mode & ALLPERMS) != (oldData->mode & ALLPERMS)) || (newData->flags != oldData->flags) || (newData->uid != oldData->uid) || (newData->gid != oldData->gid))
	return YES;
	
	if((newData->aclString && !oldData->aclString) || (!newData->aclString && oldData->aclString) || (newData->aclString && oldData->aclString && strcmp(newData->aclString, oldData->aclString)))
	return YES;
	
	if((newData->extendedAttributes && !oldData->extendedAttributes) || (!newData->extendedAttributes && oldData->extendedAttributes) || (newData->extendedAttributes && oldData->extendedAttributes && !CFEqual(newData->extendedAttributes, oldData->extendedAttributes)))
	return YES;
	
	return NO;
}

static void _DictionaryApplierFunction_Subcompare(const void* key, const void* value, void* context)
{
	void**							params = (void**)context;
	NSMutableArray**				arrays = params[0];
	DirectoryItemData*				newData = (DirectoryItemData*)value;
	DirectoryItemData*				oldData = (DirectoryItemData*)CFDictionaryGetValue(params[1], key);
	DirectoryItem*					info;
	
	bcopy(key, (char*)params[3] + (long)params[4], strlen(key) + 1);
	
	if(oldData) {
		if(params[5])
		newData->userInfo = [oldData->userInfo retain];
		
		if(_ItemContentsWasModified(oldData, newData)) {
			if(params[5])
			newData->revision = (long)params[5];
			
			info = [[DirectoryItem alloc] initWithPath:params[3] data:newData];
			[arrays[kArray_ModifiedData] addObject:info];
			[info release];
		}
		else if(params[6] && _ItemMetadataHasChanged(oldData, newData)) {
			if(params[5])
			newData->revision = (long)params[5];
			
			info = [[DirectoryItem alloc] initWithPath:params[3] data:newData];
			[arrays[kArray_ModifiedMetadata] addObject:info];
			[info release];
		}
		else if(params[5])
		newData->revision = oldData->revision;
		
		CFSetAddValue((CFMutableSetRef)params[2], key);
	}
	else {
		if(params[5])
		newData->revision = (long)params[5];
		
		info = [[DirectoryItem alloc] initWithPath:params[3] data:newData];
		[arrays[kArray_Added] addObject:info];
		[info release];
	}
}

static void _DictionaryApplierFunction_Compare(const void* key, const void* value, void* context)
{
	CFSetCallBacks					callbacks = {0, NULL, NULL, NULL, _UTF8StringCaseSensitiveEqualCallBack, _UTF8StringHashCallBack};
	void**							params = (void**)context;
	NSMutableArray**				arrays = params[0];
	CFMutableDictionaryRef			newDirectory = (CFMutableDictionaryRef)value;
	CFMutableDictionaryRef			oldDirectory = (CFMutableDictionaryRef)CFDictionaryGetValue(params[1], key);
	void*							subParams[7];
	char*							buffer;
	size_t							length;
	CFMutableSetRef					set;
	
	length = strlen(key);
	buffer = malloc(length + __DARWIN_MAXNAMLEN + 2);
	bcopy(key, buffer, length);
	if(length)
	buffer[length++] = '/';
	
	if(oldDirectory) {
		set = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
		
		subParams[0] = arrays;
		subParams[1] = oldDirectory;
		subParams[2] = set;
		subParams[3] = buffer;
		subParams[4] = (void*)(long)length;
		subParams[5] = params[2];
		subParams[6] = params[4];
		CFDictionaryApplyFunction(newDirectory, _DictionaryApplierFunction_Subcompare, subParams);
		
		subParams[0] = arrays[kArray_Removed];
		subParams[1] = set;
		subParams[2] = buffer;
		subParams[3] = (void*)(long)length;
		CFDictionaryApplyFunction(oldDirectory, _DictionaryApplierFunction_Subremove, subParams);
		
		CFRelease(set);
		
		if(params[3])
		CFSetAddValue((CFMutableSetRef)params[3], key);
	}
	else {
		subParams[0] = arrays[kArray_Added];
		subParams[1] = buffer;
		subParams[2] = (void*)(long)length;
		subParams[3] = params[2];
		CFDictionaryApplyFunction(value, _DictionaryApplierFunction_Subadd, subParams);
	}
	
	free(buffer);
}

static NSMutableDictionary* _CompareDirectories(CFDictionaryRef newDirectories, CFDictionaryRef oldDirectories, BOOL compareMetadata, BOOL detectMovedItems, BOOL reportAllRemovedItems, NSUInteger revision, BOOL sortPaths)
{
	CFSetCallBacks					callbacks = {0, NULL, NULL, NULL, _UTF8StringCaseSensitiveEqualCallBack, _UTF8StringHashCallBack};
	NSMutableDictionary*			dictionary = [NSMutableDictionary dictionary];
	NSMutableArray*					arrays[kArrayCount];
	NSInteger						i;
	void*							params[5];
	DirectoryItem*					removedItem;
	DirectoryItem*					addedItem;
	NSUInteger						removedCount,
									removedIndex,
									addedCount,
									addedIndex;
	CFMutableSetRef					set;
	
	for(i = 0; i < kArrayCount; ++i)
	arrays[i] = [NSMutableArray array];
	
	if(detectMovedItems || reportAllRemovedItems)
	set = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
	else
	set = NULL;
	
	params[0] = arrays;
	params[1] = (void*)oldDirectories;
	params[2] = (void*)(long)revision;
	params[3] = set;
	params[4] = (void*)(long)compareMetadata;
	CFDictionaryApplyFunction(newDirectories, _DictionaryApplierFunction_Compare, params);
	
	if(reportAllRemovedItems) {
		params[0] = set;
		params[1] = arrays[kArray_Removed];
		CFDictionaryApplyFunction(oldDirectories, _DictionaryApplierFunction_Prune, params);
	}
	
	if(detectMovedItems) {
		params[0] = set;
		params[1] = arrays[kArray_Missing];
		CFDictionaryApplyFunction(oldDirectories, _DictionaryApplierFunction_Prune, params);
	}
	
	if(set)
	CFRelease(set);
	
	if(detectMovedItems) {
		for(i = kArray_Missing; i >= kArray_Removed; --i) {
			for(removedIndex = 0, removedCount = [arrays[i] count]; removedIndex < removedCount; ++removedIndex) {
				removedItem = [arrays[i] objectAtIndex:removedIndex];
				for(addedIndex = 0, addedCount = [arrays[kArray_Added] count]; addedIndex < addedCount; ++addedIndex) {
					addedItem = [arrays[kArray_Added] objectAtIndex:addedIndex];
					if([addedItem isEqualToDirectoryItem:removedItem compareMetadata:compareMetadata]) {
						[addedItem setPath:[NSString stringWithFormat:@"%@:%@", [removedItem path], [addedItem path]]];
						[arrays[kArray_Moved] addObject:addedItem];
						
						[arrays[i] removeObjectAtIndex:removedIndex];
						removedIndex -= 1;
						removedCount -= 1;
						
						[arrays[kArray_Added] removeObjectAtIndex:addedIndex];
						break;
					}
				}
			}
		}
		
		if([arrays[kArray_Moved] count]) {
			if(sortPaths)
			[arrays[kArray_Moved] sortUsingFunction:_SortFunction_DirectoryItem context:NULL];
			[dictionary setObject:arrays[kArray_Moved] forKey:kDirectoryScannerResultKey_MovedItems];
		}
	}
	
	if([arrays[kArray_Added] count]) {
		if(sortPaths)
		[arrays[kArray_Added] sortUsingFunction:_SortFunction_DirectoryItem context:NULL];
		[dictionary setObject:arrays[kArray_Added] forKey:kDirectoryScannerResultKey_AddedItems];
	}
	if([arrays[kArray_Removed] count]) {
		if(sortPaths)
		[arrays[kArray_Removed] sortUsingFunction:_SortFunction_DirectoryItem context:NULL];
		[dictionary setObject:arrays[kArray_Removed] forKey:kDirectoryScannerResultKey_RemovedItems];
	}
	if([arrays[kArray_ModifiedData] count]) {
		if(sortPaths)
		[arrays[kArray_ModifiedData] sortUsingFunction:_SortFunction_DirectoryItem context:NULL];
		[dictionary setObject:arrays[kArray_ModifiedData] forKey:kDirectoryScannerResultKey_ModifiedItems_Data];
	}
	if([arrays[kArray_ModifiedMetadata] count]) {
		if(sortPaths)
		[arrays[kArray_ModifiedMetadata] sortUsingFunction:_SortFunction_DirectoryItem context:NULL];
		[dictionary setObject:arrays[kArray_ModifiedMetadata] forKey:kDirectoryScannerResultKey_ModifiedItems_Metadata];
	}
	
	return dictionary;
}

- (NSDictionary*) _scanRootDirectory:(BOOL)compare bumpRevision:(BOOL)bumpRevision detectMovedItems:(BOOL)detectMovedItems reportAllRemovedItems:(BOOL)reportAllRemovedItems
{
	NSMutableArray*					excludedPaths = [NSMutableArray array];
	NSMutableArray*					errorPaths = [NSMutableArray array];
	NSMutableDictionary*			dictionary;
	struct stat						stats;
	const char*						dirPath;
	CFMutableDictionaryRef			newDirectories;
	DirectoryItemData*				newRoot;
	DirectoryItem*					info;
	
	dirPath = [[[_rootDirectory stringByStandardizingPath] stringByResolvingSymlinksInPath] UTF8String];
	if((lstat(dirPath, &stats) != 0) || !S_ISDIR(stats.st_mode))
	return nil;
	
	if(!compare)
	_revision = 1;
	else if(!_revision)
	return nil;
	
	newRoot = _CreateDirectoryItemData(dirPath, &stats, _scanMetadata, _revision, _xattrBuffer);
	newDirectories = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &kCFTypeDictionaryValueCallBacks);
	if([self _scanSubdirectory:"" fromRootDirectory:dirPath directories:newDirectories excludedPaths:excludedPaths errorPaths:errorPaths] <= 0) {
		CFRelease(newDirectories);
		if(newRoot)
		_DirectoryItemDataReleaseCallback(NULL, newRoot);
		return nil;
	}
	
	if(compare) {
		dictionary = _CompareDirectories(newDirectories, _directories, _scanMetadata, detectMovedItems, reportAllRemovedItems, (bumpRevision ? _revision + 1 : _revision), _sortPaths);
		if(_scanMetadata && _root && _ItemMetadataHasChanged(_root, newRoot)) {
			info = [[DirectoryItem alloc] initWithPath:"" data:_root];
			if([dictionary objectForKey:kDirectoryScannerResultKey_ModifiedItems_Metadata])
			[[dictionary objectForKey:kDirectoryScannerResultKey_ModifiedItems_Metadata] insertObject:info atIndex:0];
			else
			[dictionary setObject:[NSArray arrayWithObject:info] forKey:kDirectoryScannerResultKey_ModifiedItems_Metadata];
			[info release];
		}
		if([dictionary count] && bumpRevision)
		_revision += 1;
	}
	else
	dictionary = [NSMutableDictionary dictionary];
	
	if(_root)
	_DirectoryItemDataReleaseCallback(NULL, _root);
	_root = newRoot;
	CFRelease(_directories);
	_directories = newDirectories;
	
	if([excludedPaths count]) {
		if(_sortPaths)
		[excludedPaths sortUsingFunction:_SortFunction_Paths context:NULL];
		[dictionary setObject:excludedPaths forKey:kDirectoryScannerResultKey_ExcludedPaths];
	}
	if([errorPaths count]) {
		if(_sortPaths)
		[errorPaths sortUsingFunction:_SortFunction_Paths context:NULL];
		[dictionary setObject:errorPaths forKey:kDirectoryScannerResultKey_ErrorPaths];
	}
	
	return dictionary;
}

- (NSDictionary*) scanRootDirectory
{
	return [self _scanRootDirectory:NO bumpRevision:NO detectMovedItems:NO reportAllRemovedItems:NO];
}

- (NSDictionary*) scanAndCompareRootDirectory:(DirectoryScannerOptions)options
{
	return [self _scanRootDirectory:YES bumpRevision:(options & kDirectoryScannerOption_BumpRevision) detectMovedItems:(options & kDirectoryScannerOption_DetectMovedItems) reportAllRemovedItems:!(options & kDirectoryScannerOption_OnlyReportTopLevelRemovedItems)];
}

- (NSDictionary*) compare:(DirectoryScanner*)scanner options:(DirectoryScannerOptions)options
{
	return _CompareDirectories(_directories, [scanner _directories], _scanMetadata && [scanner isScanningMetadata], NO, !(options & kDirectoryScannerOption_OnlyReportTopLevelRemovedItems), 0, _sortPaths);
}

static void _DictionaryApplierFunction_DirectoryContents(const void* key, const void* value, void* context)
{
	void**						params = (void**)context;
	size_t						length = strlen(key);
	DirectoryItem*				info;
	char*						buffer;
	void*						subParams[7];
	
	bcopy(key, (char*)params[4] + (long)params[5], length + 1);
	info = [[DirectoryItem alloc] initWithPath:params[4] data:(DirectoryItemData*)value];
	[(NSMutableArray*)params[0] addObject:info];
	[info release];
	
	if(params[1] && IS_DIRECTORY((DirectoryItemData*)value)) {
		subParams[0] = params[0];
		subParams[1] = params[1];
		subParams[2] = params[2];
		subParams[3] = params[3];
		subParams[4] = malloc((long)params[5] + length + __DARWIN_MAXNAMLEN + 2);
		subParams[5] = (void*)((long)params[5] + length + 1);
		subParams[6] = params[6];
		bcopy(params[4], subParams[4], (long)params[5] + length);
		*((char*)subParams[4] + (long)params[5] + length) = '/';
		
		if(params[6])
		CFDictionaryApplyFunction(CFDictionaryGetValue((CFDictionaryRef)params[1], params[4]), _DictionaryApplierFunction_DirectoryContents, subParams);
		else {
			buffer = malloc((long)params[3] + (long)subParams[5] + 2);
			if(params[3]) {
				bcopy(params[2], buffer, (long)params[3]);
				buffer[(long)params[3]] = '/';
			}
			bcopy(subParams[4], buffer + (params[3] ? (long)params[3] + 1 : 0), (long)subParams[5]);
			buffer[(long)params[3] + (long)subParams[5] - (params[3] ? 0 : 1)] = 0;
			CFDictionaryApplyFunction(CFDictionaryGetValue((CFDictionaryRef)params[1], buffer), _DictionaryApplierFunction_DirectoryContents, subParams);
			free(buffer);
		}
		
		free(subParams[4]);
	}
}

- (NSArray*) subpathsOfRootDirectory
{
	return [self contentsOfDirectoryAtSubpath:nil recursive:YES useAbsolutePaths:YES];
}

- (NSArray*) contentsOfDirectoryAtSubpath:(NSString*)path recursive:(BOOL)recursive useAbsolutePaths:(BOOL)absolutePaths
{
	const char*					dirPath = ([path length] ? [[path stringByStandardizingPath] UTF8String] : "");
	NSMutableArray*				array = nil;
	CFDictionaryRef				entry;
	void*						params[7];
	
	entry = CFDictionaryGetValue(_directories, dirPath);
	if(entry) {
		array = [NSMutableArray array];
		params[0] = array;
		params[1] = (recursive ? _directories : NULL);
		params[2] = (void*)dirPath;
		params[3] = (void*)(long)strlen(dirPath);
		params[4] = malloc(__DARWIN_MAXNAMLEN + 2);
		if(absolutePaths && params[3]) {
			bcopy(params[2], params[4], (long)params[3]);
			*((char*)params[4] + (long)params[3]) = '/';
			params[5] = (void*)((long)params[3] + 1);
		}
		else
		params[5] = (void*)(long)0;
		params[6] = (void*)(long)absolutePaths;
		CFDictionaryApplyFunction(entry, _DictionaryApplierFunction_DirectoryContents, params);
		free(params[4]);
		
		if(_sortPaths)
		[array sortUsingFunction:_SortFunction_DirectoryItem context:NULL];
	}
	
	return array;
}

- (DirectoryItem*) directoryItemAtSubpath:(NSString*)path
{
	DirectoryItem*				info = nil;
	NSString*					string;
	CFDictionaryRef				entry;
	DirectoryItemData*			data;
	
	path = [path stringByStandardizingPath];
	string = [path stringByDeletingLastPathComponent];
	entry = CFDictionaryGetValue(_directories, ([string length] ? [string UTF8String] : ""));
	if(entry) {
		string = [path lastPathComponent];
		if([string length]) {
			data = (DirectoryItemData*)CFDictionaryGetValue(entry, [string UTF8String]);
			if(data)
			info = [[[DirectoryItem alloc] initWithPath:[path UTF8String] data:data] autorelease];
		}
		else if(_root)
		info = [[[DirectoryItem alloc] initWithPath:"" data:_root] autorelease];
	}
	
	return info;
}

static void _DictionaryApplierFunction_Count(const void* key, const void* value, void* context)
{
	*((NSUInteger*)context) += CFDictionaryGetCount(value);
}

- (NSUInteger) numberOfDirectoryItems
{
	NSUInteger					count = 0;
	
	CFDictionaryApplyFunction(_directories, _DictionaryApplierFunction_Count, &count);
	
	return count;
}

static void _DictionaryApplierFunction_AttributeSize(const void* key, const void* value, void* context)
{
	*((unsigned long long*)context) += *((unsigned int*)value);
}

static void _DictionaryApplierFunction_ItemSize(const void* key, const void* value, void* context)
{
	DirectoryItemData*			data = (DirectoryItemData*)value;
	
	*((unsigned long long*)context) += data->dataSize + data->resourceSize;
	if(data->extendedAttributes)
	CFDictionaryApplyFunction(data->extendedAttributes, _DictionaryApplierFunction_AttributeSize, context);
}

static void _DictionaryApplierFunction_DirectorySize(const void* key, const void* value, void* context)
{
	CFDictionaryApplyFunction(value, _DictionaryApplierFunction_ItemSize, context);
}

- (unsigned long long) totalSizeOfDirectoryItems
{
	unsigned long long			size = 0;
	
	CFDictionaryApplyFunction(_directories, _DictionaryApplierFunction_DirectorySize, &size);
	
	return size;
}

- (BOOL) updateDirectoryItemAtSubpath:(NSString*)path
{
	BOOL						success = NO;
	NSString*					base;
	CFMutableDictionaryRef		entry;
	DirectoryItemData*			data;
	const char*					name;
	const char*					fullPath;
	struct stat					stats;
	
	path = [path stringByStandardizingPath];
	base = [path stringByDeletingLastPathComponent];
	entry = (CFMutableDictionaryRef)CFDictionaryGetValue(_directories, ([base length] ? [base UTF8String] : ""));
	if(entry) {
		name = [[path lastPathComponent] UTF8String];
		if(CFDictionaryContainsKey(entry, name)) {
			fullPath = [[_rootDirectory stringByAppendingPathComponent:path] UTF8String];
			if(lstat(fullPath, &stats) == 0) {
				data = _CreateDirectoryItemData(fullPath, &stats, _scanMetadata, _revision, _xattrBuffer);
				if(data) {
					CFDictionarySetValue(entry, name, data);
					success = YES;
				}
			}
		}
	}
	
	return success;
}

- (void) removeDirectoryItemAtSubpath:(NSString*)path
{
	NSString*					base;
	CFMutableDictionaryRef		entry;
	
	path = [path stringByStandardizingPath];
	base = [path stringByDeletingLastPathComponent];
	entry = (CFMutableDictionaryRef)CFDictionaryGetValue(_directories, ([base length] ? [base UTF8String] : ""));
	if(entry)
	CFDictionaryRemoveValue(entry, [[path lastPathComponent] UTF8String]);
}

- (BOOL) setUserInfo:(id)info forDirectoryItemAtSubpath:(NSString*)path
{
	BOOL						success = NO;
	NSString*					base;
	CFDictionaryRef				entry;
	DirectoryItemData*			data;
	
	path = [path stringByStandardizingPath];
	base = [path stringByDeletingLastPathComponent];
	entry = CFDictionaryGetValue(_directories, ([base length] ? [base UTF8String] : ""));
	if(entry) {
		data = (DirectoryItemData*)CFDictionaryGetValue(entry, [[path lastPathComponent] UTF8String]);
		if(data) {
			if(info != data->userInfo) {
				[data->userInfo release];
				data->userInfo = [info copy];
			}
			success = YES;
		}
	}
	
	return success;
}

static void _DictionaryApplierFunction_Enumerator(const void* key, const void* value, void* context)
{
	void**					params = (void**)context;
	
	if((long)params[2] > 1)
	bcopy(key, (char*)params[1] + (long)params[2], strlen(key) + 1);
	**((void***)params) = [[DirectoryItem alloc] initWithPath:((long)params[2] > 1 ? params[1] : key) data:(DirectoryItemData*)value];
	*((void***)params) += 1;
}

- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state objects:(id*)stackbuf count:(NSUInteger)len
{
	const char*				path = NULL;
	CFDictionaryRef			contents = NULL;
	NSUInteger				count = CFDictionaryGetCount(_directories),
							max = 0,
							i;
	void*					params[3];
	size_t					length;
	
	if((state == NULL) || (len == 0) || (count == 0))
	return 0;
	
	if(state->state == 0) {
		state->extra[0] = (unsigned long)malloc(count * sizeof(void*));
		state->extra[1] = (unsigned long)malloc(count * sizeof(void*));
		CFDictionaryGetKeysAndValues(_directories, (const void**)state->extra[0], (const void**)state->extra[1]);
		state->extra[2] = 0;
		state->itemsPtr = NULL;
		state->mutationsPtr = (unsigned long*)self;
	}
	
	if(state->itemsPtr) {
		for(i = 0; i < state->extra[2]; ++i)
		[state->itemsPtr[i] release];
		free(state->itemsPtr);
	}
	
	while(state->state < count) {
		path = ((const char**)state->extra[0])[state->state];
		contents = ((CFDictionaryRef*)state->extra[1])[state->state];
		max = CFDictionaryGetCount(contents);
		state->state += 1;
		if(max > 0)
		break;
	}
	
	if(max > 0) {
		state->extra[2] = max;
		state->itemsPtr = malloc(max * sizeof(id));
		length = strlen(path);
		params[0] = state->itemsPtr;
		params[1] = malloc(length + __DARWIN_MAXNAMLEN + 2);
		params[2] = (void*)(length + 1);
		bcopy(path, params[1], length);
		((char*)params[1])[length] = '/';
		CFDictionaryApplyFunction(contents, _DictionaryApplierFunction_Enumerator, params);
		free(params[1]);
	}
	else {
		free((void*)state->extra[0]);
		free((void*)state->extra[1]);
	}
	
	return max;
}

@end

@implementation DirectoryScanner (Serialization)

static void _DictionaryApplierFunction_EncodeExtendedAttributes(const void* key, const void* value, void* context)
{
	unsigned int				size = *((unsigned int*)value);
	CFStringRef					keyString;
	NSData*						data;
	
	keyString = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
	data = [[NSData alloc] initWithBytes:((char*)value + sizeof(unsigned int)) length:size];
	[(NSMutableDictionary*)context setObject:data forKey:(id)keyString];
	[data release];
	CFRelease(keyString);
}

static NSDictionary* _CreateDictionaryFromDirectoryItemData(DirectoryItemData* data)
{
	NSMutableDictionary*		dictionary = [NSMutableDictionary new];
	NSMutableDictionary*		attributes;
	
	[dictionary setObject:[NSNumber numberWithUnsignedInt:data->nodeID] forKey:@"nodeID"];
	[dictionary setObject:[NSNumber numberWithUnsignedInt:data->revision] forKey:@"revision"];
	[dictionary setObject:[NSNumber numberWithDouble:data->newDate] forKey:@"creationDate"];
	[dictionary setObject:[NSNumber numberWithDouble:data->modDate] forKey:@"modificationDate"];
	if(!IS_DIRECTORY(data)) {
		[dictionary setObject:[NSNumber numberWithUnsignedLongLong:data->dataSize] forKey:@"dataSize"];
		if(data->resourceSize)
		[dictionary setObject:[NSNumber numberWithUnsignedInt:data->resourceSize] forKey:@"resourceSize"];
	}
	[dictionary setObject:[NSNumber numberWithUnsignedShort:data->mode] forKey:@"mode"];
	if(data->flags)
	[dictionary setObject:[NSNumber numberWithUnsignedShort:data->flags] forKey:@"userFlags"];
	if(data->uid)
	[dictionary setObject:[NSNumber numberWithUnsignedInt:data->uid] forKey:@"userID"];
	if(data->gid)
	[dictionary setObject:[NSNumber numberWithUnsignedInt:data->gid] forKey:@"groupID"];
	if(data->aclString)
	[dictionary setObject:[NSString stringWithUTF8String:data->aclString] forKey:@"ACL"];
	if(data->extendedAttributes) {
		attributes = [NSMutableDictionary new];
		CFDictionaryApplyFunction(data->extendedAttributes, _DictionaryApplierFunction_EncodeExtendedAttributes, attributes);
		[dictionary setObject:attributes forKey:@"extendedAttributes"];
		[attributes release];
	}
	if(data->userInfo)
	[dictionary setObject:data->userInfo forKey:@"userInfo"];
	
	return dictionary;
}

static void _DictionaryApplierFunction_EncodeLeaf(const void* key, const void* value, void* context)
{
	NSDictionary*				dictionary;
	CFStringRef					keyString;
	
	dictionary = _CreateDictionaryFromDirectoryItemData((DirectoryItemData*)value);
	
	keyString = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
	[(NSMutableDictionary*)context setObject:dictionary forKey:(id)keyString];
	CFRelease(keyString);
	
	[dictionary release];
}

static void _DictionaryApplierFunction_EncodeTrunk(const void* key, const void* value, void* context)
{
	CFDictionaryRef				entries = (CFDictionaryRef)value;
	NSMutableDictionary*		dictionary;
	CFStringRef					keyString;
	
	keyString = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
	dictionary = [[NSMutableDictionary alloc] initWithCapacity:CFDictionaryGetCount(entries)];
	
	CFDictionaryApplyFunction(entries, _DictionaryApplierFunction_EncodeLeaf, dictionary);
	[(NSMutableDictionary*)context setObject:dictionary forKey:(id)keyString];
	
	[dictionary release];
	CFRelease(keyString);
}

- (id) propertyList
{
	NSMutableDictionary*		plist = [NSMutableDictionary dictionary];
	NSMutableDictionary*		info = [NSMutableDictionary dictionary];
	NSMutableDictionary*		directories;
	NSString*					key;
	NSDictionary*				dictionary;
	
	for(key in _info) {
		if([key length] && ([key characterAtIndex:0] != '.'))
		[info setObject:[_info objectForKey:key] forKey:key];
	}
	
	[plist setObject:[NSNumber numberWithUnsignedInteger:kPropertyListVersion] forKey:@"version"];
	[plist setObject:[self rootDirectory] forKey:@"rootPath"];
	[plist setObject:[NSNumber numberWithUnsignedInteger:_revision] forKey:@"revision"];
	[plist setObject:[NSNumber numberWithBool:_scanMetadata] forKey:@"scanMetadata"];
	[plist setObject:[NSNumber numberWithBool:_sortPaths] forKey:@"sortPaths"];
	[plist setObject:[NSNumber numberWithBool:_excludeHidden] forKey:@"excludeHiddenItems"];
	[plist setObject:[NSNumber numberWithBool:_excludeDSStore] forKey:@"excludeDSStoreFiles"];
	if([info count])
	[plist setObject:info forKey:@"userInfo"];
	[plist setValue:[[self exclusionPredicate] predicateFormat] forKey:@"exclusionPredicate"];
	
	if(_root) {
		dictionary = _CreateDictionaryFromDirectoryItemData(_root);
		[plist setObject:dictionary forKey:@"root"];
		[dictionary release];
	}
	
	directories = [[NSMutableDictionary alloc] initWithCapacity:CFDictionaryGetCount(_directories)];
	CFDictionaryApplyFunction(_directories, _DictionaryApplierFunction_EncodeTrunk, directories);
	[plist setObject:directories forKey:@"directories"];
	[directories release];
	
	return plist;
}

static void _DictionaryApplierFunction_DecodeExtendedAttributes(const void* key, const void* value, void* context)
{
	NSData*						data = (NSData*)value;
	NSUInteger					size = [data length];
	void*						buffer;
	
	buffer = malloc(sizeof(unsigned int) + size);
	*((unsigned int*)buffer) = size;
	bcopy([data bytes], (char*)buffer + sizeof(unsigned int), size);
	CFDictionarySetValue((CFMutableDictionaryRef)context, [(NSString*)key UTF8String], buffer);
}

static DirectoryItemData* _CreateDirectoryItemDataFromDictionary(NSDictionary* dictionary, NSUInteger version)
{
	DirectoryItemData*			data = malloc(sizeof(DirectoryItemData));
	
	data->nodeID = [[dictionary objectForKey:@"nodeID"] unsignedIntValue];
	data->revision = [[dictionary objectForKey:@"revision"] unsignedIntValue];
	if(version <= 2) {
		if([dictionary objectForKey:@"fileSize"]) {
			data->newDate = NAN;
			data->modDate = [[dictionary objectForKey:@"fileModificationDate"] doubleValue];
			data->dataSize = [[dictionary objectForKey:@"fileSize"] unsignedLongLongValue];
			data->resourceSize = 0;
		}
		else {
			data->newDate = NAN;
			data->modDate = NAN;
			data->dataSize = 0;
			data->resourceSize = 0;
		}
	}
	else {
		data->newDate = [[dictionary objectForKey:@"creationDate"] doubleValue];
		data->modDate = [[dictionary objectForKey:@"modificationDate"] doubleValue];
		data->dataSize = [[dictionary objectForKey:@"dataSize"] unsignedLongLongValue];
		data->resourceSize = [[dictionary objectForKey:@"resourceSize"] unsignedIntValue];
	}
	data->mode = [[dictionary objectForKey:@"mode"] unsignedShortValue];
	data->flags = [[dictionary objectForKey:@"userFlags"] unsignedShortValue];
	data->uid = [[dictionary objectForKey:@"userID"] unsignedIntValue];
	data->gid = [[dictionary objectForKey:@"groupID"] unsignedIntValue];
	if([dictionary objectForKey:@"ACL"])
	data->aclString = _CopyCString([[dictionary objectForKey:@"ACL"] UTF8String]);
	else
	data->aclString = NULL;
	if([dictionary objectForKey:@"extendedAttributes"]) {
		data->extendedAttributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &_XATTRValueCallbacks);
		CFDictionaryApplyFunction((CFDictionaryRef)[dictionary objectForKey:@"extendedAttributes"], _DictionaryApplierFunction_DecodeExtendedAttributes, data->extendedAttributes);
	}
	else
	data->extendedAttributes = NULL;
	if(version <= 2)
	data->userInfo = ([dictionary objectForKey:@"info"] ? [[NSNumber numberWithUnsignedInt:[[dictionary objectForKey:@"info"] unsignedIntValue]] retain] : nil);
	else
	data->userInfo = [[dictionary objectForKey:@"userInfo"] retain];
	
	return data;
}

- (id) initWithPropertyList:(id)plist
{
	CFDictionaryValueCallBacks	itemValueCallbacks = {0, NULL, _DirectoryItemDataReleaseCallback, NULL, NULL};
	NSDictionary*				directories;
	NSDictionary*				entry;
	NSString*					key;
	CFMutableDictionaryRef		dictionary;
	NSString*					path;
	DirectoryItemData*			data;
	NSUInteger					version;
	
	if(![plist isKindOfClass:[NSDictionary class]] || ([[plist objectForKey:@"version"] unsignedIntegerValue] < kPropertyListMinVersion) || ([[plist objectForKey:@"version"] unsignedIntegerValue] > kPropertyListMaxVersion)) {
		[self release];
		return nil;
	}
	
	version = [[plist objectForKey:@"version"] unsignedIntegerValue];
	if((self = [self initWithRootDirectory:[plist objectForKey:@"rootPath"] scanMetadata:[[plist objectForKey:@"scanMetadata"] boolValue]])) {
		if(version <= 2) {
			_revision = [[plist objectForKey:@"headRevision"] unsignedIntegerValue];
			_sortPaths = YES;
			[self setExclusionPredicate:[[self class] exclusionPredicateWithPaths:[plist objectForKey:@"excludedSubpaths"] names:[plist objectForKey:@"excludedNames"]]];
		}
		else {
			_revision = [[plist objectForKey:@"revision"] unsignedIntegerValue];
			_sortPaths = [[plist objectForKey:@"sortPaths"] boolValue];
			[self setExclusionPredicate:([plist objectForKey:@"exclusionPredicate"] ? [NSPredicate predicateWithFormat:[plist objectForKey:@"exclusionPredicate"]] : nil)];
		}
		_excludeHidden = [[plist objectForKey:@"excludeHiddenItems"] boolValue];
		_excludeDSStore = [[plist objectForKey:@"excludeDSStoreFiles"] boolValue]; 
		[_info addEntriesFromDictionary:[plist objectForKey:@"userInfo"]];
		
		if(version <= 2) {
			data = calloc(1, sizeof(DirectoryItemData));
			data->mode = S_IFDIR;
			data->newDate = NAN;
			data->modDate = NAN;
			data->revision = _revision;
		}
		else {
			if([plist objectForKey:@"root"])
			data = _CreateDirectoryItemDataFromDictionary([plist objectForKey:@"root"], version);
			else
			data = NULL;
		}
		_root = data;
		
		directories = [plist objectForKey:@"directories"];
		for(key in directories) {
			entry = [directories objectForKey:key];
			
			dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &itemValueCallbacks);
			for(path in entry) {
				data = _CreateDirectoryItemDataFromDictionary([entry objectForKey:path], version);
				CFDictionarySetValue(dictionary, [path UTF8String], data);
			}
			CFDictionarySetValue(_directories, [key UTF8String], dictionary);
			CFRelease(dictionary);
		}
	}
	
	return self;
}

- (BOOL) writeToFile:(NSString*)path
{
	NSAutoreleasePool*	localPool = [NSAutoreleasePool new];
	NSString*			error = nil;
	BOOL				success;
	
	success = [[NSPropertyListSerialization dataFromPropertyList:[self propertyList] format:NSPropertyListXMLFormat_v1_0 errorDescription:&error] writeToGZipFile:path];
	if(success == NO)
	NSLog(@"%s: NSPropertyListSerialization failed with error \"%@\"", __FUNCTION__, error);
	
	[localPool drain];
	
	return success;
}

- (id) initWithFile:(NSString*)path
{
	NSString*			error = nil;
	NSData*				data;
	NSAutoreleasePool*	localPool;
	
	data = [[NSData alloc] initWithGZipFile:path];
	if(data == nil) {
		[self release];
		return nil;
	}
	
	localPool = [NSAutoreleasePool new];
	self = [self initWithPropertyList:[NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&error]];
	if(self == nil)
	NSLog(@"%s: NSPropertyListSerialization failed with error \"%@\"", __FUNCTION__, error);
	[localPool drain];
	
	[data release];
	
	return self;
}

static void _DictionaryApplierFunction_ArchiveExtendedAttributes(const void* key, const void* value, void* context)
{
	NSCoder*					coder = (NSCoder*)context;
	
	[coder encodeBytes:key length:(strlen(key) + 1)];
	[coder encodeBytes:value length:(sizeof(unsigned int) + *((unsigned int*)value))];
}

static void _ArchiveDirectoryItemData(DirectoryItemData* data, NSCoder* coder)
{
	unsigned int				count;
	DirectoryItemData32			item;
	
#if __LP64__
#if __BIG_ENDIAN__
#error Unsupported architecture
#endif
	item.mode = data->mode;
	item.flags = data->flags;
	item.uid = data->uid;
	item.gid = data->gid;
	item.nodeID = CFSwapInt32(data->nodeID);
	item.revision = CFSwapInt32(data->revision);
	item.resourceSize = CFSwapInt32(data->resourceSize);
	item.userInfoPtr = (data->userInfo ? 0xFFFFFFFF : 0);
	item.aclStringPtr = (data->aclString ? 0xFFFFFFFF : 0);
	item.extendedAttributesPtr = (data->extendedAttributes ? 0xFFFFFFFF : 0);
	item.dataSize = data->dataSize;
	item.newDate = data->newDate;
	item.modDate = data->modDate;
#else
#if __BIG_ENDIAN__
	item.mode = CFSwapInt16(data->mode);
	item.flags = CFSwapInt16(data->flags);
	item.uid = CFSwapInt32(data->uid);
	item.gid = CFSwapInt32(data->gid);
	item.nodeID = CFSwapInt32(data->nodeID);
	item.revision = CFSwapInt32(data->revision);
	item.resourceSize = CFSwapInt32(data->resourceSize);
	item.userInfoPtr = data->userInfo;
	item.aclStringPtr = data->aclString;
	item.extendedAttributesPtr = data->extendedAttributes;
	item.dataSize = CFSwapInt64(data->dataSize);
	*((uint64_t*)&item.newDate) = CFSwapInt64(*((uint64_t*)&data->newDate));
	*((uint64_t*)&item.modDate) = CFSwapInt64(*((uint64_t*)&data->modDate));
#else
	bcopy(data, &item, sizeof(DirectoryItemData));
#endif
#endif
	[coder encodeBytes:&item length:sizeof(DirectoryItemData32)];
	
	if(data->userInfo)
	[coder encodeObject:data->userInfo];
	if(data->aclString)
	[coder encodeBytes:data->aclString length:(strlen(data->aclString) + 1)];
	if(data->extendedAttributes) {
		count = CFDictionaryGetCount(data->extendedAttributes);
		[coder encodeValueOfObjCType:@encode(unsigned int) at:&count];
		CFDictionaryApplyFunction(data->extendedAttributes, _DictionaryApplierFunction_ArchiveExtendedAttributes, coder);
	}
}

static void _DictionaryApplierFunction_ArchiveLeaf(const void* key, const void* value, void* context)
{
	NSCoder*					coder = (NSCoder*)context;
	
	[coder encodeBytes:key length:(strlen(key) + 1)];
	
	_ArchiveDirectoryItemData((DirectoryItemData*)value, coder);
}

static void _DictionaryApplierFunction_ArchiveTrunk(const void* key, const void* value, void* context)
{
	NSCoder*					coder = (NSCoder*)context;
	CFDictionaryRef				entries = (CFDictionaryRef)value;
	unsigned int				count;
	
	[coder encodeBytes:key length:(strlen(key) + 1)];
	
	count = CFDictionaryGetCount(entries);
	[coder encodeValueOfObjCType:@encode(unsigned int) at:&count];
	CFDictionaryApplyFunction(entries, _DictionaryApplierFunction_ArchiveLeaf, coder);
}

- (void) encodeWithCoder:(NSCoder*)aCoder
{
	NSMutableDictionary*		info = [NSMutableDictionary dictionary];
	NSString*					key;
	NSArchiver*					archiver;
	NSMutableData*				data;
	unsigned int				count;
	
	for(key in _info) {
		if([key length] && ([key characterAtIndex:0] != '.'))
		[info setObject:[_info objectForKey:key] forKey:key];
	}
	
	[aCoder encodeInteger:kDataVersion forKey:@"version"];
	[aCoder encodeObject:[self rootDirectory] forKey:@"rootPath"];
	[aCoder encodeInteger:_revision forKey:@"revision"];
	[aCoder encodeBool:_scanMetadata forKey:@"scanMetadata"];
	[aCoder encodeBool:_sortPaths forKey:@"sortPaths"];
	[aCoder encodeBool:_excludeHidden forKey:@"excludeHiddenItems"];
	[aCoder encodeBool:_excludeDSStore forKey:@"excludeDSStoreFiles"];
	[aCoder encodeObject:info forKey:@"userInfo"];
	[aCoder encodeObject:[self exclusionPredicate] forKey:@"exclusionPredicate"];
	
	if(_root) {
		data = [NSMutableData new];
		archiver = [[NSArchiver alloc] initForWritingWithMutableData:data];
		_ArchiveDirectoryItemData(_root, archiver);
		[archiver release];
		[aCoder encodeBytes:[data mutableBytes] length:[data length] forKey:@"rootData"];
		[data release];
	}
	
	if(CFDictionaryGetCount(_directories)) {
		data = [[NSMutableData alloc] initWithCapacity:(1024 * 1024)];
		archiver = [[NSArchiver alloc] initForWritingWithMutableData:data];
		count = CFDictionaryGetCount(_directories);
		[archiver encodeValueOfObjCType:@encode(unsigned int) at:&count];
		CFDictionaryApplyFunction(_directories, _DictionaryApplierFunction_ArchiveTrunk, archiver);
		[archiver release];
		[aCoder encodeBytes:[data mutableBytes] length:[data length] forKey:@"directoryData"];
		[data release];
	}
}

static DirectoryItemData* _UnarchiveDirectoryItemData(NSCoder* coder, NSUInteger version)
{
	NSUInteger					length;
	const DirectoryItemData32*	item;
	DirectoryItemData*			data;
	unsigned int				count,
								i;
	const void*					key;
	const void*					value;
	void*						buffer;
	
	item = (const DirectoryItemData32*)[coder decodeBytesWithReturnedLength:&length];
	if(length != sizeof(DirectoryItemData32))
	[NSException raise:NSInternalInconsistencyException format:@"Invalid DirectoryItemData"];
	data = malloc(sizeof(DirectoryItemData));
#if __LP64__
#if __BIG_ENDIAN__
#error Unsupported architecture
#endif
	data->mode = item->mode;
	data->flags = item->flags;
	data->uid = item->uid;
	data->gid = item->gid;
	data->nodeID = item->nodeID;
	data->revision = item->revision;
	data->resourceSize = item->resourceSize;
	data->userInfo = (NSData*)(long)item->userInfoPtr;
	data->aclString = (const char*)(long)item->aclStringPtr;
	data->extendedAttributes = (CFMutableDictionaryRef)(long)item->extendedAttributesPtr;
	data->dataSize = item->dataSize;
	data->newDate = item->newDate;
	data->modDate = item->modDate;
#else
#if __BIG_ENDIAN__
	data->mode = CFSwapInt16(item->mode);
	data->flags = CFSwapInt16(item->flags);
	data->uid = CFSwapInt32(item->uid);
	data->gid = CFSwapInt32(item->gid);
	data->nodeID = CFSwapInt32(item->nodeID);
	data->revision = CFSwapInt32(item->revision);
	data->resourceSize = CFSwapInt32(item->resourceSize);
	data->userInfo = item->userInfoPtr;
	data->aclString = item->aclStringPtr;
	data->extendedAttributes = item->extendedAttributesPtr;
	data->dataSize = CFSwapInt64(item->dataSize);
	*((uint64_t*)&data->newDate) = CFSwapInt64(*((uint64_t*)&item->newDate));
	*((uint64_t*)&data->modDate) = CFSwapInt64(*((uint64_t*)&item->modDate));
#else
	bcopy(item, data, sizeof(DirectoryItemData));
#endif
#endif
	
	if(data->userInfo)
	data->userInfo = [[coder decodeObject] retain];
	if(data->aclString)
	data->aclString = _CopyCString([coder decodeBytesWithReturnedLength:&length]);
	if(data->extendedAttributes) {
		data->extendedAttributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &_XATTRValueCallbacks);
		[coder decodeValueOfObjCType:@encode(unsigned int) at:&count];
		for(i = 0; i < count; ++i) {
			key = [coder decodeBytesWithReturnedLength:&length];
			value = [coder decodeBytesWithReturnedLength:&length];
			buffer = malloc(length);
			bcopy(value, buffer, length);
			CFDictionarySetValue(data->extendedAttributes, key, buffer);
		}
	}
	
	return data;
}

- (id) initWithCoder:(NSCoder*)aDecoder
{
	CFDictionaryValueCallBacks	itemValueCallbacks = {0, NULL, _DirectoryItemDataReleaseCallback, NULL, NULL};
	CFMutableDictionaryRef		dictionary;
	NSUInteger					version;
	NSData*						data;
	NSUnarchiver*				unarchiver;
	const void*					key1;
	const void*					key2;
	unsigned int				count1,
								i1,
								count2,
								i2;
	NSUInteger					length;
	DirectoryItemData*			item;
	const void*					bytes;
	
	version = [aDecoder decodeIntegerForKey:@"version"];
	if((version < kDataMinVersion) || (version > kDataMaxVersion)) {
		[self release];
		return nil;
	}
	
	if((self = [self initWithRootDirectory:[aDecoder decodeObjectForKey:@"rootPath"] scanMetadata:[aDecoder decodeBoolForKey:@"scanMetadata"]])) {
		_revision = [aDecoder decodeIntegerForKey:@"revision"];
		_sortPaths = [aDecoder decodeBoolForKey:@"sortPaths"];
		[self setExclusionPredicate:[aDecoder decodeObjectForKey:@"exclusionPredicate"]];
		_excludeHidden = [aDecoder decodeBoolForKey:@"excludeHiddenItems"];
		_excludeDSStore = [aDecoder decodeBoolForKey:@"excludeDSStoreFiles"]; 
		[_info addEntriesFromDictionary:[aDecoder decodeObjectForKey:@"userInfo"]];
		
		bytes = [aDecoder decodeBytesForKey:@"rootData" returnedLength:&length];
		if(bytes) {
			data = [[NSData alloc] initWithBytesNoCopy:(void*)bytes length:length freeWhenDone:NO];
			unarchiver = [[NSUnarchiver alloc] initForReadingWithData:data];
			_root = _UnarchiveDirectoryItemData(unarchiver, version);
			[unarchiver release];
			[data release];
		}
		
		bytes = [aDecoder decodeBytesForKey:@"directoryData" returnedLength:&length];
		if(bytes) {
			data = [[NSData alloc] initWithBytesNoCopy:(void*)bytes length:length freeWhenDone:NO];
			unarchiver = [[NSUnarchiver alloc] initForReadingWithData:data];
			[unarchiver decodeValueOfObjCType:@encode(unsigned int) at:&count1];
			for(i1 = 0; i1 < count1; ++i1) {
				dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &_UTF8KeyCallbacks, &itemValueCallbacks);
				key1 = [unarchiver decodeBytesWithReturnedLength:&length];
				[unarchiver decodeValueOfObjCType:@encode(unsigned int) at:&count2];
				for(i2 = 0; i2 < count2; ++i2) {
					key2 = [unarchiver decodeBytesWithReturnedLength:&length];
					item = _UnarchiveDirectoryItemData(unarchiver, version);
					CFDictionarySetValue(dictionary, key2, item);
				}
				CFDictionarySetValue(_directories, key1, dictionary);
				CFRelease(dictionary);
			}
			[unarchiver release];
			[data release];
		}
	}
	
	return self;
}

- (NSData*) serializedData
{
	NSData*					data;
	NSAutoreleasePool*		localPool;
	
	localPool = [NSAutoreleasePool new];
	data = [[[NSKeyedArchiver archivedDataWithRootObject:self] compressGZip] retain];
	[localPool drain];
	
	return [data autorelease];
}

- (id) initWithSerializedData:(NSData*)data
{
	NSAutoreleasePool*		localPool;
	
	[self release];
	
	localPool = [NSAutoreleasePool new];
	if((data = [data decompressGZip]))
	self = [[NSKeyedUnarchiver unarchiveObjectWithData:data] retain];
	else
	self = nil;
	[localPool drain];
	
	return self;
}

@end

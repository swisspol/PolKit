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

#import <Foundation/Foundation.h>

#define kDirectoryScannerResultKey_AddedItems				@"addedItems" //NSArray of DirectoryItem
#define kDirectoryScannerResultKey_RemovedItems				@"removedItems" //NSArray of DirectoryItem
#define kDirectoryScannerResultKey_ModifiedItems_Data		@"modifiedItems.data" //NSArray of DirectoryItem
#define kDirectoryScannerResultKey_ModifiedItems_Metadata	@"modifiedItems.metadata" //NSArray of DirectoryItem (always nil if "scanMetadata" is NO)
#define kDirectoryScannerResultKey_MovedItems				@"movedItems" //NSArray of DirectoryItem (path is actually "oldPath:newPath")

#define kDirectoryScannerResultKey_ErrorPaths				@"errorPaths" //NSArray of NSString
#define kDirectoryScannerResultKey_ExcludedPaths			@"excludedPaths" //NSArray of NSString

enum {
	kDirectoryScannerOption_BumpRevision					= (1 << 0), //Only applies to -scanAndCompareRootDirectory:
	kDirectoryScannerOption_DetectMovedItems				= (1 << 1), //Only applies to -scanAndCompareRootDirectory:
	kDirectoryScannerOption_OnlyReportTopLevelRemovedItems	= (1 << 2)
};
typedef NSUInteger DirectoryScannerOptions;

@class DirectoryScanner;

@protocol DirectoryScannerDelegate <NSObject>
- (BOOL) shouldAbortScanning:(DirectoryScanner*)scanner;
@end

@interface DirectoryItem : NSObject
{
@private
	uint16_t			_mode;
	uint16_t			_flags;
	uint32_t			_nodeID;
	uint32_t			_userID;
	uint32_t			_groupID;
	uint32_t			_resourceSize;
	id					_userInfo;
	NSString*			_path;
	NSString*			_aclString;
	NSDictionary*		_attributes;
	NSUInteger			_revision;
	NSTimeInterval		_creationDate,
						_modificationDate;
	uint64_t			_dataSize;
}
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly, getter=isDirectory) BOOL directory;
@property(nonatomic, readonly, getter=isSymbolicLink) BOOL symbolicLink;
@property(nonatomic, readonly) NSUInteger revision;

@property(nonatomic, readonly) NSTimeInterval creationDate; //Seconds since 1 January 2001, GMT
@property(nonatomic, readonly) NSTimeInterval modificationDate; //Seconds since 1 January 2001, GMT
@property(nonatomic, readonly) unsigned long long dataSize; //Aways 0 for a directory
@property(nonatomic, readonly) unsigned int resourceSize; //Aways 0 for a directory
@property(nonatomic, readonly) unsigned int userID; //Always 0 if "scanMetadata" is NO
@property(nonatomic, readonly) unsigned int groupID; //Always 0 if "scanMetadata" is NO
@property(nonatomic, readonly) unsigned short permissions; //Always 0 if "scanMetadata" is NO
@property(nonatomic, readonly) unsigned short userFlags; //Always 0 if "scanMetadata" is NO
@property(nonatomic, readonly) NSString* ACLText; //Always nil if "scanMetadata" is NO
@property(nonatomic, readonly) NSDictionary* extendedAttributes; //Always nil if "scanMetadata" is NO

@property(nonatomic, readonly) unsigned long long totalSize;
@property(nonatomic, readonly) id userInfo;

- (BOOL) isEqual:(id)object; //Only compares path (case-sensitive)
- (BOOL) isEqualToDirectoryItem:(DirectoryItem*)otherItem compareMetadata:(BOOL)flag;
@end

/*
File names comparison is case-sensitive, except for "excludedSubpaths" and "excludedNames"
Files that are not accessible are skipped and reported as errors only if "scanMetadata" is YES
Directories that are not accessible are skipped and reported as errors
Metadata is owner & group, permissions, user settable flags, ACLs and extended attributes (excluding the resource fork one)
*/
@interface DirectoryScanner : NSObject <NSFastEnumeration>
{
@private
	NSString*						_rootDirectory;
	NSUInteger						_revision;
	BOOL							_scanMetadata,
									_sortPaths,
									_reportHidden,
									_excludeHidden,
									_excludeDSStore;
	NSPredicate*					_exclusionPredicate;
	void*							_root;
	CFMutableDictionaryRef			_directories;
	NSMutableDictionary*			_info;
	char*							_xattrBuffer;
	id<DirectoryScannerDelegate>	_delegate;
}
+ (NSPredicate*) exclusionPredicateWithPaths:(NSArray*)paths names:(NSArray*)names;
+ (DirectoryItem*) directoryItemAtPath:(NSString*)path includeMetadata:(BOOL)includeMetadata;

- (id) initWithRootDirectory:(NSString*)rootDirectory scanMetadata:(BOOL)scanMetadata;
@property(nonatomic, assign) id<DirectoryScannerDelegate> delegate;

@property(nonatomic, copy) NSString* rootDirectory; //You should rescan after changing this
@property(nonatomic, readonly, getter=isScanningMetadata) BOOL scanningMetadata;
@property(nonatomic, readonly) NSUInteger revision; //0 if undefined

@property(nonatomic) BOOL sortPaths; //Sort returned paths the same way the Finder does - NO by default
@property(nonatomic) BOOL reportExcludedHiddenItems; //Put excluded hidden items into the excluded paths list - NO by default

@property(nonatomic) BOOL excludeHiddenItems; //Items invisible in the GUI e.g. with names starting with "." - NO by default
@property(nonatomic) BOOL excludeDSStoreFiles; //Finder's ".DS_Store" files - NO by default
@property(nonatomic, copy) NSPredicate* exclusionPredicate; //Substitution variables are $NAME, $PATH, $TYPE (0=directory, 1=file, 2=symlink), $FILE_SIZE, $DATE_CREATED and $DATE_MODIFIED - nil by default

- (NSDictionary*) scanRootDirectory; //Reset revision to 1
- (NSDictionary*) scanAndCompareRootDirectory:(DirectoryScannerOptions)options; //Return changes from current revision

- (NSArray*) subpathsOfRootDirectory;
- (NSArray*) contentsOfDirectoryAtSubpath:(NSString*)path recursive:(BOOL)recursive useAbsolutePaths:(BOOL)absolutePaths;
- (DirectoryItem*) directoryItemAtSubpath:(NSString*)path; //Returns nil if undefined
@property(nonatomic, readonly) NSUInteger numberOfDirectoryItems;
@property(nonatomic, readonly) unsigned long long totalSizeOfDirectoryItems;

- (BOOL) updateDirectoryItemAtSubpath:(NSString*)path;
- (void) removeDirectoryItemAtSubpath:(NSString*)path;
- (BOOL) setUserInfo:(id)info forDirectoryItemAtSubpath:(NSString*)path; //Must be immutable and plist compatible

- (NSDictionary*) compare:(DirectoryScanner*)scanner options:(DirectoryScannerOptions)options;

- (void) setUserInfo:(id)info forKey:(NSString*)key; //Must be plist compatible - Pass nil value to remove info - Keys starting with '.' are not serialized
- (id) userInfoForKey:(NSString*)key;
@end

@interface DirectoryScanner (Serialization) <NSCoding>
- (id) initWithPropertyList:(id)plist;
@property(nonatomic, readonly) id propertyList;

- (NSData*) serializedData;
- (id) initWithSerializedData:(NSData*)data;

- (BOOL) writeToFile:(NSString*)path;
- (id) initWithFile:(NSString*)path;
@end

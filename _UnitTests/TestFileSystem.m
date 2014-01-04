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

#import <sys/stat.h>
#import <sys/xattr.h>
#import <membership.h>

#import "UnitTesting.h"
#import "DiskImageController.h"
#import "DirectoryScanner.h"
#import "DirectoryWatcher.h"
#import "DiskWatcher.h"

#define kDirectoryPath @"/Library/Desktop Pictures"
#define kOtherDirectoryPath @"/System/Library/CoreServices"

@interface UnitTests_FileSystem : UnitTest <DirectoryWatcherDelegate, DiskWatcherDelegate>
{
	BOOL					_didUpdate;
}
@end

static NSComparisonResult _SortFunction(NSString* path1, NSString* path2, void* context)
{
	return [path1 compare:path2 options:(NSCaseInsensitiveSearch | NSNumericSearch | NSForcedOrderingSearch)];
}

@implementation UnitTests_FileSystem

- (void) directoryWatcherRootDidChange:(DirectoryWatcher*)watcher
{
	;
}

- (void) directoryWatcher:(DirectoryWatcher*)watcher didUpdate:(NSString*)path recursively:(BOOL)recursively eventID:(FSEventStreamEventId)eventID
{
	_didUpdate = YES;
}

- (void) _update:(NSTimer*)timer
{
	NSString*				path = (NSString*)[timer userInfo];
	NSError*				error;
	
	AssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:[path stringByAppendingPathComponent:@"Test.jpg"] withDestinationPath:@"Resources/Image.jpg" error:&error], [error localizedDescription]);
}

- (void) testDirectoryWatcher
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	DirectoryWatcher*		watcher;
	NSError*				error;
	
	AssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error], [error localizedDescription]);
	
	watcher = [[DirectoryWatcher alloc] initWithRootDirectory:path latency:0.0 lastEventID:0];
	AssertNotNil(watcher, nil);
	[watcher setDelegate:self];
	
	_didUpdate = NO;
	AssertEqualObjects([watcher rootDirectory], path, nil);
	[watcher startWatching];
	AssertTrue([watcher isWatching], nil);
	[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_update:) userInfo:path repeats:NO];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
	[watcher stopWatching];
	AssertTrue(_didUpdate, nil);
	
	[watcher setDelegate:nil];
	[watcher release];
	
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:&error], [error localizedDescription]);
}

- (void) _testScanner:(BOOL)flag
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSArray*				expectedContent;
	NSMutableArray*			content;
	DirectoryScanner*		scanner;
	NSDictionary*			dictionary;
	DirectoryItem*			info;
	NSData*					serializedData;
	DirectoryScanner*		serializedScanner;
	
	expectedContent = [[[NSFileManager defaultManager] subpathsAtPath:kDirectoryPath] sortedArrayUsingFunction:_SortFunction context:NULL];
	
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:kDirectoryPath scanMetadata:NO];
	[scanner setSortPaths:YES];
	AssertNotNil(scanner, nil);
	AssertEqualObjects([scanner rootDirectory], kDirectoryPath, nil);
	AssertEquals([scanner revision], (NSUInteger)0, nil);
	
	AssertNil([scanner scanAndCompareRootDirectory:0], nil);
	
	dictionary = [scanner scanRootDirectory];
	AssertNotNil(dictionary, nil);
	AssertNil([dictionary objectForKey:kDirectoryScannerResultKey_ExcludedPaths], nil);
	AssertNil([dictionary objectForKey:kDirectoryScannerResultKey_ErrorPaths], nil);
	AssertEquals([scanner revision], (NSUInteger)1, nil);
	AssertEquals([scanner numberOfDirectoryItems], [expectedContent count], nil);
	content = [NSMutableArray new];
	for(info in [scanner subpathsOfRootDirectory])
	[content addObject:[info path]];
	AssertEqualObjects(content, expectedContent, nil);
	[content release];
	content = [NSMutableArray new];
	for(info in scanner)
	[content addObject:[info path]];
	[content sortUsingFunction:_SortFunction context:NULL];
	AssertEqualObjects(content, expectedContent, nil);
	[content release];
	
	dictionary = [scanner scanAndCompareRootDirectory:0];
	AssertNotNil(dictionary, nil);
	AssertEquals([dictionary count], (NSUInteger)0, nil);
	
	[scanner setUserInfo:@"info@pol-online.net" forDirectoryItemAtSubpath:[expectedContent objectAtIndex:0]];
	AssertEqualObjects([[scanner directoryItemAtSubpath:[expectedContent objectAtIndex:0]] userInfo], @"info@pol-online.net", nil);
	
	[scanner setUserInfo:@"PolKit" forKey:@"pol-online"];
	AssertEqualObjects([scanner userInfoForKey:@"pol-online"], @"PolKit", nil);
	
	if(flag) {
		serializedData = [scanner serializedData];
		AssertNotNil(serializedData, nil);
		serializedScanner = [[DirectoryScanner alloc] initWithSerializedData:serializedData];
	}
	else {
		AssertTrue([scanner writeToFile:path], nil);
		serializedScanner = [[DirectoryScanner alloc] initWithFile:path];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	
	AssertNotNil(serializedScanner, nil);
	AssertEquals([serializedScanner revision], (NSUInteger)1, nil);
	content = [NSMutableArray new];
	for(info in [serializedScanner subpathsOfRootDirectory])
	[content addObject:[info path]];
	AssertEqualObjects(content, expectedContent, nil);
	[content release];
	dictionary = [serializedScanner compare:scanner options:0];
	AssertNotNil(dictionary, nil);
	AssertFalse([dictionary count], nil);
	AssertEqualObjects([[serializedScanner directoryItemAtSubpath:[expectedContent objectAtIndex:0]] userInfo], @"info@pol-online.net", nil);
	AssertEqualObjects([serializedScanner userInfoForKey:@"pol-online"], @"PolKit", nil);
	[serializedScanner release];
	
	[scanner removeDirectoryItemAtSubpath:[expectedContent objectAtIndex:0]];
	AssertNil([scanner directoryItemAtSubpath:[expectedContent objectAtIndex:0]], nil);
	
	[scanner setUserInfo:nil forKey:@"pol-online"];
	AssertNil([scanner userInfoForKey:@"pol-online"], nil);
	
	[scanner release];
}

- (void) testScanner1
{
	[self _testScanner:NO];
}

- (void) testScanner2
{
	DirectoryScanner*		scanner1;
	DirectoryScanner*		scanner2;
	
	scanner1 = [[DirectoryScanner alloc] initWithRootDirectory:kDirectoryPath scanMetadata:NO];
	AssertNotNil(scanner1, nil);
	
	AssertNotNil([scanner1 scanRootDirectory], nil);
	AssertNotNil([scanner1 directoryItemAtSubpath:@"Abstract"], nil);
	AssertNotNil([scanner1 directoryItemAtSubpath:@"Flow 1.jpg"], nil);
	AssertNotNil([scanner1 directoryItemAtSubpath:@"Flow 2.jpg"], nil);
	AssertNotNil([scanner1 directoryItemAtSubpath:@"Solid Colors"], nil);
	AssertNotNil([scanner1 directoryItemAtSubpath:@"Black & White/Mojave.jpg"], nil);
	AssertNotNil([scanner1 directoryItemAtSubpath:@"Plants/Bamboo Grove.jpg"], nil);
	
	scanner2 = [[DirectoryScanner alloc] initWithRootDirectory:kDirectoryPath scanMetadata:NO];
	AssertNotNil(scanner2, nil);
	
	[scanner2 setExclusionPredicate:[DirectoryScanner exclusionPredicateWithPaths:[NSArray arrayWithObjects:@"Solid Colors", [@"Abstract" lowercaseString], [@"Plants/Bamboo Grove.jpg" uppercaseString], nil] names:[NSArray arrayWithObjects:@"Flow 1.jpg", [@"Flow 2.jpg" lowercaseString], [@"Mojave.jpg" uppercaseString], nil]]];
	AssertEqualObjects([scanner2 exclusionPredicate], [NSPredicate predicateWithFormat:@"($PATH IN[c] \"Solid Colors\" AND \"Solid Colors\" IN[c] $PATH) OR ($PATH IN[c] \"abstract\" AND \"abstract\" IN[c] $PATH) OR ($PATH IN[c] \"PLANTS/BAMBOO GROVE.JPG\" AND \"PLANTS/BAMBOO GROVE.JPG\" IN[c] $PATH) OR ($NAME IN[c] \"Flow 1.jpg\" AND \"Flow 1.jpg\" IN[c] $NAME) OR ($NAME IN[c] \"flow 2.jpg\" AND \"flow 2.jpg\" IN[c] $NAME) OR ($NAME IN[c] \"MOJAVE.JPG\" AND \"MOJAVE.JPG\" IN[c] $NAME)"], nil);
	
	AssertNotNil([scanner2 scanRootDirectory], nil);
	AssertNil([scanner2 directoryItemAtSubpath:@"Abstract"], nil);
	AssertNil([scanner2 directoryItemAtSubpath:@"Flow 1.jpg"], nil);
	AssertNil([scanner2 directoryItemAtSubpath:@"Flow 2.jpg"], nil);
	AssertNil([scanner2 directoryItemAtSubpath:@"Solid Colors"], nil);
	AssertNil([scanner2 directoryItemAtSubpath:@"Black & White/Mojave.jpg"], nil);
	AssertNil([scanner2 directoryItemAtSubpath:@"Plants/Bamboo Grove.jpg"], nil);
	
	[scanner2 release];
	[scanner1 release];
}

- (void) testScanner3
{
	NSMutableArray*			expectedContent;
	NSMutableArray*			content;
	DirectoryScanner*		scanner;
	NSDictionary*			dictionary;
	DirectoryItem*			info;
	NSString*				path;
	
	expectedContent = [[NSMutableArray alloc] initWithArray:[[NSFileManager defaultManager] subpathsAtPath:kOtherDirectoryPath]];
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:kOtherDirectoryPath scanMetadata:NO];
	[scanner setSortPaths:YES];
	dictionary = [scanner scanRootDirectory];
	AssertNotNil(dictionary, nil);
	content = [NSMutableArray new];
	for(info in [scanner subpathsOfRootDirectory])
	[content addObject:[info path]];
	for(path in [dictionary objectForKey:kDirectoryScannerResultKey_ErrorPaths])
	[expectedContent removeObject:path];
	[expectedContent sortUsingFunction:_SortFunction context:NULL];
	AssertEqualObjects(content, expectedContent, nil);
	[content release];
	[scanner release];
	[expectedContent release];
}

- (void) testScanner4
{
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSString*				scratchPath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				tmpPath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				file = [scratchPath stringByAppendingPathComponent:@"file.data"];
	const char*				string1 = "Hello World!";
	const char*				string2 = "Bonjour le Monde!";
	NSDictionary*			attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSData dataWithBytes:(void*)string1 length:strlen(string1)], @"net.pol-online.foo", [NSData dataWithBytes:(void*)string2 length:strlen(string2)], @"net.pol-online.bar", nil];
	DirectoryScanner*		scanner;
	NSDictionary*			dictionary;
	NSArray*				array;
	DirectoryItem*			item;
	NSError*				error;
	DirectoryScanner*		otherScanner;
	acl_t					acl;
	acl_entry_t				aclEntry;
	acl_permset_t			aclPerms;
	uuid_t					aclQualifier;
	char*					aclText;
	
	AssertTrue([manager createDirectoryAtPath:scratchPath withIntermediateDirectories:NO attributes:nil error:&error], [error localizedDescription]);
	AssertTrue([[NSData data] writeToFile:file options:NSAtomicWrite error:&error], [error localizedDescription]);
	AssertEquals(chmod([file UTF8String], S_IRUSR | S_IWUSR | S_IRGRP), (int)0, nil);
	AssertEquals(setxattr([file UTF8String], "net.pol-online.foo", string1, strlen(string1), 0, 0), (int)0, nil);
	AssertEquals(setxattr([file UTF8String], "net.pol-online.bar", string2, strlen(string2), 0, 0), (int)0, nil);
	acl = acl_init(1);
	AssertEquals(acl_create_entry(&acl, &aclEntry), (int)0, nil);
	AssertEquals(acl_set_tag_type(aclEntry, ACL_EXTENDED_ALLOW), (int)0, nil);
	AssertEquals(mbr_gid_to_uuid(getgid(), aclQualifier), (int)0, nil);
	AssertEquals(acl_set_qualifier(aclEntry, aclQualifier), (int)0, nil);
	AssertEquals(acl_get_permset(aclEntry, &aclPerms), (int)0, nil);
	AssertEquals(acl_clear_perms(aclPerms), (int)0, nil);
	AssertEquals(acl_add_perm(aclPerms, ACL_WRITE_DATA), (int)0, nil);
	AssertEquals(acl_set_permset(aclEntry, aclPerms), (int)0, nil);
	AssertEquals(acl_set_file([file UTF8String], ACL_TYPE_EXTENDED, acl), (int)0, nil);
	aclText = acl_to_text(acl, NULL);
	acl_free(acl);
	AssertEquals(chflags([file UTF8String], UF_IMMUTABLE), (int)0, nil);
	
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:scratchPath scanMetadata:NO];
	dictionary = [scanner scanRootDirectory];
	AssertNotNil(dictionary, nil);
	AssertEquals([dictionary count], (NSUInteger)0, nil);
	array = [scanner subpathsOfRootDirectory];
	AssertEquals([array count], (NSUInteger)1, nil);
	item = [array objectAtIndex:0];
	AssertFalse([item isDirectory], nil);
	AssertEquals([item userID], (unsigned int)0, nil);
	AssertEquals([item groupID], (unsigned int)0, nil);
	AssertEquals([item permissions], (unsigned short)0, nil);
	AssertEquals([item userFlags], (unsigned short)0, nil);
	AssertEqualObjects([item ACLText], nil, nil);
	AssertEqualObjects([item extendedAttributes], nil, nil);
	[scanner release];
	
	scanner = [[DirectoryScanner alloc] initWithRootDirectory:scratchPath scanMetadata:YES];
	dictionary = [scanner scanRootDirectory];
	AssertNotNil(dictionary, nil);
	AssertEquals([dictionary count], (NSUInteger)0, nil);
	array = [scanner subpathsOfRootDirectory];
	AssertEquals([array count], (NSUInteger)1, nil);
	item = [array objectAtIndex:0];
	AssertFalse([item isDirectory], nil);
	AssertEquals([item userID], (unsigned int)getuid(), nil);
	AssertEquals([item groupID], (unsigned int)0, nil);
	AssertEquals([item permissions], (unsigned short)(S_IRUSR | S_IWUSR | S_IRGRP), nil);
	AssertEquals([item userFlags], (unsigned short)UF_IMMUTABLE, nil);
	AssertEqualObjects([item ACLText], [NSString stringWithUTF8String:aclText], nil);
	AssertEqualObjects([item extendedAttributes], attributes, nil);
	
	AssertTrue([scanner writeToFile:tmpPath], nil);
	otherScanner = [[DirectoryScanner alloc] initWithFile:tmpPath];
	AssertNotNil(otherScanner, nil);
	dictionary = [scanner compare:otherScanner options:0];
	AssertNotNil(dictionary, nil);
	AssertEquals([dictionary count], (NSUInteger)0, nil);
	AssertEquals(chflags([file UTF8String], 0), (int)0, nil);
	AssertEquals(removexattr([file UTF8String], "net.pol-online.bar", 0), (int)0, nil);
	AssertEquals(chflags([file UTF8String], UF_IMMUTABLE), (int)0, nil);
	dictionary = [scanner scanRootDirectory];
	AssertNotNil(dictionary, nil);
	AssertEquals([dictionary count], (NSUInteger)0, nil);
	dictionary = [scanner compare:otherScanner options:0];
	AssertNotNil(dictionary, nil);
	AssertEquals([dictionary count], (NSUInteger)1, nil);
	AssertEquals([[dictionary objectForKey:kDirectoryScannerResultKey_ModifiedItems_Metadata] count], (NSUInteger)1, nil);
	[otherScanner release];
	AssertTrue([manager removeItemAtPath:tmpPath error:&error], [error localizedDescription]);
	
	[scanner release];
	
	acl_free(aclText);
	AssertEquals(chflags([file UTF8String], 0), (int)0, nil);
	AssertTrue([manager removeItemAtPath:scratchPath error:&error], [error localizedDescription]);
}

- (void) testScanner5
{
	[self _testScanner:YES];
}

- (void) diskWatcherDidUpdateAvailability:(DiskWatcher*)watcher
{
	_didUpdate = YES;
}

- (void) _mount:(NSTimer*)timer
{
	DiskImageController*	controller = [DiskImageController sharedDiskImageController];
	NSString*				mountPath;
	
	mountPath = [controller mountDiskImage:[timer userInfo] atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	AssertNotNil(mountPath, nil);
	AssertTrue([controller unmountDiskImageAtPath:mountPath force:NO], nil);
}

- (void) testDiskWatcher
{
	DiskImageController*	controller = [DiskImageController sharedDiskImageController];
	NSString*				imagePath = @"Resources/Volume.dmg";
	NSString*				mountPath;
	NSString*				uuid;
	DiskWatcher*			watcher;
	
	mountPath = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	AssertNotNil(mountPath, nil);
	uuid = [DiskWatcher diskIdentifierForVolume:[mountPath lastPathComponent]];
	AssertNotNil(uuid, nil);
	AssertTrue([controller unmountDiskImageAtPath:mountPath force:NO], nil);
	
	watcher = [[DiskWatcher alloc] initWithDiskIdentifier:uuid];
	AssertNotNil(watcher, nil);
	AssertFalse([watcher isDiskAvailable], nil);
	mountPath = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	AssertNotNil(mountPath, nil);
	AssertTrue([watcher isDiskAvailable], nil);
	AssertTrue([controller unmountDiskImageAtPath:mountPath force:NO], nil);
	[watcher release];
	
	_didUpdate = NO;
	watcher = [[DiskWatcher alloc] initWithDiskIdentifier:uuid];
	[watcher setDelegate:self];
	AssertNotNil(watcher, nil);
	[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_mount:) userInfo:imagePath repeats:NO];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
	[watcher release];
	AssertTrue(_didUpdate, nil);
}

@end

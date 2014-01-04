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

#import "DiskImageController.h"
#import "Task.h"

#define kDiskImageToolPath			@"/usr/bin/hdiutil"
#define kInvalidPassword			@"[?]"

@implementation DiskImageController

+ (DiskImageController*) sharedDiskImageController
{
	static DiskImageController*		controller = nil;
	
	if(controller == nil)
	controller = [DiskImageController new];
	
	return controller;
}

- (BOOL) _makeDiskImageAtPath:(NSString*)path extension:(NSString*)extension withName:(NSString*)name password:(NSString*)password extraArguments:(NSArray*)extraArguments
{
	NSFileManager*				manager = [NSFileManager defaultManager];
	BOOL						success = NO;
	NSMutableArray*				arguments;
	NSString*					output;
	id							plist;
	
	path = [path stringByStandardizingPath];
	if([manager fileExistsAtPath:path] || ![[path pathExtension] isEqualToString:extension])
	return NO;
	
	if(![name length])
	name = [[path lastPathComponent] stringByDeletingPathExtension];
	
	arguments = [NSMutableArray arrayWithObjects:@"create", @"-plist", @"-fs", @"HFS+", @"-nospotlight", @"-volname", name, nil];
	[arguments addObjectsFromArray:extraArguments];
	if(password) {
		[arguments addObject:@"-encryption"];
		[arguments addObject:@"AES-256"];
		[arguments addObject:@"-stdinpass"];
	}
	[arguments addObject:path];
	output = [Task runWithToolPath:kDiskImageToolPath arguments:arguments inputString:password timeOut:0.0];
	if(output) {
		plist = [NSPropertyListSerialization propertyListFromData:[output dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
		if(plist)
		success = YES; //NSArray of NSStrings representing created disk image paths
	}
	
	return success;
}

- (BOOL) makeSparseBundleDiskImageAtPath:(NSString*)path withName:(NSString*)name password:(NSString*)password
{
	return [self _makeDiskImageAtPath:path extension:@"sparsebundle" withName:name password:password extraArguments:[NSArray arrayWithObjects:@"-type", @"SPARSEBUNDLE", nil]];
}

- (BOOL) makeSparseDiskImageAtPath:(NSString*)path withName:(NSString*)name size:(NSUInteger)size password:(NSString*)password
{
	return [self _makeDiskImageAtPath:path extension:@"sparseimage" withName:name password:password extraArguments:[NSArray arrayWithObjects:@"-type", @"SPARSE", @"-size", [NSString stringWithFormat:@"%ik", size], nil]];
}

- (BOOL) makeDiskImageAtPath:(NSString*)path withName:(NSString*)name size:(NSUInteger)size password:(NSString*)password
{
	return [self _makeDiskImageAtPath:path extension:@"dmg" withName:name password:password extraArguments:[NSArray arrayWithObjects:@"-type", @"UDIF", @"-size", [NSString stringWithFormat:@"%ik", size], nil]];
}

- (BOOL) makeCompressedDiskImageAtPath:(NSString*)path withName:(NSString*)name contentsOfDirectory:(NSString*)directory password:(NSString*)password
{
	return [self _makeDiskImageAtPath:path extension:@"dmg" withName:name password:password extraArguments:[NSArray arrayWithObjects:@"-format", @"UDZO", @"-imagekey", @"zlib-level=1", @"-noanyowners", @"-noskipunreadable", @"-srcfolder", directory, nil]]; //NOTE: UDZO = gzip and UDBZ = bzip2 - zlib level is [1,9] with 1 being the default for hdiutil
}

- (BOOL) makeCompressedDiskImageAtPath:(NSString*)destinationPath withDiskImage:(NSString*)sourcePath password:(NSString*)password
{
	NSFileManager*				manager = [NSFileManager defaultManager];
	BOOL						success = NO;
	NSMutableArray*				arguments;
	NSString*					output;
	id							plist;
	
	destinationPath = [destinationPath stringByStandardizingPath];
	if([manager fileExistsAtPath:destinationPath] || ![[destinationPath pathExtension] isEqualToString:@"dmg"])
	return NO;
	
	arguments = [NSMutableArray arrayWithObjects:@"convert", @"-plist", @"-format", @"UDZO", @"-imagekey", @"zlib-level=6", @"-o", destinationPath, nil]; //NOTE: zlib level is [1,9] with 1 being the default for hdiutil
	if(password) {
		[arguments addObject:@"-encryption"];
		[arguments addObject:@"AES-256"];
		[arguments addObject:@"-stdinpass"];
	}
	[arguments addObject:sourcePath];
	output = [Task runWithToolPath:kDiskImageToolPath arguments:arguments inputString:password timeOut:0.0];
	if(output) {
		plist = [NSPropertyListSerialization propertyListFromData:[output dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
		if(plist)
		success = YES; //NSArray of NSStrings representing created disk image paths
	}
	
	return success;
}

- (NSString*) mountDiskImage:(NSString*)imagePath atPath:(NSString*)mountPath password:(NSString*)password
{
	return [self mountDiskImage:imagePath atPath:mountPath usingShadowFile:nil password:password private:NO verify:YES];
}

- (NSString*) mountDiskImage:(NSString*)imagePath atPath:(NSString*)mountPath usingShadowFile:(NSString*)shadowPath password:(NSString*)password private:(BOOL)private verify:(BOOL)verify
{
	NSMutableArray*				arguments = [NSMutableArray arrayWithObjects:@"attach", @"-plist", @"-owners", @"off", @"-noautoopen", @"-noidme", @"-stdinpass", nil];
	NSString*					output;
	id							plist;
	NSArray*					array;
	NSDictionary*				dictionary;
	
	if(private) {
		[arguments addObject:@"-private"];
		[arguments addObject:@"-nobrowse"];
	}
	if(verify) {
		[arguments addObject:@"-verify"];
		[arguments addObject:@"-autofsck"];
	}
	else {
		[arguments addObject:@"-noverify"];
		[arguments addObject:@"-noautofsck"];
	}
	if([shadowPath length]) {
		[arguments addObject:@"-shadow"];
		[arguments addObject:[shadowPath stringByStandardizingPath]];
	}
	if([mountPath length]) {
		[arguments addObject:@"-mountpoint"];
		[arguments addObject:[mountPath stringByStandardizingPath]];
	}
	else {
		[arguments addObject:@"-mount"];
		[arguments addObject:@"required"];
	}
	[arguments addObject:[imagePath stringByStandardizingPath]];
	
	mountPath = nil;
	output = [Task runWithToolPath:kDiskImageToolPath arguments:arguments inputString:(password ? password : kInvalidPassword) timeOut:0.0];
	if(output) {
		plist = [NSPropertyListSerialization propertyListFromData:[output dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
		if(plist && (array = [plist objectForKey:@"system-entities"])) {
			for(dictionary in array) {
				mountPath = [dictionary objectForKey:@"mount-point"];
				if(mountPath) {
#ifdef __DEBUG__
					if(![mountPath hasPrefix:@"/Volumes/"])
					NSLog(@"<Mounted \"%@\" to \"%@\">", imagePath, mountPath);
#endif
					break;
				}
			}
		}
	}
	
	return mountPath;
}

- (BOOL) unmountDiskImageAtPath:(NSString*)mountPath force:(BOOL)force
{
	NSMutableArray*				arguments = [NSMutableArray arrayWithObject:@"detach"];
	
	if(force)
	[arguments addObject:@"-force"];
	[arguments addObject:[mountPath stringByStandardizingPath]];
	
	if([Task runWithToolPath:kDiskImageToolPath arguments:arguments inputString:nil timeOut:0.0] == nil)
	return NO;
	
#ifdef __DEBUG__
	if(![mountPath hasPrefix:@"/Volumes/"])
	NSLog(@"<Unmounted \"%@\">", mountPath);
#endif
	
	return YES;
}

- (NSDictionary*) infoForDiskImageAtPath:(NSString*)path password:(NSString*)password
{
	NSMutableArray*				arguments = [NSMutableArray arrayWithObjects:@"imageinfo", @"-plist", @"-stdinpass", nil];
	NSString*					output;
	id							plist;
	
	[arguments addObject:[path stringByStandardizingPath]];
	
	output = [Task runWithToolPath:kDiskImageToolPath arguments:arguments inputString:(password ? password : kInvalidPassword) timeOut:0.0];
	if(output) {
		plist = [NSPropertyListSerialization propertyListFromData:[output dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
		if([plist isKindOfClass:[NSDictionary class]])
		return plist;
	}
	
	return NO;
}

- (BOOL) compactSparseDiskImage:(NSString*)path password:(NSString*)password
{
	NSMutableArray*				arguments = [NSMutableArray arrayWithObjects:@"compact", @"-plist", @"-stdinpass", nil];
	
	[arguments addObject:[path stringByStandardizingPath]];
	
	if(![Task runWithToolPath:kDiskImageToolPath arguments:arguments inputString:(password ? password : kInvalidPassword) timeOut:0.0])
	return NO;
	
	return YES;
}

@end

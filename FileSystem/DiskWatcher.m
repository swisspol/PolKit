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

#import <DiskArbitration/DiskArbitration.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/mount.h>

#import "DiskWatcher.h"

static NSMutableSet*		_clients = nil;
static DASessionRef			_session = NULL;

static inline void _AppendToData(NSMutableData* data, id value)
{
	[data appendData:[[value description] dataUsingEncoding:NSUTF8StringEncoding]];
}

static NSString* _DiskIdentifierFromDiskDescription(NSDictionary* description)
{
	NSString*				string = nil;
	CFUUIDRef				uuid;
	NSMutableData*			data;
	unsigned char			md5[16];
	
	uuid = (CFUUIDRef)[description objectForKey:(id)kDADiskDescriptionVolumeUUIDKey];
	if(uuid)
	string = [(id)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
	
	if(string == nil) {
		uuid = (CFUUIDRef)[description objectForKey:(id)kDADiskDescriptionMediaUUIDKey];
		if(uuid)
		string = [(id)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
	}
	
	if(string == nil) {
#ifdef __DEBUG__
		string = [description objectForKey:(id)kDADiskDescriptionVolumeNameKey];
		if(string == nil)
		string = [description objectForKey:(id)kDADiskDescriptionMediaNameKey];
		NSLog(@"%s: DADiskCopyDescription() contains no UUID for \"%@\"", __FUNCTION__, string);
#endif
		data = [NSMutableData new];
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionVolumeKindKey]);
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionVolumeNameKey]);
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionMediaNameKey]);
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionDeviceVendorKey]);
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionDeviceModelKey]);
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionDeviceProtocolKey]);
		_AppendToData(data, [description objectForKey:(id)kDADiskDescriptionMediaSizeKey]);
		CC_MD5([data mutableBytes], [data length], md5);
		[data release];
		string = [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X", md5[0], md5[1], md5[2], md5[3], md5[4], md5[5], md5[6], md5[7], md5[8], md5[9], md5[10], md5[11], md5[12], md5[13], md5[14],md5[15]];
	}
	
	return string;
}

static NSString* _DiskIdentifierFromPath(DASessionRef session, NSString* path)
{
	NSString*				string = nil;
	DADiskRef				disk;
	CFDictionaryRef			description;
	struct statfs			stats;
	
	if(statfs([path UTF8String], &stats) != 0)
	return NULL;
	
	disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, stats.f_mntfromname);
	if(disk) {
		description = DADiskCopyDescription(disk);
		if(description) {
			string = _DiskIdentifierFromDiskDescription((NSDictionary*)description);
			CFRelease(description);
		}
		else
		NSLog(@"%s: DADiskCopyDescription() failed for path \"%s\"", __FUNCTION__, stats.f_mntfromname);
		CFRelease(disk);
	}
	else
	NSLog(@"%s: DADiskCreateFromBSDName() failed for path \"%s\"", __FUNCTION__, stats.f_mntfromname);
	
	return string;
}

@implementation DiskWatcher

@synthesize diskIdentifier=_identifier, delegate=_delegate;

+ (void) initialize
{
	if(_clients == nil)
	_clients = [NSMutableSet new];
}

static void _DiskCallback(DADiskRef disk, void* context)
{
	NSAutoreleasePool*			pool = [NSAutoreleasePool new];
	CFDictionaryRef				description;
	DiskWatcher*				watcher;
	NSString*					identifier;
	
	if((description = DADiskCopyDescription(disk))) {
		identifier = _DiskIdentifierFromDiskDescription((NSDictionary*)description);
		for(watcher in _clients) {
			if([identifier isEqualToString:watcher->_identifier])
			[watcher->_delegate diskWatcherDidUpdateAvailability:watcher];
		}
		CFRelease(description);
	}
	
	[pool drain];
}

+ (void) _addClient:(DiskWatcher*)watcher
{
	if(![_clients containsObject:watcher]) {
		if(_session == NULL) {
			_session = DASessionCreate(kCFAllocatorDefault);
			if(_session) {
				DARegisterDiskAppearedCallback(_session, kDADiskDescriptionMatchVolumeMountable, _DiskCallback, NULL);
				DARegisterDiskDisappearedCallback(_session, kDADiskDescriptionMatchVolumeMountable, _DiskCallback, NULL);
				DASessionScheduleWithRunLoop(_session, CFRunLoopGetMain(), kCFRunLoopCommonModes);
			}
			else {
				NSLog(@"%s: DASessionCreate() failed", __FUNCTION__);
				return;
			}
		}
		[_clients addObject:watcher];
	}
}

+ (void) _removeClient:(DiskWatcher*)watcher
{
	[_clients removeObject:watcher];
	if(![_clients count] && _session) {
		DASessionUnscheduleFromRunLoop(_session, CFRunLoopGetMain(), kCFRunLoopCommonModes);
		DAUnregisterCallback(_session, _DiskCallback, self);
		CFRelease(_session);
		_session = NULL;
	}
}

+ (NSString*) diskIdentifierForPath:(NSString*)path
{
	NSString*				string = nil;
	DASessionRef			session;
	
	if(![path length])
	return nil;
	
	session = DASessionCreate(kCFAllocatorDefault);
	if(session) {
		string = _DiskIdentifierFromPath(session, path);
		CFRelease(session);
	}
	
	return string;
}

+ (NSString*) diskIdentifierForVolume:(NSString*)name
{
	if(![name length])
	return nil;
	
	return [self diskIdentifierForPath:[@"/Volumes" stringByAppendingPathComponent:name]];
}

- (id) initWithDiskIdentifier:(NSString*)identifier
{
	if(![identifier length]) {
		[self release];
		return nil;
	}
	
	if((self = [super init]))
	_identifier = [identifier copy];
	
	return self;
}

- (void) dealloc
{
	[self setDelegate:nil];
	
	[_identifier release];
	
	[super dealloc];
}

- (void) setDelegate:(id<DiskWatcherDelegate>)delegate
{
	if(delegate && !_delegate) {
		[DiskWatcher _addClient:self];
		_delegate = delegate;
	}
	else if(!delegate && _delegate) {
		[DiskWatcher _removeClient:self];
		_delegate = nil;
	}
}

- (BOOL) isDiskAvailable
{
	BOOL					available = NO;
	DASessionRef			session;
	NSString*				name;
	NSString*				identifier;
	
	session = (_delegate ? (DASessionRef)CFRetain(_session) : DASessionCreate(kCFAllocatorDefault));
	if(session) {
		for(name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:NULL]) {
			if(![name hasPrefix:@"."] && (identifier = _DiskIdentifierFromPath(session, [@"/Volumes" stringByAppendingPathComponent:name]))) {
				available = [identifier isEqualToString:_identifier];
				if(available)
				break;
			}
		}
		CFRelease(session);
	}
	
	return available;
}

@end

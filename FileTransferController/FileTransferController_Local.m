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

#import <sys/mount.h>
#import <pthread.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

#if !TARGET_OS_IPHONE
static CFMutableBagRef		_mountedList = NULL;
static pthread_mutex_t		_mountedMutex = PTHREAD_MUTEX_INITIALIZER;
#endif

@implementation LocalTransferController

+ (BOOL) useAsyncStreams
{
	return NO;
}

+ (NSString*) urlScheme
{
	return @"file";
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	return [NSNumber numberWithBool:YES];
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSString*				basePath = [url path];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSMutableDictionary*	dictionary;
	NSError*				error;
	NSArray*				array;
	NSString*				path;
	NSMutableDictionary*	entry;
	NSDictionary*			info;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(url) {
		array = [manager contentsOfDirectoryAtPath:basePath error:&error];
		if(array == nil) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return nil;
		}
		
		dictionary = [NSMutableDictionary dictionary];
		for(path in array) {
			info = [manager attributesOfItemAtPath:[basePath stringByAppendingPathComponent:path] error:&error];
			if(info == nil) {
				NSLog(@"%s: %@", __FUNCTION__, error);
				continue; //FIXME: Is this the best behavior?
			}
			
			entry = [NSMutableDictionary new];
			[entry setValue:[info objectForKey:NSFileType] forKey:NSFileType];
			[entry setValue:[info objectForKey:NSFileCreationDate] forKey:NSFileCreationDate];
			[entry setValue:[info objectForKey:NSFileModificationDate] forKey:NSFileModificationDate];
			[entry setValue:[info objectForKey:NSFileSize] forKey:NSFileSize];
			[dictionary setObject:entry forKey:path];
			[entry release];
		}
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", remotePath)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return dictionary;
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(url) {
		if(![[NSFileManager defaultManager] createDirectoryAtPath:[url path] withIntermediateDirectories:NO attributes:nil error:&error]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return NO;
		}
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", remotePath)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSDictionary*			info;
	NSError*				error;
	CFReadStreamRef			readStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	if(url == nil) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
		[[self delegate] fileTransferControllerDidStart:self];
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", remotePath)];
		return NO;
	}
	
	info = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:&error];
	if(info == nil)
	return NO;
	[self setMaxLength:[[info objectForKey:NSFileSize] unsignedIntegerValue]];
	
	readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)url);
	if(readStream == NULL)
	return NO;
	
	return [[self runReadStream:readStream dataStream:stream userInfo:nil isFileTransfer:YES] boolValue];
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	CFWriteStreamRef		writeStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	if(url == nil) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
		[[self delegate] fileTransferControllerDidStart:self];
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", remotePath)];
		return NO;
	}
	
	writeStream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)url);
	if(writeStream == NULL)
	return NO;
	
	return [[self runWriteStream:writeStream dataStream:stream userInfo:nil isFileTransfer:YES] boolValue];
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	NSURL*					fromURL = [self absoluteURLForRemotePath:fromRemotePath];
	NSURL*					toURL = [self absoluteURLForRemotePath:toRemotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(fromURL && toURL) {
		if([manager fileExistsAtPath:[toURL path]] && ![manager removeItemAtPath:[toURL path] error:&error]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return NO;
		}
		
		if(![manager moveItemAtPath:[fromURL path] toPath:[toURL path] error:&error]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return NO;
		}
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" or \"%@\" are not reachable", fromRemotePath, toRemotePath)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	NSURL*					fromURL = [self absoluteURLForRemotePath:fromRemotePath];
	NSURL*					toURL = [self absoluteURLForRemotePath:toRemotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(fromURL && toURL) {
		if([manager fileExistsAtPath:[toURL path]] && ![manager removeItemAtPath:[toURL path] error:&error]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return NO;
		}

		if(![manager copyItemAtPath:[fromURL path] toPath:[toURL path] error:&error]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return NO;
		}
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" or \"%@\" are not reachable", fromRemotePath, toRemotePath)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(url) {
		if([manager fileExistsAtPath:[url path]] && ![manager removeItemAtPath:[url path] error:&error]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
			return NO;
		}
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", remotePath)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) deleteDirectoryRecursivelyAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

@end

#if !TARGET_OS_IPHONE

@implementation RemoteTransferController

+ (void) initialize
{
	if(_mountedList == NULL)
	_mountedList = CFBagCreateMutable(kCFAllocatorDefault, 0, &kCFTypeBagCallBacks);
}

- (id) initWithBaseURL:(NSURL*)url
{
	NSMutableArray*			components;
	
	if((self = [super initWithBaseURL:url])) {
		components = [NSMutableArray arrayWithArray:[[url path] pathComponents]];
		if([components count])
		[components removeObjectAtIndex:0];
		if(![components count]) {
			[self release];
			return nil;
		}
		_sharePoint = [[components objectAtIndex:0] copy];
		[components removeObjectAtIndex:0];
		_subPath = ([components count] ? [[NSString pathWithComponents:components] copy] : @"");
	}
	
	return self;
}

- (void) _unmount
{
	NSURL*					url = [self baseURL];
	pid_t					dissenter;
	OSStatus				error;
	
	if(_fd) {
		close(_fd);
		_fd = 0;
	}
	
	if(_volumeRefNum) {
		pthread_mutex_lock(&_mountedMutex);
		if(CFBagContainsValue(_mountedList, url)) {
			CFBagRemoveValue(_mountedList, url);
			if(CFBagGetCountOfValue(_mountedList, url) == 0) {
				error = FSUnmountVolumeSync(_volumeRefNum, 0, &dissenter);
				if(error != noErr)
				NSLog(@"%s: FSUnmountVolumeSync() failed with error %i", __FUNCTION__, error);
			}
		}
		pthread_mutex_unlock(&_mountedMutex);
		_volumeRefNum = 0;
	}
	
	[_basePath release];
	_basePath = nil;
}

- (void) _cleanUp_RemoteTransferController
{
	if(_basePath)
	[self _unmount];
}

- (void) finalize
{
	[self _cleanUp_RemoteTransferController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_RemoteTransferController];
	
	[_subPath release];
	[_sharePoint release];
	
	[super dealloc];
}

- (BOOL) _automount
{
	NSURL*					url = [self baseURL];
	NSArray*				volumes;
	OSStatus				error;
	FSRef					directory;
	NSURL*					volumeURL;
	NSString*				path;
	const char*				filePath;
	
	if(![[NSFileManager defaultManager] fileExistsAtPath:_basePath]) { //FIXME: Find a more reliable way to know if the volume is still mounted
		if(_basePath) {
			NSLog(@"%s: Volume is unavailable", __FUNCTION__);
			[self _unmount];
		}
		
		volumes = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:NULL];
		volumeURL = [NSURL URLWithScheme:[[self class] urlScheme] user:nil password:nil host:[url host] port:0 path:_sharePoint];
		error = FSMountServerVolumeSync((CFURLRef)volumeURL, NULL, (CFStringRef)[url user], (CFStringRef)[url passwordByReplacingPercentEscapes], &_volumeRefNum, 0);
		if(error != noErr)
		NSLog(@"%s: FSMountServerVolumeSync() failed with error %i", __FUNCTION__, error);
		else {
			error = FSGetVolumeInfo(_volumeRefNum, 0, NULL, kFSVolInfoNone, NULL, NULL, &directory);
			if(error != noErr)
			NSLog(@"%s: FSGetVolumeInfo() failed with error %i", __FUNCTION__, error);
			else {
				path = [(NSURL*)[NSMakeCollectable(CFURLCreateFromFSRef(kCFAllocatorDefault, &directory)) autorelease] path];
				if(path == nil) {
					NSLog(@"%s: CFURLCreateFromFSRef() failed", __FUNCTION__);
					error = -1;
				}
				else {
					_basePath = [[path stringByAppendingPathComponent:_subPath] copy];
					
					pthread_mutex_lock(&_mountedMutex);
					if(!CFBagContainsValue(_mountedList, url) && [volumes containsObject:[path lastPathComponent]]) //NOTE: Check if volume was already mounted
					_volumeRefNum = 0;
					else
					CFBagAddValue(_mountedList, url);
					pthread_mutex_unlock(&_mountedMutex);
				}
			}
		}
		if(error != noErr)
		return NO;
		
		filePath = [[_basePath stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] UTF8String];
		_fd = open(filePath, O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR);
		if(_fd > 0) {
			if(unlink(filePath) != 0)
			NSLog(@"%s: unlink(%s) failed with error \"%s\"", __FUNCTION__, filePath, strerror(errno));
		}
		else
		NSLog(@"%s: open(%s) failed with error \"%s\"", __FUNCTION__, filePath, strerror(errno));
	}
	
	return YES;
}

/* Override completely */
- (NSURL*) absoluteURLForRemotePath:(NSString*)path
{
	if(![self _automount])
	return nil;
	
	return [NSURL fileURLWithPath:[_basePath stringByAppendingPathComponent:path]];
}

@end

@implementation AFPTransferController

+ (NSString*) urlScheme
{
	return @"afp";
}

@end

@implementation SMBTransferController

+ (NSString*) urlScheme
{
	return @"smb";
}

@end

#endif

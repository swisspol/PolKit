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

#import "DiskWatcher.h"
#import "NetworkReachability.h"
#import "NetworkConfiguration.h"
#import "DirectoryWatcher.h"

@interface Controller : NSObject <DiskWatcherDelegate, DirectoryWatcherDelegate, NetworkReachabilityDelegate>
@end

@implementation Controller

- (void) diskWatcherDidUpdateAvailability:(DiskWatcher*)watcher
{
	printf("%s: %i\n", __FUNCTION__, [watcher isDiskAvailable]);
}

- (void) directoryWatcherRootDidChange:(DirectoryWatcher*)watcher
{
	printf("%s: %s\n", __FUNCTION__, [[watcher rootDirectory] UTF8String]);
}

- (void) directoryWatcher:(DirectoryWatcher*)watcher didUpdate:(NSString*)path recursively:(BOOL)recursively eventID:(FSEventStreamEventId)eventID
{
	printf("%s: %s\n", __FUNCTION__, [[watcher rootDirectory] UTF8String]);
}

- (void) didChangeNetworkConfiguration:(NSNotification*)notification
{
	printf("%s: %s\n", __FUNCTION__, [[[NetworkConfiguration sharedNetworkConfiguration] locationName] UTF8String]);
}

- (void) networkReachabilityDidUpdate:(NetworkReachability*)reachability
{
	printf("%s: %i\n", __FUNCTION__, [reachability isReachable]);
}

@end

int main(int argc, const char* argv[])
{
	NSAutoreleasePool*				localPool = [NSAutoreleasePool new];
	Controller*						controller = [Controller new];
	NSMutableArray*					diskWatchers = [NSMutableArray array];
	DirectoryWatcher*				directoryWatcher;
	NetworkReachability*			networkReachability;
	DiskWatcher*					diskWatcher;
	NSString*						volume;
	
	if([NetworkConfiguration sharedNetworkConfiguration]) {
		[[NSNotificationCenter defaultCenter] addObserver:controller selector:@selector(didChangeNetworkConfiguration:) name:NetworkConfigurationDidChangeNotification object:nil];
		printf("Observing [network configuration]...\n");
	}
	networkReachability = [[NetworkReachability alloc] initWithHostName:@"apple.com"];
	if(networkReachability) {
		[networkReachability setDelegate:controller];
		printf("Observing \"apple.com\"...\n");
	}
	directoryWatcher = [[DirectoryWatcher alloc] initWithRootDirectory:[NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"] latency:0.0 lastEventID:0];
	if(directoryWatcher) {
		[directoryWatcher setDelegate:controller];
		printf("Observing \"~/Desktop\"...\n");
	}
	for(volume in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:NULL]) {
		if([volume hasPrefix:@"."])
		continue;
		diskWatcher = [[DiskWatcher alloc] initWithDiskIdentifier:[DiskWatcher diskIdentifierForVolume:volume]];
		if(diskWatcher) {
			printf("Observing \"%s\" (%s)...\n", [volume UTF8String], [[diskWatcher diskIdentifier] UTF8String]);
			[diskWatcher setDelegate:controller];
			[diskWatchers addObject:diskWatcher];
			[diskWatcher release];
		}
		else
		printf("WARNING: Unable to observe \"%s\"\n", [volume UTF8String]);
	}
	
	[[NSRunLoop currentRunLoop] run];
	
	for(diskWatcher in diskWatchers)
	[diskWatcher setDelegate:nil];
	[diskWatchers removeAllObjects];
	[directoryWatcher setDelegate:nil];
	[directoryWatcher release];
	[networkReachability setDelegate:nil];
	[networkReachability release];
	[[NSNotificationCenter defaultCenter] removeObserver:controller name:NetworkConfigurationDidChangeNotification object:nil];
	[controller release];
	[localPool drain];
	return 0;
}

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

#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

#import "NetworkReachability.h"

#define IS_REACHABLE(__FLAGS__) (((__FLAGS__) & kSCNetworkFlagsReachable) && !((__FLAGS__) & kSCNetworkFlagsConnectionRequired))

@implementation NetworkReachability

@synthesize delegate=_delegate;

static void _ReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkConnectionFlags flags, void* info)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	NetworkReachability*	self = (NetworkReachability*)info;
	
	[self->_delegate networkReachabilityDidUpdate:self];
	
	[pool drain];
}

- (id) _initWithNetworkReachability:(SCNetworkReachabilityRef)reachability
{
	if(reachability == NULL) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_runLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetMain());
		_reachability = (void*)reachability;
	}
	
	return self;
}

- (id) init
{
	return [self initWithIPv4Address:INADDR_ANY];
}

- (id) initWithAddress:(const struct sockaddr*)address
{
	return [self _initWithNetworkReachability:(address ? SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address) : NULL)];
}

- (id) initWithIPv4Address:(UInt32)address
{
	struct sockaddr_in				ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin_len = sizeof(ipAddress);
	ipAddress.sin_family = AF_INET;
	ipAddress.sin_addr.s_addr = htonl(address);
	
	return [self initWithAddress:(struct sockaddr*)&ipAddress];
}

- (id) initWithHostName:(NSString*)name
{
	return [self _initWithNetworkReachability:([name length] ? SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [name UTF8String]) : NULL)];
}

- (void) _cleanUp_NetworkReachability
{
	if(_runLoop)
	CFRelease(_runLoop);
	if(_reachability)
	CFRelease(_reachability);
}

- (void) finalize
{
	[self _cleanUp_NetworkReachability];
	
	[super finalize];
}

- (void) dealloc
{
	[self setDelegate:nil];
	
	[self _cleanUp_NetworkReachability];
	
	[super dealloc];
}

- (BOOL) isReachable
{
	SCNetworkConnectionFlags		flags;
	
	return (SCNetworkReachabilityGetFlags(_reachability, &flags) && IS_REACHABLE(flags) ? YES : NO);
}

- (void) setDelegate:(id<NetworkReachabilityDelegate>)delegate
{
	SCNetworkReachabilityContext	context = {0, self, NULL, NULL, NULL};
	
	if(delegate && !_delegate) {
		if(SCNetworkReachabilitySetCallback(_reachability, _ReachabilityCallBack, &context)) {
			if(!SCNetworkReachabilityScheduleWithRunLoop(_reachability, _runLoop, kCFRunLoopCommonModes)) {
				SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
				delegate = nil;
			}
		}
		else
		delegate = nil;
		if(delegate == nil)
		NSLog(@"%s: Failed installing SCNetworkReachability callback on runloop %p", __FUNCTION__, _runLoop);
	}
	else if(!delegate && _delegate) {
		SCNetworkReachabilityUnscheduleFromRunLoop(_reachability, _runLoop, kCFRunLoopCommonModes);
		SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
	}
	
	_delegate = delegate;
}

@end

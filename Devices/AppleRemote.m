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

#import "AppleRemote.h"
#import "HIDController.h"

#if 0
enum {
	kAppleRemoteCookie_Enter = 21,
	kAppleRemoteCookie_Up = 29,
	kAppleRemoteCookie_Down = 30,
	kAppleRemoteCookie_Left = 23,
	kAppleRemoteCookie_Left_Hold = 3,
	kAppleRemoteCookie_Right = 22,
	kAppleRemoteCookie_Right_Hold = 4,
	kAppleRemoteCookie_Menu = 20,
	kAppleRemoteCookie_Menu_Hold = 18
};
#else
enum {
	kAppleRemoteCookie_Enter = 23,
	kAppleRemoteCookie_Up = 31,
	kAppleRemoteCookie_Down = 32,
	kAppleRemoteCookie_Left = 25,
	kAppleRemoteCookie_Left_Hold = 13,
	kAppleRemoteCookie_Right = 24,
	kAppleRemoteCookie_Right_Hold = 14,
	kAppleRemoteCookie_Menu = 22,
	kAppleRemoteCookie_Menu_Hold = 20
};
#endif

@interface AppleRemote () <HIDControllerDelegate>
@end

@implementation AppleRemote

- (id) initWithExclusiveUse:(BOOL)exclusive
{
	NSDictionary*					devices = [HIDController allDevices];
	NSEnumerator*					enumerator = [devices keyEnumerator];
	NSString*						path;
	
	if((self = [super init])) {
		while((path = [enumerator nextObject])) {
			if(![[[devices objectForKey:path] objectForKey:@"Product"] isEqualToString:@"Apple IR"])
			continue;
			_remoteController = [[HIDController alloc] initWithDevicePath:path exclusive:exclusive];
			[_remoteController setDelegate:self];
			[_remoteController setEnabled:YES];
			break;
		}
		if(_remoteController == nil) {
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) dealloc
{
	[_remoteController setDelegate:nil];
	[_remoteController release];
	
	[super dealloc];
}

- (void) setDelegate:(id<AppleRemoteDelegate>)delegate
{
	_remoteDelegate = delegate;
}

- (id<AppleRemoteDelegate>) delegate
{
	return _remoteDelegate;
}

- (void) HIDControllerDidConnect:(HIDController*)controller
{
	;
}

- (void) HIDControllerDidDisconnect:(HIDController*)controller
{
	;
}

- (void) HIDController:(HIDController*)controller didUpdateElementWithCookie:(unsigned long)cookie value:(SInt32)value min:(SInt32)min max:(SInt32)max info:(NSDictionary*)info
{
#if 0
	NSLog(@"HID EVENT: %i = %i (%i:%i)", cookie, value, min, max);
#endif
	if (value > 0) {
		switch(cookie) {
			
			case kAppleRemoteCookie_Enter:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidPressEnterButton:)])
			[_remoteDelegate appleRemoteDidPressEnterButton:self];
			break;
			
			case kAppleRemoteCookie_Up:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidPressUpButton:)])
			[_remoteDelegate appleRemoteDidPressUpButton:self];
			break;
			
			case kAppleRemoteCookie_Down:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidPressDownButton:)])
			[_remoteDelegate appleRemoteDidPressDownButton:self];
			break;
			
			case kAppleRemoteCookie_Left:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidPressLeftButton:)])
			[_remoteDelegate appleRemoteDidPressLeftButton:self];
			break;
			
			case kAppleRemoteCookie_Left_Hold:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidHoldLeftButton:)])
			[_remoteDelegate appleRemoteDidHoldLeftButton:self];
			break;
			
			case kAppleRemoteCookie_Right:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidPressRightButton:)])
			[_remoteDelegate appleRemoteDidPressRightButton:self];
			break;
			
			case kAppleRemoteCookie_Right_Hold:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidHoldRightButton:)])
			[_remoteDelegate appleRemoteDidHoldRightButton:self];
			break;
			
			case kAppleRemoteCookie_Menu:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidPressMenuButton:)])
			[_remoteDelegate appleRemoteDidPressMenuButton:self];
			break;
			
			case kAppleRemoteCookie_Menu_Hold:
			if([_remoteDelegate respondsToSelector:@selector(appleRemoteDidHoldMenuButton:)])
			[_remoteDelegate appleRemoteDidHoldMenuButton:self];
			break;
			
		}
	}
}

@end

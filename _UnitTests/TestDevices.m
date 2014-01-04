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

#import <IOKit/hid/IOHIDUsageTables.h>
#import <IOKit/hid/IOHIDKeys.h>

#import "UnitTesting.h"
#import "HIDController.h"
#import "MidiController.h"

@interface UnitTests_Devices : UnitTest
@end

@implementation UnitTests_Devices

- (void) testHID
{
	HIDController*			controller;
	NSDictionary*			dictionary;
	NSString*				key;
	NSString*				string;
	
	dictionary = [HIDController allDevices];
	AssertNotNil(dictionary, nil);
	
	for(key in dictionary) {
		if((string = [[dictionary objectForKey:key] objectForKey:@"Product"]) && ([string rangeOfString:@"Keyboard"].location != NSNotFound) && ([[[dictionary objectForKey:key] objectForKey:@kIOHIDPrimaryUsageKey] unsignedShortValue] == kHIDUsage_GD_Keyboard)) {
			controller = [[HIDController alloc] initWithDevicePath:key exclusive:NO];
			AssertNotNil(controller, nil);
			AssertTrue([controller vendorID], nil);
			AssertTrue([controller productID], nil);
			AssertTrue([controller primaryUsagePage], nil);
			AssertTrue([controller primaryUsage], nil);
			AssertNotNil([controller devicePath], nil);
			
			[controller setEnabled:YES];
			AssertTrue([controller isEnabled], nil);
			AssertTrue([controller isConnected], nil);
			AssertNotNil([controller info], nil);
			AssertNotNil([controller allElements], nil);
			[controller release];
			return;
		}
	}
	
	[self logMessage:@"WARNING: No keyboard found for HID testing:\n%@", dictionary];
}

- (void) testMidi
{
	MidiController*			controller;
	
	controller = [[MidiController alloc] initWithName:@"PolKit" uniqueID:0];
	AssertNotNil(controller, nil);
	[controller release];
}

@end

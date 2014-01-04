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

extern NSString* UnitTest_MakeFormatString(NSString* format, ...);

#define _LogAssertionFailureMessage(__MESSAGE__, __DESCRIPTION__, ...) \
	do { \
		NSString* _description = UnitTest_MakeFormatString(__DESCRIPTION__, ##__VA_ARGS__); \
		[self logMessage:@"%s @ line %i\n%@\n%@", __FILE__, __LINE__, __MESSAGE__, _description]; \
	} while(0)
	
#define AssertTrue(__EXPRESSION__, __DESCRIPTION__, ...) \
do { \
	BOOL _bool = (__EXPRESSION__); \
	if(!_bool) { \
		NSString* _message = [NSString stringWithFormat:@"((%@) == TRUE)", [NSString stringWithUTF8String: #__EXPRESSION__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
	else \
	[self reportResult:YES]; \
} while(0)

#define AssertFalse(__EXPRESSION__, __DESCRIPTION__, ...) \
do { \
	BOOL _bool = (__EXPRESSION__); \
	if(_bool) { \
		NSString* _message = [NSString stringWithFormat:@"((%@) == FALSE)", [NSString stringWithUTF8String: #__EXPRESSION__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
	else \
	[self reportResult:YES]; \
} while(0)

#define AssertEquals(__VALUE1__, __VALUE2__, __DESCRIPTION__, ...) \
do { \
	__typeof__(__VALUE1__) _value1 = (__VALUE1__); \
	__typeof__(__VALUE2__) _value2 = (__VALUE2__); \
	if(strcmp(@encode(__typeof__(_value1)), @encode(__typeof__(_value2))) || (_value1 != _value2)) { \
		NSString* _message = [NSString stringWithFormat:@"((%@) == (%@))", [NSString stringWithUTF8String: #__VALUE1__], [NSString stringWithUTF8String: #__VALUE2__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
	else \
	[self reportResult:YES]; \
} while(0)

#define AssertNotEquals(__VALUE1__, __VALUE2__, __DESCRIPTION__, ...) \
do { \
	__typeof__(__VALUE1__) _value1 = (__VALUE1__); \
	__typeof__(__VALUE2__) _value2 = (__VALUE2__); \
	if(!strcmp(@encode(__typeof__(_value1)), @encode(__typeof__(_value2))) && (_value1 == _value2)) { \
		NSString* _message = [NSString stringWithFormat:@"((%@) != (%@))", [NSString stringWithUTF8String: #__VALUE1__], [NSString stringWithUTF8String: #__VALUE2__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
	else \
	[self reportResult:YES]; \
} while(0)

#define AssertNil(__OBJECT__, __DESCRIPTION__, ...) \
do { \
	id _object = (__OBJECT__); \
	if(_object != nil) { \
		NSString* _message = [NSString stringWithFormat:@"((%@) == nil)", [NSString stringWithUTF8String: #__OBJECT__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
	else \
	[self reportResult:YES]; \
} while(0)

#define AssertNotNil(__OBJECT__, __DESCRIPTION__, ...) \
do { \
	id _object = (__OBJECT__); \
	if(_object == nil) { \
		NSString* _message = [NSString stringWithFormat:@"((%@) != nil)", [NSString stringWithUTF8String: #__OBJECT__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
	else \
	[self reportResult:YES]; \
} while(0)

#define AssertEqualObjects(__OBJECT1__, __OBJECT2__, __DESCRIPTION__, ...) \
do { \
	id _object1 = (__OBJECT1__); \
	id _object2 = (__OBJECT2__); \
	if((_object1 == _object2) || (!strcmp(@encode(__typeof__(_object1)), @encode(id)) && !strcmp(@encode(__typeof__(_object2)), @encode(id)) && [(id)_object1 isEqual:(id)_object2])) \
	[self reportResult:YES]; \
	else { \
		NSString* _message = [NSString stringWithFormat:@"((%@) == (%@))", [NSString stringWithUTF8String: #__OBJECT1__], [NSString stringWithUTF8String: #__OBJECT2__]]; \
		_LogAssertionFailureMessage(_message, __DESCRIPTION__, ##__VA_ARGS__); \
		[self reportResult:NO]; \
	} \
} while(0)

@interface UnitTest : NSObject
{
@private
	NSUInteger				_successes,
							_failures;
}
@property(nonatomic, readonly) NSUInteger numberOfSuccesses;
@property(nonatomic, readonly) NSUInteger numberOfFailures;
@property(nonatomic, readonly) BOOL hasFailures;
- (void) logMessage:(NSString*)message, ...;
- (void) reportResult:(BOOL)success;
@end

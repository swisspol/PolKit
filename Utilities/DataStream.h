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

@protocol DataStreamSource <NSObject>
- (BOOL) openDataStream:(id)userInfo;
- (NSInteger) readDataFromStream:(id)userInfo buffer:(void*)buffer maxLength:(NSUInteger)length; //Return num read bytes on success, 0 at end or <0 on error
- (void) closeDataStream:(id)userInfo;
@end

@interface DataReadStream : NSInputStream
{
@private
	id<DataStreamSource>		_source;
	id							_info;
	NSStreamStatus				_status;
	NSError*					_error;
}
- (id) initWithDataSource:(id<DataStreamSource>)source userInfo:(id)info;
@property(nonatomic, readonly) id<DataStreamSource> dataSource;
@end

@protocol DataStreamDestination <NSObject>
- (BOOL) openDataStream:(id)userInfo;
- (NSInteger) writeDataToStream:(id)userInfo buffer:(const void*)buffer maxLength:(NSUInteger)length; //Return num written bytes on success, 0 at end or <0 on error
- (void) closeDataStream:(id)userInfo;
@end

@interface DataWriteStream : NSOutputStream
{
@private
	id<DataStreamDestination>	_destination;
	id							_info;
	NSStreamStatus				_status;
	NSError*					_error;
}
- (id) initWithDataDestination:(id<DataStreamDestination>)destination userInfo:(id)info;
@property(nonatomic, readonly) id<DataStreamDestination> dataDestination;
@end

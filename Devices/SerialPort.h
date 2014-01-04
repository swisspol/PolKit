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
#import <termios.h>

@interface SerialPort : NSObject
{
@private
	int					_fileDescriptor;
	struct termios		_originalTTYAttrs;
}
- (id) initWithBSDPath:(NSString*)path speed:(speed_t)speed controlFlags:(tcflag_t)flags;

- (void) invalidate;
- (BOOL) isValid;

- (BOOL) writeBytes:(unsigned char)firstByte, ...; //Last byte must be null
- (BOOL) write:(unsigned)length bytes:(unsigned char)firstByte, ...;
- (BOOL) writeBytes:(const void*)bytes length:(unsigned)length;
- (BOOL) writeUTF8String:(const char*)string;

- (NSData*) readBytes:(unsigned)length; //Returns nil on error
- (BOOL) readBytes:(void*)bytes length:(unsigned)length;
@end

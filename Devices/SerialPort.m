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

#import <unistd.h>
#import <sys/ioctl.h>

#import "SerialPort.h"

@implementation SerialPort

- (id) init
{
	return [self initWithBSDPath:nil speed:0 controlFlags:0];
}

- (id) initWithBSDPath:(NSString*)path speed:(speed_t)speed controlFlags:(tcflag_t)flags
{
	const char*			bsdPath = [path UTF8String];
	struct termios		options;
	
	if((self = [super init])) {
		//Open the serial port read/write, with no controlling terminal, and don't wait for a connection (the O_NONBLOCK flag also causes subsequent I/O on the device to be non-blocking)
		_fileDescriptor = open(bsdPath, O_RDWR | O_NOCTTY | O_NONBLOCK);
		if(_fileDescriptor == -1) {
			NSLog(@"%s:Error opening serial port %s - %s(%d)", __FUNCTION__, bsdPath, strerror(errno), errno);
			[self release];
			return nil;
		}
		
		//Prevent additional opens except by root-owned processes
		if(ioctl(_fileDescriptor, TIOCEXCL) == -1) {
			NSLog(@"%s:Error setting TIOCEXCL on %s - %s(%d)", __FUNCTION__, bsdPath, strerror(errno), errno);
			[self release];
			return nil;
		}
		
		//Now that the device is open, clear the O_NONBLOCK flag so subsequent I/O will block.
		if(fcntl(_fileDescriptor, F_SETFL, 0) == -1) {
			NSLog(@"%s:Error clearing O_NONBLOCK %s - %s(%d)", __FUNCTION__, bsdPath, strerror(errno), errno);
			[self release];
			return nil;
		}
		
		//Get the current options and save them so we can restore the default settings later
		if(tcgetattr(_fileDescriptor, &_originalTTYAttrs) == -1) {
			NSLog(@"%s:Error getting tty attributes %s - %s(%d)", __FUNCTION__, bsdPath, strerror(errno), errno);
			[self release];
			return nil;
		}
		
		//Set new options
		options = _originalTTYAttrs;
		cfmakeraw(&options); //Set raw input (non-canonical) mode, with reads blocking until either a single character has been received or a one second timeout expires
		options.c_cc[VMIN] = 1;
		options.c_cc[VTIME] = 10;
		cfsetspeed(&options, speed); //Set baud rate
		options.c_cflag |= flags; //Set word size (CS7 / CS8), parity (PARENB + PARODD) and flow control of input / output (CRTS_IFLOW / CCTS_OFLOW)
#ifdef __DEBUG__
		NSLog(@"Input baud rate for '%s' changed to %i", bsdPath, cfgetispeed(&options));
		NSLog(@"Output baud rate for '%s' changed to %i", bsdPath, cfgetospeed(&options));
#endif
		if(tcsetattr(_fileDescriptor, TCSANOW, &options) == -1) {
			NSLog(@"Error setting tty attributes %s - %s(%d)", __FUNCTION__, bsdPath, strerror(errno), errno);
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) finalize
{
	[self invalidate];
	
	[super finalize];
}

- (void) dealloc
{
	[self invalidate];
	
	[super dealloc];
}

- (void) invalidate
{
	if(_fileDescriptor > 0) {
		//Block until all written output has been sent from the device.
		if(tcdrain(_fileDescriptor) == -1)
		NSLog(@"%s:Error waiting for drain - %s(%d)", __FUNCTION__, strerror(errno), errno);
		
		//Restore serial port to original state
		if(tcsetattr(_fileDescriptor, TCSANOW, &_originalTTYAttrs) == -1)
		NSLog(@"%s:Error resetting tty attributes - %s(%d)", __FUNCTION__, strerror(errno), errno);
		
		//Close port
		close(_fileDescriptor);
		_fileDescriptor = 0;
	}
}

- (BOOL) isValid
{
	return (_fileDescriptor > 0);
}

- (BOOL) writeBytes:(unsigned char)firstByte, ...
{
	unsigned			length = 0;
	unsigned char		buffer[256];
	va_list				list;
	
	va_start(list, firstByte);
	while(firstByte) {
		buffer[length++] = firstByte;
		firstByte = va_arg(list, unsigned int);
	}
	va_end(list);
	
	return [self writeBytes:buffer length:length];
}

- (BOOL) write:(unsigned)length bytes:(unsigned char)firstByte, ...
{
	unsigned char		buffer[length];
	va_list				list;
	unsigned			i;
	
	buffer[0] = firstByte;
	va_start(list, firstByte);
	for(i = 1; i < length; ++i)
	buffer[i] = va_arg(list, unsigned int);
	va_end(list);
	
	return [self writeBytes:buffer length:length];
}

- (BOOL) writeBytes:(const void*)bytes length:(unsigned)length
{
	ssize_t				numBytes;
	
	if(_fileDescriptor > 0) {
		while(1) {
			numBytes = write(_fileDescriptor, bytes, length);
			if(numBytes == length)
			return YES;
			if(numBytes == -1) {
				NSLog(@"%s:Failed writing bytes - %s(%d)", __FUNCTION__, strerror(errno), errno);
				return NO;
			}
			length -= numBytes;
			bytes = (char*)bytes + numBytes;
		}
	}
	
	return NO;
}

- (BOOL) writeUTF8String:(const char*)string
{
	return [self writeBytes:string length:(string ? strlen(string) : 0)];
}

- (NSData*) readBytes:(unsigned)length
{
	NSMutableData*		data = [NSMutableData dataWithLength:length];
	
	return ([self readBytes:[data mutableBytes] length:[data length]] ? data : nil);
}

- (BOOL) readBytes:(void*)bytes length:(unsigned)length
{
	ssize_t				numBytes;
	
	if(_fileDescriptor > 0) {
		while(1) {
			numBytes = read(_fileDescriptor, bytes, length);
			if(numBytes == length)
			return YES;
			if(numBytes == -1) {
				NSLog(@"%s:Failed reading bytes - %s(%d)", __FUNCTION__, strerror(errno), errno);
				return NO;
			}
			length -= numBytes;
			bytes = (char*)bytes + numBytes;
		}
	}
	
	return NO;
}

@end

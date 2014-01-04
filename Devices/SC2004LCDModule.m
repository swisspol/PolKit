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

#import "SC2004LCDModule.h"

@implementation SC2004LCDModule

- (id) initWithSerialPortBSDPath:(NSString*)path highBaudRate:(BOOL)flag
{
	return [super initWithBSDPath:path speed:(flag ? B19200 : B9600) controlFlags:CS8];
}

- (id) initWithBSDPath:(NSString*)path speed:(speed_t)speed controlFlags:(tcflag_t)flags
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (void) clearCharacter
{
	[self writeBytes:0x08, 0x00];
}

- (void) clearRow:(unsigned char)row
{
	[self write:3 bytes:0xFE, 0x2D, MIN(row, kSC2004LCDModule_NumRows)];
}

- (void) clearColumn:(unsigned char)column
{
	[self write:3 bytes:0xFE, 0x2E, MIN(column, kSC2004LCDModule_NumColumns)];
}

- (void) clearDisplay
{
	[self writeBytes:0x0D, 0x00];
}

- (void) moveCursorLeft
{
	[self writeBytes:0x0E, 0x00];
}

- (void) moveCursorRight
{
	[self writeBytes:0x0F, 0x00];
}

- (void) moveCursorToNextLine
{
	[self writeBytes:0x0C, 0x00];
}

- (void) moveCursorToOrigin
{
	[self writeBytes:0x0B, 0x00];
}

- (void) moveCursorToRow:(unsigned char)row column:(unsigned char)column
{
	[self write:4 bytes:0xFE, 0x32, MIN(row, kSC2004LCDModule_NumRows), MIN(column, kSC2004LCDModule_NumColumns)];
}

- (void) writeString:(NSString*)string
{
	NSData*					data = [string dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	
	[self writeBytes:[data bytes] length:[data length]];
}

- (void) writeStringOnLine:(NSString*)string
{
	if([string length] > kSC2004LCDModule_NumColumns)
	string = [string substringToIndex:kSC2004LCDModule_NumColumns];
	[self writeString:string];
	
	if([string length] < kSC2004LCDModule_NumColumns)
	[self moveCursorToNextLine];
}

- (void) beginSavingScreen:(unsigned char)index
{
	[self writeBytes:0x0D, 0xFE, 0xC9 + MIN(index, kSC2004LCDModule_NumSavedScreens), 0x00];
}

- (void) endSavingScreen
{
	[self writeBytes:0xFF, 0x00];
}

- (void) displaySavedScreen:(unsigned char)index
{
	[self writeBytes:0x0D, 0xFE, 0x2A, 1 + MIN(index, kSC2004LCDModule_NumSavedScreens), 0x00];
}

- (void) setGeneralPurposeOutput:(BOOL)output1 :(BOOL)output2 :(BOOL)output3
{
	[self write:3 bytes:0xFE, 0x2F, (output3 ? 4 : 0) | (output2 ? 2 : 0) | (output1 ? 1 : 0)];
}

- (BOOL) getGeneralPurposeInput:(BOOL*)input1 :(BOOL*)input2 :(BOOL*)input3
{
	unsigned char			status;
	
	[self writeBytes:0xFE, 0x0A, 0x00];
	if(![self readBytes:&status length:1])
	return NO;
	
	if(input1)
	*input1 = (status & 1 ? YES : NO);
	if(input2)
	*input2 = (status & 2 ? YES : NO);
	if(input3)
	*input3 = (status & 4 ? YES : NO);
	
	return YES;
}

- (float) readAnalogInputPort:(unsigned char)index
{
	uint16_t				value;
	
	if(index >= kSC2004LCDModule_NumAnalogInputPorts)
	return -1.0;
	
	[self writeBytes:0xFE, 0x0B + index, 0x00];
	if(![self readBytes:&value length:2])
	return -1.0;
	value = CFSwapInt16BigToHost(value);
	
	return (float)value / (float)1023; //10 bits resolution
}

- (void) showBlinkingCursor
{
	[self writeBytes:0xFE, 0x02, 0x00];
}

- (void) showUnderlineCursor
{
	[self writeBytes:0xFE, 0x01, 0x00];
}

- (void) hideCursor
{
	[self writeBytes:0xFE, 0x03, 0x00];
}

- (void) setBacklightEnabled:(BOOL)flag
{
	[self writeBytes:0xFE, (flag ? 0x06 : 0x07), 0x00];
}

- (void) setBacklightOffDelay:(unsigned char)delay
{
	[self write:3 bytes:0xFE, 0x29, delay];
}

- (void) setBacklightBrigthness:(float)brightness
{
	[self writeBytes:0xFE, 0x28, (unsigned char)(50 + 200 * MAX(MIN(brightness, 1.0), 0.0)), 0x00];
}

- (void) setHighBaudRate:(BOOL)flag
{
	[self writeBytes:0xFE, (flag ? 0x1F : 0x1E), 0x00];
}

- (void) saveSettings
{
	[self writeBytes:0xFE, 0x20, 0x00];
}

@end

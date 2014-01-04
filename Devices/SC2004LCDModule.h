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

#import "SerialPort.h"

#define kSC2004LCDModule_NumRows				4
#define kSC2004LCDModule_NumColumns				20
#define kSC2004LCDModule_NumAnalogInputPorts	4
#define kSC2004LCDModule_NumSavedScreens		4

@interface SC2004LCDModule : SerialPort
- (id) initWithSerialPortBSDPath:(NSString*)path highBaudRate:(BOOL)flag;

- (void) moveCursorLeft;
- (void) moveCursorRight;
- (void) moveCursorToNextLine;
- (void) moveCursorToOrigin;
- (void) moveCursorToRow:(unsigned char)row column:(unsigned char)column;

- (void) clearCharacter; //Also moves backward
- (void) clearRow:(unsigned char)row; //Move cursor to beginning of next row
- (void) clearColumn:(unsigned char)column; //Move cursor to beginning of next column
- (void) clearDisplay; //Also moves cursor to origin

- (void) writeString:(NSString*)string; //String will be converted to ASCII
- (void) writeStringOnLine:(NSString*)string; //String will be converted to ASCII and truncated to fit on line - Also move cursor to next line

- (void) beginSavingScreen:(unsigned char)index; //Do not draw more than 4 lines of text between begin / end
- (void) endSavingScreen;
- (void) displaySavedScreen:(unsigned char)index;

- (void) setGeneralPurposeOutput:(BOOL)output1 :(BOOL)output2 :(BOOL)output3;
- (BOOL) getGeneralPurposeInput:(BOOL*)input1 :(BOOL*)input2 :(BOOL*)input3; //Auto-updated every 500ms
- (float) readAnalogInputPort:(unsigned char)index; //In [0,1] range or < 0 on error

- (void) showBlinkingCursor;
- (void) showUnderlineCursor;
- (void) hideCursor;
- (void) setBacklightEnabled:(BOOL)flag;
- (void) setBacklightOffDelay:(unsigned char)delay; //In seconds (0 means infinite)
- (void) setBacklightBrigthness:(float)brightness; //In [0,1] range
- (void) setHighBaudRate:(BOOL)flag; //19200bps instead of 9600bps
- (void) saveSettings;
@end

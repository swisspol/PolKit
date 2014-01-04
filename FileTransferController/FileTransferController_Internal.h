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

#import "FileTransferController.h"

#define MAKE_ERROR(__DOMAIN__, __CODE__, ...) [NSError errorWithDomain:__DOMAIN__ code:__CODE__ userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:__VA_ARGS__] forKey:NSLocalizedDescriptionKey]]
#define MAKE_FILETRANSFERCONTROLLER_ERROR(...) MAKE_ERROR(@"FileTransferController", -1, __VA_ARGS__)

#if TARGET_OS_IPHONE
#define NSMakeCollectable(__ARG__) (id)(__ARG__)
#endif

@interface FileTransferController ()
@property(nonatomic) NSUInteger currentLength;
@property(nonatomic) NSUInteger maxLength;

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream; //To be implemented by subclasses
- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream; //To be implemented by subclasses

+ (BOOL) useAsyncStreams;
+ (NSString*) urlScheme;

- (BOOL) openInputStream:(NSInputStream*)stream isFileTransfer:(BOOL)isFileTransfer;
- (NSInteger) readFromInputStream:(NSInputStream*)stream bytes:(void*)bytes maxLength:(NSUInteger)length;
- (void) closeInputStream:(NSInputStream*)stream;

- (BOOL) openOutputStream:(NSOutputStream*)stream isFileTransfer:(BOOL)isFileTransfer;
- (BOOL) writeToOutputStream:(NSOutputStream*)stream bytes:(const void*)bytes maxLength:(NSUInteger)length;
- (BOOL) flushOutputStream:(NSOutputStream*)stream;
- (void) closeOutputStream:(NSOutputStream*)stream;
@end

@interface StreamTransferController ()
@property(nonatomic, readonly) CFTypeRef activeStream;

- (void) readStreamClientCallBack:(CFReadStreamRef)stream type:(CFStreamEventType)type;
- (id) runReadStream:(CFReadStreamRef)readStream dataStream:(NSOutputStream*)dataStream userInfo:(id)info isFileTransfer:(BOOL)allowEncryption;
- (void) writeStreamClientCallBack:(CFWriteStreamRef)stream type:(CFStreamEventType)type;
- (id) runWriteStream:(CFWriteStreamRef)writeStream dataStream:(NSInputStream*)dataStream userInfo:(id)info isFileTransfer:(BOOL)allowEncryption;

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error;
- (void) invalidate;
@end

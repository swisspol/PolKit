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

#import <netinet/in.h>
#import "libssh2.h"
#import "libssh2_sftp.h"

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

#define kDefaultSSHPort					22
#define kDefaultMode					0755
#define kNameBufferSize					1024
#define kTransferBufferSize				(32 * 1024)

static inline NSError* _MakeLibSSH2Error(LIBSSH2_SESSION* session, LIBSSH2_SFTP* sftp)
{
	char*						message;
	int							error;
	
	error = libssh2_session_last_error(session, &message, NULL, 0);
	
	return [NSError errorWithDomain:@"libssh2" code:error userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:message], NSLocalizedDescriptionKey, (libssh2_sftp_last_error(sftp) ? [NSNumber numberWithUnsignedLong:libssh2_sftp_last_error(sftp)] : nil), @"SFTPLastError", nil]];
}

static CFSocketRef _CreateSocketConnectedToHost(NSString* name, UInt16 port, CFOptionFlags callBackTypes, CFSocketCallBack callback, const CFSocketContext* context, CFTimeInterval timeOut)
{
	int							on = 1;
	struct sockaddr_in			ipAddress;
	CFHostRef					host;
	CFStreamError				error;
	NSData*						data;
	const struct sockaddr*		address;
	CFSocketSignature			signature;
	CFSocketRef					socket;
	
	if(!name || !port)
	return NULL;
	
	host = CFHostCreateWithName(kCFAllocatorDefault, (CFStringRef)name);
	if(host) {
		if(CFHostStartInfoResolution(host, kCFHostAddresses, &error)) {
			for(data in (NSArray*)CFHostGetAddressing(host, NULL)) {
				address = (const struct sockaddr*)[data bytes];
				if((address->sa_family == AF_INET) && (address->sa_len == sizeof(ipAddress))) {
					bcopy(address, &ipAddress, address->sa_len);
					ipAddress.sin_port = htons(port);
					port = 0;
					break;
				}
			}
		}
		else
		NSLog(@"%s: CFHostStartInfoResolution() for host \"%@\" failed with error %i", __FUNCTION__, name, error.error);
		CFRelease(host);
	}
	if(port)
	return NULL;
	
	signature.protocolFamily = AF_INET;
	signature.socketType = SOCK_STREAM;
	signature.protocol = IPPROTO_IP;
	signature.address = (CFDataRef)[NSData dataWithBytes:&ipAddress length:ipAddress.sin_len];
	
	socket = CFSocketCreateConnectedToSocketSignature(kCFAllocatorDefault, &signature, callBackTypes, callback, context, timeOut);
	if(socket) {
		if(setsockopt(CFSocketGetNative(socket), SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on)) != 0)
		NSLog(@"%s: setsockopt(SO_NOSIGPIPE) failed with error \"%s\"", __FUNCTION__, strerror(errno));
	}
	else
	NSLog(@"%s: CFSocketCreateConnectedToSocketSignature() failed", __FUNCTION__);
	
	return socket;
}

@implementation SFTPTransferController

+ (NSString*) urlScheme;
{
	return @"ssh";
}

- (id) initWithBaseURL:(NSURL*)url
{
	if(![url user] || ![url password]) {
		[self release];
		return nil;
	}
	
	return [super initWithBaseURL:url];
}

- (void) _disconnect
{
	if(_sftp) {
		libssh2_sftp_shutdown(_sftp);
		_sftp = NULL;
	}
	
	if(_session) {
		libssh2_session_free(_session);
		_session = NULL;
	}
	
	if(_socket) {
		CFSocketInvalidate(_socket);
		CFRelease(_socket);
		_socket = NULL;
	}
}

- (void) finalize
{
	[self _disconnect];
	
	[super finalize];
}

- (void) dealloc
{
	[self _disconnect];
	
	[super dealloc];
}

- (void) _setTimeOut:(NSTimeInterval)timeOut
{
	struct timeval			tv = {(__darwin_time_t)(timeOut > 0.0 ? ceil(timeOut) : 0), 0};
	
	if(setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv)) != 0)
	NSLog(@"%s: setsockopt(SO_SNDTIMEO) failed with error \"%s\"", __FUNCTION__, strerror(errno));
	if(setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) != 0)
	NSLog(@"%s: setsockopt(SO_RCVTIMEO) failed with error \"%s\"", __FUNCTION__, strerror(errno));
}

- (BOOL) _reconnect:(NSTimeInterval)timeOut
{
	NSURL*					url = [self baseURL];
	char*					message;
	int						error;
	
	if(_session && (libssh2_session_last_error(_session, NULL, NULL, 0) == LIBSSH2_ERROR_SOCKET_TIMEOUT)) {
		NSLog(@"%s: Connection was broken", __FUNCTION__);
		[self _setTimeOut:1.0];
		[self _disconnect];
	}
	
	if(_socket == NULL) {
		_socket = _CreateSocketConnectedToHost([url host], ([url port] ? [[url port] unsignedShortValue] : kDefaultSSHPort), kCFSocketNoCallBack, NULL, NULL, timeOut);
		if(_socket) {
			_session = libssh2_session_init();
			if(_session) {
				if(libssh2_session_startup(_session, CFSocketGetNative(_socket)) == 0) {
					if(libssh2_userauth_password(_session, [[url user] UTF8String], [[url passwordByReplacingPercentEscapes] UTF8String]) == 0) {
						_sftp = libssh2_sftp_init(_session);
						if(_sftp == NULL) {
							error = libssh2_session_last_error(_session, &message, NULL, 0);
							NSLog(@"%s: libssh2_sftp_init() failed (error %i): %s", __FUNCTION__, error, message);
						}
					}
					else {
						error = libssh2_session_last_error(_session, &message, NULL, 0);
						NSLog(@"%s: libssh2_userauth_password() failed (error %i): %s", __FUNCTION__, error, message);
					}
				}
				else {
					error = libssh2_session_last_error(_session, &message, NULL, 0);
					NSLog(@"%s: libssh2_session_startup() failed (error %i): %s", __FUNCTION__, error, message);
				}
			}
			else
			NSLog(@"%s: libssh2_session_init() failed", __FUNCTION__);
		}
		if(_sftp == NULL) {
			[self _disconnect];
			return NO;
		}
	}
	
	[self _setTimeOut:timeOut];
	
	return YES;
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	const char*				serverPath = [[self absolutePathForRemotePath:remotePath] UTF8String];
	BOOL					success = NO;
	NSUInteger				length = 0;
	NSTimeInterval			timeOut = [self timeOut];
	CFTimeInterval			lastTime = 0.0,
							time;
	unsigned char			buffer[kTransferBufferSize];
	ssize_t					numBytes;
	LIBSSH2_SFTP_HANDLE*	handle;
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	NSError*				error;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	if(![self openOutputStream:stream isFileTransfer:YES])
	return NO;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if([self _reconnect:timeOut]) {
		handle = libssh2_sftp_open(_sftp, serverPath, LIBSSH2_FXF_READ, 0);
		if(handle) {
			if((libssh2_sftp_fstat(handle, &attributes) == 0) && (attributes.flags & LIBSSH2_SFTP_ATTR_SIZE)) {
				[self setMaxLength:attributes.filesize];
			
				[self _setTimeOut:1.0];
				do {
					numBytes = libssh2_sftp_read(handle, (char*)buffer, kTransferBufferSize);
					time = CFAbsoluteTimeGetCurrent();
					if(numBytes == LIBSSH2SFTP_EAGAIN) {
						if((timeOut > 0.0) && (time - lastTime >= timeOut))
						numBytes = -1;
						else
						continue;
					}
					else
					lastTime = time;
					if(numBytes > 0) {
						if(![self writeToOutputStream:stream bytes:buffer maxLength:numBytes]) {
							if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)]) {
								error = [stream streamError];
								[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed writing to output stream (status = %i)", [stream streamStatus]))];
							}
							break;
						}
						
						length += numBytes;
						[self setCurrentLength:length];
					}
					else if(numBytes == 0) {
						if([self flushOutputStream:stream]) {
							if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
							[[self delegate] fileTransferControllerDidSucceed:self];
							success = YES;
						}
						else if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)]) {
							error = [stream streamError];
							[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed flushing output stream (status = %i)", [stream streamStatus]))];
						}
						break;
					}
					else {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
						[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
						break;
					}
				} while(!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]);
				[self _setTimeOut:timeOut];
			}
			else if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
				
			libssh2_sftp_close(handle);
		}
		else if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
	}
	
	[self closeOutputStream:stream];
	
	return success;
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	const char*				serverPath = [[self absolutePathForRemotePath:remotePath] UTF8String];
	NSUInteger				length = 0;
	BOOL					success = NO;
	NSTimeInterval			timeOut = [self timeOut];
	CFTimeInterval			lastTime = 0.0,
							time;
	LIBSSH2_SFTP_HANDLE*	handle;
	unsigned char			buffer[kTransferBufferSize];
	ssize_t					numBytes,
							result,
							offset;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	if(![self openInputStream:stream isFileTransfer:YES])
	return NO;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if([self _reconnect:timeOut]) {
		handle = libssh2_sftp_open(_sftp, serverPath, LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC | LIBSSH2_FXF_WRITE, kDefaultMode);
		if(handle) {
			[self _setTimeOut:1.0];
			do {
				numBytes = [self readFromInputStream:stream bytes:buffer maxLength:kTransferBufferSize];
				if(numBytes > 0) {
					offset = 0;
					do {
						result = libssh2_sftp_write(handle, (char*)buffer + offset, numBytes - offset);
						time = CFAbsoluteTimeGetCurrent();
						if(result == LIBSSH2SFTP_EAGAIN) {
							if((timeOut > 0.0) && (time - lastTime >= timeOut)) {
								result = -1;
								break;
							}
							if(!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]) {
								result = 0;
								continue;
							}
						}
						else
						lastTime = time;
						offset += result;
					} while((result >= 0) && (offset < numBytes));
					if(result < 0) {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
						[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
						break;
					}
					
					length += numBytes;
					[self setCurrentLength:length];
				}
				else {
					if(numBytes == 0) {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
						[[self delegate] fileTransferControllerDidSucceed:self];
						success = YES;
					}
					else {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
						[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed reading from input stream")];
					}
					break;
				}
			} while(!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]);
			[self _setTimeOut:timeOut];
			
			libssh2_sftp_close(handle);
		}
		else if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
	}
	
	[self closeInputStream:stream];
	
	return success;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[self absolutePathForRemotePath:remotePath] UTF8String];
	NSMutableDictionary*	listing = [NSMutableDictionary dictionary];
	char					buffer[kNameBufferSize];
	LIBSSH2_SFTP_HANDLE*	handle;
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	NSMutableDictionary*	dictionary;
	int						result;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(![self _reconnect:[self timeOut]]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
		return nil;
	}
	
	handle = libssh2_sftp_opendir(_sftp, serverPath);
	if(handle == NULL) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
		return nil;
	}
	
	while((result = libssh2_sftp_readdir(handle, buffer, kNameBufferSize, &attributes)) > 0) {
		if((buffer[0] == '.') && ((buffer[1] == 0) || (buffer[1] == '.')))
		continue;
		if(!(attributes.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS))
		continue; //FIXME: What should we do?
		if(S_ISLNK(attributes.permissions))
		continue; //FIXME: We ignore symlinks
		
		dictionary = [NSMutableDictionary new];
		[dictionary setObject:(S_ISDIR(attributes.permissions) ? NSFileTypeDirectory : NSFileTypeRegular) forKey:NSFileType];
		if(attributes.flags & LIBSSH2_SFTP_ATTR_ACMODTIME)
		[dictionary setObject:[NSDate dateWithTimeIntervalSince1970:attributes.mtime] forKey:NSFileModificationDate];
		if(S_ISREG(attributes.permissions) && (attributes.flags & LIBSSH2_SFTP_ATTR_SIZE))
		[dictionary setObject:[NSNumber numberWithUnsignedLongLong:attributes.filesize] forKey:NSFileSize];
		[listing setObject:dictionary forKey:[NSString stringWithUTF8String:buffer]];
		[dictionary release];
	}
	
	if(result < 0) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
		[[self delegate] fileTransferControllerDidSucceed:self];
	}
	
	libssh2_sftp_closedir(handle);
	
	return listing;
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[self absolutePathForRemotePath:remotePath] UTF8String];
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(![self _reconnect:[self timeOut]]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
		return NO;
	}
	
	if(libssh2_sftp_mkdir(_sftp, serverPath, kDefaultMode)) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	const char*				fromPath = [[self absolutePathForRemotePath:fromRemotePath] UTF8String];
	const char*				toPath = [[self absolutePathForRemotePath:toRemotePath] UTF8String];
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(![self _reconnect:[self timeOut]]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
		return NO;
	}
	
	if(libssh2_sftp_rename(_sftp, fromPath, toPath)) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[self absolutePathForRemotePath:remotePath] UTF8String];
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(![self _reconnect:[self timeOut]]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
		return NO;
	}
	
	if(!libssh2_sftp_lstat(_sftp, serverPath, &attributes) && libssh2_sftp_unlink(_sftp, serverPath)) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[self absolutePathForRemotePath:remotePath] UTF8String];
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(![self _reconnect:[self timeOut]]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:MAKE_FILETRANSFERCONTROLLER_ERROR(@"\"%@\" is not reachable", [[self baseURL] URLByDeletingUserAndPassword])];
		return NO;
	}
	
	if(!libssh2_sftp_lstat(_sftp, serverPath, &attributes) && libssh2_sftp_rmdir(_sftp, serverPath)) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeLibSSH2Error(_session, _sftp)];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

@end

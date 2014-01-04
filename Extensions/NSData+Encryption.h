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

@interface NSData (Encryption)
+ (NSData*) md5DigestWithBytes:(const void*)bytes length:(NSUInteger)length;
+ (NSData*) sha1DigestWithBytes:(const void*)bytes length:(NSUInteger)length;

/* 'openssl dgst -md5 IN_FILE' */
- (NSData*) md5Digest;

/* Equivalent to 'openssl dgst -sha1 IN_FILE'  */
- (NSData*) sha1Digest;

/* Equivalent to 'openssl sha1 -hmac KEY IN_FILE' */
- (NSData*) sha1HMacWithKey:(NSString*)key;

/* Equivalent to 'openssl bf-cbc -e/-d -k PASSWORD [-nosalt] -in IN_FILE -out OUT_FILE' */
- (NSData*) encryptBlowfishWithPassword:(NSString*)password useSalt:(BOOL)flag;
- (NSData*) decryptBlowfishWithPassword:(NSString*)password useSalt:(BOOL)flag;

/* Equivalent to 'openssl aes-128-cbc -e/-d -k PASSWORD [-nosalt] -in IN_FILE -out OUT_FILE' */
- (NSData*) encryptAES128WithPassword:(NSString*)password useSalt:(BOOL)flag;
- (NSData*) decryptAES128WithPassword:(NSString*)password useSalt:(BOOL)flag;

/* Equivalent to 'openssl aes-256-cbc -e/-d -k PASSWORD [-nosalt] -in IN_FILE -out OUT_FILE' */
- (NSData*) encryptAES256WithPassword:(NSString*)password useSalt:(BOOL)flag;
- (NSData*) decryptAES256WithPassword:(NSString*)password useSalt:(BOOL)flag;

/* Equivalent to 'openssl base64 -e -in IN_FILE -out OUT_FILE' */
- (NSString*) encodeBase64;
@end

@interface NSString (Encryption)
/* Equivalent to 'openssl base64 -d -in IN_FILE -out OUT_FILE' */
- (NSData*) decodeBase64;
@end

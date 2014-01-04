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

#import <pthread.h>
#import <TargetConditionals.h>
#if !TARGET_OS_IPHONE
#import <objc/objc-runtime.h>
#endif

#import "WorkerThread.h"

@implementation WorkerThread

@synthesize running=_running;

- (id) init
{
	if((self = [super init])) {
		pthread_mutex_init(&_threadMutex, NULL);
		pthread_mutex_init(&_mutex, NULL);
		pthread_cond_init(&_condition, NULL);
	}
	
	return self;
}

- (void) _cleanUp_WorkerThread
{
	pthread_mutex_destroy(&_threadMutex);
	pthread_mutex_destroy(&_mutex);
	pthread_cond_destroy(&_condition);
}

- (void) finalize
{
	[self _cleanUp_WorkerThread];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_WorkerThread];
	
	[super dealloc];
}

- (void) _workerThread:(NSArray*)arguments
{
	NSAutoreleasePool*				localPool = [NSAutoreleasePool new];
	
	pthread_mutex_lock(&_threadMutex);
	_running = YES;
	
	pthread_mutex_lock(&_mutex);
	pthread_cond_signal(&_condition);
	pthread_mutex_unlock(&_mutex);
	
	[NSThread setThreadPriority:0.0];
	@try {
		objc_msgSend([arguments objectAtIndex:0], [[arguments objectAtIndex:1] pointerValue], ([arguments count] > 2 ? [arguments objectAtIndex:2] : nil));
	}
	@catch(id exception) {
		NSLog(@"%s: IGNORED EXCEPTION IN WORKER THREAD: %@", __FUNCTION__, exception);
	}
	
	_running = NO;
	pthread_mutex_unlock(&_threadMutex);
	
	[localPool drain];
}

- (void) startWithTarget:(id)target selector:(SEL)selector argument:(id)argument
{
	if(_running)
	[NSException raise:NSInternalInconsistencyException format:@"Worker thread is already running"];
	if(!target || !selector)
	[NSException raise:NSInvalidArgumentException format:@"Invalid arguments"];
	
	pthread_mutex_lock(&_mutex);
	[NSThread detachNewThreadSelector:@selector(_workerThread:) toTarget:self withObject:[NSArray arrayWithObjects:target, [NSValue valueWithPointer:selector], argument, nil]];
	pthread_cond_wait(&_condition, &_mutex);
	pthread_mutex_unlock(&_mutex);
}

- (void) waitUntilDone
{
	pthread_mutex_lock(&_threadMutex);
	pthread_mutex_unlock(&_threadMutex);
}

@end

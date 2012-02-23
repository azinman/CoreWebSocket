//
//  CoreWebSocket.h
//  CoreWebSocketCore
//
//  Created by Mirek Rusin on 07/03/2011.
//  Copyright 2011 Inteliv Ltd. All rights reserved.
//

#ifndef __CORE_WEB_SOCKET_WEB_SOCKET__
#define __CORE_WEB_SOCKET_WEB_SOCKET__ 1

#include "CoreWebSocketTypes.h"

#define __CoreWebSocketMaxHeaderKeyLength 4096

#pragma mark Lifecycle

CoreWebSocketRef CoreWebSocketCreate  (CFAllocatorRef allocator, CFStringRef host, UInt16 port, void *userInfo);

// Create CoreWebSocketRef using any host and any available port.
CoreWebSocketRef CoreWebSocketCreateWithUserInfo(CFAllocatorRef allocator, void *userInfo);

CoreWebSocketRef CoreWebSocketRetain  (CoreWebSocketRef webSocket);
CoreWebSocketRef CoreWebSocketRelease (CoreWebSocketRef webSocket);

UInt16 CoreWebSocketGetPort(CoreWebSocketRef webSocket);

void    CoreWebSocketWriteWithString               (CoreWebSocketRef webSocket, CFStringRef value);
CFIndex CoreWebSocketWriteWithStringAndClientIndex (CoreWebSocketRef webSocket, CFStringRef value, CFIndex index);

#pragma mark Callbacks

void CoreWebSocketSetClientReadCallback(CoreWebSocketRef webSocket, CoreWebSocketDidClientReadCallback callback);
void CoreWebSocketSetDidAddClientCallback(CoreWebSocketRef webSocket, CoreWebSocketDidAddClientCallback callback);
void CoreWebSocketSetWillRemoveClientCallback(CoreWebSocketRef webSocket, CoreWebSocketWillRemoveClientCallback callback);

#pragma mark Internal, client management

CFIndex __CoreWebSocketAppendClient (CoreWebSocketRef webSocket, CoreWebSocketClientRef client);
CFIndex __CoreWebSocketRemoveClient (CoreWebSocketRef webSocket, CoreWebSocketClientRef client);

#pragma mark Internal, socket callback

void __CoreWebSocketAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

#endif


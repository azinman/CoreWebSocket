//
//  CoreWebSocketTypes.h
//  CoreWebSocketCore
//
//  Created by Mirek Rusin on 07/03/2011.
//  Copyright 2011 Inteliv Ltd. All rights reserved.
//

#ifndef __CORE_WEB_SOCKET_TYPES__
#define __CORE_WEB_SOCKET_TYPES__ 1

#import "CoreWebSocketLib.h"
#include <CoreFoundation/CoreFoundation.h>

#define CoreWebSocketLog(fmt, ...) printf(fmt, __VA_ARGS__)

#define kCoreWebSocketHostAny      CFSTR("0.0.0.0")
#define kCoreWebSocketHostLoopBack CFSTR("127.0.0.1")
#define kCoreWebSocketPortAny      0

typedef struct CoreWebSocket  CoreWebSocket;
typedef        CoreWebSocket *CoreWebSocketRef;

typedef struct CoreWebSocketClient  CoreWebSocketClient;
typedef        CoreWebSocketClient *CoreWebSocketClientRef;

#pragma mark CoreWebSocket Protocol

typedef enum CoreWebSocketProtocol CoreWebSocketProtocol;

enum CoreWebSocketProtocol {
  kCoreWebSocketProtocolUnknown           = -1,
  kCoreWebSocketProtocolDraftIETF_HYBI_00 =  0,
  kCoreWebSocketProtocolDraftIETF_HYBI_06 =  6
};

#pragma mark CoreWebSocket Callbacks

typedef void (*CoreWebSocketDidAddClientCallback)     (CoreWebSocketRef webSocket, CoreWebSocketClientRef client);
typedef void (*CoreWebSocketWillRemoveClientCallback) (CoreWebSocketRef webSocket, CoreWebSocketClientRef client);
typedef void (*CoreWebSocketDidClientReadCallback)    (CoreWebSocketRef webSocket, CoreWebSocketClientRef client, CFStringRef value);

typedef struct CoreWebSocketCallbacks CoreWebSocketCallbacks;

struct CoreWebSocketCallbacks {
  CoreWebSocketDidAddClientCallback     didAddClientCallback;
  CoreWebSocketWillRemoveClientCallback willRemoveClientCallback;
  CoreWebSocketDidClientReadCallback    didClientReadCallback;
};

#pragma mark CoreWebSocket Client

enum CoreWebSocketClientState {
  kCoreWebSocketClientInitialized,
  kCoreWebSocketClientReadStreamOpened,
  kCoreWebSocketClientWriteStreamOpened,
  kCoreWebSocketClientHandShakeError,
  kCoreWebSocketClientHandShakeRead,
  kCoreWebSocketClientHandShakeSent,
  kCoreWebSocketClientReady
};

struct CoreWebSocketClient {
  CFUUIDRef uuid;
  CFAllocatorRef allocator;
  CFIndex retainCount;
  CoreWebSocketRef webSocket;
  CFSocketNativeHandle handle;
  CFReadStreamRef read;
  CFWriteStreamRef write;

  CFMutableArrayRef writeQueue;

  CFHTTPMessageRef handShakeRequestHTTPMessage;
  CoreWebSocketProtocol protocol;

  // Linked list of clients
  CoreWebSocketClientRef previousClient;
  CoreWebSocketClientRef nextClient;

  CFStreamClientContext context;

  bool didReadHandShake;
  bool didWriteHandShake;

};

struct CoreWebSocket {
  CFAllocatorRef allocator;
  CFIndex retainCount;
  void *userInfo;

  struct sockaddr_in addr;
  CFSocketRef socket;
  CFReadStreamRef read;
  CFWriteStreamRef write;

  CFIndex clientsUsedLength;
  CFIndex clientsLength;
  CoreWebSocketClientRef *clients;

  CFSocketContext context;

  CoreWebSocketCallbacks callbacks;
};

#endif


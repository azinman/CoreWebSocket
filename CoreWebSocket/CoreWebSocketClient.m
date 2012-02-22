//
//  CoreWebSocketClient.c
//  CoreWebSocketCore
//
//  Created by Mirek Rusin on 07/03/2011.
//  Copyright 2011 Inteliv Ltd. All rights reserved.
//

#include "CoreWebSocketClient.h"

#pragma mark Write

// Internal functions
CFIndex __CoreWebSocketClientWriteFrame(CoreWebSocketClientRef client, const UInt8 *buffer, CFIndex length);
CFStringRef __CoreWebSocketCreateBase64StringWithData(CFAllocatorRef allocator, CFDataRef inputData);
void __CoreWebSocketClientReadCallBack(CFReadStreamRef stream, CFStreamEventType eventType, void *info);
void __CoreWebSocketClientWriteCallBack(CFWriteStreamRef stream, CFStreamEventType eventType, void *info);
bool __CoreWebSocketClientWriteHandShakeDraftIETF_HYBI_06(CoreWebSocketClientRef client);
bool __CoreWebSocketClientHandShakeConsumeHTTPMessage(CoreWebSocketClientRef client);
bool __CoreWebSocketClientWriteHandShakeDraftIETF_HYBI_00(CoreWebSocketClientRef client);
bool __CoreWebSocketClientHandShakeUpdateProtocolBasedOnHTTPMessage(CoreWebSocketClientRef client);

// Internal function, write provided buffer in a frame [0x00 ... 0xff]
CFIndex __CoreWebSocketClientWriteFrame(CoreWebSocketClientRef client, const UInt8 *buffer, CFIndex length) {
  CFIndex bytes = -1;
  if (client) {
    if (buffer) {
      if (length > 0) {
        if (CFWriteStreamCanAcceptBytes(client->write)) {
          CFWriteStreamWrite(client->write, (UInt8[]){ 0x00 }, 1);
          bytes = CFWriteStreamWrite(client->write, buffer, length);
          CFWriteStreamWrite(client->write, (UInt8[]){ 0xff }, 1);
        } else {
          //printf("__CoreWebSocketClientWriteFrame: can't write to stream\n");
        }
      }
    }
  }
  return bytes;
}

CFIndex CoreWebSocketClientWriteWithData(CoreWebSocketClientRef client, CFDataRef value) {
  return __CoreWebSocketClientWriteFrame(client, CFDataGetBytePtr(value), CFDataGetLength(value));
}

CFIndex CoreWebSocketClientWriteWithString(CoreWebSocketClientRef client, CFStringRef value) {
  CFIndex bytes = -1;
  if (client) {
    if (value) {
      CFDataRef data = CFStringCreateExternalRepresentation(client->allocator, value, kCFStringEncodingUTF8, 0);
      if (data) {
        bytes = CoreWebSocketClientWriteWithData(client, data);
        CFRelease(data);
      }
    }
  }
  return bytes;
}

#pragma mark Read callback

bool __CoreWebSocketClientWriteHandShake(CoreWebSocketClientRef client);

void __CoreWebSocketClientReadCallBack(CFReadStreamRef stream, CFStreamEventType eventType, void *info) {
  CoreWebSocketClientRef client = info;
  if (client) {
    switch (eventType) {
      case kCFStreamEventOpenCompleted:
        break;

      case kCFStreamEventHasBytesAvailable:
        if (!client->didReadHandShake) {
          if (__CoreWebSocketClientReadHandShake(client)) {
            if (!client->didWriteHandShake) {
              if (CFWriteStreamCanAcceptBytes(client->write)) {
                if (__CoreWebSocketClientWriteHandShake(client)) {
//                  printf("Successfully written handshake\n");
                } else {
                  printf("TODO: Error writting handshake\n");
                }
              } else {
//                printf("TODO: Didn't handshake and client doesn't accept bytes yet. Write callback will handle writting handshake as soon as we can write.\n");
              }
            } else {
              printf("TODO: Just read handshake and handshake already written, shouldn't happen, fault?\n");
            }
            __CoreWebSocketAppendClient(client->webSocket, client);
          } else {
            printf("TODO: Didn't read handshake and __CoreWebSocketClientReadHandShake failed.\n");
          }
        } else {

          // Did handshake already and there are bytes to read.
          // It's incomming message.

          UInt8 b[4096];
          memset(b, 0, sizeof(b));
          CFIndex by = 0;
          if (CFReadStreamHasBytesAvailable(client->read)) {
            by = CFReadStreamRead(stream, b, sizeof(b) - 1);
            if (by > 2) {
              const char *from = (const char *)b + 1;
              const char *to = strchr(from, 0xff);
              while (to) {
                if (client->webSocket->callbacks.didClientReadCallback) {
                  CFDataRef data = CFDataCreate(client->allocator, (const void *)from, to - from);
                  if (data) {
                    CFStringRef string = CFStringCreateWithBytes(client->allocator, CFDataGetBytePtr(data), CFDataGetLength(data), kCFStringEncodingUTF8, 0);
                    if (string) {
                      client->webSocket->callbacks.didClientReadCallback(client->webSocket, client, string);
                      CFRelease(string);
                    }
                    CFRelease(data);
                  }
                }
                from = to + 2;
                to = strchr(from, 0xff);
              }
            }
            char *end = strchr((const char *)b, 0xff);
            if (end) {
              *end = 0x00;
            }
          } else {
            // Something was wrong with the message
          }
        }
        break;

      case kCFStreamEventErrorOccurred:
        break;

      case kCFStreamEventEndEncountered:
        break;

      default:
        break;
    }
  }
}

bool __CoreWebSocketClientWriteWithHTTPMessage(CoreWebSocketClientRef client, CFHTTPMessageRef message) {
  bool success = 0;
  if (client && message) {
    CFDataRef data = CFHTTPMessageCopySerializedMessage(message);
    if (data) {
      CFIndex written = CFWriteStreamWrite(client->write, CFDataGetBytePtr(data), CFDataGetLength(data));
      if (written == CFDataGetLength(data)) {
        success = 1; // TODO: do it properly
      }
      client->didWriteHandShake = 1;
      CFRelease(data);
    }
  }
  return success;
}

bool __CoreWebSocketClientWriteHandShakeDraftIETF_HYBI_00(CoreWebSocketClientRef client) {
  bool success = 0;
  if (client) {
    if (client->protocol == kCoreWebSocketProtocolDraftIETF_HYBI_00) {
      CFStringRef key1 = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-Websocket-Key1"));
      CFStringRef key2 = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-Websocket-Key2"));
      CFDataRef key3 = CFHTTPMessageCopyBody(client->handShakeRequestHTTPMessage);
      CFStringRef origin = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Origin"));
      CFStringRef host = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Host"));

      CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(NULL, 0);
      CFHTTPMessageAppendBytes(response, (const UInt8 *)"HTTP/1.1 101 Web Socket Protocol Handshake\r\n", 44);
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Upgrade"), CFSTR("WebSocket"));
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Connection"), CFSTR("Upgrade"));
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Sec-Websocket-Origin"), origin);

      CFMutableStringRef location = CFStringCreateMutable(client->allocator, 0);
      CFStringAppend(location, CFSTR("ws://"));
      CFStringAppend(location, host);
      CFStringAppend(location, CFSTR("/"));
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Sec-Websocket-Location"), location);
      CFRelease(location);

      // Set MD5 hash
      {
        CFMutableDataRef mutable = CFDataCreateMutable(client->allocator, 0);
        __CoreWebSocketDataAppendMagickNumberWithKeyValueString(mutable, key1);
        __CoreWebSocketDataAppendMagickNumberWithKeyValueString(mutable, key2);
        CFDataAppendBytes(mutable, CFDataGetBytePtr(key3), CFDataGetLength(key3));
        CFDataRef data = __CoreWebSocketCreateMD5Data(client->allocator, mutable);
        CFHTTPMessageSetBody(response, data);
        CFRelease(mutable);
        CFRelease(data);
      }

      //CFShow(response);

      success = __CoreWebSocketClientWriteWithHTTPMessage(client, response);

      CFRelease(response);

      CFRelease(host);
      CFRelease(origin);
      CFRelease(key3);
      CFRelease(key2);
      CFRelease(key1);
    }
  }
  return success;
}

// The source code has been copied and modified from
// http://www.opensource.apple.com/source/CFNetwork/CFNetwork-128/HTTP/CFHTTPAuthentication.c
// See _CFEncodeBase64 function. The source code has been released under
// Apple Public Source License Version 2.0 http://www.opensource.apple.com/apsl/
CFStringRef __CoreWebSocketCreateBase64StringWithData(CFAllocatorRef allocator, CFDataRef inputData) {
  unsigned outDataLen;
  CFStringRef result = NULL;
  unsigned char *outData = cuEnc64(CFDataGetBytePtr(inputData), (unsigned int)CFDataGetLength(inputData), &outDataLen);
  if(outData) {
    // current cuEnc64 appends \n and NULL, trim them
    unsigned char *c = outData + outDataLen - 1;
    while((*c == '\n') || (*c == '\0')) {
      c--;
      outDataLen--;
    }
    result = CFStringCreateWithBytes(allocator, outData, outDataLen, kCFStringEncodingASCII, FALSE);
    free(outData);
  }
  return result;
}

bool __CoreWebSocketClientWriteHandShakeDraftIETF_HYBI_06(CoreWebSocketClientRef client) {
  bool success = 0;
  if (client) {
    if (client->protocol == kCoreWebSocketProtocolDraftIETF_HYBI_06) {

      CFStringRef key = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-WebSocket-Key"));
      CFStringRef keyWithMagick = CFStringCreateWithFormat(client->allocator, NULL, CFSTR("%@%@"), key, CFSTR("258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
      CFDataRef keyWithMagickSHA1 = __CoreWebSocketCreateSHA1DataWithString(client->allocator, keyWithMagick, kCFStringEncodingUTF8);
      CFStringRef keyWithMagickSHA1Base64 = __CoreWebSocketCreateBase64StringWithData(client->allocator, keyWithMagickSHA1);

      //CFShow(keyWithMagickSHA1Base64);

      CFStringRef origin = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-WebSocket-Origin"));
      CFStringRef host = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Host"));

      CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(NULL, 0);
      CFHTTPMessageAppendBytes(response, (const UInt8 *)"HTTP/1.1 101 Switching Protocols\r\n", 44);
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Upgrade"), CFSTR("websocket"));
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Connection"), CFSTR("Upgrade"));
      CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Sec-WebSocket-Accept"), keyWithMagickSHA1Base64);

      success = __CoreWebSocketClientWriteWithHTTPMessage(client, response);

      CFRelease(response);

      CFRelease(keyWithMagickSHA1Base64);
      CFRelease(keyWithMagickSHA1);
      CFRelease(keyWithMagick);
      CFRelease(key);
      CFRelease(origin);
      CFRelease(host);
    }
  }
  return success;
}

bool __CoreWebSocketClientWriteHandShake(CoreWebSocketClientRef client) {
  bool success = 0;
  if (client->didReadHandShake) {
    if (!client->didWriteHandShake) {
      switch (client->protocol) {
        case kCoreWebSocketProtocolDraftIETF_HYBI_00:
          success = __CoreWebSocketClientWriteHandShakeDraftIETF_HYBI_00(client);
          break;
        case kCoreWebSocketProtocolDraftIETF_HYBI_06:
          success = __CoreWebSocketClientWriteHandShakeDraftIETF_HYBI_06(client);
          break;
        default:
          printf("Unknown protocol, can't write handshake. TODO: disconnect\n");
          // Unknown protocol, can't write handshake
          break;
      }
    }
  }
  return success;
}

void __CoreWebSocketClientWriteCallBack(CFWriteStreamRef stream, CFStreamEventType eventType, void *info) {
  CoreWebSocketClientRef client = info;
  if (client) {
    switch (eventType) {

      case kCFStreamEventCanAcceptBytes:
        if (!client->didWriteHandShake && client->didReadHandShake)
          __CoreWebSocketClientWriteHandShake(client);
        break;

      case kCFStreamEventEndEncountered:
        break;

      case kCFStreamEventErrorOccurred:
        printf("kCFStreamEventErrorOccurred (write)\n");
        CFErrorRef error = CFWriteStreamCopyError(stream);
        if (error) {
          CFShow(error);
          CFRelease(error);
        }
        break;

      default:
        break;
    }
  }
}

#pragma mark Lifecycle

CoreWebSocketClientRef CoreWebSocketClientCreate(CoreWebSocketRef webSocket, CFSocketNativeHandle handle) {
  CoreWebSocketClientRef client = NULL;
  if (webSocket) {
    client = CFAllocatorAllocate(webSocket->allocator, sizeof(CoreWebSocketClient), 0);
    if (client) {
      client->allocator = webSocket->allocator ? CFRetain(webSocket->allocator) : NULL;
      client->retainCount = 1;
      client->uuid = CFUUIDCreate(client->allocator);

      client->webSocket = CoreWebSocketRetain(webSocket);
      client->handle = handle;

      client->read = NULL;
      client->write = NULL;

      client->context.version = 0;
      client->context.info = client;
      client->context.copyDescription = NULL;
      client->context.retain = NULL;
      client->context.release = NULL;

      client->handShakeRequestHTTPMessage = NULL;
      client->didReadHandShake = 0;
      client->didWriteHandShake = 0;
      client->protocol = kCoreWebSocketProtocolUnknown;

      CFStreamCreatePairWithSocket(client->allocator, handle, &client->read, &client->write);
      if (!client->read || !client->write) {
        close(handle);
        fprintf(stderr, "CFStreamCreatePairWithSocket() failed, %p, %p\n", read, write);
      } else {
//        printf("ok\n");
      }

      CFReadStreamSetClient(client->read, kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, __CoreWebSocketClientReadCallBack, &client->context);
      CFWriteStreamSetClient(client->write, kCFStreamEventOpenCompleted | kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, __CoreWebSocketClientWriteCallBack, &client->context);

      CFReadStreamScheduleWithRunLoop(client->read, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
      CFWriteStreamScheduleWithRunLoop(client->write, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);

      if (!CFReadStreamOpen(client->read)) {
        printf("couldn't open read stream\n");
      } else {
//        printf("opened read stream\n");
      }

      if (!CFWriteStreamOpen(client->write)) {
        printf("couldn't open write stream\n");
      } else {
        //        printf("opened write stream\n");
      }
    }
  }
  return client;
}

CoreWebSocketClientRef CoreWebSocketClientRetain(CoreWebSocketClientRef client) {
  if (client)
    client->retainCount++;
  return client;
}

CoreWebSocketClientRef CoreWebSocketClientRelease(CoreWebSocketClientRef client) {
  if (client) {
    if (--client->retainCount == 0) {
      CFAllocatorRef allocator = client->allocator;

      if (client->read) {
        if (CFReadStreamGetStatus(client->read) != kCFStreamStatusClosed)
          CFReadStreamClose(client->read);
        CFRelease(client->read);
        client->read = NULL;
      }

      if (client->write) {
        if (CFWriteStreamGetStatus(client->write) != kCFStreamStatusClosed)
          CFWriteStreamClose(client->write);
        CFRelease(client->write);
        client->write = NULL;
      }
      CFRelease(client->uuid);
      client->uuid = NULL;
      CFAllocatorDeallocate(allocator, client);
      client = NULL;

      if (allocator)
        CFRelease(allocator);
    }
  }
  return client;
}

#pragma Handshake

// Return magic number for the key needed to generate handshake hash
uint32_t __CoreWebSocketGetMagicNumberWithKeyValueString(CFStringRef string) {
  uint32_t magick = -1;
  if (string) {
    UInt8 buffer[__CoreWebSocketMaxHeaderKeyLength];
    CFIndex usedBufferLength = 0;
    char numberBuffer[__CoreWebSocketMaxHeaderKeyLength];
    memset(numberBuffer, 0, sizeof(numberBuffer));
    CFIndex usedNumberBufferLength = 0;
    CFStringGetBytes(string, CFRangeMake(0, CFStringGetLength(string)), kCFStringEncodingASCII, 0, 0, buffer, sizeof(buffer), &usedBufferLength);
    UInt32 number = 0;
    UInt32 spaces = 0;
    for (int i = 0; i < usedBufferLength; i++) {
      if (buffer[i] >= '0' && buffer[i] <= '9')
        numberBuffer[usedNumberBufferLength++] = buffer[i];
      if (buffer[i] == ' ')
        spaces++;
    }
    if (spaces > 0) {
      number = (UInt32)strtoul(numberBuffer, NULL, 10);
      magick = number / spaces;
    }
  }
  return magick;
}

// Appends big-endian uint32 magic number with key string to the mutable data
bool __CoreWebSocketDataAppendMagickNumberWithKeyValueString(CFMutableDataRef data, CFStringRef string) {
  bool success = 0;
  if (data && string) {
    uint32_t magick = __CoreWebSocketGetMagicNumberWithKeyValueString(string);
    uint32_t swapped = CFSwapInt32HostToBig(magick);
    CFDataAppendBytes(data, (const void *)&swapped, sizeof(swapped));
    success = 1;
  }
  return success;
}

CFDataRef __CoreWebSocketCreateMD5Data(CFAllocatorRef allocator, CFDataRef value) {
  unsigned char digest[CC_MD5_DIGEST_LENGTH];
  CC_MD5((unsigned char *)CFDataGetBytePtr(value), (CC_LONG)CFDataGetLength(value), digest);
  return CFDataCreate(allocator, digest, CC_MD5_DIGEST_LENGTH);
}

CFDataRef __CoreWebSocketCreateSHA1DataWithData(CFAllocatorRef allocator, CFDataRef value) {
  unsigned char digest[CC_SHA1_DIGEST_LENGTH];
  CC_SHA1((unsigned char *)CFDataGetBytePtr(value), (CC_LONG)CFDataGetLength(value), digest);
  return CFDataCreate(allocator, digest, CC_SHA1_DIGEST_LENGTH);
}

CFDataRef __CoreWebSocketCreateSHA1DataWithString(CFAllocatorRef allocator, CFStringRef value, CFStringEncoding encoding) {
  CFDataRef data = NULL;
  if (value) {
    CFDataRef valueData = CFStringCreateExternalRepresentation(allocator, value, encoding, 0);
    if (valueData) {
      data = __CoreWebSocketCreateSHA1DataWithData(allocator, valueData);
      CFRelease(valueData);
    }
  }
  return data;
}

bool __CoreWebSocketClientHandShakeConsumeHTTPMessage(CoreWebSocketClientRef client) {
  bool success = 0;
  if (client) {
    UInt8 buffer[4096];
    CFIndex bytes = 0;
    client->handShakeRequestHTTPMessage = CFHTTPMessageCreateEmpty(client->allocator, 1);
    while (CFReadStreamHasBytesAvailable(client->read)) {
      if ((bytes = CFReadStreamRead(client->read, buffer, sizeof(buffer))) > 0) {
        CFHTTPMessageAppendBytes(client->handShakeRequestHTTPMessage, buffer, bytes);
      } else if (bytes < 0) {
        CFErrorRef error = CFReadStreamCopyError(client->read);
        CFShow(error);
        CFRelease(error);
        goto fin;
      }
    }
    success = 1;
  }
fin:
  return success;
}

bool __CoreWebSocketClientHandShakeUpdateProtocolBasedOnHTTPMessage(CoreWebSocketClientRef client) {
  bool success = 0;
  if (client) {

    // Get the protocol version
    client->protocol = kCoreWebSocketProtocolUnknown;
    CFStringRef upgrade = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Upgrade"));
    if (upgrade) {
      if (CFStringCompare(CFSTR("WebSocket"), upgrade, kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
        CFStringRef version = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-WebSocket-Version"));
        if (version) {
          if (CFStringCompare(CFSTR("6"), version, kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
            client->protocol = kCoreWebSocketProtocolDraftIETF_HYBI_06;
            success = 1;
          } else { // Version different than 6, we don't know of any other, leave the protocol as unknown
          }
          CFRelease(version);
        } else {

          // Sec-CoreWebSocket-Version header field is missing.
          // It may be 00 protocol, which doesn't have this field.
          // 00 protocol has to have Sec-CoreWebSocket-Key1 and Sec-CoreWebSocket-Key2
          // fields - let's check for those.
          CFStringRef key1 = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-WebSocket-Key1"));
          if (key1) {
            CFStringRef key2 = CFHTTPMessageCopyHeaderFieldValue(client->handShakeRequestHTTPMessage, CFSTR("Sec-WebSocket-Key2"));
            if (key2) {
              client->protocol = kCoreWebSocketProtocolDraftIETF_HYBI_00;
              success = 1;
              CFRelease(key2);
            }
            CFRelease(key1);
          } else { // Key2 missing, no version specified = unknown protocol
          }
        }
      } else { // Upgrade HTTP field seems to be different from "CoreWebSocket" (case ignored)
      }
      CFRelease(upgrade);
    } else { // Upgrade HTTP field seems to be absent
    }
  }
  return success;
}

bool __CoreWebSocketClientReadHandShake(CoreWebSocketClientRef client) {
  bool success = 0;
  if (client) {
    if ((success = __CoreWebSocketClientHandShakeConsumeHTTPMessage(client))) {
      if ((success = __CoreWebSocketClientHandShakeUpdateProtocolBasedOnHTTPMessage(client))) {

        // Dump http message
        CFDictionaryRef headerFields = CFHTTPMessageCopyAllHeaderFields(client->handShakeRequestHTTPMessage);
        if (headerFields) {
          //CFShow(headerFields);
          CFRelease(headerFields);
        }
//        printf("__CoreWebSocketClientReadHandShake: protocol %i\n", client->protocol);
      }
    }
    client->didReadHandShake = 1;
  }
  return success;
}


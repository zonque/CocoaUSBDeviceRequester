/***
 This file is part of CocoaUSBDeviceRequester
 
 Copyright 2010 Daniel Mack <daniel@caiaq.de>
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2.1 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with PulseAudio; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
 USA.
 ***/


#include <IOKit/IOKitLib.h>
#include <IOKit/IODataQueueShared.h>
#include <IOKit/IODataQueueClient.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

#include <pthread.h>
#include <mach/mach_port.h>

#import <CoreFoundation/CFMachPort.h>
#import <CoreFoundation/CFNumber.h>
#import <CoreFoundation/CoreFoundation.h>

__BEGIN_DECLS
#include <mach/mach.h>
#include <IOKit/iokitmig.h>
__END_DECLS

#import "DeviceRequesterAppDelegate.h"

@implementation USBDeviceRequesterAppDelegate

@synthesize window;
@synthesize deviceTable;
@synthesize deviceVID;
@synthesize devicePID;
@synthesize requestType;
@synthesize requestRecipient;
@synthesize bRequest;
@synthesize wValue;
@synthesize wIndex;
@synthesize memData;
@synthesize requestBox;
@synthesize setButton;
@synthesize getButton;
@synthesize resetButton;
@synthesize dataSize;

#pragma mark ######### static wrappers #########

static void
staticDeviceAdded (void *refCon, io_iterator_t iterator)
{
	USBDeviceRequesterAppDelegate *del = refCon;

	if (del)
		[del deviceAdded : iterator];
}

static void
staticDeviceRemoved (void *refCon, io_iterator_t iterator)
{
	USBDeviceRequesterAppDelegate *del = refCon;

	if (del)
		[del deviceRemoved : iterator];
}

#pragma mark ######### hotplug callbacks #########

- (void) deviceAdded: (io_iterator_t) iterator
{
	io_service_t		serviceObject;
	IOCFPlugInInterface	**plugInInterface = NULL;
	IOUSBDeviceInterface	**dev = NULL;
	SInt32			score;
	kern_return_t		kr;
	HRESULT			result;
	CFMutableDictionaryRef	entryProperties = NULL;

	while ((serviceObject = IOIteratorNext(iterator))) {
		printf("%s(): device added %d.\n", __func__, (int) serviceObject);
		IORegistryEntryCreateCFProperties(serviceObject, &entryProperties, NULL, 0);

		kr = IOCreatePlugInInterfaceForService(serviceObject,
						       kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
						       &plugInInterface, &score);

		if ((kr != kIOReturnSuccess) || !plugInInterface) {
			printf("%s(): Unable to create a plug-in (%08x)\n", __func__, kr);
			continue;
		}

		// create the device interface
		result = (*plugInInterface)->QueryInterface(plugInInterface,
							    CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
							    (LPVOID *)&dev);

		// don’t need the intermediate plug-in after device interface is created
		(*plugInInterface)->Release(plugInInterface);

		if (result || !dev) {
			printf("%s(): Couldn’t create a device interface (%08x)\n", __func__, (int) result);
			continue;
		}

		NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity: 0];

		UInt16 vendorID, productID;
		(*dev)->GetDeviceVendor(dev, &vendorID);
		(*dev)->GetDeviceProduct(dev, &productID);
		NSString *name = CFDictionaryGetValue(entryProperties, CFSTR(kUSBProductString));
		if (!name)
			continue;
		
		printf(" *dev = %p\n", *dev);

		[dict setObject: [NSString stringWithFormat: @"0x%04x", vendorID]
			 forKey: @"VID"];
		[dict setObject: [NSString stringWithFormat: @"0x%04x", productID]
			 forKey: @"PID"];
		[dict setObject: [NSString stringWithString: name]
			 forKey: @"name"];
		[dict setObject: [NSValue valueWithPointer: dev]
			 forKey: @"dev"];
		[dict setObject: [NSNumber numberWithInt: serviceObject]
			 forKey: @"service"];

		[deviceArray addObject: dict];
	}

	[deviceTable reloadData];
}

- (void) deviceRemoved: (io_iterator_t) iterator
{
	io_service_t serviceObject;

	while ((serviceObject = IOIteratorNext(iterator))) {
		NSEnumerator *enumerator = [deviceArray objectEnumerator];
		printf("%s(): device removed %d.\n", __func__, (int) serviceObject);
		NSDictionary *dict;

		while (dict = [enumerator nextObject]) {
			if ((io_service_t) [[dict valueForKey: @"service"] intValue] == serviceObject) {
				[deviceArray removeObject: dict];
				break;
			}
		}

		IOObjectRelease(serviceObject);
	}

	[deviceTable reloadData];

	if ([deviceTable selectedRow] < 0)
		[self setDeviceEnabled: NO];
}

#pragma mark ######### GUI related #########

- (void) listenForDevices
{
	OSStatus ret;
	CFRunLoopSourceRef runLoopSource;
	mach_port_t masterPort;
	kern_return_t kernResult;

	deviceArray = [[NSMutableArray alloc] initWithCapacity: 0];

	// Returns the mach port used to initiate communication with IOKit.
	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);

	if (kernResult != kIOReturnSuccess) {
		printf("%s(): IOMasterPort() returned %08x\n", __func__, kernResult);
		return;
	}

	classToMatch = IOServiceMatching(kIOUSBDeviceClassName);
	if (!classToMatch) {
		printf("%s(): IOServiceMatching returned a NULL dictionary.\n", __func__);
		return;
	}

	// increase the reference count by 1 since die dict is used twice.
	CFRetain(classToMatch);

	gNotifyPort = IONotificationPortCreate(masterPort);
	runLoopSource = IONotificationPortGetRunLoopSource(gNotifyPort);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);

	ret = IOServiceAddMatchingNotification(gNotifyPort,
					       kIOFirstMatchNotification,
					       classToMatch,
					       staticDeviceAdded,
					       self,
					       &gNewDeviceAddedIter);

	// Iterate once to get already-present devices and arm the notification
	[self deviceAdded: gNewDeviceAddedIter];

	ret = IOServiceAddMatchingNotification(gNotifyPort,
					       kIOTerminatedNotification,
					       classToMatch,
					       staticDeviceRemoved,
					       self,
					       &gNewDeviceRemovedIter);

	// Iterate once to get already-present devices and arm the notification
	[self deviceRemoved : gNewDeviceRemovedIter];

	// done with the masterport
	mach_port_deallocate(mach_task_self(), masterPort);
}

#pragma mark ######### table view data source protocol ############

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:obj
   forTableColumn:(NSTableColumn *)col
	      row:(NSInteger)rowIndex
{
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)col
	    row:(NSInteger)rowIndex
{
	NSDictionary *dict = [deviceArray objectAtIndex: rowIndex];
	return [dict valueForKey: [col identifier]];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [deviceArray count];
}

- (void) setDeviceEnabled: (BOOL) en
{
	[requestType setEnabled: en];
	[requestRecipient setEnabled: en];
	[bRequest setEnabled: en];
	[wIndex setEnabled: en];
	[wValue setEnabled: en];
	[dataSize setEnabled: en];
	[setButton setEnabled: en];
	[getButton setEnabled: en];
	[resetButton setEnabled: en];
	[memData setEditable: en];
	
	if (!en) {
		[deviceVID setStringValue: @"-"];
		[devicePID setStringValue: @"-"];
	}
}

#pragma mark ############ IBActions #############

- (IBAction) selectDevice: (id) sender
{
	NSInteger selectedRow = [sender selectedRow];

	if (selectedRow < 0) {
		[self setDeviceEnabled: NO];
		return;
	}

	[self setDeviceEnabled: YES];

	NSDictionary *dict = [deviceArray objectAtIndex: selectedRow];
	[deviceVID setStringValue: [dict valueForKey: @"VID"]];
	[devicePID setStringValue: [dict valueForKey: @"PID"]];
}


#pragma mark ############ NSApplication delegate protocol #############

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[memData setFont: [NSFont fontWithName: @"Courier New" size: 11]];
	[self listenForDevices];
	[self setDeviceEnabled: NO];
}

- (UInt) convertData: (unsigned char *) dest maxLength: (UInt) len
{
	char tmp[1024], *next;
	NSInteger n = 0;

	[[memData stringValue] getCString: tmp
				maxLength: sizeof(tmp)
				 encoding: NSASCIIStringEncoding];
        next = strtok(tmp, " ");
        while (next && n < len) {
		dest[n++] = strtol(next, NULL, 0);
		next = strtok(NULL, " ");
	}

	return n;
}

- (NSInteger) convertToInt: (NSString *) string
{
	char tmp[64];
	
	[string getCString: tmp
		 maxLength: sizeof(tmp)
		  encoding: NSASCIIStringEncoding];

	if (tmp[0] == '0' && tmp[1] == 'x')
		return strtol(tmp, NULL, 16);
	
	return strtol(tmp, NULL, 10);
}

- (void) makeRequestToDevice: (IOUSBDeviceInterface **) dev
       directionHostToDevice: (BOOL) directionHostToDevice
{
	HRESULT kr;
	IOUSBDevRequest req;
	UInt count;
	unsigned char tmp[1024];
	
	if (directionHostToDevice) {
		count = [self convertData: tmp
				maxLength: sizeof(tmp)];
		[dataSize setIntValue: count];
	} else {
		count = [dataSize intValue];
		[memData setStringValue: @""];
	}

	req.bmRequestType = USBmakebmRequestType(directionHostToDevice ? kUSBOut: kUSBIn,
						 [requestType indexOfSelectedItem],
						 [requestRecipient indexOfSelectedItem]);
	req.bRequest = [self convertToInt: [bRequest stringValue]];
	req.wValue = EndianS16_NtoL([self convertToInt: [wValue stringValue]]);
	req.wIndex = EndianS16_NtoL([self convertToInt: [wIndex stringValue]]);
	req.wLength = EndianS16_NtoL(count);
	req.pData = tmp;

	kr = (*dev)->DeviceRequest(dev, &req);

	if (kr)
		NSBeginCriticalAlertSheet(@"Request failed",
					  @"Oh, well.",
					  nil, nil,
					  [NSApp mainWindow],
					  nil, nil, nil, NULL,
					  @"OS reported error code %08x", kr);

	if (!directionHostToDevice) {
		char tmpstr[(5 * count) + 1];
		NSInteger i;

		memset(tmpstr, 0, sizeof(tmpstr));
		for (i = 0; i < count; i++)
			snprintf(tmpstr + (i * 5), 5, "0x%02x ", tmp[i]);
		
		[memData setStringValue: [NSString stringWithCString: tmpstr
							    encoding: NSASCIIStringEncoding]];
	}
}

- (void) makeRequestToSelectedDevice: (BOOL) outputDirection
{
	NSInteger selectedRow = [deviceTable selectedRow];
	NSDictionary *dict = [deviceArray objectAtIndex: selectedRow];
	IOUSBDeviceInterface **dev = [[dict valueForKey: @"dev"] pointerValue];
	
	[self makeRequestToDevice: dev
	    directionHostToDevice: outputDirection];	
}

- (IBAction) getData: (id) sender
{
	[self makeRequestToSelectedDevice: NO];
}

- (IBAction) setData: (id) sender
{
	[self makeRequestToSelectedDevice: YES];
}

- (IBAction) resetDevice: (id) sender
{
	NSInteger selectedRow = [deviceTable selectedRow];
	NSDictionary *dict = [deviceArray objectAtIndex: selectedRow];
	IOUSBDeviceInterface187 **dev = [[dict valueForKey: @"dev"] pointerValue];
	OSStatus kr;

	kr = (*dev)->USBDeviceOpen(dev);
	if (kr)
		NSBeginCriticalAlertSheet(@"Exclusive Device open failed",
					  @"Oh, well.",
					  nil, nil,
					  [NSApp mainWindow],
					  nil, nil, nil, NULL,
					  @"OS reported error code %08x", kr);
	
	kr = (*dev)->ResetDevice(dev);
	if (kr)
		NSBeginCriticalAlertSheet(@"Device reset failed",
					  @"Oh, well.",
					  nil, nil,
					  [NSApp mainWindow],
					  nil, nil, nil, NULL,
					  @"OS reported error code %08x", kr);

	kr = (*dev)->USBDeviceReEnumerate(dev, 0);
	if (kr)
		NSBeginCriticalAlertSheet(@"USBDeviceReEnumerate failed",
					  @"Oh, well.",
					  nil, nil,
					  [NSApp mainWindow],
					  nil, nil, nil, NULL,
					  @"OS reported error code %08x", kr);
}

@end

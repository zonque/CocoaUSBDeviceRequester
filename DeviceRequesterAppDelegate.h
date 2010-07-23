#import <Cocoa/Cocoa.h>

@interface USBDeviceRequesterAppDelegate : NSObject <NSApplicationDelegate> {
	NSWindow	*window;
	NSTableView	*deviceTable;
	NSTextField	*deviceVID;
	NSTextField	*devicePID;
	NSPopUpButton	*requestType;
	NSPopUpButton	*requestRecipient;
	NSTextField	*bRequest;
	NSTextField	*wValue;
	NSTextField	*wIndex;
	NSTextField	*dataSize;
	NSTextField	*memData;
	NSBox		*requestBox;
	NSButton	*setButton;
	NSButton	*getButton;

	NSMutableArray			*deviceArray;
	io_iterator_t			gNewDeviceAddedIter;
	io_iterator_t			gNewDeviceRemovedIter;
	IONotificationPortRef		gNotifyPort;
	CFMutableDictionaryRef		classToMatch;
}

@property (assign) IBOutlet NSWindow	*window;
@property (assign) IBOutlet NSTableView *deviceTable;
@property (assign) IBOutlet NSTextField *deviceVID;
@property (assign) IBOutlet NSTextField *devicePID;
@property (assign) IBOutlet NSTextField *bRequest;
@property (assign) IBOutlet NSTextField *wValue;
@property (assign) IBOutlet NSTextField *wIndex;
@property (assign) IBOutlet NSTextField *dataSize;
@property (assign) IBOutlet NSTextField	*memData;
@property (assign) IBOutlet NSBox	*requestBox;
@property (assign) IBOutlet NSButton	*setButton;
@property (assign) IBOutlet NSButton	*getButton;
@property (assign) IBOutlet NSPopUpButton *requestType;
@property (assign) IBOutlet NSPopUpButton *requestRecipient;


- (void) deviceAdded: (io_iterator_t) iterator;
- (void) deviceRemoved: (io_iterator_t) iterator;
- (void) setDeviceEnabled: (BOOL) en;

- (IBAction) selectDevice: (id) sender;
- (IBAction) setData: (id) sender;
- (IBAction) getData: (id) sender;
- (IBAction) dataChanged: (id) sender;

@end

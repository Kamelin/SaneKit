//
//  SKScanDevice.m
//  SaneKit
//
//  Created by MK on 03.09.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "SKScanDevice.h"
#import "SKStructs.h"
#include <sane/sane.h>
#include <math.h>
#include <assert.h>

@interface SKScanDevice (private)

+(void) checkParameters:(SANE_Parameters*) parameters;

@end


@implementation SKScanDevice (private)

+(void) checkParameters:(SANE_Parameters*) parameters
{
    if (!parameters || !parameters->format || !parameters->depth)
        return;
    
    // TODO: replace assert() calls
    switch (parameters->format)
    {
        case SANE_FRAME_RED:
        case SANE_FRAME_GREEN:
        case SANE_FRAME_BLUE:
            assert (parameters->depth == 8);
            break;
            
        case SANE_FRAME_GRAY:
            assert ((parameters->depth == 1)
                    || (parameters->depth == 8)
                    || (parameters->depth == 16));
        case SANE_FRAME_RGB:
            assert ((parameters->depth == 8)
                    || (parameters->depth == 16));
            break;
            
        default:
            break;
    }
}

@end


@implementation SKScanDevice

/**
 * Initialize the class.
 */
-(id) initWithName:(NSString*) aName vendor:(NSString*) aVendor model:(NSString*) aModel type:(NSString*) aType
{
    self = [super init];
    if (self)
    {
        name = [aName retain];
        vendor = [aVendor retain];
        model = [aModel retain];
        type = [aType retain];
        handle = malloc(sizeof(handle));
    }
    return self;
}


/**
 * Release all ressources
 */
-(void) dealloc
{
    [name release];
    [vendor release];
    [model release];
    [type release];
    free(handle);
    
    [super dealloc];
}


/**
 * Returns an NSString instance describing the SKScanDevice
 */
-(NSString*) description
{
    NSString* deviceDescription = [NSString stringWithFormat: @"ScanDevice:\n\tName: %@\n\tVendor: %@\n\tModel: %@\n\tType: %@\n", name, vendor, model, type];
    return deviceDescription;
}


/**
 * Open the scan device.
 *
 * @return YES if successful, NO otherwise
 */
-(BOOL) open
{
	SANE_Status openStatus = 0;
    openStatus = sane_open([name UTF8String], &(handle->deviceHandle));
    
    return (SANE_STATUS_GOOD == openStatus) ? YES : NO;
}


/**
 * Close the scan device.
 */
-(void) close
{
	sane_close(handle->deviceHandle);
}


/**
 * Prints all options available from the current device.
 */
-(void) printOptions
{
    SANE_Int numOptions = 0;
    SANE_Status optionStatus = 0;
    
    optionStatus = sane_control_option(handle->deviceHandle, 0, SANE_ACTION_GET_VALUE, &numOptions, 0);
    
    const SANE_Option_Descriptor* optionDescr;
    for (int i = 0; i < numOptions; ++i)
    {
        optionDescr = sane_get_option_descriptor(handle->deviceHandle, i);
        if (optionDescr && optionDescr->name)
            NSLog(@"Option #%d: %s", i, optionDescr->name);
    }
    
}


/**
 * Print the current parameters.
 */
-(void) printParameters
{
    SANE_Parameters parameters;
    SANE_Status status;
    status = sane_get_parameters(handle->deviceHandle, &parameters);
    NSLog(@"Parameters:\n\tFormat: %d\n\tLastFrame: %d\n\tBytes/Line: %d\n\tPixels/Line: %d\n\tLines: %d\n\tDepth: %d",
          parameters.format,
          parameters.last_frame,
          parameters.bytes_per_line,
          parameters.pixels_per_line,
          parameters.lines,
          parameters.depth
          );    
}


/**
 * This method does a basic scan but currently doesn't do anything with the read data.
 */
-(BOOL) doScan
{
	SANE_Status scanStatus = 0;
    SANE_Parameters scanParameters;
    
    scanStatus = sane_start (handle->deviceHandle);
    if (SANE_STATUS_GOOD != scanStatus)
    {
        NSLog(@"Sane start error: %s", sane_strstatus(scanStatus));
        return NO;
    }
    
    SANE_Int readBytes = 0;
    SANE_Int maxBufferSize = 32 * 1024;
    SANE_Byte* buffer = malloc(maxBufferSize);
    SANE_Word totalBytes = 0;

    do
    {
        scanStatus = sane_get_parameters(handle->deviceHandle, &scanParameters);
        if (SANE_STATUS_GOOD != scanStatus)
        {
            NSLog(@"Sane get parameters error: %s", sane_strstatus(scanStatus));
            free(buffer);
            return NO;
        }

        [SKScanDevice checkParameters: (&scanParameters)];

        if (scanParameters.lines >= 0)
            NSLog(@"Scanning image of size %dx%d pixels at %d bits/pixel\nFormat: %d\nDepth: %d",
                  scanParameters.pixels_per_line,
                  scanParameters.lines,
                  8 * scanParameters.bytes_per_line / scanParameters.pixels_per_line,
                  scanParameters.format,
                  scanParameters.depth
            );
        const int SCALE_FACTOR = ((scanParameters.format == SANE_FRAME_RGB || scanParameters.format == SANE_FRAME_GRAY) ? 1:3);
        int hundredPercent = scanParameters.bytes_per_line
                             * scanParameters.lines
                             * SCALE_FACTOR;
        do
        {
            scanStatus = sane_read(handle->deviceHandle, buffer, maxBufferSize, &readBytes);
            totalBytes += (SANE_Word)readBytes;
            double progr = ((totalBytes * 100.0) / (double) hundredPercent);
            progr = fminl(progr, 100.0);
            NSLog(@"Progress: %3.1f%%, total bytes: %d\n", progr, totalBytes);
        }
        while (SANE_STATUS_GOOD == scanStatus || SANE_STATUS_EOF != scanStatus);
    }
    while (!scanParameters.last_frame);
    
    sane_cancel(handle->deviceHandle);
    
    free(buffer);
    return YES;
}


@end

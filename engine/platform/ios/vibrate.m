/*
vibrate.m - iOS vibration support
Copyright (C) 2026 Xash3D FWGS contributors

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#import <AudioToolbox/AudioServices.h>
#import <CoreHaptics/CoreHaptics.h>

static CHHapticEngine *g_hapticEngine;
static id<CHHapticAdvancedPatternPlayer> g_hapticPlayer;

static bool IOS_HapticsAvailable( void )
{
	if( !@available( iOS 13.0, * ))
		return false;

	// doesn't depend on the actual device state, only on hardware support
	return [CHHapticEngine capabilitiesForHardware].supportsHaptics;
}

static bool IOS_HapticsInit( void )
{
	NSError *error = nil;

	g_hapticEngine = [[CHHapticEngine alloc] initAndReturnError:&error];
	if( !g_hapticEngine )
		return false;

	g_hapticEngine.resetHandler = ^{
		[g_hapticEngine startAndReturnError:nil];
	};

	g_hapticEngine.stoppedHandler = ^(CHHapticEngineStoppedReason stoppedReason) {
		[g_hapticEngine startAndReturnError:nil];
	};

	if( ![g_hapticEngine startAndReturnError:&error] )
	{
		[g_hapticEngine release];
		g_hapticEngine = nil;
		return false;
	}

	return true;
}

static void IOS_HapticsStop( void )
{
	if( g_hapticPlayer )
	{
		[g_hapticPlayer stopAtTime:0 error:nil];
		[g_hapticPlayer release];
		g_hapticPlayer = nil;
	}
}

void IOS_Vibrate( float time, int amplitude )
{
	if( time <= 0.0f || amplitude <= 0 )
	{
		IOS_HapticsStop();
		return;
	}

	if( !IOS_HapticsAvailable())
	{
		AudioServicesPlaySystemSound( kSystemSoundID_Vibrate );
		return;
	}

	@autoreleasepool
	{
		NSError *error = nil;

		if( !g_hapticEngine && !IOS_HapticsInit())
		{
			AudioServicesPlaySystemSound( kSystemSoundID_Vibrate );
			return;
		}

		IOS_HapticsStop();

		float intensity = (float)amplitude / 255.0f;
		if( intensity > 1.0f ) intensity = 1.0f;
		else if( intensity < 0.0f ) intensity = 0.0f;

		double duration = time / 1000.0; // time is in milliseconds
		if( duration < 0.05 )
			duration = 0.05; // CoreHaptics rejects too short continuous events

		CHHapticEventParameter *intensityParam = [[CHHapticEventParameter alloc]
			initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity];
		CHHapticEventParameter *sharpnessParam = [[CHHapticEventParameter alloc]
			initWithParameterID:CHHapticEventParameterIDHapticSharpness value:0.5f];
		CHHapticEvent *event = [[CHHapticEvent alloc]
			initWithEventType:CHHapticEventTypeHapticContinuous
			parameters:[NSArray arrayWithObjects:intensityParam, sharpnessParam, nil]
			relativeTime:0
			duration:duration];

		CHHapticPattern *pattern = [[CHHapticPattern alloc]
			initWithEvents:[NSArray arrayWithObject:event] parameters:nil error:&error];

		[event release];
		[sharpnessParam release];
		[intensityParam release];

		if( !pattern )
			return;

		g_hapticPlayer = [g_hapticEngine createAdvancedPlayerWithPattern:pattern error:&error];
		if( !g_hapticPlayer )
		{
			[pattern release];
			return;
		}

		[g_hapticPlayer retain];
		[pattern release];

		[g_hapticPlayer startAtTime:0 error:nil];
	}
}
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
#import <math.h>

static CHHapticEngine *g_hapticEngine API_AVAILABLE( ios(13.0) );
static id<CHHapticAdvancedPatternPlayer> g_hapticPlayer API_AVAILABLE( ios(13.0) );
static float g_impulseDuration = -1.0f;

static bool IOS_HapticsAvailable( void )
{
	if( !@available( iOS 13.0, * ))
		return false;

	// doesn't depend on the actual device state, only on hardware support
	return [CHHapticEngine capabilitiesForHardware].supportsHaptics;
}

static bool IOS_HapticsInit( void )
{
	if( !@available( iOS 13.0, * ))
		return false;

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
	if( !@available( iOS 13.0, * ))
		return;

	if( g_hapticPlayer )
	{
		[g_hapticPlayer stopAtTime:0 error:nil];
		[g_hapticPlayer release];
		g_hapticPlayer = nil;
		g_impulseDuration = -1.0f;
	}
}

void IOS_Vibrate( float time, int low_freq, int high_freq )
{
	if( time <= 0.0f )
	{
		IOS_HapticsStop();
		return;
	}

	if( !IOS_HapticsAvailable())
	{
		AudioServicesPlaySystemSound( kSystemSoundID_Vibrate );
		return;
	}

	if( !@available( iOS 13.0, * ))
		return;

	@autoreleasepool
	{
		NSError *error = nil;

		if( !g_hapticEngine && !IOS_HapticsInit())
		{
			AudioServicesPlaySystemSound( kSystemSoundID_Vibrate );
			return;
		}

		double duration = time / 1000.0; // time is in milliseconds
		if( duration < 0.05 )
			duration = 0.05; // CoreHaptics rejects too short continuous events
		if( duration > 0.5 )
			duration = 0.5; // keep the pattern bounded

		// single-motor phone: take the stronger of the two rumble channels for the
		// intensity, and use the channel balance as the sharpness - low frequency
		// jerks feel sharp and percussive, high frequency rumbles feel smooth
		int chan = ( low_freq > high_freq ) ? low_freq : high_freq;
		int sum = low_freq + high_freq;
		float mix = sum > 0 ? (float)high_freq / (float)sum : 0.5f;
		float intensity = (float)( 1 + ( chan * 254 ) / 0xFFFF ) / 255.0f;
		float sharpness = 1.0f - mix;

		if( !g_hapticPlayer || (float)fabs( g_impulseDuration - duration ) > 0.001f )
		{
			// the impulse length changed, rebuild the event and the player
			IOS_HapticsStop();

			CHHapticEventParameter *intensityParam = [[CHHapticEventParameter alloc]
				initWithParameterID:CHHapticEventParameterIDHapticIntensity value:intensity];
			CHHapticEventParameter *sharpnessParam = [[CHHapticEventParameter alloc]
				initWithParameterID:CHHapticEventParameterIDHapticSharpness value:sharpness];
			CHHapticEvent *event = [[CHHapticEvent alloc]
				initWithEventType:CHHapticEventTypeHapticContinuous
				parameters:[NSArray arrayWithObjects:intensityParam, sharpnessParam, nil]
				relativeTime:0
				duration:duration];

			CHHapticPattern *pattern = [[CHHapticPattern alloc]
				initWithEvents:[NSArray arrayWithObject:event] parameters:@[] error:&error];

			[event release];
			[sharpnessParam release];
			[intensityParam release];

			if( !pattern )
				return;

			g_hapticPlayer = [g_hapticEngine createAdvancedPlayerWithPattern:pattern error:&error];
			[pattern release];
			if( !g_hapticPlayer )
				return;

			[g_hapticPlayer retain];
			g_impulseDuration = duration;
		}
		else
		{
			// reuse the cached player, only update the strength of the running event
			CHHapticDynamicParameter *intensityDyn = [CHHapticDynamicParameter
				dynamicParameterWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:intensity];
			CHHapticDynamicParameter *sharpnessDyn = [CHHapticDynamicParameter
				dynamicParameterWithParameterID:CHHapticDynamicParameterIDHapticSharpnessControl value:sharpness];

			[g_hapticPlayer sendParameters:[NSArray arrayWithObjects:intensityDyn, sharpnessDyn, nil] atTime:0 error:&error];
		}

		[g_hapticPlayer startAtTime:0 error:nil];
	}
}
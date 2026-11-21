/**************************************************************************/
/*  register_types.cpp                                                  */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "register_types.h"

#include "audio_duck_mix.h"
#include "audio_mix_snapshot_controller.h"
#include "gameplay_attribute_set.h"
#include "gameplay_cooldown_tracker.h"
#include "gameplay_cue_queue.h"
#include "gameplay_effect_application_gate.h"
#include "gameplay_effect_stack_policy.h"
#include "gameplay_effect_timeline.h"
#include "radial_force_field_3d.h"
#include "sound_concurrency.h"
#include "sound_propagation.h"
#include "spatial_sound_event_policy.h"

#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_audio_mix_snapshot_controller.h"
#include "tests/test_spatial_sound_event_policy.h"
#endif

void initialize_gameplay_fx_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SoundConcurrency);
	GDREGISTER_CLASS(SoundConcurrencyManager);
	GDREGISTER_CLASS(SoundPropagation);
	GDREGISTER_CLASS(SpatialSoundEventPolicy);
	GDREGISTER_CLASS(RadialForceField3D);
	GDREGISTER_CLASS(GameplayEffectTimeline);
	GDREGISTER_CLASS(GameplayAttributeSet);
	GDREGISTER_CLASS(GameplayCooldownTracker);
	GDREGISTER_CLASS(GameplayCueQueue);
	GDREGISTER_CLASS(GameplayEffectApplicationGate);
	GDREGISTER_CLASS(GameplayEffectStackPolicy);
	GDREGISTER_CLASS(AudioDuckMix);
	GDREGISTER_CLASS(AudioMixSnapshotController);
}

void uninitialize_gameplay_fx_module(ModuleInitializationLevel) {
}

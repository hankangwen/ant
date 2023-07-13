#pragma once

#include <css/Property.h>
#include <core/Tween.h>
#include <core/ID.h>
#include <core/AnimationKey.h>

namespace Rml {

class ElementTransition {
public:
	ElementTransition(const Property& in_prop, const Property& out_prop, const Transition& transition);
	void Update(Element& element, PropertyId id, float delta);
	bool IsComplete() const { return animation_complete; }
	bool IsValid(Element& element);
	float GetTime() const { return time; }
protected:
	void UpdateProperty(Element& element, PropertyId id, float time);
protected:
	Property in_prop;
	Property out_prop;
	float time;
	float duration;
	Tween tween;
	bool animation_complete;
};

class ElementAnimation: public ElementTransition {
public:
	ElementAnimation(const Property& in_prop, const Property& out_prop, const Animation& animation);
	void AddKey(float target_time, const Property& property);
	bool IsValid(Element& element);
	void Update(Element& element, PropertyId id, float delta);
	const std::string& GetName() const { return name; }
protected:
	void UpdateProperty(Element& element, PropertyId id, float time);
private:
	std::string name;
	std::vector<AnimationKey> keys;
	int num_iterations;       // -1 for infinity
	int current_iteration;
	bool alternate_direction; // between iterations
	bool reverse_direction;
};

}

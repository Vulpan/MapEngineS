shader_type canvas_item;

uniform float speed : hint_range(0.5, 5.0) = 2.0;
uniform float min_alpha : hint_range(0.0, 1.0) = 0.1;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    float pulse = mix(min_alpha, max_alpha, (sin(TIME * speed) + 1.0) * 0.5);
    COLOR.a *= pulse;
}
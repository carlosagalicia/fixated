shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;   // 0..1
uniform float radius   : hint_range(0.0, 0.5) = 0.42;  // ring size in UV
uniform float thickness: hint_range(0.001, 0.2) = 0.06; // ring thickness

uniform vec4  fg_color : source_color = vec4(0.0, 0.0, 1.0, 1.0); // light blue
uniform vec4  bg_color : source_color = vec4(1.0, 1.0, 1.0, 0.15); // dim background

// Initial angle (in radians). -PI/2 = starting up
uniform float start_angle = -1.57079632679;

void fragment() {
    // centered UV (-0.5..0.5)
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    // soft anti-aliasing
    float aa = 0.002;

    // Ring mask
    float inner = radius - thickness * 0.5;
    float outer = radius + thickness * 0.5;

    float ring = smoothstep(inner - aa, inner + aa, dist) *
                 (1.0 - smoothstep(outer - aa, outer + aa, dist));

    // Angle 0..1, starting on start_angle
    float ang = atan(uv.y, uv.x);            // [-PI, PI]
    float a = ang - start_angle;             // displaces beggining
    // normalizes to [0, 2PI)
    a = mod(a + 6.28318530718, 6.28318530718);
    float t = a / 6.28318530718;             // [0,1)

    // Filled segment based on progress
    float fill = step(t, progress);

    vec4 col = mix(bg_color, fg_color, fill);
    col.a *= ring;

    COLOR = col;
}
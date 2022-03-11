#include "ShaderConstants.fxh"
#include "util.fxh"

struct PS_Input
{
    float3 pos: pos;
    float4 position : SV_Position;
    float2 uv : TEXCOORD_0_FB_MSAA;
};

struct PS_Output
{
    float4 color : SV_Target;
};

// ▼ Struct
struct Color {
    float3 sun_main;
    float3 sun_flare1;
    float3 sun_flare2;
    float3 moon_outside;
    float3 moon_inside;
    //float3 moon_light;
};
// ▲ Struct

// ▼ Functions

float hash(float2 p) {
    float3 p3 = frac(float3(p.xyx) * 0.13); 
    p3 += dot(p3, p3.yzx + 3.33); 
    return frac((p3.x + p3.y) * p3.z); 
}

float noise(in float2 st) {
    float2 i = floor(st);
    float2 f = frac(st);
    // Four corners in 2D of a tile
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    // Smooth Interpolation
    // Cubic Hermine Curve.  Same as SmoothStep()
    float2 u = f*f*(3.0-2.0*f);
    // u = smoothstep(0.,1.,f);
    // Mix 4 coorners percentages
    return lerp(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}

#define OCTAVES 8
float fbm(float2 x, float level) {
    float final = 0.0;
    float a = 0.5;
    for (int i = 0; i < OCTAVES; ++i) {
        final += a * noise(x);
        x *= 2.0;
        a *= 0.5;
        x.xy -= float(i + 1);
    }
    return saturate(final)*level;
}

float4 sun(float size, float3 color, float d) {
    return float4(float3(color), saturate(-d+1.*.5)*size);
}

float4 sun_cal(Color col, float d) {
    float4 main = sun(.75, col.sun_main, d);
    float4 flare1 = sun(1.5, col.sun_flare1, d);
    float4 flare2 = sun(4., col.sun_flare2, d);
    flare2 = smoothstep(-0.05, 1., flare2);
    return main/3. + flare1/3. + flare2/3.;
}

float4 moon_cal(float size, float d, float2 uv, Color col, float2 map_uv) {
    // Moon normal
    float3 moon_n = normalize(
        float3( uv, sqrt(size*size-d*d) )
    );
    // Light for Moon (pos)
    float moon_map_x = floor(map_uv.x*4.)*.25;
    float moon_map_y = step(.5, map_uv.y);
    float phase = (moon_map_x + moon_map_y)*3.14159265; // Moon phases
    float3 light = float3(
        sin(phase), 
        -.2, 
        -cos(-phase)
    );
    // Inner product of light and normal
    float moon_dot = dot(normalize(light), moon_n);

    float3 moon_shade = float3(moon_dot ,moon_dot, moon_dot);

    // Craters & Sea
    float craters = fbm(uv.yx*32., .2);
    float sea = fbm(uv.yx*12., .4);

    float4 result = float4(
        float3( // rgb
            lerp( // outside & inside COLOR
                col.moon_outside, 
                col.moon_inside + craters*.7 - sea*.5, 
                moon_shade
            )
        ),
        1. // alpha
    );

    return result;
}

// ▲ Funcitons

ROOT_SIGNATURE
void main(in PS_Input psi, out PS_Output PSOutput)
{
/*
#if !defined(TEXEL_AA) || !defined(TEXEL_AA_FEATURE) || (VERSION < 0xa000 /*D3D_FEATURE_LEVEL_10_0*//*) 
	float4 diffuse = TEXTURE_0.Sample(TextureSampler0, PSInput.uv);
#else
	float4 diffuse = texture2D_AA(TEXTURE_0, TextureSampler0, PSInput.uv);
#endif

#ifdef ALPHA_TEST
    if( diffuse.a < 0.5 )
    {
        discard;
    }
#endif

#ifdef IGNORE_CURRENTCOLOR
    PSOutput.color = diffuse;
#else
    PSOutput.color = CURRENT_COLOR * diffuse;
#endif

#ifdef WINDOWSMR_MAGICALPHA
    // Set the magic MR value alpha value so that this content pops over layers
    PSOutput.color.a = 133.0f / 255.0f;
#endif*/

struct Color col = { // Colors
    float3(1.0, 1.0, 0.786),        // Sun main color
    float3(1.0, 0.8, 0.2),          // Sun flare Color I
    float3(1.0, 0.4, 0.0),          // Sun flare Color II
    float3(0.0, 0.043, 0.1098)*1.3, // Moon outside color
    float3(0.7, 0.7, 0.75)*1.1      // Moon inside color
    //float3(0.6, 1.0, 1.0)         // Moonlight color
};

// ▼DB
float isRain = bool(step(FOG_CONTROL.x, 0.)) ? 0. : smoothstep(.5, .4, FOG_CONTROL.x);// With the exception of Underwater
float2 uv = psi.pos.xz;
float d = length(uv);
const float moon_r = .3; // Moon size
// ▲ DB

if (TEXTURE_0.Sample(TextureSampler0, float2(.5, .5)).r > .1) {
    // Output SUN
    float4 sun = sun_cal(col, d);
    sun.a = lerp(sun.a, 0., isRain);
    PSOutput.color = sun;
} else {
    // Output MOON
    PSOutput.color = moon_cal(moon_r, d, uv, col, psi.uv);

    /* moonlight没
    float4 moonlight = float4(float3(col.moon_light), saturate(-d+1.*.5)*8.);
    PSOutput.color = lerp(
        moonlight,
        moon_cal(moon_r, d, uv, col),
        saturate(step(d, moon_r))
    );
    */
}


}
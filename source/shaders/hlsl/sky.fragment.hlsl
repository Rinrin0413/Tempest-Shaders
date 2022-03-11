#include "ShaderConstants.fxh"

struct PS_Input {
    float4 position: SV_Position;
    float4 color: COLOR;
    float fog: fog;
    float3 pos: pos;
};

struct PS_Output {
    float4 color: SV_Target;
};

// ▼ Structs

struct Color {
    float3 day;
    float3 night;
    float3 twilight;
    float3 rain;
};

// ▲ Structs

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

float fbm(int octaves, float2 x, float s) {
    float final = 0.0;
    float a = 0.5;
    for (int i = 0; i < octaves; ++i) {
        final += a * noise(x);
        x *= 2.0;
        a *= 0.5;
        x.xy -= TOTAL_REAL_WORLD_TIME * s * float(i + 1);
    }
    return final;
}

float3 get_color(Color col, float isDay, float isTwilight, float isRain) {
    float3 result = lerp( // 晴雨分岐
        lerp( // 黄昏orその他分岐
            lerp(col.night, col.day, isDay), // 昼夜分岐
            col.twilight, 
            isTwilight
        ), 
        col.rain, 
        isRain
    );
    return result;
}

// ▲ Funcitons

ROOT_SIGNATURE
void main(in PS_Input psi, out PS_Output PSOutput)
{
    
/*+:｡. Tempest Shaders main sky .｡:+*/

float4 diffuse = CURRENT_COLOR;//psi.color

struct Color sky_col = { // Sky color
    float3(0.2, 0.467, 0.7372),        // Day sky color
    float3(0.0, 0.043, 0.1098),        // Night sky color
    float3(0.12549, 0.17647, 0.17647), // Dusk & Dawn sky color
    float3(0.0, 0.0, 0.0)              // Rainy sky color
};

struct Color cloud_col = { // Cloud color
    float3(0.8, 0.9, 1.0),            // Day cloud color
    float3(0.1686, 0.262745, 0.3882), // Night cloud color
    float3(0.525, 0.475, 0.425)*0.87, // Dusk & Dawn cloud color
    float3(0.7, 0.7, 0.7)             // Rainy cloud color
};

struct Color fog_col = { // Fog color
    float3(1.0, 1.0, 1.0),   // Day cloud color
    float3(0.0, 0.0, 0.0),   // Night cloud color
    FOG_COLOR.rgb,           // Dusk & Dawn cloud color
    float3(0.78, 0.78, 0.78) // Rainy cloud color
};

// ▼DB
float isDay = saturate(CURRENT_COLOR.b + CURRENT_COLOR.g); // ex: lerp(night, day, isDay)
float isRain = bool(step(FOG_CONTROL.x, 0.)) ? 0. : smoothstep(.5, .4, FOG_CONTROL.x);// With the exception of Underwater
float isTwilight = clamp((FOG_COLOR.r-.1)-FOG_COLOR.b,0.,.5)*2.;// Dusk & Dawn | ex: lerp(other, dust&dawn, isTwilight)
// ▲ DB

// Color calculation
float3 sky_color = get_color(sky_col, isDay, isTwilight, isRain);
float3 cloud_color = get_color(cloud_col, isDay, isTwilight, isRain);
float3 fog_colour = get_color(fog_col, isDay, isTwilight, isRain);

// Cloud calculation 
float2 uv = float2(psi.pos.x, psi.pos.z); // 2D
float cloud_lower = lerp(0.5, -0.2, isRain); // On a rainy day, the clouds will be deeper

float cloud = fbm( // MAIN CLOUD
    16, // Octaves
    sin(uv.xy)*10., // Shape
    .05 // Speed .05
);

if (cloud > 0.) { // CLOUD SHADOW I
    float cloud_shadow = fbm(
        8, // Octaves
        sin(uv.xy)*9.5, // Shape
        .05 // Speed .05
    );
    cloud_color *= lerp(1., .63, smoothstep(.54, .88, cloud_shadow));
}

if (cloud > .7) { // CLOUD SHADOW II
    float cloud_shadow = fbm(
        4, // Octaves
        sin(uv.xy)*9., // Shape
        .05 // Speed .05
    );
    cloud_color *= lerp(1., .9, smoothstep(.6, .99, cloud_shadow));
}

// Rendering

float3 sky_result = lerp(sky_color, cloud_color, smoothstep(cloud_lower, 0.68, cloud));

float sky = smoothstep(0.5, 0.0, psi.fog);
float adyss = smoothstep(0.65, 0.0, psi.fog);

diffuse.rgb = lerp(lerp(fog_colour, CURRENT_COLOR, adyss), sky_result, sky);

/*えらーかくにんよう*/ //diffuse.rgb = 0.0;

/*+:^\ ▲ Tempest Shaders sky END ▲ /^:+*/

PSOutput.color = diffuse;//lerp( diffuse, FOG_COLOR, psi.fog )
}
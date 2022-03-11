#include "ShaderConstants.fxh"

struct PS_Input
{
    float4 position : SV_Position;
    float4 color : COLOR;
};

struct PS_Output
{
    float4 color : SV_Target;
};

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

// ▲ Functions

ROOT_SIGNATURE
void main(in PS_Input psi, out PS_Output PSOutput)
{
    //PSOutput.color = PSInput.color;
    //PSOutput.color.rgb *= CURRENT_COLOR.rgb * PSInput.color.a;
    const float scale = 16.;
    float3 pos = psi.position.xyz;
    float r = noise(pos.xy/pos.z*scale);
    float g = noise(pos.xz/pos.y*scale);
    float b = noise(pos.zy/pos.x*scale);
    PSOutput.color = saturate(float4(r, g, b, 1.) + .66);
}
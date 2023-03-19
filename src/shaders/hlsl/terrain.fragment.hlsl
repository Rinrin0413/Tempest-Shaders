#include "ShaderConstants.fxh"
#include "util.fxh"

struct PS_Input {
	float4 position: SV_Position;
	float3 pos: pos;
	float waterFlag: waterFlag;
	float3 wP: Wp;
	#ifndef BYPASS_PIXEL_SHADER
		lpfloat4 color: COLOR;
		snorm float2 uv0: TEXCOORD_0_FB_MSAA;
		snorm float2 uv1: TEXCOORD_1_FB_MSAA;
	#endif
	#ifdef FOG
		float4 fogColor: FOG_COLOR;
	#endif
};

struct PS_Output {
	float4 color: SV_Target;
};

// ▼ Struct
struct LightColor {
	float3 primary;
	float3 rain;
	float3 underwater;
	float3 deep_underwater;
};

struct EnvironmentColor {
	float3 day;
	float3 night;
	float3 twilight;
	float3 twilight_top;
};

struct FogColor {
	float3 day;
	float3 night;
	float3 twilight;
	float3 rain;
};

struct Color {
    float3 day;
    float3 night;
    float3 twilight;
    float3 rain;
};

struct SunMoonColor {
	float3 sun_main;
	float3 sun_flare;
	float3 moon_main;
	float3 moonlight;
};
// ▲ Struct

// ▼ Functions

float3 lighting(float3 color, float light) {
	if (light < 0.937) { 
		return color*5.;
	} else {
		return color*2.5;
	}
}

// https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
float3 ACESFilm(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

float grayscale(float3 col) {
    return dot(col, float3(.22, .707, .071));
}

float hash(float2 p) {
    float3 p3 = frac(float3(p.xyx) * 0.13); 
    p3 += dot(p3, p3.yzx + 3.33); 
    return frac((p3.x + p3.y) * p3.z); 
}

float noise (in float2 st) {
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

    //st.x -= TOTAL_REAL_WORLD_TIME * 0.03 * st.x;

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

float get_wave(float3 pos) {
	float t = TOTAL_REAL_WORLD_TIME;
	float result = noise(t * 1.7 + pos.xz + pos.z*3.) 
        - noise(t*.39 + pos.xz + float2(t*1.2 + pos.x*.5 + sin(pos.z), t*1.6 + cos(-pos.x) + pos.z*1.4));
		// OLD_WAVE: noise(t * 1.7 + pos.xz) - noise(t*.39 + pos.xz + float2(t*1.2 + pos.x + sin(pos.z), t*1.6 + cos(-pos.x) + pos.z*2.4));
	return result*.052; //*.05
}

float3 get_wave_normal(float3 pos) {
    static const float step = .05;
    float height = get_wave(pos);
    float2 dxy = height - float2(
		get_wave(pos + float3(step, 0., 0.)),
        get_wave(pos + float3(0., 0., step))
	);
    return normalize(float3(dxy/step, 1.));
}

float3x3 get_tbn_mat(const float3 normal) {
    float3 t = float3(abs(normal.y) + normal.z, 0., normal.x);
    float3 b = cross(t, normal);
    float3 n = float3(-normal.x, normal.y, normal.z);
    return float3x3(t, b, n);
}

/*
float3x3 get_tbn_mat_TEST(const float3 normal) {
    float3 t = normalize(cross(normal, float3(-1., 0., 0.)));
    float3 n = normalize(normal);
    float3 b = cross(n, t)*2.;
    return transpose(float3x3(t, b, n));
}
*/

float3 tex_height_normal(float2 uv, float2 px, float scale) {
    float2 step = 1./px;
    float height = TEXTURE_0.Sample(TextureSampler0, uv).r;
    float2 dxy = height - float2(
		TEXTURE_0.Sample(TextureSampler0, uv + float2(step.x, 0.)).r,
        TEXTURE_0.Sample(TextureSampler0, uv + float2(0., step.y)).r
	);
    return normalize(float3(dxy*scale/step, 1.));
}

bool isPlants(float3 col, float3 pos) {
    float3 pos_fc = frac(pos.xyz);
    #if defined(ALPHA_TEST)
        return (col.g != col.b && col.r < col.g + col.b) || (pos_fc.y == .9375 && (pos_fc.z == 0. || pos_fc.x == 0.));
    #else
        return false;
    #endif
}

bool isBlend() {
	#ifdef BLEND
		return true;
	#else
		return false;
	#endif
}

bool isColorless(float3 rgb) {
	return rgb.r == rgb.g && rgb.g == rgb.b;
}

// ▲ Functions


ROOT_SIGNATURE
void main(in PS_Input psi, out PS_Output PSOutput)
{
#ifdef BYPASS_PIXEL_SHADER
    PSOutput.color = float4(0.0f, 0.0f, 0.0f, 0.0f);
    return;
#else

#if USE_TEXEL_AA
	float4 diffuse = texture2D_AA(TEXTURE_0, TextureSampler0, psi.uv0 );
#else
	float4 diffuse = TEXTURE_0.Sample(TextureSampler0, psi.uv0);
#endif

#if USE_ALPHA_TEST
	#ifdef ALPHA_TO_COVERAGE
		#define ALPHA_THRESHOLD 0.05
	#else
		#define ALPHA_THRESHOLD 0.5
	#endif
	if(diffuse.a < ALPHA_THRESHOLD)
		discard;
#endif

#if defined(BLEND)
	diffuse.a *= psi.color.a;
#endif

/*#if !defined(ALWAYS_LIT)
	diffuse = diffuse * TEXTURE_1.Sample(TextureSampler1, psi.uv1);
#endif*/
#if !defined(ALWAYS_LIT)
    diffuse = diffuse * TEXTURE_1.Sample(TextureSampler1, float2(psi.uv1.x * .5, psi.uv1.y));
#endif

#ifndef SEASONS
	#if !USE_ALPHA_TEST && !defined(BLEND)
		diffuse.a = psi.color.a;
	#endif	

	diffuse.rgb *= psi.color.rgb;
#else
	float2 uv = psi.color.xy;
	diffuse.rgb *= lerp(1.0f, TEXTURE_2.Sample(TextureSampler2, uv).rgb*2.0f, psi.color.b);
	diffuse.rgb *= psi.color.aaa;
	diffuse.a = 1.0f;
#endif

/*+:｡. Tempest Shaders main shading .｡:+*/

struct LightColor light_col = { // Light color
	float3(1.0, 1.0, 0.56),    // Primary light color
	float3(1.0, 1.0, 1.0)*0.7, // Rain light color
	float3(0.1, 1.0, 0.7)*2.1, // Underwater light color
	float3(0.3, 0.5, 1.0)*1.8  // Deep underwater color
};

struct EnvironmentColor env_col = { // Environment color
	float3(1.0, 1.036, 1.1)*1.5,      // Day env. color
	float3(0.94, 0.97, 1.0)*0.8,      // Night env. color
	float3(0.87, 0.4, 0.0)*.25 - .34, // Dast & Dawn env. color
	float3(0.73, 0.4, 0.0)*.4         // Dast & Dawn env. color(top)
};

struct FogColor fog_col = { // Fog color
	float3(0.75, 0.8, 0.9),      // Day fog color 
	float3(0.0, 0.05, 0.1)-0.5,  // Night fog color
	float3(0.82, 0.35, 0.0)*0.7, // Dask & Dawn fog color
	float3(0.6, 0.7, 0.8)        // Rain fog color
};

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

struct Color sky_fog_col = { // Fog color
    float3(1.0, 1.0, 1.0),   // Day cloud color
    float3(0.0, 0.0, 0.0),   // Night cloud color
    FOG_COLOR.rgb,           // Dusk & Dawn cloud color
    float3(0.78, 0.78, 0.78) // Rainy cloud color
};

struct SunMoonColor sm_col = { // Sun & Moon color
	float3(2.0, 1.2, 1.0)*2., // Sun main color
	float3(1.0, 1.0, 0.8)/2., // Sun flare color 
	float3(1.0, 1.3, 1.5)*2., // Moon main color
	float3(0.8, 1.0, 1.0)/2.  // Moonlight color
};

// ▼ DB
float isDay = TEXTURE_1.Sample(TextureSampler1, float2(0., 1.)).r; // ex: lerp(night, day, isDay)
float isRain = smoothstep(.5, .4, FOG_CONTROL.x); // ex: lerp(other, rain, isRain)
float isTwilight = clamp((FOG_COLOR.r-0.1)-FOG_COLOR.b,0.0,0.5)*2.0; // ex: lerp(other, dust&dawn, isTwilight)
float3 n = normalize(cross(ddx(-psi.pos), ddy(psi.pos))); // surface normal
if(psi.waterFlag > .5) { // TBN mat
	float3 wave_n = get_wave_normal(psi.pos);
	n = mul(get_tbn_mat(n), wave_n);
} else {
	float normal_px = lerp(2048., 4096., isRain);
	float normal_scale = lerp(.00032, .00016, isRain);
	float3 tex_height_n = tex_height_normal(psi.uv0, normal_px, normal_scale);
	n = mul(get_tbn_mat(n), tex_height_n);
}
float isTop = saturate(n.y);
float3 pos = psi.pos.xyz; // pos
float trwt = TOTAL_REAL_WORLD_TIME; // TIME
// ▲ DB

// Tone map
diffuse.rgb = ACESFilm(diffuse.rgb);

// Shadows
float3 gs = grayscale(diffuse.rgb);
float3 shadow_col = lerp(gs + 1.5, gs*1.7, isDay); // too dark, so adjusted the shadows at night.
float3 shadow = lerp(shadow_col, 1., smoothstep(.775, .823, psi.uv1.y));
diffuse.rgb *= lerp(shadow, 1., psi.uv1.x);

// Light
float3 light_color = lighting( lerp(light_col.primary, light_col.rain, isRain), psi.uv1.x );
float3 light_color_underwater = lighting( lerp(light_col.deep_underwater,  light_col.underwater, psi.uv1.y), psi.uv1.x ); // Under Water

float light_intensity = psi.uv1.x * psi.uv1.x * psi.uv1.x * psi.uv1.x * psi.uv1.x * psi.uv1.x * psi.uv1.x * psi.uv1.x;
float3 suppress_by_sunlight = lerp(1., lerp(lerp(.34, .1, psi.uv1.y), lerp(1., .2, psi.uv1.y), isRain), isDay);
					 // Note: lerp(夜, lerp(lerp(内昼晴, 外昼晴,    y), lerp(内昼雨, 外昼雨,  y) 

if (FOG_CONTROL.x != 0.) {
    diffuse.rgb *= lerp(1., light_color , light_intensity*2.*suppress_by_sunlight);
} else {
    diffuse.rgb *= lerp(1., light_color_underwater , light_intensity)*max(psi.uv1.x-1.8, 1.);
}

// ▼ Env.
// Day Night env.
diffuse.rgb *= lerp( // day night BRANCH
	env_col.night, // Night env.
	env_col.day, // Day env.
	isDay
);
// Twilight env.
diffuse.rgb += lerp( // {In, Out}door BRANCH
	0.,
	lerp(
		0., 
		lerp(env_col.twilight, env_col.twilight_top, isTop), 
		isTwilight
	),
	psi.uv1.y
);
// Rainy(day && outdoor) env.
diffuse.rgb *= lerp(1., lerp(1., lerp(1., .6, psi.uv1.y), isDay), isRain);
// ▲ Env.

// ▼ Underwater
if(FOG_CONTROL.x == 0.) {
	diffuse.rgb += float3(0.4, 0.5, 1.0)/4. - .3;
	float light_intensity = smoothstep(
    	.66,
        1.,
        abs(saturate(abs(
            noise(pos.xz*.8) 
				- noise(pos.xz*.4 + float2(trwt*1.8 + pos.x*1.6 + pos.z*.4, trwt + pos.x/10.))
        )) -1.)
    )*lerp(.26, 1., psi.uv1.y);
	diffuse.rgb = lerp(
		diffuse.rgb*.7, 
		lerp(diffuse.rgb, 1.7, .37), 
		light_intensity
	);
}
// ▲ Underwater

// ▼ Reflection
float3 pos_n = reflect(normalize(psi.wP.xyz), n);
float2 pos_ref = pos_n.zx/pos_n.y;
float cloud = smoothstep(
    .5,
	.68,
    fbm(
	    16, // Octaves
        pos_ref, // Shape
    	.05 // Speed
	)
) + lerp(0., .17, isRain);
float3 sky_color = lerp(
    0.,
	get_color(sky_col, isDay, isTwilight, isRain),
    .53
);
float3 cloud_color = get_color(cloud_col, isDay, isTwilight, isRain);
float3 sky_fog_color = get_color(sky_fog_col, isDay, isTwilight, isRain);
float cloud_lower = lerp(0.5, -.3, isRain); // On a rainy day, the clouds will be deeper
float3 sky = lerp(
	sky_color,
	lerp(
		sky_color, 
		cloud_color, 
		smoothstep(cloud_lower, 1.5, cloud)
	),
	smoothstep(0., .3, pos_n.y)
);

float3 sm_pos = lerp( // Sun Moon pos
	float3(-2., 2., 0.), // Moon
	float3(.85, 1., 0.), // Sun
	isDay
);
float3 sm_coord = cross(normalize(pos_n), sm_pos);
float3 sm_ref = abs(saturate(
	dot(sm_coord, sm_coord)*dot(sm_coord, sm_coord)
) - 1.);
float3 sun_main_ref = smoothstep(.98, 1., sm_ref);
float3 sun_flare_ref = smoothstep(.67, 1., sm_ref) - sun_main_ref;
float3 moon_main_ref = smoothstep(.99, 1., sm_ref);
float3 moonlight_ref = smoothstep(.65, 1., sm_ref) - moon_main_ref;
float3 sm_main_col = lerp(sm_col.moon_main, sm_col.sun_main, isDay);
float3 sm_main_ref = lerp(moon_main_ref, sun_main_ref, isDay);
float3 sm_sub_col = lerp(sm_col.moonlight, sm_col.sun_flare, isDay);
float3 sm_sub_ref = lerp(moonlight_ref, sun_flare_ref, isDay);
const float star_scale = 128.;
float3 star_col = float3(
	noise(psi.wP.xy/psi.wP.z*star_scale),
	noise(psi.wP.xz/psi.wP.y*star_scale),
	noise(psi.wP.zy/psi.wP.x*star_scale)
) + .74;
float star = lerp(
	smoothstep(0.97, 1.0, noise(pos_n.xz*65.)),
	0.,
	isDay
);

// ▽ ALBEDO

// sky&cloud & Fog
float3 albedo = lerp(
	sky_fog_color, 
	sky, 
	smoothstep(-1.2, .15, pos_n.y)
);	
// Sun Flare || Moonlight
albedo += lerp(0., sm_sub_col, sm_sub_ref);
// {Sun, Moon} main
albedo += lerp(0., sm_main_col, sm_main_ref);
// Sun Moon alpha
float albedo_alpha = lerp(0., .6, sm_main_ref);
// Stars
albedo = lerp(albedo, star_col, star);

// ▽ BRANCH(WaterSurface, Other)

// Water surface reflection
if(psi.waterFlag > .5) {
	diffuse.a -= .1;
	// In the shade...
	diffuse.rgb = lerp( 
		lerp(
			float3(0.,.02,.05) + .23, // Lower side color 
			float3(0.,0.,0.),  // Base color
			smoothstep(-1.2, .15, pos_n.y)
		),
		albedo.rgb, 
		psi.uv1.y
	);
	diffuse.a = lerp(.4, diffuse.a + albedo_alpha, psi.uv1.y);

// Other reflections
} else {
	if(FOG_CONTROL.x != 0.) { // not Underwater
    	if( // Main Reflection
    		(
    			isBlend() || 
    			(
    				TEXTURE_0.Sample(TextureSampler0, psi.uv0).a < .9 &&
    				TEXTURE_0.Sample(TextureSampler0, psi.uv0).a > 0.874 &&
    				!isPlants(psi.color.rgb, pos.xyz) &&
    				isColorless(psi.color.rgb)
    			)
    		)
    	) {
    		diffuse.rgb = lerp( // In the rain...
    			lerp( // In the shade...
    				diffuse.rgb,
    				lerp(diffuse.rgb, albedo, .5), 
    				psi.uv1.y
    			),
    			diffuse.rgb,
    			isRain
    		);
    		diffuse.a += lerp(0., albedo_alpha, psi.uv1.y);
    	}
		// Puddles
		diffuse.rgb = lerp(
			diffuse.rgb, 
			lerp(
				diffuse.rgb, 
				lerp(
					diffuse.rgb, 
					lerp(diffuse.rgb, sky, .39), 
					isTop
				), 
				psi.uv1.y
			), 
			isRain
		);
	}
}
// ▲ Reflection

// ▼ Fog
float3 fog_colour = lerp( // 雨天分岐
	lerp( // 夕分岐
		lerp( // 昼夜分岐
			fog_col.night, 
			fog_col.day, 
			isDay
		), 
		fog_col.twilight, 
		isTwilight
	), 
	fog_col.rain, 
	isRain
);

float rain_dist = lerp(1., .42, isRain);
float fog_level = smoothstep(0., RENDER_DISTANCE*1.3*rain_dist, length(psi.wP));
diffuse.rgb = lerp(diffuse.rgb, fog_colour, fog_level);
// ▲ Fog

//diffuse.rgb = normalize(cross(ddx(-psi.pos), ddy(psi.pos))) + .5; // view normal

/*+:^\ ▲ Tempest Shaders main shading END ▲ /^:+*/

PSOutput.color = diffuse / 1.2;

#ifdef VR_MODE
	// On Rift, the transition from 0 brightness to the lowest 8 bit value is abrupt, so clamp to 
	// the lowest 8 bit value.
	PSOutput.color = max(PSOutput.color, 1 / 255.0f);
#endif

#endif // BYPASS_PIXEL_SHADER
}
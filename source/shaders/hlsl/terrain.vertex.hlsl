#include "ShaderConstants.fxh"

struct VS_Input {
	float3 position : POSITION;
	float4 color : COLOR;
	float2 uv0 : TEXCOORD_0;
	float2 uv1 : TEXCOORD_1;
#ifdef INSTANCEDSTEREO
	uint instanceID : SV_InstanceID;
#endif
};


struct PS_Input {
	float4 position : SV_Position;
	float3 pos : pos;
	float waterFlag : waterFlag;
	float3 wP : Wp;

#ifndef BYPASS_PIXEL_SHADER
	lpfloat4 color : COLOR;
	snorm float2 uv0 : TEXCOORD_0_FB_MSAA;
	snorm float2 uv1 : TEXCOORD_1_FB_MSAA;
#endif

#ifdef FOG
	float4 fogColor : FOG_COLOR;
#endif
#ifdef GEOMETRY_INSTANCEDSTEREO
	uint instanceID : SV_InstanceID;
#endif
#ifdef VERTEXSHADER_INSTANCEDSTEREO
	uint renTarget_id : SV_RenderTargetArrayIndex;
#endif
};


static const float rA = 1.0;
static const float rB = 1.0;
static const float3 UNIT_Y = float3(0, 1, 0);
static const float DIST_DESATURATION = 56.0 / 255.0; //WARNING this value is also hardcoded in the water color, don'tchange

// ▼ Functions
bool isPlants(float3 col, float3 pos) {
    float3 pos_fc = frac(pos.xyz);
    #if defined(ALPHA_TEST)
        return (col.g != col.b && col.r < col.g + col.b) || (pos_fc.y == .9375 && (pos_fc.z == 0. || pos_fc.x == 0.));
    #else
        return false;
    #endif
}
// ▲ Functions

ROOT_SIGNATURE
void main(in VS_Input vsi, out PS_Input PSInput)
{
PSInput.waterFlag = 0.0;
PSInput.pos = vsi.position.xyz;
#ifndef BYPASS_PIXEL_SHADER
	PSInput.uv0 = vsi.uv0;
	PSInput.uv1 = vsi.uv1;
	PSInput.color = vsi.color;
#endif

#ifdef AS_ENTITY_RENDERER
	#ifdef INSTANCEDSTEREO
		int i = vsi.instanceID;
		PSInput.position = mul(WORLDVIEWPROJ_STEREO[i], float4(vsi.position, 1));
	#else
		PSInput.position = mul(WORLDVIEWPROJ, float4(vsi.position, 1));
	#endif
		float3 worldPos = PSInput.position;
#else
		float3 worldPos = (vsi.position.xyz * CHUNK_ORIGIN_AND_SCALE.w) + CHUNK_ORIGIN_AND_SCALE.xyz;

	// ▼ Waves
	// DB
	float3 p = abs(vsi.position.xyz - 8.);
	float trwt = TOTAL_REAL_WORLD_TIME;
	// Water wave
	#ifdef BLEND
		if(vsi.color.b > vsi.color.r) {
    		worldPos.y += sin(p.x*.8 + p.y + p.z*1.6 + trwt*1.3)*.047 - .0625;
		}
	#endif
	// Underwater refract
	if(FOG_CONTROL.x == 0.0) {
		worldPos.xz += sin(p.x + p.y + p.z + trwt*1.9)*.06;
	}
	// Plants wave
	if(isPlants(vsi.color.rgb, vsi.position.xyz)) {
		worldPos.x += cos(p.x*1.13 + p.y*.84 + p.z*.9 + trwt*1.7)*.05*lerp(.15, 1., vsi.uv1.y);
	}
	// ▲ Waves

	#ifdef INSTANCEDSTEREO
		int i = vsi.instanceID;
	
		PSInput.position = mul(WORLDVIEW_STEREO[i], float4(worldPos, 1 ));
		PSInput.position = mul(PROJ_STEREO[i], PSInput.position);
	
	#else
		PSInput.position = mul(WORLDVIEW, float4( worldPos, 1 ));
		PSInput.position = mul(PROJ, PSInput.position);
	#endif
PSInput.wP = worldPos;
#endif
#ifdef GEOMETRY_INSTANCEDSTEREO
		PSInput.instanceID = vsi.instanceID;
#endif 
#ifdef VERTEXSHADER_INSTANCEDSTEREO
		PSInput.renTarget_id = vsi.instanceID;
#endif
///// find distance from the camera

#if defined(FOG) || defined(BLEND)
	#ifdef FANCY
		float3 relPos = -worldPos;
		float cameraDepth = length(relPos);
	#else
		float cameraDepth = PSInput.position.z;
	#endif
#endif

	///// apply fog

#ifdef FOG
	float len = cameraDepth / RENDER_DISTANCE;
#ifdef ALLOW_FADE
	len += RENDER_CHUNK_FOG_ALPHA.r;
#endif

	PSInput.fogColor.rgb = FOG_COLOR.rgb;
	PSInput.fogColor.a = clamp((len - FOG_CONTROL.x) / (FOG_CONTROL.y - FOG_CONTROL.x), 0.0, 1.0);

#endif



///// blended layer (mostly water) magic
#ifdef BLEND
	//Mega hack: only things that become opaque are allowed to have vertex-driven transparency in the Blended layer...
	//to fix this we'd need to find more space for a flag in the vertex format. color.a is the only unused part
	bool shouldBecomeOpaqueInTheDistance = vsi.color.a < 0.95;
	if(shouldBecomeOpaqueInTheDistance) {
		#ifdef FANCY  /////enhance water
			float cameraDist = cameraDepth / FAR_CHUNKS_DISTANCE;
		#else
			float3 relPos = -worldPos.xyz;
			float camDist = length(relPos);
			float cameraDist = camDist / FAR_CHUNKS_DISTANCE;
		#endif //FANCY
		
		float alphaFadeOut = clamp(cameraDist, 0.0, 1.0);
		PSInput.color.a = lerp(vsi.color.a, 1.0, alphaFadeOut);
		PSInput.waterFlag = 1.0;
	}
#endif

}

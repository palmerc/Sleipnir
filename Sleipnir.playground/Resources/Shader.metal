#include <metal_stdlib>

using namespace metal;



typedef struct {
    packed_float2 position;
    packed_float2 texCoords;
} VertexIn;

typedef struct {
    float4 position [[ position ]];
    float2 texCoords [[ user(texturecoord) ]];
} FragmentVertex;

vertex FragmentVertex simple_vertex(device VertexIn *vertexArray [[ buffer(0) ]],
                                      uint vertexIndex [[ vertex_id ]])
{
    VertexIn in = vertexArray[vertexIndex];

    FragmentVertex out;
    out.position = float4(in.position, 0.f, 1.f);
    out.texCoords = in.texCoords;

    return out;
}

fragment float4 simple_fragment(FragmentVertex in [[ stage_in ]],
                                texture2d<uint, access::sample> inputTexture [[ texture(0) ]],
                               sampler linearSampler [[ sampler(0) ]])
{
    const uint2 imageSizeInPixels = uint2(360, 230);
    float imageSizeInPixelsWidth = imageSizeInPixels.x;
    float imageSizeInPixelsHeight = imageSizeInPixels.y;
    float3 color = float3(inputTexture.sample(linearSampler, in.texCoords).x / 255.f);
    return float4(color, 1.0);
}

kernel void doNothingComputeShader(texture2d<uint, access::write> outputTexture [[ texture(0) ]],
                                   const device uchar *pixelValues [[ buffer(0) ]],
                                   uint threadIdentifier [[ thread_position_in_grid ]])
{
    // Imagine for a moment a useful bit of work being done
    const uint2 imageSizeInPixels = uint2(360, 230);
    uint imageSizeInPixelsWidth = imageSizeInPixels.x;
//    uint imageSizeInPixelsHeight = imageSizeInPixels.y;

    uint x = threadIdentifier % imageSizeInPixelsWidth;
    uint y = threadIdentifier / imageSizeInPixelsWidth;

    uint pixelValue = pixelValues[threadIdentifier];

    outputTexture.write(pixelValue, uint2(x, y));
}

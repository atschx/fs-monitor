#include <metal_stdlib>
using namespace metal;
// FP32 port of the frozen CPU Double reference. NOT pixel-equivalence proof.
// No threshold/iteration/material tuning: notably abs(field)>1e-9 stays 1e-9.
struct EyeUniform {
    float4 bounds; float4 sclera; float4 shell;
    float4 directionIris; float4 pupilEdge;
};
float3 norm3(float3 v) { float n=sqrt(v.x*v.x+v.y*v.y+v.z*v.z);return n<=1e-12f?float3(0,0,1):v/n; }
float3 lightDir() { return norm3(float3(-0.28f,-0.32f,0.90f)); }
float ss(float a,float b,float x) {float t=clamp((x-a)/max(b-a,1e-9f),0.0f,1.0f);return t*t*(3-2*t);}
float3 mix3(float3 a,float3 b,float t) {return a+(b-a)*clamp(t,0.0f,1.0f);}
float3 axisU(float3 d) {float3 u=cross(float3(0,1,0),d);if(length(u)<1e-6f)u=float3(1,0,0);return norm3(u);}
float3 axisV(float3 d,float3 u) {return norm3(cross(d,u));}
struct Field {float value;float3 normal;float weight;};
Field field(float3 q,float3 c,float r) {
    float a=length(q)-1,b=length(q-c)-r;
    float w=clamp(0.5f+0.5f*(a-b)/0.080f,0.0f,1.0f);
    float value=a*(1-w)+b*w-0.080f*w*(1-w);
    float3 n=norm3(norm3(q)*(1-w)+norm3(q-c)*w);
    return {value,n,w};
}
struct Hit {float3 point;float3 normal;float weight;};
Hit wetHit(float x,float y,float3 d,float irisAlpha) {
    float rho2=x*x+y*y;float3 c=d*0.50f;
    float radius=sqrt(1.25f-cos(irisAlpha));
    float dx=x-c.x,dy=y-c.y,disc=radius*radius-dx*dx-dy*dy;
    float z=sqrt(1-rho2);if(disc>=0)z=max(z,c.z+sqrt(disc));
    float3 q=float3(x,y,z);Field f=field(q,c,radius);
    if(abs(f.value)>1e-9f) {
        float lo=z,hi=max(1.0f,c.z+radius)+0.080f;
        for(uint i=0;i<18;i++) {
            float mid=(lo+hi)*0.5f;
            float value=field(float3(x,y,mid),c,radius).value;
            if(value>0)hi=mid;else lo=mid;
        }
        z=(lo+hi)*0.5f;q=float3(x,y,z);f=field(q,c,radius);
    }
    return {q,f.normal,f.weight};
}
float wetReflection(float3 n,float w) {
    float ci=max(0.0f,n.z);float3 rv=n*(2*ci)-float3(0,0,1);
    float key=ss(cos(0.36f),cos(0.25f),dot(rv,lightDir()));
    float fresnel=0.0204f+0.9796f*pow(1-ci,5.0f);
    float3 halfVector=norm3(lightDir()+float3(0,0,1));
    float sharp=min(1.0f,key*fresnel*54)+0.045f*pow(max(0.0f,dot(n,halfVector)),18.0f);
    float rough=0.035f*pow(max(0.0f,dot(n,halfVector)),38.0f);
    w=clamp(w,0.0f,1.0f);return rough*(1-w)+sharp*w;
}
float3 irisAlbedo(float polar,float ia,float pa,float3 p,float3 d) {
    float span=max(ia-pa,1e-6f),t=clamp((polar-pa)/span,0.0f,1.0f);
    float3 u=axisU(d),v=axisV(d,u);
    float az=atan2(dot(p,v),dot(p,u));
    float wavy=az+0.17f*sin(az*6.0f)+0.09f*sin(az*17.0f+1.1f);
    float bundle=0.5f+0.5f*sin(wavy*28);
    float fine=0.5f+0.5f*sin(wavy*64+0.6f),fiber=0.7f*bundle+0.3f*fine;
    float3 inner=float3(0.227f,0.110f,0.047f),mid=float3(0.553f,0.322f,0.149f);
    float3 fibers=float3(0.659f,0.416f,0.208f),dark=float3(0.361f,0.188f,0.078f);
    float3 gold=float3(0.769f,0.604f,0.322f),edge=float3(0.290f,0.141f,0.063f);
    float3 base=mix3(inner,mid,ss(0.05f,0.55f,t));
    base=mix3(base,fibers,ss(0.35f,0.78f,t)*0.55f);
    float3 fc=mix3(dark,gold,0.25f+0.35f*t);
    base=mix3(base,fc,max(0.0f,fiber-0.42f)*0.28f);
    base=mix3(base,gold,ss(0.78f,0.90f,t)*0.85f);
    return mix3(base,edge,ss(0.90f,1.0f,t));
}
float4 globeSample(float x,float y,constant EyeUniform& u) {
    float r2=x*x+y*y;if(r2>=1)return float4(0);
    float z=sqrt(1-r2),rho=sqrt(r2),coverage=1;
    float3 p=float3(x,y,z),d=u.directionIris.xyz;
    float ia=u.directionIris.w,pa=u.pupilEdge.x,edge=u.pupilEdge.y;
    if(edge>1e-9f && rho>1-edge) {coverage=max(0.0f,(1-rho)/edge);coverage=coverage*coverage*(3-2*coverage);}
    Hit h=wetHit(x,y,d,ia);
    float ndl=max(0.0f,dot(p,lightDir())),rim=pow(1-z,2.0f);
    float3 sc=mix3(float3(0.984f,0.965f,0.933f),float3(0.910f,0.847f,0.769f),0.26f*rim);
    float scleraShade=(0.76f+0.24f*ndl)*(1-0.13f*rim);
    float3 albedo=sc;float shade=scleraShade;
    float eta=1.0f/1.336f,ci=max(0.0f,h.normal.z);
    float ct=sqrt(max(0.0f,1-eta*eta*(1-ci*ci)));
    float3 transmitted=float3(0,0,-eta)+h.normal*(eta*ci-ct);
    float plane=cos(ia),denom=dot(transmitted,d);
    float t=(plane-dot(h.point,d))/min(-1e-8f,denom);
    float3 ip=h.point+transmitted*max(0.0f,t);
    float axial=dot(ip,d),radial=length(ip-d*axial),polar=asin(min(0.99999f,radial));
    float irisEdge=1-ss(sin(ia)-0.020f,sin(ia),radial);
    float clearCornea=ss(plane-0.025f,plane+0.025f,dot(h.point,d));
    float visibility=irisEdge*clearCornea;
    if(visibility>0) {
        float3 tissue=irisAlbedo(polar,ia,pa,ip,d);
        float3 ic=mix3(float3(0.078f,0.047f,0.031f),tissue,ss(pa-0.008f,pa+0.008f,polar));
        float3 v=axisV(d,axisU(d));float localY=dot(ip,v)/max(0.01f,sin(ia));
        float irisShade=(0.82f+0.18f*max(0.0f,dot(d,lightDir())))*(0.84f+0.16f*ss(-0.8f,0.4f,localY));
        albedo=mix3(sc*scleraShade,ic*irisShade,visibility);shade=1;
    }
    float spec=wetReflection(h.normal,h.weight);
    float upper=1-ss(-0.75f,0.25f,y),gap=max(0.0f,1-rho);
    float contact=(0.10f+0.27f*upper)*exp(-gap/0.022f);shade*=1-contact;
    return float4(min(float3(1),albedo*shade*(1-min(1.0f,spec))+spec),coverage);
}
float4 lidSample(float x,float y,constant EyeUniform& u) {
    float sx=(x-u.shell.x)/u.shell.z,sy=(y-u.shell.y)/u.shell.w;
    float r2=sx*sx+sy*sy;if(r2>=1)return float4(0);
    float z=sqrt(1-r2);float3 n=norm3(float3(sx,sy,z*1.12f));
    float lambert=max(0.0f,dot(n,lightDir()));
    float3 halfVector=norm3(lightDir()+float3(0,0,1));
    float spec=0.08f*pow(max(0.0f,dot(n,halfVector)),26.0f),limb=pow(1-z,2.0f);
    float shade=(0.71f+0.29f*lambert)*(1-0.15f*limb);
    float gx=(x-u.sclera.x)/u.sclera.z,gy=(y-u.sclera.y)/u.sclera.w;
    float dist=max(0.0f,sqrt(gx*gx+gy*gy)-1);
    float bead=exp(-pow((dist-0.025f)/0.019f,2.0f));
    float crease=exp(-pow(dist/0.010f,2.0f));
    float upperLight=clamp(0.6f-gy*0.35f-gx*0.20f,0.0f,1.0f);
    shade*=1-0.24f*crease;float lift=bead*(0.08f+upperLight*0.14f);
    float a=clamp((1-sqrt(r2))*min(u.shell.z,u.shell.w)/1.4f,0.0f,1.0f);
    return float4(min(float3(1),float3(0.902f,0.796f,0.702f)*shade+spec+lift),a);
}
kernel void eyePixels(texture2d<float,access::write> out [[texture(0)]],constant EyeUniform& u [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
    if(id.x>=uint(u.bounds.z)||id.y>=uint(u.bounds.w))return;
    float x=u.bounds.x+float(id.x)+0.5f,y=u.bounds.y+float(id.y)+0.5f;
    float4 g=globeSample((x-u.sclera.x)/u.sclera.z,(y-u.sclera.y)/u.sclera.w,u);
    float4 l=g.a<1?lidSample(x,y,u):float4(0);
    float a=g.a+l.a*(1-g.a),back=l.a*(1-g.a);
    float4 premul=float4(g.rgb*g.a+l.rgb*back,a);
    // Mirror positive Swift .rounded() before Unorm storage, not shader half.
    out.write(floor(clamp(premul,0.0f,1.0f)*255.0f+0.5f)/255.0f,id);
}
struct Quad {float4 corners;}; // x0,y0 top-left / x1,y1 bottom-right in NDC.
struct Varying {float4 position [[position]];float2 uv;};
vertex Varying eyeQuad(uint id [[vertex_id]],constant Quad& q [[buffer(0)]]) {
    float2 uv=float2(id>=2?1:0,id%2?1:0);
    float2 p=float2(mix(q.corners.x,q.corners.z,uv.x),mix(q.corners.y,q.corners.w,uv.y));
    return {float4(p,0,1),uv};
}
fragment float4 eyePresent(Varying in [[stage_in]],texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::linear);
    return image.sample(s,in.uv);
}

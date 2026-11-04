// Continuous, downward-flowing fire with an independently legible notch rim.
// The only texture is deterministic 128 x 128 scalar noise, generated in memory.
enum NotchFlameShader {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 viewport;
        float2 notchOrigin;
        float2 notchSize;
        float pixelScale;
        float time;
        float heat;
        float visibility;
        float drawsAnchor;
        float cornerRadius;
        float4 flameColor;
        float4 style;
        float4 motion;
    };
    struct Vertex { float4 position [[position]]; float2 uv; };

    vertex Vertex flameVertex(uint id [[vertex_id]]) {
        float2 p = id == 0 ? float2(-1,-1) : id == 1 ? float2(3,-1) : float2(-1,3);
        return { float4(p,0,1), float2((p.x+1)*.5, (1-p.y)*.5) };
    }

    // Continuous arclength through the real display's two lower corners.
    float2 rim(float2 p, constant Uniforms &u) {
        p -= u.notchOrigin;
        float radius = min(u.cornerRadius, min(u.notchSize.x, u.notchSize.y)*.5);
        float center = u.notchSize.x*.5;
        float cornerY = u.notchSize.y-radius;
        float straight = u.notchSize.x-radius*2.0;
        float arc = M_PI_F*radius;
        float total = cornerY*2.0+straight+arc;
        bool left = p.x < center;
        float2 q = float2(abs(p.x-center)-(center-radius), p.y-cornerY);
        float distance = length(max(q, 0.0))+min(max(q.x,q.y),0.0)-radius;
        float s;
        if (q.x > 0.0 && q.y <= 0.0) {
            s = left ? p.y : total-p.y;
        } else if (q.x > 0.0 && q.y > 0.0) {
            float a = atan2(q.y,q.x);
            s = left ? cornerY+a*radius : total-cornerY-a*radius;
        } else {
            s = cornerY+arc*.5+p.x-radius;
        }
        return float2(s,distance);
    }

    float2 noise2(texture2d<float> noise, float2 p) {
      float2 cell = floor(p);
      float2 f = fract(p);
      f = f*f*f*(f*(f*6.0-15.0)+10.0);
      constexpr sampler lookup(coord::normalized, address::repeat, filter::linear);
      return noise.sample(lookup, (cell + f + .5) / 128.0).rg;
    }
    float hash(float n) { return fract(sin(n*127.1+31.7)*43758.5453); }

    float noise3(texture2d<float> noise,float3 p) {
      float z = floor(p.z);
      float f = fract(p.z);
      f = f*f*f*(f*(f*6.0-15.0)+10.0);
      float2 offset = float2(37.0,19.0);
      return mix(noise2(noise,p.xy+z*offset).r,
                 noise2(noise,p.xy+(z+1.0)*offset).r,f);
    }

    float turbulence(texture2d<float> noise,float3 p) {
      float value = .56*noise3(noise,p);
      p = p*2.03+float3(17.1,9.2,13.7);
      value += .27*noise3(noise,p);
      p = p*2.01+float3(5.7,21.3,3.1);
      value += .12*noise3(noise,p);
      return value+.05*noise3(noise,p*2.07);
    }

    // Integrate a shallow turbulent volume. Density determines the silhouette:
    // there are no repeated pointed shapes or ink outlines around the flame body.
    float4 volumeFire(texture2d<float> noise,float2 p,float2 edge,float h,float t,constant Uniforms &u) {
      float n = max(0.0,edge.y);
      float x = p.x-u.notchOrigin.x;
      float below = p.y-u.notchOrigin.y-u.notchSize.y;
      float bottom = smoothstep(-5.0,3.0,below)
          *smoothstep(-3.0,9.0,x)*(1.0-smoothstep(u.notchSize.x-9.0,u.notchSize.x+3.0,x));
      float reach = mix(5.0+7.0*h,16.0+40.0*h,bottom)*u.style.w;
      float v = n/reach;
      if (v > 1.035) return float4(0.0);
      float limit = 1.0-smoothstep(.87,1.035,v);
      float4 volume = float4(0.0);
      float3 tint = u.flameColor.rgb;
      float core = u.style.y;
      float disturbance = u.motion.x;
      float warm = clamp((tint.r-max(tint.g*.80,tint.b))*2.0,0.0,1.0);
      float3 hotColor = mix(mix(tint,float3(1.0),.40+.44*core),float3(1.0,.89,.43),warm);
      for (int i=0; i<6; ++i) {
        float z = (float(i)+.5)/3.0-1.0;
        float3 q = float3(edge.x*.10-t*.035,n*.052-t*.95,z*.52+t*.13);
        float bend = noise3(noise,q*.58+float3(7.3,2.1,t*.07))-.5;
        float roll = noise3(noise,q*.81+float3(19.1,3.7,-t*.09))-.5;
        q += float3(bend*(1.0+v*2.4),roll*1.65,bend*.4)*disturbance;
        float churn = turbulence(noise,q);
        float detail = noise3(noise,q*3.17+float3(3.7,-t*.21,7.9));
        float fuel = 1.06-v*1.22+(churn-.5)*2.5*(.25+.75*disturbance)+(detail-.5)*.34;
        float density = smoothstep(.06,.74,fuel)*exp(-z*z*1.65)*limit;
        float temperature = clamp(fuel*(.40+.26*core)+detail*(.02+.20*core)
            +(1.0-v)*(.06+.14*core),0.0,1.0);
        float3 color = mix(tint*.24,tint,smoothstep(.08,.58,temperature));
        color = mix(color,hotColor,smoothstep(.85-.30*core,1.07-.18*core,temperature));
        color = mix(color,mix(tint,float3(1.0),.97),
            pow(smoothstep(1.02-.20*core,1.04,temperature),2.0));
        // Preserve volume shading even for a user-selected white tint.
        color *= mix(.62+.38*smoothstep(.48,1.0,temperature),1.0,smoothstep(.5,1.0,core));
        color = clamp(color*u.style.x,0.0,1.0);
        float opacity = 1.0-exp(-density*mix(.66,.16,u.style.z));
        volume.rgb += color*opacity*(1.0-volume.a);
        volume.a += opacity*(1.0-volume.a);
      }
      // Optical depth keeps the mid-body readable over white without drawing a hard contour.
      float opacity = 1.0-pow(1.0-volume.a,1.7);
      return float4(volume.rgb/max(volume.a,.00001)*opacity,opacity);
    }

    float4 over(float3 color,float opacity,float4 under) {
      return float4(color*opacity,opacity)+under*(1.0-opacity);
    }

    fragment float4 flameFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]],
                                  texture2d<float> noise [[texture(0)]]) {
      if (u.visibility < .0001) return float4(0.0);
      float2 p = in.uv*u.viewport;
      float x = p.x-u.notchOrigin.x;
      float flameMask = smoothstep(.75,3.25,min(x,u.notchSize.x-x));
      float2 edge = rim(p,u);
      float d = edge.y;
      float aa = .65/u.pixelScale;
      float outside = smoothstep(-aa,aa,d);
      float3 notch = float3(.010,.013,.018);
      float anchor = (1.0-outside)*u.drawsAnchor;
      if (d < -aa || u.heat < .0001) {
        return float4(notch*anchor,anchor)*u.visibility;
      }
      float h = u.heat;
      float t = u.time;
      float n = max(d, 0.0);
      float3 tint = u.flameColor.rgb;
      float3 coreColor = mix(tint,float3(1.0),.78);
      float4 fire = volumeFire(noise,p,edge,h,t,u)*flameMask;
      float halo = exp(-n/2.0)*(.055+.055*h)*(1.0-smoothstep(3.0,4.0,n));
      float4 result = float4(tint*halo,halo);
      float rimGuard = (1.0-smoothstep(2.2,3.1,n))*.86;
      result = over(float3(.009,.012,.022),max(rimGuard,fire.a*.32),result);
      result = fire+result*(1.0-fire.a);

      // A few descending embers break away from the flowing body.
      for (int i=0; i<5; ++i) {
        float seed = hash(float(i)+71.0);
        float life = fract(t*(.24+seed*.12)+seed*5.0);
        float x = u.notchOrigin.x+u.notchSize.x*(.08+.84*hash(float(i)+91.0));
        x += sin(t*.9+seed*17.0+life*4.0)*3.0*life;
        float y = u.notchOrigin.y+u.notchSize.y+(11.0+life*42.0)*u.style.w;
        float radius = .55+seed*.65;
        float distance = length((p-float2(x,y))/float2(radius,radius*1.65));
        float lifeFade = smoothstep(0.0,.14,life)*(1.0-smoothstep(.64,1.0,life))*(.25+.65*h)*flameMask;
        float spark = (1.0-smoothstep(.25,1.2,distance))*lifeFade;
        float guard = (1.0-smoothstep(.8,2.0,distance))*lifeFade*.65;
        result = over(float3(.009,.012,.022),guard*(1.0-result.a),result);
        result = over(mix(tint,coreColor,.72),spark,result);
      }

      // Light travels along the original U-shaped outline. Its shape and width stay fixed.
      float rimLight = pow(.5+.5*sin(edge.x*.055-t*1.8),4.0);
      float shimmer = noise2(noise,float2(edge.x*.10-t*.55,t*.12)).r;
      float stroke = 1.0-smoothstep(1.45-aa,1.45+aa,n);
      result = over(mix(tint,coreColor,.14+.72*rimLight+.10*shimmer),stroke*.98,result);
      float contact = (1.0-smoothstep(.23-aa*.5,.55+aa*.5,n))*.94;
      result = over(mix(tint,coreColor,.40+.55*rimLight),contact,result);
      result.rgb = result.rgb*outside+notch*(1.0-outside)*u.drawsAnchor;
      result.a = result.a*outside+(1.0-outside)*u.drawsAnchor;
      return result*u.visibility;
    }
    """#
}

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coords: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
};

struct OctreeNode {
    children: array<u32, 8>,
    parent: u32,
    color: u32,
}

struct AABB {
    min: vec3<f32>,
    max: vec3<f32>,
}

struct Camera {
    position: vec3<f32>,
    rotation: vec2<f32>,
}

@vertex
fn vs_main(
    model: VertexInput,
) -> VertexOutput {
    var out: VertexOutput;
    out.tex_coords = model.tex_coords;
    out.clip_position = vec4<f32>(model.position, 1.0);
    return out;
}

@group(0)
@binding(0)
var<storage, read> octree: array<OctreeNode, 26208>;

@group(0)
@binding(1)
var<uniform> camera: Camera;

let max_steps = 200;
let max_distance = 30.;


fn is_null(val: u32) -> bool {
    return val == 4294967295u;
}

//random function from https://www.shadertoy.com/view/MlsXDf
fn rnd(v: vec4<f32>) -> f32 { return fract(4.e4 * sin(dot(v,vec4<f32>(13.46,41.74,-73.36,14.27))+17.34)); }

//hash function by Dave_Hoskins https://www.shadertoy.com/view/4djSRW
fn hash33(p: vec3<f32>) -> vec3<f32>
{
	var p3 = fract(p * vec3<f32>(.1031, .1030, .0973));
    p3 += vec3<f32>(dot(p3, p3.yxz+19.19));
    return fract((p3.xxy + p3.yxx)*p3.zyx);
}

//0 is empty, 1 is subdivide and 2 is full
fn getvoxel(p: vec3<f32>, size: f32) -> i32 {
    let val = rnd(vec4<f32>(p,size));
    
    if (val < .5) {
        return 0;
    } else if (val < .95) {
        return 1;
    } else {
        return 2;
    }
    
    return i32(val*val*3.0);
}

//ray-cube intersection, on the inside of the cube
fn voxel(ro: vec3<f32>, rd: vec3<f32>, ird: vec3<f32>, size: f32) -> vec3<f32> {
    return -(sign(rd) * (ro - (size * .5))- (size * .5)) * ird;
}

fn cast_ray(orig: vec3<f32>, dir: vec3<f32>) -> vec4<f32> {
    var current_node = octree[0];

    var size = 1.0;

    var origin = orig;

    var lro = origin % size;
    var fro = origin - lro;
    var ird = 1.0 / max(abs(dir), vec3<f32>(0.001));
    var mask: vec3<f32>;
    var exitoct = false;
    var recursions = 0;
    var dist = 0.;
    var fdist = 0.;
    var edge = 1.;
    var lastmask: vec3<f32>;
    var normal: vec3<f32>;
    var i = 0;

    for (i = 0; i < max_steps; i++) {
        if (dist > max_distance) { break; }

        if (exitoct) {
            var newfro = floor(fro / (size * 2.)) * (size * 2.);

            lro += fro - newfro;
            fro = newfro;
            recursions -= 1;
            size *= 2.;

            exitoct = (recursions > 0) && (abs(dot(((fro / size + 0.5) % 2.) - 1. + mask * sign(dir) * .5, mask)) < .1);
        } else {
            var voxelstate = getvoxel(fro, size);
            if (voxelstate == 1 && recursions > 5) {
                voxelstate = 0;
            }
            if (voxelstate == 1 && recursions <= 5) {
                recursions += 1;
                size *= .5;
            
                var mask2 = step(vec3<f32>(size), lro);
                fro += mask2 * size;
                lro -= mask2 * size;
            } else if (voxelstate == 0 || voxelstate == 2) {
                let hit = voxel(lro, dir, ird, size);

                mask = vec3<f32>(hit < min(hit.yzx, hit.zxy));

                let len = dot(hit, mask);

                if (voxelstate == 2) {
                    break;
                }

                //moving forward in ray direction, and checking if i need to go up a level
                dist += len;
                fdist += len;
                lro += dir * len - mask * sign(dir) * size;
                let newfro = fro + mask * sign(dir) * size;
                exitoct = any(floor(newfro / size * 0.5 + 0.25) != floor(fro / size * 0.5 + 0.25)) && (recursions > 0);
                fro = newfro;
                lastmask = mask;
            }
        }
    }

    origin += dir * dist;
    if (i < max_steps && dist < max_distance) {
        let val = fract(dot(fro, vec3<f32>(15.23, 754.345, 3.454)));

        normal = -lastmask * sign(dir);

        let color = sin(val * vec3<f32>(39.896, 57.3225, 48.25)) * .5 + .5;
        return vec4<f32>(color * (normal * .25 + .75), 1.) * edge;
    } else {
        return vec4<f32>(edge);
    }
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = (in.tex_coords.xy * 2.) - 1.;
    
    let ro = vec3<f32>(.5) + camera.position;
    var rd = normalize(vec3<f32>(uv,1.0));

    let rotx = -camera.rotation.x;
    let roty = -camera.rotation.y;

    let ymat = mat2x2<f32>(cos(rotx),sin(rotx),-sin(rotx),cos(rotx));
    let xmat = mat2x2<f32>(cos(roty),sin(roty),-sin(roty),cos(roty));

    var newrd = rd.yz * ymat;
    rd = vec3<f32>(rd.x, newrd.x, newrd.y);

    newrd = rd.xz * xmat;
    rd = vec3<f32>(newrd.x, rd.y, newrd.y);

    let voxel_hit = cast_ray(ro, rd);

    return voxel_hit;

    // // If transparent return
    // if ((voxel_hit & 255u) != 255u) {
    //     return vec4<f32>(.2, .2, .2, 1.);
    // }

    // // Otherwise convert the color

    // return vec4<f32>(
    //     f32(voxel_hit >> 24u) / 255.,
    //     f32((voxel_hit >> 16u) & 255u) / 255.,
    //     f32((voxel_hit >> 8u) & 255u) / 255.,
    //     1.,
    // );
}
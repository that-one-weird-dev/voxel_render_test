struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coords: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
};

struct OctreeNode {
    children: u32,
    parent: u32,
    color: u32,
}

struct Camera {
    position: vec3<f32>,
    rotation: vec2<f32>,
    aspect_ratio: f32,
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

let max_steps = 100;
let max_distance = 30.;
let octree_depth = 8;
let ray_length = 100.;

fn cast_ray(origin: vec3<f32>, dir: vec3<f32>) -> vec4<f32> {

    var current_node = octree[0];

    var size = 32.;

    let inv_dir = 1. / dir;

    var index = 0u;

    var current_aabb: vec3<f32>;

    var tmin: vec3<f32>;
    var tmax: vec3<f32>;

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var t1offset: vec3<f32>;
    var biggest: f32;

    var tnear: f32;
    var tfar: f32;

    let inside_mask = 1. - f32(all(origin > current_aabb) && all(origin < (current_aabb + size)));

    var old_node = 0u;
    var child = 0u;
    
    for (var i = 0; i < max_steps; i += 1) {
        // Intersect
        tmin = (current_aabb - origin) * inv_dir;
        tmax = (current_aabb + size - origin) * inv_dir;
        t0 = min(tmin, tmax);
        t1 = max(tmin, tmax);
        tnear = max(max(t0.x, t0.y), t0.z);
        tfar = min(min(t1.x, t1.y), t1.z);

        if (tnear > tfar || tfar < 0.) {
            break;
        }

        t0 = origin + (inside_mask * dir * (tnear + 0.000001));
        t1 = origin + dir * tfar;

        t1offset = abs(t1 - (current_aabb + (size * .5)));
        biggest = max(max(t1offset.x, t1offset.y), t1offset.z);

        t1.x += f32(biggest == t1offset.x) * sign(dir.x) * 0.001;
        t1.y += f32(biggest == t1offset.y) * sign(dir.y) * 0.001;
        t1.z += f32(biggest == t1offset.z) * sign(dir.z) * 0.001;

        if (size < 31.) {
            size = 32.;
            current_aabb = vec3<f32>();
            current_node = octree[0];

            t0 = t1;
        }

        // Check smallest voxel
        loop {
            // If leaf then break
            if (current_node.children == 0u) {
                if (old_node == child - 1u) {
                    return vec4<f32>(.2, .2, .2, 1.);
                }
                old_node = child - 1u;

                break;
            }

            size *= .5;
            index = (u32(t0.x > (current_aabb.x + size)) * 4u)
                  | (u32(t0.y > (current_aabb.y + size)) * 2u)
                  | (u32(t0.z > (current_aabb.z + size)) * 1u);

            child = current_node.children + index;
            current_node = octree[child - 1u];

            current_aabb.x += f32((index & 4u) == 4u) * size;
            current_aabb.y += f32((index & 2u) == 2u) * size;
            current_aabb.z += f32((index & 1u) == 1u) * size;
        }

        if (current_node.color != 0u) {
            break;
        }
    }

    // If transparent return
    if (current_node.color == 0u) {
        return vec4<f32>(.2, .2, .2, 1.);
    }

    var color: vec4<f32>;

    // Otherwise convert the color
    color = vec4<f32>(
        f32(current_node.color >> 24u) / 255.,
        f32((current_node.color >> 16u) & 255u) / 255.,
        f32((current_node.color >> 8u) & 255u) / 255.,
        1.,
    );

    if ((biggest == t1offset.x && dir.x < 0.)
     || (biggest == t1offset.y && dir.y < 0.)
     || (biggest == t1offset.z && dir.z < 0.)) {
        color += vec4<f32>(.2, .2, .2, 0.);
    }

    return color;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = ((in.tex_coords.xy * 2.) - 1.) * vec2<f32>(1., camera.aspect_ratio);
    
    let ro = vec3<f32>(16.0001, 16.0001, 16.0001) + camera.position;
    var rd = normalize(vec3<f32>(uv,1.0));

    let rotx = -camera.rotation.x;
    let roty = -camera.rotation.y;

    let ymat = mat2x2<f32>(cos(rotx),sin(rotx),-sin(rotx),cos(rotx));
    let xmat = mat2x2<f32>(cos(roty),sin(roty),-sin(roty),cos(roty));

    var newrd = rd.yz * ymat;
    rd = vec3<f32>(rd.x, newrd.x, newrd.y);

    newrd = rd.xz * xmat;
    rd = vec3<f32>(newrd.x, rd.y, newrd.y);

    let color = cast_ray(ro, rd * ray_length);

    return color;
}
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

struct RayHit {
    hit: bool,
    color: vec4<f32>,
    position: vec3<f32>,
    node: u32,
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
var<storage, read> octree: array<OctreeNode, 52416>;

@group(0)
@binding(1)
var<uniform> camera: Camera;

let max_steps = 100;
let max_distance = 30.;
let octree_depth = 16;
let ray_length = 1000.;
let background_color = vec4<f32>(.2, .2, .2, 1.);
let frac_1_255 = 0.003921569; // Approximation of 1. / 255.

fn cast_ray(origin: vec3<f32>, dir: vec3<f32>) -> RayHit {
    var current_node = octree[0];

    var size = 1024.;

    let inv_dir = 1. / dir;

    var index = 0u;

    var current_aabb = vec3<f32>(-512., -512., -512.);

    var stack_index = 0u;
    var aabb_stack: array<vec3<f32>, octree_depth>;
    aabb_stack[stack_index] = current_aabb;

    var tmin: vec3<f32>;
    var tmax: vec3<f32>;

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var toffset: vec3<f32>;
    var biggest: f32;

    var tnear: f32;
    var tfar: f32;

    var result: RayHit;

    let inside_mask = 1. - f32(all(origin > current_aabb) && all(origin < (current_aabb + size)));
    
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

        t0 = origin + (inside_mask * dir * tnear);
        t1 = origin + dir * tfar;

        toffset = abs(t1 - (current_aabb + (size * .5)));
        biggest = max(max(toffset.x, toffset.y), toffset.z);

        t1.x += f32(biggest == toffset.x) * sign(dir.x) * 0.001;
        t1.y += f32(biggest == toffset.y) * sign(dir.y) * 0.001;
        t1.z += f32(biggest == toffset.z) * sign(dir.z) * 0.001;

        if (current_node.children == 0u) {
            loop {
                // This means the ray is outside of the max bounding box
                if (stack_index == 0u) {
                    return result;
                }

                current_node = octree[current_node.parent - 1u];

                stack_index -= 1u;
                current_aabb = aabb_stack[stack_index];
                size *= 2.;

                if (!(any(t1 < current_aabb) || any(t1 > (current_aabb + size)))) {
                    break;
                }
            }

            t0 = t1;
        }

        // Check smallest voxel
        loop {
            // If leaf then break
            if (current_node.children == 0u) {
                break;
            }

            size *= .5;
            index = (u32(t0.x > (current_aabb.x + size)) * 4u)
                  | (u32(t0.y > (current_aabb.y + size)) * 2u)
                  | (u32(t0.z > (current_aabb.z + size)) * 1u);

            result.node = current_node.children + index - 1u;
            current_node = octree[result.node];

            current_aabb.x += f32((index & 4u) == 4u) * size;
            current_aabb.y += f32((index & 2u) == 2u) * size;
            current_aabb.z += f32((index & 1u) == 1u) * size;

            stack_index += 1u;
            aabb_stack[stack_index] = current_aabb;
        }

        if (current_node.color != 0u) {
            break;
        }
    }

    if (i == max_steps) {
        return result;
    }

    result.position = t0 - (sign(dir) * 0.002);
    result.hit = true;

    result.color = vec4<f32>(
        f32(current_node.color >> 24u) * frac_1_255 + f32(biggest == toffset.x && dir.x < 0.) * .1,
        f32((current_node.color >> 16u) & 255u) * frac_1_255 + f32(biggest == toffset.y && dir.y < 0.) * .1,
        f32((current_node.color >> 8u) & 255u) * frac_1_255 + f32(biggest == toffset.z && dir.z < 0.) * .1,
        1.,
    );

    return result;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = ((in.tex_coords.xy * 2.) - 1.) * vec2<f32>(1., camera.aspect_ratio) * 2.;
    
    let ro = camera.position;
    var rd = normalize(vec3<f32>(uv,1.0));

    let rotx = -camera.rotation.x;
    let roty = -camera.rotation.y;

    let ymat = mat2x2<f32>(cos(rotx),sin(rotx),-sin(rotx),cos(rotx));
    let xmat = mat2x2<f32>(cos(roty),sin(roty),-sin(roty),cos(roty));

    var newrd = rd.yz * ymat;
    rd = vec3<f32>(rd.x, newrd.x, newrd.y);

    newrd = rd.xz * xmat;
    rd = vec3<f32>(newrd.x, rd.y, newrd.y);

    let result = cast_ray(ro, rd * ray_length);

    if (!result.hit) {
        return background_color;
    }

    return result.color;
}
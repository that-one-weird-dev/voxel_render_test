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

let max_steps = 100;
let cube_color = vec4<f32>(0., 1., 0., 1.);

fn is_null(val: u32) -> bool {
    return val == 4294967295u;
}

fn cast_ray(origin: vec3<f32>, dir: vec3<f32>) -> u32 {

    let inv_dir = 1. / dir;

    var current_node = octree[0];
    var half_size = f32(1u << (8u - 1u)) * .5;

    var aabb_stack: array<AABB, 8>;
    var stack_index: u32;

    var current_aabb: AABB;
    current_aabb.min = vec3<f32>(
        0.,
        0.,
        0.,
    );
    current_aabb.max = vec3<f32>(
        half_size * 2.,
        half_size * 2.,
        half_size * 2.,
    ); 

    aabb_stack[stack_index] = current_aabb;

    var tmin: vec3<f32>;
    var tmax: vec3<f32>;

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var tnear: f32;
    var tfar: f32;

    var index: u32;

    var voxel_hit: u32;

    var cast_ray = true;
    var find_node = true;
    var reset = false;

    // Checks if the root is also a leaf node
    if (is_null(current_node.children[0])) {
        return current_node.color;
    }

    var i: i32;

    for (i = 0; i < max_steps; i++) {
        if (cast_ray) {
            // -------------- Collision checking ---------------------
            tmin = (current_aabb.min - origin) * inv_dir;
            tmax = (current_aabb.max - origin) * inv_dir;

            t0 = min(tmin, tmax);
            t1 = max(tmin, tmax);

            tnear = max(max(t0.x, t0.y), t0.z);
            tfar = min(min(t1.x, t1.y), t1.z);

            if (tfar < 0.) {
                // The box is in the other direction
                return 0u;
            }

            if (tnear > tfar) {
                // Ray isn't intersecting the box
                return 0u;
            }

            t0 = origin + dir * (tnear + 0.001);
            t1 = origin + dir * (tfar + 0.001);

            if (i % 3 == 1) {
                reset = true;
                find_node = false;
            }
        }

        if (find_node) {
            // Find smallest voxel in that point
            loop {
                // Subdivision index calculcation
                index = 0u;
                if (t0.x >= current_aabb.min.x + half_size) {
                    index |= 4u;
                    current_aabb.min.x += half_size;
                } else {
                    current_aabb.max.x -= half_size;
                }
                if (t0.y >= current_aabb.min.y + half_size) {
                    index |= 2u;
                    current_aabb.min.y += half_size;
                } else {
                    current_aabb.max.y -= half_size;
                }
                if (t0.z >= current_aabb.min.z + half_size) {
                    index |= 1u;
                    current_aabb.min.z += half_size;
                } else {
                    current_aabb.max.z -= half_size;
                }

                let child = current_node.children[index];
                current_node = octree[child];

                half_size *= .5;
                stack_index += 1u;
                aabb_stack[stack_index] = current_aabb;
                
                if (is_null(current_node.children[0])) {
                    voxel_hit = current_node.color;
                    reset = false;
                    cast_ray = true;
                    break;
                }
            }
        }

        // Check if the voxel has data
        if (voxel_hit != 0u) {
            break;
        }
        
        if (reset) {
            t0 = t1;

            stack_index = 0u;
            current_aabb = aabb_stack[stack_index];
            current_node = octree[0];
            half_size = f32(1u << (8u - 1u)) * .5;
            
            cast_ray = false;
            find_node = true;
            reset = false;
        }
    }

    return voxel_hit;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let ray_origin = camera.position + vec3<f32>(in.tex_coords * 160., 1.);
    let center_distance = (in.tex_coords - .5) * 20.;
    let ray_direction = vec3<f32>(
        100. * sin(camera.rotation.y) + center_distance.x,
        center_distance.y,
        100. * cos(camera.rotation.y),
    );

    let voxel_hit = cast_ray(ray_origin, ray_direction);

    // If transparent return
    if ((voxel_hit & 255u) != 255u) {
        return vec4<f32>(.2, .2, .2, 1.);
    }

    // Otherwise convert the color

    return vec4<f32>(
        f32(voxel_hit >> 24u) / 255.,
        f32((voxel_hit >> 16u) & 255u) / 255.,
        f32((voxel_hit >> 8u) & 255u) / 255.,
        1.,
    );
}
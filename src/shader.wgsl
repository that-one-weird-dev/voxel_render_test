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
    data: u32,
}

struct AABB {
    min: vec3<f32>,
    max: vec3<f32>,
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
var<storage, read> octree: array<OctreeNode>;

let max_steps = 100;
let cube_color = vec4<f32>(0., 1., 0., 1.);

fn is_null(val: u32) -> bool {
    return val == 4294967295u;
}

fn cast_ray(origin: vec3<f32>, dir: vec3<f32>) -> u32 {

    let inv_dir = 1. / dir;

    var current_node = octree[0];
    var half_size = f32(1 << (8u - 1u)) * .5;

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

    aabb_stack[0] = current_aabb;

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var tmin: f32;
    var tmax: f32;

    var index: u32;

    var voxel_hit: u32;

    var cast_ray = true;

    // Checks if the root is also a leaf node
    if (is_null(current_node.children[0])) {
        return current_node.data;
    }

    for (var i = 0; i < max_steps; i++) {
        if (cast_ray) {
            // -------------- Collision checking ---------------------
            t0 = (current_aabb.min - origin) * inv_dir;
            t1 = (current_aabb.max - origin) * inv_dir;

            tmin = max(max(min(t0.x, t1.x), min(t0.y, t1.y)), min(t0.z, t1.z));
            tmax = min(min(max(t0.x, t1.x), max(t0.y, t1.y)), max(t0.z, t1.z));

            if (tmax < 0.) {
                // The box is in the other direction
                return 0u;
            }

            if (tmin > tmax) {
                // Ray isn't intersecting the box
                return 0u;
            }

            t0 = origin + dir * ((tmin / length(dir)) + 0.001);
            t1 = origin + dir * ((tmax / length(dir)) + 0.001);
        }

        // Find smallest voxel in that point
        for (var j=0; j < 100; j++) {
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
                voxel_hit = current_node.data;
                break;
            }
        }

        // Check if the voxel has data
        if (voxel_hit != 0u) {
            break;
        }
        
        // Check for next voxel
        if (cast_ray) {
            // Finding the first parent that contains this point
            loop {
                if (stack_index == 0u) {
                    break;
                }

                stack_index -= 1u;
                current_aabb = aabb_stack[stack_index];
                current_node = octree[current_node.parent];
                half_size *= 2.;

                if (t1.x > current_aabb.min.x
                    && t1.y > current_aabb.min.y
                    && t1.z > current_aabb.min.z
                    && t1.x < current_aabb.max.x
                    && t1.y < current_aabb.max.y
                    && t1.z < current_aabb.max.z
                ) {
                    break;
                }
            }
        }
        cast_ray = !cast_ray;
    }

    return 0u;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let ray_origin = vec3<f32>(in.tex_coords * 160., -20.);
    let ray_direction = vec3<f32>(0.001, 0.001, 100.);

    let voxel_hit = cast_ray(ray_origin, ray_direction);

    var color: vec4<f32>;

    switch voxel_hit {
        case 1u: {
            color = vec4<f32>(1., 0., 0., 1.);
        }
        case 2u: {
            color = vec4<f32>(0., 1., 0., 1.);
        }
        case 3u: {
            color = vec4<f32>(0., 0., 1., 1.);
        }
        default: {
            color = vec4<f32>(.2, .2, .2, 1.);
        }
    }

    return color;
}
struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coords: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
};

struct OctreeNode {
    parent: u32,
    children: array<u32, 8>,
    data: u32,
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

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let ray_origin = vec3<f32>(in.tex_coords * 2., -20.);
    let ray_direction = vec3<f32>(0.001, 0.001, 100.);
    let inverse_ray_dir = 1. / ray_direction;

    var current_node = octree[0];
    var half_size = f32(1 << (8u - 2u));

    var b0 = vec3<f32>(
        -half_size,
        -half_size,
        -half_size,
    );
    var b1 = vec3<f32>(
        half_size,
        half_size,
        half_size,
    ); 

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var tmin: f32;
    var tmax: f32;

    var index: u32;

    var voxel_hit: u32;

    for (var i = 0; i < max_steps; i++) {
        if (is_null(current_node.children[0])) {
            return vec4<f32>(0., 1., 0., 1.);
            //voxel_hit = current_node.data;
            //break;
        }

        // Collision checking
        t0 = (b0 - ray_origin) * inverse_ray_dir;
        t1 = (b1 - ray_origin) * inverse_ray_dir;

        tmin = max(max(min(t0.x, t1.x), min(t0.y, t1.y)), min(t0.z, t1.z));
        tmax = min(min(max(t0.x, t1.x), max(t0.y, t1.y)), max(t0.z, t1.z));

        if (tmax < 0.) {
            // The box is in the other direction
            break;
        }

        if (tmin > tmax) {
            // Ray isn't intersecting the box
            return vec4<f32>(0., 0., 1., 1.);
            // break;
        }

        // Voxel check
        index = 0u;

        if (t0.x >= 0.) {
            index |= 4u;
        }
        if (t0.y >= 0.) {
            index |= 2u;
        }
        if (t0.z >= 0.) {
            index |= 1u;
        }

        current_node = octree[current_node.children[index]];

        half_size /= 2.;

        if ((index & 4u) == 4u) {
            b0.x += half_size;
        } else {
            b1.x -= half_size;
        }
        if ((index & 2u) == 2u) {
            b0.y += half_size;
        } else {
            b1.y -= half_size;
        }
        if ((index & 1u) == 1u) {
            b0.z += half_size;
        } else {
            b1.z -= half_size;
        }
    }

    var color: vec4<f32>;

    switch voxel_hit {
        case 1u: {
            color = vec4<f32>(0., 1., 0., 1.);
        }
        default {
            color = vec4<f32>(.2, .2, .2, 1.);
        }
    }

    return color;
}
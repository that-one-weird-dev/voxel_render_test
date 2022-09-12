struct OctreeNode {
    parent: u32,
    children: array<u32, 8>,
    data: u32,
}

@group(0)
@binding(0)
var<storage, read> octree: array<OctreeNode>;

@group(0)
@binding(1)
var output: texture_storage_2d<rgba8unorm, write>;

let max_steps = 100;
let cube_color = vec4<f32>(0., 1., 0., 1.);

fn is_null(val: u32) -> bool {
    return val == 4294967295u;
}

@compute
@workgroup_size(1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let view_size = vec2<f32>(textureDimensions(output));

    var ray_origin = vec3<f32>(vec2<f32>(global_id.xy) / 10., -20.);
    let ray_direction = normalize(vec3<f32>(0.01, 0.01, 1.));

    var current_node = octree[0];
    var half_size = f32(1 << (8u - 2u));

    var b0: vec3<f32>;
    var b1: vec3<f32>; 

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var txmin: f32;
    var txmax: f32;
    var tymin: f32;
    var tymax: f32;
    var tzmin: f32;
    var tzmax: f32;

    var index: u32;

    var voxel_hit: u32;

    var color: vec4<f32> = vec4<f32>(.2, .2, .2, 1.);

    for (var i = 0; i < max_steps; i++) {
        // Box bounds
        b0 = vec3<f32>(
            -half_size,
            -half_size,
            -half_size,
        );
        b1 = vec3<f32>(
            half_size,
            half_size,
            half_size,
        );
    
        txmin = (b0.x - ray_origin.x) / ray_direction.x; 
        txmax = (b1.x - ray_origin.x) / ray_direction.x; 
        tymin = (b0.y - ray_origin.y) / ray_direction.y; 
        tymax = (b1.y - ray_origin.y) / ray_direction.y; 
    
        if (txmin > tymax || tymin > txmax) {
            // if (i > 0) {
            //     color = vec4<f32>(1., 0., 0., 1.);
            // }
            break;
        }
    
        if (tymin > txmin) {
            txmin = tymin; 
        }
        if (tymax < txmax) {
            txmax = tymax; 
        }
    
        tzmin = (b0.z - ray_origin.z) / ray_direction.z;
        tzmax = (b1.z - ray_origin.z) / ray_direction.z;
    
        if (txmin > tzmax || tzmin > txmax) {
            break;
        }
    
        if (tzmin > txmin) {
            txmin = tzmin; 
        }
        if (tzmax < txmax) {
            txmax = tzmax; 
        }

    
        if (is_null(current_node.children[0])) {
            voxel_hit = current_node.data;
            break;
        }

        index = 0u;

        if (ray_origin.x + txmin >= 0.) {
            index |= 4u;
            txmin -= half_size;
        }
        if (ray_origin.y + tymin >= 0.) {
            index |= 2u;
            tymin -= half_size;
        }
        if (ray_origin.z + tzmin >= 0.) {
            index |= 1u;
            tzmin -= half_size;
        }

        ray_origin = vec3<f32>(txmin, tymin, tzmin);

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

    switch voxel_hit {
        case 1u: {
            color = vec4<f32>(0., 1., 0., 1.);
        }
        default {}
    }

    textureStore(output, vec2<i32>(global_id.xy), color);
}
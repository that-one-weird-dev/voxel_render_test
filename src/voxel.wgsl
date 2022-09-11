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

@compute
@workgroup_size(1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    var color: vec4<f32> = vec4<f32>(.2, .2, .2, 1.);

    let view_size = vec2<f32>(textureDimensions(output));

    let ray_origin = vec3<f32>((vec2<f32>(global_id.xy) - (view_size / 2.)) / 10., -1.);
    let ray_direction = normalize(vec3<f32>(0.5, 0.5, 1.));

    var current_node = octree[0];
    var half_size = 51.2 / 2.;

    var b0: vec3<f32>;
    var b1: vec3<f32>; 

    var t0: vec3<f32>;
    var t1: vec3<f32>;

    var tmin: f32;
    var tmax: f32;
    var tymin: f32;
    var tymax: f32;
    var tzmin: f32;
    var tzmax: f32;

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
    
        tmin = (b0.x - ray_origin.x) / ray_direction.x; 
        tmax = (b1.x - ray_origin.x) / ray_direction.x; 
        tymin = (b0.y - ray_origin.y) / ray_direction.y; 
        tymax = (b1.y - ray_origin.y) / ray_direction.y; 
    
        if (tmin > tymax || tymin > tmax) {
            break;
        }
    
        if (tymin > tmin) {
            tmin = tymin; 
        }
        if (tymax < tmax) {
            tmax = tymax; 
        }
    
        tzmin = (b0.z - ray_origin.z) / ray_direction.z;
        tzmax = (b1.z - ray_origin.z) / ray_direction.z;
    
        if (tmin > tzmax || tzmin > tmax) {
            break;
        }
    
        if (tzmin > tmin) {
            tmin = tzmin; 
        }
        if (tzmax < tmax) {
            tmax = tzmax; 
        }
    
        color = cube_color * ((tmin + half_size) / half_size);
        break;
    }

    textureStore(output, vec2<i32>(global_id.xy), color)
}
use bytemuck::{Pod, Zeroable};


#[repr(C)]
#[derive(Clone, Copy, Zeroable, Pod)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32, // Used for alignment
    pub w: f32, // Used for alignment
}

impl Vec3 {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z, w: 0. }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Zeroable, Pod)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
    pub z: f32, // Used for alignment
    pub w: f32, // Used for alignment
}

impl Vec2 {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y, z: 0., w: 0. }
    }
}

#[repr(C, align(16))]
#[derive(Clone, Copy, Zeroable, Pod)]
pub struct Camera {
    pub position: Vec3,
    pub rotation: Vec2,
}
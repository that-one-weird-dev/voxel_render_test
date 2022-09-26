use bytemuck::{Pod, Zeroable};


#[repr(C)]
#[derive(Clone, Copy, Zeroable, Pod)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vec3 {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Zeroable, Pod)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
}

impl Vec2 {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Zeroable, Pod)]
pub struct Camera {
    pub position: Vec3,
    _padding1: f32,
    pub rotation: Vec2,
    pub aspect_ratio: f32,
    _padding2: f32,
}

impl Camera {
    pub fn new(position: Vec3, rotation: Vec2, aspect_ratio: f32) -> Self {
        Self {
            position,
            _padding1: 0.,
            rotation,
            aspect_ratio,
            _padding2: 0.,
        }
    }
}
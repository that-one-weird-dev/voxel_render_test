
#[repr(C)]
#[derive(Clone, Copy, Default, PartialEq)]
pub struct Voxel {
    color: u32,
}

impl Voxel {
    pub fn new(r: u8, g: u8, b: u8) -> Self {
        Self::new_alpha(r, g, b, 255)
    }

    pub fn new_alpha(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self {
            color: a as u32 + ((b as u32) << 8) + ((g as u32) << 16) + ((r as u32) << 24),
        }
    }

    pub fn clear() -> Self {
        Self { color: 0 ,}
    }
}
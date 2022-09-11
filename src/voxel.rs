
#[derive(Clone, Copy, Default, PartialEq)]
pub struct Voxel {
    pub id: u32,
}

impl Voxel {
    pub fn with_id(id: u32) -> Self {
        Self { id }
    }
}
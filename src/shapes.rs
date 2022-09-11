use crate::vertex::Vertex;


pub const QUAD: &[Vertex] = &[
    Vertex { position: [-1., -1., 0.], tex_coords: [0., 0.] },
    Vertex { position: [1., -1., 0.], tex_coords: [1.0, 0.0] },
    Vertex { position: [-1., 1., 0.], tex_coords: [0.0, 1.0] },
    Vertex { position: [1., 1., 0.], tex_coords: [1.0, 1.0] },
];

pub const QUAD_INDICES: &[u16] = &[
    2, 0, 1,
    3, 2, 1,
];
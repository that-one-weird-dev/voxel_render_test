# Voxel render test
This is an attempt at creating a voxel raycast renderer using rust.

# At what state is it?
Right now it can render vox files at a "not that good" performance.

# How?
For the data serialization i'm using [Ocpalm](https://github.com/ugomanu/ocpalm) (an octree data structure implementation by me).
It can serialize the entire octree with 0 time cost, the only BIG downsite that i will need to address is the time that it takes to write voxels (for some of the example models it can take up to 30 seconds on my hardware).
And for the rendering it's using wgpu (it will be moved to a bevy plugin in the future (far future).

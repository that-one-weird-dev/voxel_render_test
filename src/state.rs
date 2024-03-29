use std::{iter::once, mem::size_of, collections::HashSet};
use rand::prelude::*;
use ocpalm::Octree;
use wgpu::{Surface, Device, Queue, SurfaceConfiguration, SurfaceError, TextureViewDescriptor, CommandEncoderDescriptor, include_wgsl, BindingResource, TextureUsages, RenderPassDescriptor, RenderPassColorAttachment, Operations, Color, RenderPipeline, util::{DeviceExt, BufferInitDescriptor}, Buffer, BufferUsages, IndexFormat, BindGroupDescriptor, BindGroupEntry, BindGroupLayoutDescriptor, BindGroup, BufferBinding, BindGroupLayoutEntry, ShaderStages, BindingType, BufferBindingType, PresentMode, Backends};
use winit::{dpi::PhysicalSize, event::{WindowEvent, VirtualKeyCode, ElementState, Event, DeviceEvent}, window::Window};

use crate::{vertex::Vertex, shapes, voxel::Voxel, types::{Vec3, Camera, Vec2}, set_cursor_locked};

pub struct State {
    surface: Surface,
    device: Device,
    queue: Queue,
    config: SurfaceConfiguration,
    pub size: PhysicalSize<u32>,
    render_pipeline: RenderPipeline,
    vertex_buffer: Buffer,
    index_buffer: Buffer,
    render_bind_group: BindGroup,
    octree: Octree<Voxel>,
    octree_buffer: Buffer,
    camera_buffer: Buffer,
    camera: Camera,
    keys_down: HashSet<VirtualKeyCode>,
    keys_pressed: HashSet<VirtualKeyCode>,
    velocity: Vec3,
    cube_pos: f32,
    is_cursor_locked: bool,
}

impl State {
    pub async fn new(window: &Window) -> Self {
        let size = window.inner_size();

        // ---------------- Octree -------------
        let mut octree = Octree::new(16);

        // Loading the model
        let vox_data = vox_format::from_slice(include_bytes!("assets/#treehouse.vox")).unwrap();
        for model in vox_data.models {
            println!("Loading model of size: {:?}", model.size);
            for vox in model.voxels.iter() {
                let color = vox_data.palette.colors[vox.color_index.0 as usize];

                let x = vox.point.x;
                let y = vox.point.y;
                let z = vox.point.z;

                octree.set(
                    x as i32,
                    z as i32,
                    y as i32,
                    Voxel::new(color.r, color.g, color.b),
                );
            }
        }

        // octree.set(0, 0, 0, Voxel::clear());

        // The instance is a handle to our GPU
        // Backends::all => Vulkan + Metal + DX12 + Browser WebGPU
        let instance = wgpu::Instance::new(get_backend());
        let surface = unsafe { instance.create_surface(window) };
        let adapter = instance.request_adapter(
            &wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            },
        ).await.unwrap();

        let (device, queue) = adapter.request_device(
            &wgpu::DeviceDescriptor {
                features: wgpu::Features::empty(),
                // WebGL doesn't support all of wgpu's features, so if
                // we're building for the web we'll have to disable some.
                limits: if cfg!(target_arch = "wasm32") {
                    wgpu::Limits::downlevel_webgl2_defaults()
                } else {
                    wgpu::Limits::default()
                },
                label: None,
            },
            None,
        ).await.unwrap();

        let config = wgpu::SurfaceConfiguration {
            usage: TextureUsages::RENDER_ATTACHMENT,
            format: surface.get_supported_formats(&adapter)[0],
            width: size.width,
            height: size.height,
            present_mode: PresentMode::AutoNoVsync,
        };
        surface.configure(&device, &config);

        // ------------------------------------ Render pipeline ----------------------------------------
        let camera = Camera::new(
            Vec3::new(0., 0., 0.),
            Vec2::new(0., 0.),
            size.height as f32 / size.width as f32,
        );

        let octree_buffer = device.create_buffer_init(&BufferInitDescriptor {
            label: Some("Octree buffer"),
            contents: octree.as_byte_slice(),
            usage: BufferUsages::STORAGE | BufferUsages::COPY_DST,
        });

        let camera_buffer = device.create_buffer_init(&BufferInitDescriptor {
            label: Some("Camera buffer"),
            contents: bytemuck::bytes_of(&camera),
            usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
        });

        let render_bind_group_layout = device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            entries: &[
                BindGroupLayoutEntry {
                    binding: 0,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Storage {
                            read_only: true,
                        },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 1,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
            label: Some("Texture bind group layout"),
        });

        let render_bind_group = device.create_bind_group(&BindGroupDescriptor {
            label: Some("Voxel texture bind group"),
            layout: &render_bind_group_layout,
            entries: &[
                BindGroupEntry {
                    binding: 0,
                    resource: BindingResource::Buffer(BufferBinding {
                        buffer: &octree_buffer,
                        offset: 0,
                        size: None,
                    }),
                },
                BindGroupEntry {
                    binding: 1,
                    resource: BindingResource::Buffer(BufferBinding {
                        buffer: &camera_buffer,
                        offset: 0,
                        size: None,
                    }),
                },
            ],
        });

        let render_shader = device.create_shader_module(include_wgsl!("shader.wgsl"));
        let render_pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Render Pipeline Layout"),
            bind_group_layouts: &[&render_bind_group_layout],
            push_constant_ranges: &[],
        });
        let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Render Pipeline"),
            layout: Some(&render_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &render_shader,
                entry_point: "vs_main",
                buffers: &[
                    Vertex::desc(),
                ],
            },
            fragment: Some(wgpu::FragmentState {
                module: &render_shader,
                entry_point: "fs_main",
                targets: &[Some(wgpu::ColorTargetState {
                    format: config.format,
                    blend: Some(wgpu::BlendState::REPLACE),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: Some(wgpu::Face::Back),
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview: None,
        });

        let vertex_buffer = device.create_buffer_init(&BufferInitDescriptor {
            label: Some("Vertex buffer"),
            contents: bytemuck::cast_slice(shapes::QUAD),
            usage: BufferUsages::VERTEX,
        });

        let index_buffer = device.create_buffer_init(&BufferInitDescriptor {
            label: Some("Index buffer"),
            contents: bytemuck::cast_slice(shapes::QUAD_INDICES),
            usage: BufferUsages::INDEX,
        });

        Self {
            surface,
            device,
            queue,
            config,
            size,
            render_pipeline,
            vertex_buffer,
            index_buffer,
            render_bind_group,
            octree,
            octree_buffer,
            camera_buffer,
            camera,
            keys_down: HashSet::new(),
            keys_pressed: HashSet::new(),
            velocity: Vec3::new(0., 0., 0.),
            cube_pos: 0.,
            is_cursor_locked: true,
        }
    }

    pub fn resize(&mut self, new_size: PhysicalSize<u32>) {
        if new_size.width > 0 && new_size.height > 0 {
            self.size = new_size;
            self.config.width = new_size.width;
            self.config.height = new_size.height;
            self.surface.configure(&self.device, &self.config);
            self.camera.aspect_ratio = new_size.height as f32 / new_size.width as f32;
        }
    }

    pub fn input(&mut self, event: &Event<()>) {
        const SENSITIVITY: f32 = 0.001;

        match event {
            Event::DeviceEvent { event: DeviceEvent::MouseMotion { delta }, .. } => {
                self.camera.rotation.x += delta.1 as f32 * SENSITIVITY;
                self.camera.rotation.y -= delta.0 as f32 * SENSITIVITY;
            },
            Event::WindowEvent { event: WindowEvent::KeyboardInput { input, ..  }, .. } => {
                match input.virtual_keycode {
                    Some(keycode) => {
                        match input.state {
                            ElementState::Pressed => {
                                self.keys_down.insert(keycode);
                                self.keys_pressed.insert(keycode);
                            },
                            ElementState::Released => {
                                self.keys_down.remove(&keycode);
                            },
                        }
                    },
                    None => {},
                };
            },
            _ => {},
        }
    }

    pub fn update(&mut self, delta: f32, window: &Window) {
        const SPEED: f32 = 1.;

        self.velocity.x = 0.;
        self.velocity.y = 0.;
        self.velocity.z = 0.;

        if self.keys_down.contains(&VirtualKeyCode::E) {
            let mut rng = rand::thread_rng();

            let x = rng.gen_range(-64..64);
            let y = rng.gen_range(-64..64);
            let z = rng.gen_range(-64..64);

            self.octree.set(x, y, z, Voxel::new(255, 0, 255));
        }

        if self.keys_down.contains(&VirtualKeyCode::D) {
            self.velocity.x += SPEED * self.camera.rotation.y.cos();
            self.velocity.z += SPEED * self.camera.rotation.y.sin();
        }
        if self.keys_down.contains(&VirtualKeyCode::A) {
            self.velocity.x -= SPEED * self.camera.rotation.y.cos();
            self.velocity.z -= SPEED * self.camera.rotation.y.sin();
        }
        if self.keys_down.contains(&VirtualKeyCode::W) {
            self.velocity.x -= SPEED * self.camera.rotation.y.sin();
            self.velocity.z += SPEED * self.camera.rotation.y.cos();
        }
        if self.keys_down.contains(&VirtualKeyCode::S) {
            self.velocity.x += SPEED * self.camera.rotation.y.sin();
            self.velocity.z -= SPEED * self.camera.rotation.y.cos();
        }
        if self.keys_down.contains(&VirtualKeyCode::Space) {
            self.velocity.y += SPEED;
        }
        if self.keys_down.contains(&VirtualKeyCode::LShift) {
            self.velocity.y += -SPEED;
        }

        if self.keys_pressed.contains(&VirtualKeyCode::Escape) {
            self.is_cursor_locked = !self.is_cursor_locked;
            set_cursor_locked(window, self.is_cursor_locked);
        }

        self.keys_pressed.clear();

        self.camera.position.x += self.velocity.x * delta;
        self.camera.position.y += self.velocity.y * delta;
        self.camera.position.z += self.velocity.z * delta;

        // Flying cube

        self.cube_pos += delta;

        let x = self.cube_pos as i32 + 5;
        let y = 10;
        let z = 5;

        for z in z..z+2 {
            for y in y..y+2 {
                self.octree.set(x - 1, y, z, Voxel::clear());
            }
        }

        for z in z..z+2 {
            for y in y..y+2 {
                for x in x..x+2 {
                    self.octree.set(x, y, z, Voxel::new(156, 200, 120));
                }
            }
        }
    }

    pub fn render(&mut self) -> Result<(), SurfaceError> {
        let output = self.surface.get_current_texture()?;
        let output_view = output.texture.create_view(&TextureViewDescriptor::default());

        let mut encoder = self.device.create_command_encoder(&CommandEncoderDescriptor { label: Some("Render Encoder") });

        let octree_bytes = self.octree.as_byte_slice();

        // Updating voxel buffer
        self.queue.write_buffer(&self.octree_buffer, 0, octree_bytes);

        // Updating camera position
        let staging_camera_buffer = self.device.create_buffer_init(&BufferInitDescriptor {
            label: Some("Camera buffer"),
            contents: bytemuck::bytes_of(&self.camera),
            usage: BufferUsages::UNIFORM | BufferUsages::COPY_SRC,
        });

        encoder.copy_buffer_to_buffer(
            &staging_camera_buffer,
            0,
            &self.camera_buffer,
            0,
            size_of::<Camera>() as u64,
        );

        {
            let mut render_pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some("Render pass"),
                color_attachments: &[
                    Some(RenderPassColorAttachment {
                        view: &output_view,
                        resolve_target: None,
                        ops: Operations {
                            load: wgpu::LoadOp::Clear(Color::BLACK),
                            store: true,
                        },
                    })
                ],
                depth_stencil_attachment: None,
            });

            render_pass.set_pipeline(&self.render_pipeline);
            render_pass.set_bind_group(0, &self.render_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            render_pass.set_index_buffer(self.index_buffer.slice(..), IndexFormat::Uint16);
            render_pass.draw_indexed(0..shapes::QUAD_INDICES.len() as u32, 0, 0..1);
        }

        self.queue.submit(once(encoder.finish()));
        output.present();

        Ok(())
    }
}

fn get_backend() -> Backends {
    if cfg!(target_os = "linux") {
        Backends::VULKAN
    } else {
        Backends::all()
    }
}

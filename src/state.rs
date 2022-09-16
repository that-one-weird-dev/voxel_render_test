use std::iter::once;

use ocpalm::Octree;
use wgpu::{Surface, Device, Queue, SurfaceConfiguration, SurfaceError, TextureViewDescriptor, CommandEncoderDescriptor, include_wgsl, BindingResource, TextureFormat, TextureUsages, RenderPassDescriptor, RenderPassColorAttachment, Operations, Color, RenderPipeline, util::{DeviceExt, BufferInitDescriptor}, Buffer, BufferUsages, IndexFormat, BindGroupDescriptor, BindGroupEntry, BindGroupLayoutDescriptor, BindGroup, BufferBinding, BindGroupLayoutEntry, ShaderStages, BindingType, BufferBindingType};
use winit::{dpi::PhysicalSize, event::{WindowEvent, VirtualKeyCode}, window::Window};

use crate::{vertex::Vertex, shapes, voxel::Voxel};

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
}

impl State {
    pub async fn new(window: &Window) -> Self {
        let size = window.inner_size();

        // ---------------- Octree -------------
        let mut octree = Octree::new(8);

        octree.set(0, 0, 0, Voxel::with_id(1));
        octree.set(0, 1, 0, Voxel::with_id(1));
        octree.set(1, 0, 0, Voxel::with_id(1));
        octree.set(30, 30, 30, Voxel::with_id(2));

        // The instance is a handle to our GPU
        // Backends::all => Vulkan + Metal + DX12 + Browser WebGPU
        let instance = wgpu::Instance::new(wgpu::Backends::all());
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
            usage: TextureUsages::RENDER_ATTACHMENT | TextureUsages::COPY_DST,
            format: TextureFormat::Bgra8Unorm,
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
        };
        surface.configure(&device, &config);

        // ------------------------------------ Render pipeline ----------------------------------------
        let octree_buffer = device.create_buffer_init(&BufferInitDescriptor {
            label: Some("Octree buffer"),
            contents: octree.as_byte_slice(),
            usage: BufferUsages::STORAGE,
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
        }
    }

    pub fn resize(&mut self, new_size: PhysicalSize<u32>) {
        if new_size.width > 0 && new_size.height > 0 {
            self.size = new_size;
            self.config.width = new_size.width;
            self.config.height = new_size.height;
            self.surface.configure(&self.device, &self.config);
        }
    }

    pub fn input(&mut self, event: &WindowEvent) -> bool {
        match event {
            WindowEvent::KeyboardInput { input, ..  } => {
                match input.virtual_keycode {
                    Some(VirtualKeyCode::E) => {
                        self.octree.set(0, 0, 0, Voxel::with_id(1));
                        println!("Set voxel");
                    },
                    _ => {},
                }
            },
            _ => {},
        }
        false
    }

    pub fn update(&mut self) {
    }

    pub fn render(&mut self) -> Result<(), SurfaceError> {
        let output = self.surface.get_current_texture()?;
        let output_view = output.texture.create_view(&TextureViewDescriptor::default());

        let mut encoder = self.device.create_command_encoder(&CommandEncoderDescriptor { label: Some("Render Encoder") });

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
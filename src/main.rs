mod state;
mod vertex;
mod shapes;
mod voxel;
mod types;

use std::time::Instant;

use state::State;
use wgpu::SurfaceError;
use winit::{event_loop::{EventLoop, ControlFlow}, window::{WindowBuilder, CursorGrabMode}, event::{Event, WindowEvent}};

fn main() {
    pollster::block_on(run());
}

async fn run() {
    env_logger::init();

    let event_loop = EventLoop::new();
    let window = WindowBuilder::new().build(&event_loop).unwrap();

    let mut state = State::new(&window).await;

    let mut last_render_time = Instant::now();

    window.set_cursor_visible(false);
    match window.set_cursor_grab(CursorGrabMode::Confined) {
        Err(_) => {
            window.set_cursor_grab(CursorGrabMode::Locked).ok();
        },
        Ok(_) => {},
    }

    event_loop.run(move |event, _, control_flow| {

        state.input(&event);

        match event {
            Event::WindowEvent {
                ref event,
                window_id
            } if window_id == window.id() => match event {
                WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                WindowEvent::Resized(physical_size) => state.resize(*physical_size),
                WindowEvent::ScaleFactorChanged { new_inner_size, .. } => state.resize(**new_inner_size),
                _ => {},
            },
            Event::RedrawRequested(window_id) if window_id == window.id() => {
                let now = Instant::now();
                let dt = now - last_render_time;
                last_render_time = now;

                state.update(dt.as_secs_f32());

                match state.render() {
                    Ok(_) => {},
                    Err(SurfaceError::Lost) => state.resize(state.size),
                    Err(SurfaceError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                    Err(e) => eprintln!("{:?}", e),
                }
            },
            Event::MainEventsCleared => {
                window.request_redraw();
            },
            _ => {},
        }
    });
}

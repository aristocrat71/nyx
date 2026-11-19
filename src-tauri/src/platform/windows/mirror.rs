use super::overlay::{overlay_window, place, Target};
use crate::engine::{self, MirrorEvent};
use std::collections::HashMap;
use std::sync::OnceLock;
use windows::core::{factory, w, Interface};
use windows::Foundation::TypedEventHandler;
use windows::Graphics::Capture::{Direct3D11CaptureFramePool, GraphicsCaptureItem, GraphicsCaptureSession};
use windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
use windows::Graphics::DirectX::DirectXPixelFormat;
use windows::Graphics::SizeInt32;
use windows::Win32::Foundation::{COLORREF, HMODULE, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Direct3D::D3D_DRIVER_TYPE_HARDWARE;
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11DeviceContext, ID3D11Texture2D, D3D11_BOX, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
    D3D11_SDK_VERSION, D3D11_TEXTURE2D_DESC,
};
use windows::Win32::Graphics::DirectComposition::{DCompositionCreateDevice, IDCompositionDevice, IDCompositionTarget};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_ALPHA_MODE_IGNORE, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC};
use windows::Win32::Graphics::Dxgi::{
    CreateDXGIFactory2, IDXGIDevice, IDXGIFactory2, IDXGISwapChain1, DXGI_CREATE_FACTORY_FLAGS, DXGI_PRESENT,
    DXGI_SCALING_STRETCH, DXGI_SWAP_CHAIN_DESC1, DXGI_SWAP_CHAIN_FLAG, DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
    DXGI_USAGE_RENDER_TARGET_OUTPUT,
};
use windows::Win32::System::WinRT::Direct3D11::{CreateDirect3D11DeviceFromDXGIDevice, IDirect3DDxgiInterfaceAccess};
use windows::Win32::System::WinRT::Graphics::Capture::IGraphicsCaptureItemInterop;
use windows::Win32::UI::WindowsAndMessaging::{
    DefWindowProcW, DestroyWindow, RegisterClassW, SetLayeredWindowAttributes, SetWindowDisplayAffinity, HTTRANSPARENT,
    LWA_ALPHA, WDA_EXCLUDEFROMCAPTURE, WM_NCHITTEST, WNDCLASSW, WS_EX_NOREDIRECTIONBITMAP,
};

// Mirror: what the user sees through the placeholders. Windows Graphics Capture streams each
// protected window even while it is covered, into a window excluded from every capture.

struct Gpu {
    device: ID3D11Device,
    context: ID3D11DeviceContext,
    winrt: IDirect3DDevice,
    factory: IDXGIFactory2,
    dcomp: IDCompositionDevice,
}

struct Shown {
    hwnd: HWND,
    pool: Direct3D11CaptureFramePool,
    session: GraphicsCaptureSession,
    swap: IDXGISwapChain1,
    _target: IDCompositionTarget,
    size: SizeInt32,
    placed: Option<RECT>,
}

#[derive(Default)]
pub struct Mirror {
    epoch: u64,
    running: bool,
    pid: Option<i32>,
    gpu: Option<Gpu>,
    shown: HashMap<isize, Shown>,
}

fn post_event(epoch: u64, event: MirrorEvent) {
    engine::post(move |nyx| {
        if nyx.mirror.epoch == epoch {
            nyx.mirror_event(event);
        }
    });
}

impl Mirror {
    /// Sessions follow the windows on screen, so they are opened by `restack` each tick.
    pub fn start(&mut self, pid: i32) {
        self.stop();
        self.pid = Some(pid);
        if self.gpu.is_none() {
            self.gpu = gpu().inspect_err(|e| log::error!("no gpu for the mirror: {e}")).ok();
        }
        if self.gpu.is_none() {
            post_event(self.epoch, MirrorEvent::Failed);
        }
    }

    pub fn stop(&mut self) {
        self.epoch += 1;
        self.running = false;
        self.pid = None;
        for (_, shown) in self.shown.drain() {
            let _ = shown.session.Close();
            let _ = shown.pool.Close();
            let _ = unsafe { DestroyWindow(shown.hwnd) };
        }
    }

    /// Placed after the covers each tick, so every mirror window sits on its own cover.
    pub fn restack(&mut self, targets: &[Target]) {
        let Some(gpu) = self.pid.and(self.gpu.as_ref()) else { return };
        self.shown.retain(|id, shown| {
            let live = targets.iter().any(|t| t.hwnd == *id);
            if !live {
                let _ = shown.session.Close();
                let _ = unsafe { DestroyWindow(shown.hwnd) };
            }
            live
        });
        for t in targets {
            if !self.shown.contains_key(&t.hwnd) {
                match show(gpu, t, self.epoch) {
                    Ok(shown) => drop(self.shown.insert(t.hwnd, shown)),
                    // Some popups cannot be captured; they stay black for the user too, which never leaks.
                    Err(e) => log::debug!("window not mirrored: {e}"),
                }
            }
            if let Some(shown) = self.shown.get_mut(&t.hwnd).filter(|s| s.placed != Some(t.frame)) {
                place(shown.hwnd, t.frame, shown.placed.is_none());
                shown.placed = Some(t.frame);
            }
        }
        if self.shown.is_empty() && !targets.is_empty() {
            post_event(self.epoch, MirrorEvent::Failed);
        }
    }

    /// True on the first frame, when the mirror starts running.
    fn present(&mut self, id: isize) -> bool {
        let (Some(gpu), Some(shown)) = (self.gpu.as_ref(), self.shown.get_mut(&id)) else { return false };
        if copy_frame(gpu, shown).is_err() {
            return false;
        }
        !std::mem::replace(&mut self.running, true)
    }
}

fn gpu() -> windows::core::Result<Gpu> {
    let (mut device, mut context) = (None, None);
    unsafe {
        D3D11CreateDevice(None, D3D_DRIVER_TYPE_HARDWARE, HMODULE::default(), D3D11_CREATE_DEVICE_BGRA_SUPPORT, None,
            D3D11_SDK_VERSION, Some(&mut device), None, Some(&mut context))?;
    }
    let device = device.expect("created above");
    let dxgi: IDXGIDevice = device.cast()?;
    Ok(Gpu {
        winrt: unsafe { CreateDirect3D11DeviceFromDXGIDevice(&dxgi)? }.cast()?,
        factory: unsafe { CreateDXGIFactory2(DXGI_CREATE_FACTORY_FLAGS(0))? },
        dcomp: unsafe { DCompositionCreateDevice(&dxgi)? },
        context: context.expect("created above"),
        device,
    })
}

fn show(gpu: &Gpu, t: &Target, epoch: u64) -> windows::core::Result<Shown> {
    let interop = factory::<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()?;
    let item: GraphicsCaptureItem = unsafe { interop.CreateForWindow(HWND(t.hwnd as _))? };
    let size = item.Size()?;
    let pool = Direct3D11CaptureFramePool::CreateFreeThreaded(&gpu.winrt, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size)?;
    let session = pool.CreateCaptureSession(&item)?;
    let _ = session.SetIsBorderRequired(false);
    let _ = session.SetIsCursorCaptureEnabled(false);
    let id = t.hwnd;
    // Frames land on a worker thread; only the id crosses, and the main thread pulls the frame.
    pool.FrameArrived(&TypedEventHandler::new(move |_, _| {
        engine::post(move |nyx| {
            if nyx.mirror.epoch == epoch && nyx.mirror.present(id) {
                nyx.mirror_event(MirrorEvent::Running);
            }
        });
        Ok(())
    }))?;

    let hwnd = mirror_window();
    let desc = DXGI_SWAP_CHAIN_DESC1 {
        Width: size.Width.max(1) as u32,
        Height: size.Height.max(1) as u32,
        Format: DXGI_FORMAT_B8G8R8A8_UNORM,
        SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
        BufferUsage: DXGI_USAGE_RENDER_TARGET_OUTPUT,
        BufferCount: 2,
        Scaling: DXGI_SCALING_STRETCH,
        SwapEffect: DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
        AlphaMode: DXGI_ALPHA_MODE_IGNORE,
        ..Default::default()
    };
    let swap = unsafe { gpu.factory.CreateSwapChainForComposition(&gpu.device, &desc, None)? };
    let target = unsafe { gpu.dcomp.CreateTargetForHwnd(hwnd, true)? };
    let visual = unsafe { gpu.dcomp.CreateVisual()? };
    unsafe {
        visual.SetContent(&swap)?;
        target.SetRoot(&visual)?;
        gpu.dcomp.Commit()?;
    }
    session.StartCapture()?;
    Ok(Shown { hwnd, pool, session, swap, _target: target, size, placed: None })
}

fn copy_frame(gpu: &Gpu, shown: &mut Shown) -> windows::core::Result<()> {
    let frame = shown.pool.TryGetNextFrame()?;
    let size = frame.ContentSize()?;
    let access: IDirect3DDxgiInterfaceAccess = frame.Surface()?.cast()?;
    let source: ID3D11Texture2D = unsafe { access.GetInterface()? };
    if size != shown.size {
        shown.size = size;
        shown.pool.Recreate(&gpu.winrt, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size)?;
        let (w, h) = (size.Width.max(1) as u32, size.Height.max(1) as u32);
        unsafe { shown.swap.ResizeBuffers(2, w, h, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SWAP_CHAIN_FLAG(0))? };
    }
    let back: ID3D11Texture2D = unsafe { shown.swap.GetBuffer(0)? };
    let mut desc = D3D11_TEXTURE2D_DESC::default();
    unsafe { source.GetDesc(&mut desc) };
    let area = D3D11_BOX { right: desc.Width.min(size.Width as u32), bottom: desc.Height.min(size.Height as u32), back: 1, ..Default::default() };
    unsafe {
        gpu.context.CopySubresourceRegion(&back, 0, 0, 0, 0, &source, 0, Some(&area));
        shown.swap.Present(0, DXGI_PRESENT(0)).ok()
    }
}

/// Excluded from capture before it is ever shown, so no mirrored frame reaches a viewer.
fn mirror_window() -> HWND {
    static CLASS: OnceLock<u16> = OnceLock::new();
    CLASS.get_or_init(|| {
        let class = WNDCLASSW { lpfnWndProc: Some(mirror_proc), lpszClassName: w!("NyxMirror"), ..Default::default() };
        unsafe { RegisterClassW(&class) }
    });
    let hwnd = overlay_window(w!("NyxMirror"), WS_EX_NOREDIRECTIONBITMAP);
    unsafe {
        let _ = SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);
        let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), 255, LWA_ALPHA);
    }
    hwnd
}

unsafe extern "system" fn mirror_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if msg == WM_NCHITTEST {
        return LRESULT(HTTRANSPARENT as isize);
    }
    unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) }
}

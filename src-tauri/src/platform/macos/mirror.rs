use super::overlay::Target;

#[derive(Default)]
pub struct Mirror;

impl Mirror {
    pub fn start(&mut self, _pid: i32) {}
    pub fn stop(&mut self) {}
    pub fn restack(&mut self, _targets: &[Target]) {}
}

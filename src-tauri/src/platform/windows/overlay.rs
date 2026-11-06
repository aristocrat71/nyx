#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Target;

pub fn windows_of(_pid: i32) -> Vec<Target> {
    vec![]
}

#[derive(Default)]
pub struct Placeholders;

impl Placeholders {
    pub fn cover(&mut self, _targets: &[Target]) {}
    pub fn clear(&mut self) {}
}

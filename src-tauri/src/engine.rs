use crate::{platform, store::ProtectionList};
use serde::Serialize;
use std::cell::RefCell;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::Duration;
use tauri::AppHandle;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Idle,
    /// Covered and mirrored: viewers see black, the user sees their app.
    Active,
    /// Covered, no mirror: still hidden from viewers, but the user is blind too.
    Blind,
}

const RESNAP: Duration = Duration::from_millis(16);
const CAPTURE_POLL: Duration = Duration::from_secs(1);

pub struct Nyx {
    pub list: ProtectionList,
    pub state: State,
    engaged: Option<i32>,
    covers: platform::Placeholders,
    pub mirror: platform::Mirror,
    capturing: bool,
}

thread_local! {
    static NYX: RefCell<Option<Nyx>> = const { RefCell::new(None) };
}
static APP: OnceLock<AppHandle> = OnceLock::new();
static PERIOD_MS: AtomicU64 = AtomicU64::new(1000);

/// Runs `f` on the main thread, where every native object Nyx owns lives.
pub fn post(f: impl FnOnce(&mut Nyx) + Send + 'static) {
    if let Some(app) = APP.get() {
        let _ = app.run_on_main_thread(move || {
            with(f);
        });
    }
}

pub fn with<R>(f: impl FnOnce(&mut Nyx) -> R) -> Option<R> {
    NYX.with(|cell| cell.borrow_mut().as_mut().map(f))
}

pub fn start(app: AppHandle, list: ProtectionList) {
    NYX.with(|cell| {
        *cell.borrow_mut() = Some(Nyx {
            list,
            state: State::Idle,
            engaged: None,
            covers: Default::default(),
            mirror: Default::default(),
            capturing: platform::capturing(),
        })
    });
    let _ = APP.set(app);
    platform::observe(|| post(Nyx::evaluate), || post(Nyx::displays_changed));
    platform::observe_capture(|| post(Nyx::evaluate));
    std::thread::spawn(|| loop {
        std::thread::sleep(Duration::from_millis(PERIOD_MS.load(Ordering::Relaxed)));
        post(Nyx::tick);
    });
    with(Nyx::evaluate);
}

impl Nyx {
    /// Keyed on the process, not a window existing yet: `tick` covers whatever is on
    /// screen each frame, so late windows need no retry.
    pub fn evaluate(&mut self) {
        self.capturing = platform::capturing();
        let front = platform::frontmost().filter(|_| self.list.enabled && self.capturing);
        match front.filter(|app| self.list.contains(&app.id)) {
            Some(app) => self.engage(app.pid),
            None => self.disengage(),
        }
        self.set_period();
    }

    fn tick(&mut self) {
        if let Some(pid) = self.engaged {
            self.resnap(pid);
        }
        if platform::capturing() != self.capturing {
            self.evaluate();
        }
    }

    fn set_period(&self) {
        let period = if self.engaged.is_some() { RESNAP } else { CAPTURE_POLL };
        PERIOD_MS.store(period.as_millis() as u64, Ordering::Relaxed);
    }

    fn engage(&mut self, pid: i32) {
        if self.engaged == Some(pid) {
            return;
        }
        self.tear_down();
        self.engaged = Some(pid);
        // Cover first, from the window list alone, before anything that can fail or go async.
        self.resnap(pid);
        self.publish(State::Blind);
        self.mirror.start(pid);
        log::debug!("engaged");
    }

    pub fn disengage(&mut self) {
        if self.engaged.is_none() {
            return;
        }
        self.tear_down();
        self.publish(State::Idle);
        log::debug!("disengaged");
    }

    /// A projector arriving is exactly when a share starts, so the mirror is rebuilt
    /// for the new displays without ever dropping cover.
    pub fn displays_changed(&mut self) {
        if let Some(pid) = self.engaged {
            self.publish(State::Blind);
            self.mirror.start(pid);
        }
    }

    fn tear_down(&mut self) {
        self.engaged = None;
        self.mirror.stop();
        self.covers.clear();
    }

    /// Cover, then lift the mirror onto the covers, so it never rises above a cover not yet placed.
    fn resnap(&mut self, pid: i32) {
        let targets = platform::windows_of(pid);
        self.covers.cover(&targets);
        self.mirror.restack(&targets);
    }

    fn publish(&mut self, state: State) {
        if self.state != state {
            self.state = state;
            crate::state_changed(state);
        }
    }
}

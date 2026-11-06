use crate::{platform, store::ProtectionList};
use serde::Serialize;
use std::cell::RefCell;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};
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

pub enum MirrorEvent {
    Running,
    NoPermission,
    Failed,
    UserStopped,
}

const RESNAP: Duration = Duration::from_millis(16);
const TAB_POLL: Duration = Duration::from_millis(350);
const CAPTURE_POLL: Duration = Duration::from_secs(1);
const MIN_RETRY: Duration = Duration::from_millis(500);
const MAX_RETRY: Duration = Duration::from_secs(30);

pub struct Nyx {
    pub list: ProtectionList,
    pub state: State,
    engaged: Option<i32>,
    covers: platform::Placeholders,
    pub mirror: platform::Mirror,
    retry_at: Option<Instant>,
    retry_delay: Duration,
    capturing: bool,
    tab_pid: Option<i32>,
    last_tab: Option<platform::Tab>,
    next_tab_check: Instant,
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

pub fn app() -> &'static AppHandle {
    APP.get().expect("engine started")
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
            retry_at: None,
            retry_delay: MIN_RETRY,
            capturing: platform::capturing(),
            tab_pid: None,
            last_tab: None,
            next_tab_check: Instant::now(),
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
    pub fn set_enabled(&mut self, enabled: bool) {
        self.list.set_enabled(enabled);
        self.evaluate();
        crate::list_changed(&self.list);
    }

    /// Keyed on the process, not a window existing yet: `tick` covers whatever is on
    /// screen each frame, so late windows need no retry.
    pub fn evaluate(&mut self) {
        self.capturing = platform::capturing();
        let front = platform::frontmost().filter(|_| self.list.enabled && self.capturing);
        let watch_tab = front.as_ref().is_some_and(|app| {
            !self.list.contains(&app.id) && !self.list.sites.is_empty() && platform::is_browser(&app.id)
        });
        self.tab_pid = if watch_tab { front.as_ref().map(|a| a.pid) } else { None };
        if !watch_tab {
            self.last_tab = None;
        }
        match front.filter(|app| self.list.contains(&app.id) || (watch_tab && self.front_tab_protected(app.pid))) {
            Some(app) => {
                platform::check_identity(&app, &self.list);
                self.engage(app.pid);
            }
            None => self.disengage(),
        }
        self.set_period();
    }

    fn front_tab_protected(&mut self, pid: i32) -> bool {
        self.last_tab = platform::browser_tab(pid);
        let Some(tab) = &self.last_tab else { return false };
        match &tab.host {
            Some(host) => self.list.sites.iter().any(|s| s.matches_host(host)),
            None => tab.title.as_ref().is_some_and(|t| self.list.sites.iter().any(|s| s.matches_title(t))),
        }
    }

    fn tick(&mut self) {
        if let Some(pid) = self.engaged {
            self.resnap(pid);
            if self.retry_at.is_some_and(|at| Instant::now() >= at) {
                self.retry_at = None;
                self.mirror.start(pid);
            }
        }
        let tab_changed = self.tab_pid.is_some_and(|pid| {
            Instant::now() >= self.next_tab_check && {
                self.next_tab_check = Instant::now() + TAB_POLL;
                platform::browser_tab(pid) != self.last_tab
            }
        });
        if tab_changed || platform::capturing() != self.capturing {
            self.evaluate();
        }
    }

    fn set_period(&self) {
        let period = if self.engaged.is_some() {
            RESNAP
        } else if self.tab_pid.is_some() {
            TAB_POLL
        } else {
            CAPTURE_POLL
        };
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
        self.retry_at = None;
        self.retry_delay = MIN_RETRY;
        self.mirror.stop();
        self.covers.clear();
    }

    /// Cover, then lift the mirror onto the covers, so it never rises above a cover not yet placed.
    fn resnap(&mut self, pid: i32) {
        let targets = platform::windows_of(pid);
        self.covers.cover(&targets);
        self.mirror.restack(&targets);
    }

    pub fn mirror_event(&mut self, event: MirrorEvent) {
        if self.engaged.is_none() {
            return;
        }
        if let MirrorEvent::Running = event {
            self.retry_delay = MIN_RETRY;
            return self.publish(State::Active);
        }
        self.publish(State::Blind);
        self.mirror.stop();
        match event {
            // An explicit click on the system "Stop Sharing" is the one thing allowed to drop protection.
            MirrorEvent::UserStopped => {
                log::error!("capture stopped from system UI, protection off");
                self.set_enabled(false);
            }
            MirrorEvent::NoPermission => {
                crate::permission_lost();
                self.schedule_retry();
            }
            _ => self.schedule_retry(),
        }
    }

    /// Backoff, not a tight loop: the covers stay up between attempts, so a failing stream never strobes.
    fn schedule_retry(&mut self) {
        self.retry_at = Some(Instant::now() + self.retry_delay);
        self.retry_delay = (self.retry_delay * 2).min(MAX_RETRY);
    }

    fn publish(&mut self, state: State) {
        if self.state != state {
            self.state = state;
            crate::state_changed(state);
        }
    }
}

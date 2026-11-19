use serde::{Deserialize, Serialize};

/// A host to cover while it is the browser's front tab. Stored bare, so one
/// spelling covers every way it was typed.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProtectedSite {
    pub host: String,
}

const MAX_HOST_LEN: usize = 253;

impl ProtectedSite {
    pub fn is_well_formed(&self) -> bool {
        let h = &self.host;
        (4..=MAX_HOST_LEN).contains(&h.len())
            && h.contains('.')
            && !h.starts_with('.')
            && !h.ends_with('.')
            && !h.starts_with('-')
            && !h.contains("..")
            && h.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'.' || b == b'-')
    }

    /// Takes a bare host or a whole pasted URL and reduces it to the stored form.
    pub fn normalize(raw: &str) -> Option<String> {
        let mut text = raw.trim().to_lowercase();
        if let Some(i) = text.find("://") {
            text.drain(..i + 3);
        }
        if let Some(i) = text.find(['/', '?', '#']) {
            text.truncate(i);
        }
        if let Some(i) = text.rfind('@') {
            text.drain(..=i);
        }
        if let Some(i) = text.find(':') {
            text.truncate(i);
        }
        let mut text = text.trim_end_matches('.');
        text = text.strip_prefix("www.").unwrap_or(text);
        let site = ProtectedSite { host: text.to_string() };
        site.is_well_formed().then_some(site.host)
    }

    /// Whole labels only: "youtube.com" covers "m.youtube.com", never "notyoutube.com".
    pub fn matches_host(&self, candidate: &str) -> bool {
        let lower = candidate.to_lowercase();
        let bare = lower.split(':').next().unwrap_or("").trim_end_matches('.');
        bare == self.host || bare.ends_with(&format!(".{}", self.host))
    }

    /// The brand label a page title likely carries: the one left of the public suffix.
    pub fn title_keyword(&self) -> Option<&str> {
        let mut labels: Vec<&str> = self.host.split('.').collect();
        labels.pop();
        if labels.len() >= 2 && labels.last().is_some_and(|l| l.len() <= 2) {
            labels.pop();
        }
        labels.last().copied().filter(|k| k.len() >= 3)
    }

    /// Only for browsers that publish no URL. Coarser by design: over-covering beats not covering.
    pub fn matches_title(&self, title: &str) -> bool {
        self.title_keyword().is_some_and(|k| title.to_lowercase().contains(k))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn site(host: &str) -> ProtectedSite {
        ProtectedSite { host: host.into() }
    }

    #[test]
    fn normalize_accepts_and_rejects() {
        for (input, want) in [
            ("youtube.com", "youtube.com"),
            ("  YouTube.com  ", "youtube.com"),
            ("www.youtube.com", "youtube.com"),
            ("https://www.youtube.com/watch?v=abc", "youtube.com"),
            ("http://m.youtube.com", "m.youtube.com"),
            ("youtube.com.", "youtube.com"),
            ("youtube.com:8443", "youtube.com"),
            ("https://user:pass@youtube.com/x", "youtube.com"),
            ("https://news.ycombinator.com/item?id=1#c", "news.ycombinator.com"),
            ("bbc.co.uk", "bbc.co.uk"),
            ("youtube.com/../etc", "youtube.com"),
        ] {
            assert_eq!(ProtectedSite::normalize(input).as_deref(), Some(want), "{input}");
        }
        let long = format!("{}.com", "a".repeat(250));
        for input in ["", "   ", "localhost", "youtube", ".com", "youtube..com", "-youtube.com",
                      "you tube.com", "https://", "a.b", "café.com", &long] {
            assert_eq!(ProtectedSite::normalize(input), None, "{input}");
        }
    }

    #[test]
    fn host_matching_is_by_whole_label() {
        let yt = site("youtube.com");
        for c in ["youtube.com", "www.youtube.com", "m.youtube.com", "YouTube.com", "youtube.com.", "youtube.com:443"] {
            assert!(yt.matches_host(c), "{c}");
        }
        for c in ["notyoutube.com", "youtube.com.example.net", "youtube.co", "example.com", "xyoutube.com"] {
            assert!(!yt.matches_host(c), "{c}");
        }
        let mail = site("mail.google.com");
        assert!(!mail.matches_host("google.com") && !mail.matches_host("docs.google.com"));
    }

    #[test]
    fn title_matching_uses_the_brand_label() {
        for (host, kw) in [("youtube.com", "youtube"), ("bbc.co.uk", "bbc"),
                           ("news.ycombinator.com", "ycombinator"), ("web.whatsapp.com", "whatsapp")] {
            assert_eq!(site(host).title_keyword(), Some(kw));
        }
        assert_eq!(site("x.com").title_keyword(), None);
        assert!(site("youtube.com").matches_title("Some video - YouTube"));
        assert!(!site("youtube.com").matches_title("Inbox (3) - Mail"));
    }
}

const ANALYTICS_ENDPOINT = "/api/analytics";

// Generate a unique session ID for this visit
const SESSION_ID =
  "sess_" + Math.random().toString(36).substr(2, 9) + "_" + Date.now();

// Core function to send analytics event
function trackEvent(eventType, data = {}) {
  const payload = {
    event_type: eventType,
    session_id: SESSION_ID,
    timestamp: new Date().toISOString(),
    page_url: window.location.href,
    user_agent: navigator.userAgent,
    ...data,
  };

  // Send to analytics collector
  fetch(ANALYTICS_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }).catch((err) => console.log("Analytics error:", err));

  // Also log to console for debugging
  console.log("[Analytics]", eventType, payload);
}

// ============================================
// EVENT 1: Page View
// Tracks every time someone visits the site
// ============================================
document.addEventListener("DOMContentLoaded", function () {
  trackEvent("page_view", {
    referrer: document.referrer || "direct",
    screen_width: window.screen.width,
    screen_height: window.screen.height,
  });
});

// ============================================
// EVENT 2: Section Scroll
// Tracks which sections users actually reach
// Useful to know if users scroll past the fold
// ============================================
const sections = [
  { id: "tm-section-1", name: "hero" },
  { id: "tm-section-2", name: "videos" },
  { id: "tm-section-3", name: "speakers" },
  { id: "tm-section-4", name: "programs" },
  { id: "tm-section-5", name: "register" },
];

const observedSections = new Set();

const sectionObserver = new IntersectionObserver(
  function (entries) {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        const sectionName = entry.target.getAttribute("data-section-name");
        if (sectionName && !observedSections.has(sectionName)) {
          observedSections.add(sectionName);
          trackEvent("section_scroll", {
            section_name: sectionName,
          });
        }
      }
    });
  },
  { threshold: 0.3 },
);

document.addEventListener("DOMContentLoaded", function () {
  sections.forEach((section) => {
    const el = document.getElementById(section.id);
    if (el) {
      el.setAttribute("data-section-name", section.name);
      sectionObserver.observe(el);
    }
  });
});

// ============================================
// EVENT 3: Speaker Card Click
// Tracks which speakers generate most interest
// ============================================
document.addEventListener("DOMContentLoaded", function () {
  const speakerCards = document.querySelectorAll(
    ".tm-speaker-item, .col-md-6 figure",
  );
  speakerCards.forEach((card, index) => {
    card.style.cursor = "pointer";
    card.addEventListener("click", function () {
      const speakerName =
        card.querySelector("h4, figcaption")?.textContent?.trim() ||
        "Speaker " + (index + 1);
      trackEvent("speaker_click", {
        speaker_name: speakerName,
        speaker_index: index + 1,
      });
    });
  });
});

// ============================================
// EVENT 4: Program Track View
// Tracks which program tracks users engage with
// ============================================
document.addEventListener("DOMContentLoaded", function () {
  const programItems = document.querySelectorAll(".tm-program-item, table tr");
  programItems.forEach((item, index) => {
    item.addEventListener("mouseenter", function () {
      const trackName =
        item.querySelector("td, h5")?.textContent?.trim() ||
        "Track " + (index + 1);
      trackEvent("program_track_view", {
        track_name: trackName,
        track_index: index + 1,
      });
    });
  });
});

// ============================================
// EVENT 5: Registration Attempt
// Tracks when users try to submit the form
// Useful to measure conversion rate
// ============================================
document.addEventListener("DOMContentLoaded", function () {
  const registerForm = document.querySelector("form, #tm-section-5 form");
  if (registerForm) {
    registerForm.addEventListener("submit", function (e) {
      const nameField = registerForm.querySelector(
        'input[name="name"], input[type="text"]',
      );
      const emailField = registerForm.querySelector(
        'input[name="email"], input[type="email"]',
      );
      trackEvent("registration_attempt", {
        has_name: nameField ? nameField.value.length > 0 : false,
        has_email: emailField ? emailField.value.length > 0 : false,
      });
    });
  }
});

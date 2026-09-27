import { useEffect, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { scrollToId } from './scroll/useSmoothScroll';
import './landing.css';

interface Industry {
  id: string;
  name: string;
  badge: string;
  image: string;
  imageAlt: string;
  headline: string;
  description: string;
  stats: { label: string; value: string };
  details: string[];
}

const industries: Industry[] = [
  {
    id: 'tourism',
    name: 'Tourism & Trips',
    badge: 'EXPERIENCE & TOURS',
    image: '/landing/tourism.jpg',
    imageAlt: 'A luxury travel catamaran cruise sailing on turquoise tropical ocean water with guests enjoying the tour',
    headline: 'Keep every experience and slot on schedule.',
    description: 'Coordinate excursions, vessel capacities, instructor schedules, and guest gear rentals with zero double-bookings.',
    stats: { label: 'Slot Utilization', value: '98.5%' },
    details: ['Capacity management', 'Equipment rental tracking', 'Instructor assignments', 'Automated confirmations'],
  },
  {
    id: 'hospitality',
    name: 'Hospitality & Stays',
    badge: 'HOTELS & RESORTS',
    image: '/landing/homestay.jpg',
    imageAlt: 'A tropical coastal boutique homestay framed by palm trees',
    headline: 'Make every guest check-in feel effortless.',
    description: 'Keep room turnover, housekeeping tasks, guest preferences, and multi-branch calendars perfectly in sync.',
    stats: { label: 'Turnaround Time', value: '-35 min' },
    details: ['Room & villa calendar', 'Housekeeping dispatch', 'Guest dietary & notes', 'Payment & folio tracking'],
  },
  {
    id: 'health',
    name: 'Health & Wellness',
    badge: 'CLINICS & SPAS',
    image: '/landing/health-wellness.jpg',
    imageAlt: 'A bright, welcoming wellness clinic and therapy reception studio',
    headline: 'Give every client session a calmer rhythm.',
    description: 'Bring practitioner schedules, treatment room allocation, recurring appointments, and consumable supplies together.',
    stats: { label: 'Patient Retention', value: '+42%' },
    details: ['Practitioner schedules', 'Treatment room booking', 'Automated SMS reminders', 'Consumables inventory'],
  },
  {
    id: 'retail',
    name: 'Retail & Boutiques',
    badge: 'SHOPS & COMMERCE',
    image: '/landing/retail.jpg',
    imageAlt: 'An artisanal retail boutique with curated merchandise displays and checkout desk',
    headline: 'Total clarity across shop floor and back-office.',
    description: 'Track fast-moving inventory, trigger low-stock purchase orders, manage staff shifts, and review sales trends in seconds.',
    stats: { label: 'Stock Accuracy', value: '99.9%' },
    details: ['Live barcode & SKU count', 'Low stock auto-orders', 'Staff shift schedules', 'Multi-location inventory'],
  },
  {
    id: 'education',
    name: 'Education & Studios',
    badge: 'WORKSHOPS & ACADEMIES',
    image: '/landing/education.jpg',
    imageAlt: 'An interactive creative training workshop and learning studio in an open loft',
    headline: 'Make room for deeper focus and better teaching.',
    description: 'Manage class timetables, student enrollments, room capacities, and materials without administrative clutter.',
    stats: { label: 'Admin Hours Saved', value: '18 hrs/wk' },
    details: ['Batch enrollments', 'Instructor timetables', 'Materials distribution', 'Attendance check-in'],
  },
  {
    id: 'services',
    name: 'Professional Services',
    badge: 'AGENCIES & STUDIOS',
    image: '/landing/services.jpg',
    imageAlt: 'A modern collaborative consulting and client strategy studio with glass partitions',
    headline: 'Stay aligned on every project and milestone.',
    description: 'Provide clients with frictionless booking, assign consultants by skill, track billable engagements, and automate follow-ups.',
    stats: { label: 'Client Satisfaction', value: '4.9 / 5.0' },
    details: ['Client appointment booking', 'Resource utilization', 'Deliverable milestones', 'Automated follow-ups'],
  },
];

const features = [
  {
    icon: 'calendar',
    title: 'Bookings that stay clear',
    text: 'Real-time multi-branch availability, conflict-free scheduling, and automated guest confirmations in one unified view.',
    tone: 'mint',
    tag: 'SCHEDULING',
  },
  {
    icon: 'team',
    title: 'Your team in harmony',
    text: 'Smart roster management, clear shift assignments, instant role handovers, and check-in tracking with zero ambiguity.',
    tone: 'blue',
    tag: 'PEOPLE',
  },
  {
    icon: 'inventory',
    title: 'Stock without surprises',
    text: 'Live inventory telemetry, automated low-stock reorder triggers, purchase order workflows, and supplier audit trails.',
    tone: 'coral',
    tag: 'INVENTORY',
  },
  {
    icon: 'insights',
    title: 'Intelligence that clicks',
    text: 'Real-time executive metrics, revenue forecasting, capacity analytics, and actionable alerts without messy spreadsheets.',
    tone: 'violet',
    tag: 'ANALYTICS',
  },
];

function FeatureIcon({ name }: { name: string }) {
  const paths: Record<string, ReactNode> = {
    calendar: (
      <>
        <rect x="3" y="4" width="18" height="18" rx="4" />
        <path d="M16 2v4M8 2v4M3 10h18" />
        <path d="m9 16 2 2 4-4" />
      </>
    ),
    team: (
      <>
        <circle cx="9" cy="7" r="4" />
        <path d="M2 21v-2a6 6 0 0 1 12 0v2" />
        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
      </>
    ),
    inventory: (
      <>
        <path d="m12 3 9 5-9 5-9-5 9-5Z" />
        <path d="m3 12 9 5 9-5" />
        <path d="m3 17 9 5 9-5" />
      </>
    ),
    insights: (
      <>
        <path d="M3 3v18h18" />
        <path d="m19 9-5 5-4-4-5 5" />
        <circle cx="19" cy="9" r="2" />
      </>
    ),
  };

  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}

function IndustryIcon({ id }: { id: string }) {
  const icons: Record<string, ReactNode> = {
    tourism: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="10" />
        <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20" />
        <path d="M2 12h20" />
      </svg>
    ),
    hospitality: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 21h18M5 21V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16" />
        <path d="M9 9h1M9 13h1M9 17h1M14 9h1M14 13h1M14 17h1" />
      </svg>
    ),
    health: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
        <path d="M12 9v6M9 12h6" />
      </svg>
    ),
    retail: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
        <path d="M3 6h18M16 10a4 4 0 0 1-8 0" />
      </svg>
    ),
    education: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M22 10v6M2 10l10-5 10 5-10 5z" />
        <path d="M6 12v5c3 3 9 3 12 0v-5" />
      </svg>
    ),
    services: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="7" width="20" height="14" rx="2" ry="2" />
        <path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16" />
      </svg>
    ),
  };

  return icons[id] || null;
}

function InteractiveDashboardPreview() {
  const [activeTab, setActiveTab] = useState<'schedule' | 'inventory' | 'team'>('schedule');

  return (
    <div className="lp-home-dash" aria-label="Interactive Unify Workspace Preview">
      <div className="lp-home-dash-top">
        <div className="lp-home-dash-title">
          <span className="lp-home-dash-logo">U</span>
          <strong>Unify Workspace</strong>
          <span className="lp-home-dash-env">MAIN BRANCH · LIVE</span>
        </div>
        <div className="lp-home-dash-live-badge">
          <span className="lp-pulse-dot" />
          <span>CONNECTED</span>
        </div>
      </div>

      <div className="lp-home-dash-content">
        <aside className="lp-home-dash-nav">
          <button
            type="button"
            className={activeTab === 'schedule' ? 'is-active' : ''}
            onClick={() => setActiveTab('schedule')}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="3" y="4" width="18" height="18" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /></svg>
            <span>Overview</span>
          </button>
          <button
            type="button"
            className={activeTab === 'inventory' ? 'is-active' : ''}
            onClick={() => setActiveTab('inventory')}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m12 3 9 5-9 5-9-5 9-5Z" /><path d="m3 12 9 5 9-5M3 17l9 5 9-5" /></svg>
            <span>Inventory</span>
          </button>
          <button
            type="button"
            className={activeTab === 'team' ? 'is-active' : ''}
            onClick={() => setActiveTab('team')}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="9" cy="7" r="4" /><path d="M2 21v-2a6 6 0 0 1 12 0v2M16 3.13a4 4 0 0 1 0 7.75M22 21v-2a4 4 0 0 0-3-3.87" /></svg>
            <span>Roster</span>
          </button>
        </aside>

        <section className="lp-home-dash-view">
          <div className="lp-home-dash-header-bar">
            <div>
              <small>ACTIVE WORKSPACE</small>
              <h4>Operational Rhythm</h4>
            </div>
            <span className="lp-badge-sync">All systems synced</span>
          </div>

          <div className="lp-home-metrics">
            <div className="lp-metric-card">
              <small>TODAY'S BOOKINGS</small>
              <div className="lp-metric-val">
                <b>28</b>
                <span className="lp-trend-up">+14% vs avg</span>
              </div>
            </div>
            <div className="lp-metric-card">
              <small>AVAILABLE SLOTS</small>
              <div className="lp-metric-val">
                <b>06</b>
                <span className="lp-trend-neutral">Optimized</span>
              </div>
            </div>
            <div className="lp-metric-card">
              <small>TEAM ON DUTY</small>
              <div className="lp-metric-val">
                <b>14</b>
                <span className="lp-trend-good">100% In Sync</span>
              </div>
            </div>
          </div>

          {activeTab === 'schedule' && (
            <div className="lp-home-agenda">
              <div className="lp-home-agenda-title">
                <b>Upcoming Schedule</b>
                <span className="lp-view-link">Real-time view</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">09:30</span>
                <span className="lp-agenda-dot is-cyan" />
                <div className="lp-agenda-info">
                  <b>VIP Client Session — 8 attendees</b>
                  <small>Main Floor · Assigned: Sarah W.</small>
                </div>
                <span className="lp-status-tag">Confirmed</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">11:15</span>
                <span className="lp-agenda-dot is-amber" />
                <div className="lp-agenda-info">
                  <b>Shift Roster Handover & Briefing</b>
                  <small>Operations Studio · Full Team</small>
                </div>
                <span className="lp-status-tag is-pending">Next Up</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">14:00</span>
                <span className="lp-agenda-dot is-violet" />
                <div className="lp-agenda-info">
                  <b>Group Experience Booking — 16 Guests</b>
                  <small>South Wing · Assigned: Marcus K.</small>
                </div>
                <span className="lp-status-tag">Prepared</span>
              </div>
            </div>
          )}

          {activeTab === 'inventory' && (
            <div className="lp-home-agenda">
              <div className="lp-home-agenda-title">
                <b>Stock Status & Reorders</b>
                <span className="lp-view-link">Automated POs</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">SKU-402</span>
                <span className="lp-agenda-dot is-cyan" />
                <div className="lp-agenda-info">
                  <b>Premium Equipment Kit (Batch A)</b>
                  <small>In Stock: 142 units · Reorder threshold: 30</small>
                </div>
                <span className="lp-status-tag">Healthy</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">SKU-891</span>
                <span className="lp-agenda-dot is-amber" />
                <div className="lp-agenda-info">
                  <b>Essential Consumables Pack</b>
                  <small>In Stock: 8 units · Auto-PO #6719 Sent</small>
                </div>
                <span className="lp-status-tag is-pending">In Transit</span>
              </div>
            </div>
          )}

          {activeTab === 'team' && (
            <div className="lp-home-agenda">
              <div className="lp-home-agenda-title">
                <b>Staff Roster & Roles</b>
                <span className="lp-view-link">14 On Duty</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">Lead</span>
                <span className="lp-agenda-dot is-cyan" />
                <div className="lp-agenda-info">
                  <b>Sarah Wickramasinghe</b>
                  <small>Manager Role · Checked in at 08:15 AM</small>
                </div>
                <span className="lp-status-tag">Active</span>
              </div>
              <div className="lp-agenda-item">
                <span className="lp-time">Staff</span>
                <span className="lp-agenda-dot is-cyan" />
                <div className="lp-agenda-info">
                  <b>David Perera & 12 others</b>
                  <small>Client Specialists · 0 handover delays</small>
                </div>
                <span className="lp-status-tag">On Track</span>
              </div>
            </div>
          )}
        </section>
      </div>
    </div>
  );
}

export default function LandingPage() {
  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const saved = localStorage.getItem('unify-home-theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

  const [selectedIndustry, setSelectedIndustry] = useState(0);

  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => {
      delete document.documentElement.dataset.unifyTheme;
    };
  }, [theme]);

  const toggleTheme = (newTheme: 'light' | 'dark') => {
    setTheme(newTheme);
  };

  return (
    <div className="lp lp-home">
      {/* Dynamic Background Glow Orbs */}
      <div className="lp-bg-mesh" aria-hidden="true">
        <div className="lp-mesh-orb lp-mesh-orb-1" />
        <div className="lp-mesh-orb lp-mesh-orb-2" />
        <div className="lp-mesh-orb lp-mesh-orb-3" />
      </div>

      {/* Floating Glass Navigation */}
      <header className="lp-home-nav">
        <nav className="lp-home-shell lp-nav-inner" aria-label="Primary Navigation">
          <Link className="lp-home-brand" to="/">
            <img src="/unify-logo.svg" alt="Unify Logo" />
            <div className="lp-brand-text">
              <span className="lp-brand-name">unify</span>
              <small className="lp-brand-tagline">OPERATIONS · SIMPLIFIED</small>
            </div>
          </Link>

          <div className="lp-home-nav-links">
            <button type="button" onClick={() => scrollToId('solutions')}>
              Solutions
            </button>
            <button type="button" onClick={() => scrollToId('how-it-works')}>
              How it works
            </button>
            <button type="button" onClick={() => scrollToId('built-for-you')}>
              Industries
            </button>
            <button type="button" onClick={() => scrollToId('faq')}>
              FAQ
            </button>
          </div>

          <div className="lp-nav-right">
            {/* Interactive Animated Theme Switcher */}
            <div className="lp-home-theme-toggle" role="radiogroup" aria-label="Theme mode selector">
              <button
                type="button"
                className={`lp-theme-btn ${theme === 'light' ? 'is-active' : ''}`}
                onClick={() => toggleTheme('light')}
                aria-checked={theme === 'light'}
                role="radio"
                title="Switch to Light Theme"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="12" cy="12" r="5" />
                  <line x1="12" y1="1" x2="12" y2="3" />
                  <line x1="12" y1="21" x2="12" y2="23" />
                  <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
                  <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
                  <line x1="1" y1="12" x2="3" y2="12" />
                  <line x1="21" y1="12" x2="23" y2="12" />
                  <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
                  <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
                </svg>
                <span>Light</span>
              </button>
              <button
                type="button"
                className={`lp-theme-btn ${theme === 'dark' ? 'is-active' : ''}`}
                onClick={() => toggleTheme('dark')}
                aria-checked={theme === 'dark'}
                role="radio"
                title="Switch to Dark Theme"
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
                </svg>
                <span>Dark</span>
              </button>
            </div>

            <div className="lp-home-nav-actions">
              <Link to="/login" className="lp-nav-signin">
                Sign in
              </Link>
              <Link className="lp-home-nav-cta" to="/register">
                <span>Start free</span>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
              </Link>
            </div>
          </div>
        </nav>
      </header>

      <main>
        {/* HERO SECTION */}
        <section className="lp-home-hero">
          <div className="lp-home-shell lp-home-hero-grid">
            <div className="lp-home-hero-copy">
              <div className="lp-hero-pill-badge">
                <span className="lp-pill-indicator" />
                <span>UNIFIED BUSINESS OS</span>
                <span className="lp-pill-divider">·</span>
                <span className="lp-pill-highlight">Multi-Branch Ready</span>
              </div>

              <h1>
                Make the busy<br />
                feel <em>beautiful.</em>
              </h1>

              <p className="lp-home-lede">
                Unify turns reservations, team shifts, inventory tracking, and client handovers into one calm, delightful operating system your entire business will love.
              </p>

              <div className="lp-home-hero-actions">
                <Link className="lp-home-primary" to="/register">
                  <span>Create your workspace</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
                </Link>
                <button
                  type="button"
                  className="lp-hero-ghost-btn"
                  onClick={() => scrollToId('solutions')}
                >
                  <span>Explore features</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M7 13l5 5 5-5M7 6l5 5 5-5" /></svg>
                </button>
              </div>

              <div className="lp-home-trust">
                <div className="lp-home-avatars">
                  <span title="Colombo Diving Center">C</span>
                  <span title="Villa Ceylon">V</span>
                  <span title="Kandy Wellness Studio">K</span>
                  <span title="Artisan Store Colombo">A</span>
                  <span className="lp-avatar-plus">+</span>
                </div>
                <p>
                  <b>Trusted by 450+ modern businesses.</b>
                  <br />
                  <span>No credit card required · Full setup in 2 minutes</span>
                </p>
              </div>
            </div>

            <div className="lp-home-visual">
              {/* High Quality Authentic Photography Showcase */}
              <div className="lp-home-photo-card">
                <img
                  src="/landing/operations-hub.jpg"
                  alt="High energy modern operations team managing bookings and logistics seamlessly"
                  loading="eager"
                />
                <div className="lp-photo-glass-overlay">
                  <div className="lp-overlay-top">
                    <span className="lp-overlay-live-pill">
                      <i /> LIVE WORKSPACE
                    </span>
                    <span className="lp-overlay-metric">0 Scheduling Conflicts</span>
                  </div>
                  <strong className="lp-overlay-caption">
                    Clear context. Confident decisions. Every day.
                  </strong>
                </div>
              </div>

              {/* Dynamic Interactive Mini Dashboard */}
              <InteractiveDashboardPreview />
            </div>
          </div>

          {/* Continuous Capability Marquee */}
          <div className="lp-home-ticker" aria-label="Unify workspace capabilities">
            <div className="lp-ticker-track">
              <span className="lp-ticker-pill">
                <b /> REAL-TIME ENGINE
              </span>
              <span>CALENDAR & SLOTS</span>
              <i />
              <span>TEAM ROSTERS</span>
              <i />
              <span>INVENTORY TELEMETRY</span>
              <i />
              <span>PURCHASE ORDERS</span>
              <i />
              <span>CLIENT CARDS</span>
              <i />
              <span>MULTI-BRANCH DISPATCH</span>
              <i />
              <span>EXECUTIVE ANALYTICS</span>
              <i />
              <span className="lp-ticker-pill">
                <b /> REAL-TIME ENGINE
              </span>
              <span>CALENDAR & SLOTS</span>
              <i />
              <span>TEAM ROSTERS</span>
              <i />
              <span>INVENTORY TELEMETRY</span>
              <i />
              <span>PURCHASE ORDERS</span>
              <i />
              <span>CLIENT CARDS</span>
              <i />
              <span>MULTI-BRANCH DISPATCH</span>
              <i />
              <span>EXECUTIVE ANALYTICS</span>
              <i />
            </div>
          </div>
        </section>

        {/* 4 CORE VALUE PILLARS (SOLUTIONS) */}
        <section className="lp-home-intro" id="solutions">
          <div className="lp-home-shell">
            <div className="lp-home-section-head">
              <p className="lp-home-section-kicker">DESIGNED FOR SEAMLESS FLOW</p>
              <div className="lp-home-intro-row">
                <h2>
                  Everything speaks.<br />
                  <em>Nothing falls through.</em>
                </h2>
                <p>
                  When your appointment book, inventory ledger, and team shifts talk to each other in real time, everyone can stop chasing updates and focus on what customers actually remember.
                </p>
              </div>
            </div>

            <div className="lp-home-feature-grid">
              {features.map((feature, index) => (
                <article className={`lp-home-feature is-${feature.tone}`} key={feature.title}>
                  <div className="lp-feature-card-glow" />
                  <div className="lp-feature-top">
                    <span className="lp-feature-tag">{feature.tag}</span>
                    <span className="lp-home-feature-num">0{index + 1}</span>
                  </div>
                  <div className="lp-home-feature-icon">
                    <FeatureIcon name={feature.icon} />
                  </div>
                  <h3>{feature.title}</h3>
                  <p>{feature.text}</p>
                  <button
                    type="button"
                    className="lp-feature-explore-btn"
                    onClick={() => scrollToId('built-for-you')}
                  >
                    <span>See workflow</span>
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
                  </button>
                </article>
              ))}
            </div>
          </div>
        </section>

        {/* STORY / OPERATIONS ARCHITECTURE */}
        <section className="lp-home-story" id="how-it-works">
          <div className="lp-home-shell lp-home-story-grid">
            <div className="lp-home-story-image-wrap">
              <div className="lp-story-photo-frame">
                <img
                  src="/landing/homestay.jpg"
                  alt="A welcoming coastal boutique homestay surrounded by lush palms"
                  loading="lazy"
                />
                <div className="lp-story-floating-stat lp-stat-top">
                  <div className="lp-stat-icon">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M20 6 9 17l-5-5" /></svg>
                  </div>
                  <div>
                    <strong>99.4% Fulfillment</strong>
                    <small>Zero missed guest requests</small>
                  </div>
                </div>

                <div className="lp-story-floating-stat lp-stat-bottom">
                  <div className="lp-stat-dot-pulse" />
                  <div>
                    <strong>Live Inventory Linked</strong>
                    <small>Auto-PO triggered when stock &lt; 20%</small>
                  </div>
                </div>
              </div>
            </div>

            <div className="lp-home-story-copy">
              <p className="lp-home-section-kicker">BUILT AROUND NATURAL HABITS</p>
              <h2>
                Start simple.<br />
                <em>Scale effortlessly.</em>
              </h2>
              <p className="lp-story-lede">
                Tell Unify what kind of business you operate. We tailor the terminology, booking rules, inventory units, and staff permissions to how your days already flow.
              </p>

              <ol className="lp-story-steps">
                <li>
                  <span className="lp-step-num">01</span>
                  <div className="lp-step-body">
                    <strong>Pick your industry blueprint</strong>
                    <small>Pre-configured workflows tailored for clinics, dive hubs, boutique stays, retail, and academies.</small>
                  </div>
                </li>
                <li>
                  <span className="lp-step-num">02</span>
                  <div className="lp-step-body">
                    <strong>Invite your staff with clean roles</strong>
                    <small>Staff only see the shifts and tasks they own; managers see real-time branch oversight.</small>
                  </div>
                </li>
                <li>
                  <span className="lp-step-num">03</span>
                  <div className="lp-step-body">
                    <strong>Run every day with complete calm</strong>
                    <small>Take online reservations, automate stock replenishment, and track revenue without chaos.</small>
                  </div>
                </li>
              </ol>

              <div className="lp-story-cta-row">
                <Link to="/register" className="lp-home-primary">
                  <span>Start your workspace</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
                </Link>
                <Link to="/login" className="lp-story-secondary-link">
                  Already have an account? Sign in
                </Link>
              </div>
            </div>
          </div>
        </section>

        {/* INDUSTRY SPECIFIC SHOWCASE WITH DEDICATED PHOTOGRAPHY */}
        <section className="lp-home-industries" id="built-for-you">
          <div className="lp-home-shell">
            <div className="lp-home-industries-head">
              <div>
                <p className="lp-home-section-kicker">FITS EXACTLY HOW YOU WORK</p>
                <h2>
                  One powerful engine.<br />
                  <em>Your exact business.</em>
                </h2>
              </div>
              <p>
                Select your industry below to see how Unify configures terminology, reservation constraints, inventory telemetry, and shift handovers specifically for your team.
              </p>
            </div>

            <div className="lp-home-industry-showcase">
              {/* Tab Selector */}
              <div className="lp-home-industry-list" role="tablist" aria-label="Select industry workspace">
                {industries.map((industry, index) => {
                  const isActive = index === selectedIndustry;
                  return (
                    <button
                      type="button"
                      key={industry.id}
                      role="tab"
                      aria-selected={isActive}
                      className={`lp-industry-tab ${isActive ? 'is-active' : ''}`}
                      onClick={() => setSelectedIndustry(index)}
                    >
                      <span className="lp-tab-idx">0{index + 1}</span>
                      <span className="lp-tab-icon">
                        <IndustryIcon id={industry.id} />
                      </span>
                      <span className="lp-tab-name">{industry.name}</span>
                      <svg className="lp-tab-arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                        <path d="M7 17L17 7M17 7H7M17 7V17" />
                      </svg>
                    </button>
                  );
                })}
              </div>

              {/* Active Industry Showcase Preview Card */}
              <article
                key={industries[selectedIndustry].id}
                className="lp-home-industry-preview"
                aria-live="polite"
              >
                <div className="lp-home-industry-photo">
                  <img
                    src={industries[selectedIndustry].image}
                    alt={industries[selectedIndustry].imageAlt}
                    loading="lazy"
                  />
                  <div className="lp-industry-photo-top-badge">
                    <span className="lp-industry-tag-pill">
                      <span className="lp-dot-pill" />
                      {industries[selectedIndustry].badge}
                    </span>
                  </div>
                  <div className="lp-industry-photo-stat-card">
                    <div className="lp-stat-card-dot" />
                    <div>
                      <strong>{industries[selectedIndustry].stats.value}</strong>
                      <small>{industries[selectedIndustry].stats.label}</small>
                    </div>
                  </div>
                </div>

                <div className="lp-home-industry-copy">
                  <div className="lp-industry-header-row">
                    <span className="lp-industry-section-tag">
                      {industries[selectedIndustry].name}
                    </span>
                    <span className="lp-industry-blueprint-pill">Standard Blueprint</span>
                  </div>
                  <h3>{industries[selectedIndustry].headline}</h3>
                  <p>{industries[selectedIndustry].description}</p>

                  <div className="lp-industry-features-label">
                    <span>CONFIGURED CAPABILITIES</span>
                  </div>
                  <ul className="lp-industry-features-list">
                    {industries[selectedIndustry].details.map((detail) => (
                      <li key={detail}>
                        <div className="lp-check-bubble">
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                            <polyline points="20 6 9 17 4 12" />
                          </svg>
                        </div>
                        <span>{detail}</span>
                      </li>
                    ))}
                  </ul>

                  <div className="lp-industry-action-bar">
                    <Link to="/register" className="lp-home-primary lp-industry-cta">
                      <span>Launch {industries[selectedIndustry].name} workspace</span>
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
                    </Link>
                  </div>
                </div>
              </article>
            </div>
          </div>
        </section>

        {/* REAL-TIME OPERATIONS PULSE */}
        <section className="lp-home-pulse">
          <div className="lp-home-shell lp-home-pulse-grid">
            <div className="lp-pulse-copy-block">
              <p className="lp-home-section-kicker">SYNCHRONIZED OPERATIONS</p>
              <h2>
                Less chasing.<br />
                <em>More delivering.</em>
              </h2>
              <p className="lp-home-pulse-copy">
                Every reservation, inventory adjustment, or roster change lands instantaneously where the next team member needs it. No WhatsApp screenshots, no forgotten stickies, no crossed wires.
              </p>

              <div className="lp-home-pulse-stats">
                <div className="lp-pulse-stat-card">
                  <strong>100%</strong>
                  <span>Cloud telemetry across all branches</span>
                </div>
                <div className="lp-pulse-stat-card">
                  <strong>&lt; 2 min</strong>
                  <span>Average daily shift handover</span>
                </div>
                <div className="lp-pulse-stat-card">
                  <strong>Zero</strong>
                  <span>Double-bookings or stockouts</span>
                </div>
              </div>
            </div>

            <div className="lp-home-pulse-visual" aria-label="Illustration of a synchronized business day">
              <div className="lp-pulse-card-header">
                <div className="lp-pulse-live-indicator">
                  <span className="lp-pulse-dot" />
                  <b>STREAMING TELEMETRY</b>
                </div>
                <small>Real-time system events</small>
              </div>

              <div className="lp-pulse-stream">
                <div className="lp-stream-item">
                  <time>08:45 AM</time>
                  <div className="lp-stream-bubble is-cyan">
                    <b>Online Booking Confirmed</b>
                    <p>Party of 4 booked Sunset Lagoon Safari · Slots updated</p>
                  </div>
                  <span className="lp-stream-badge">Auto</span>
                </div>

                <div className="lp-stream-item">
                  <time>10:15 AM</time>
                  <div className="lp-stream-bubble is-green">
                    <b>Morning Shift Handover Completed</b>
                    <p>8 staff checked in on mobile · 0 maintenance blockers</p>
                  </div>
                  <span className="lp-stream-badge is-verified">Verified</span>
                </div>

                <div className="lp-stream-item">
                  <time>11:30 AM</time>
                  <div className="lp-stream-bubble is-amber">
                    <b>Automated Stock Alert Handled</b>
                    <p>Diving Oxygen regulators reached threshold · PO-6719 dispatched</p>
                  </div>
                  <span className="lp-stream-badge">Stock</span>
                </div>

                <div className="lp-stream-item">
                  <time>01:15 PM</time>
                  <div className="lp-stream-bubble is-violet">
                    <b>Daily Revenue Target Achieved</b>
                    <p>LKR 285,000 processed across cards &amp; online portal</p>
                  </div>
                  <span className="lp-stream-badge is-verified">Synced</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* FREQUENTLY ASKED QUESTIONS */}
        <section className="lp-home-faq" id="faq">
          <div className="lp-home-shell lp-home-faq-grid">
            <div>
              <p className="lp-home-section-kicker">CLEAR ANSWERS</p>
              <h2>
                Built to feel<br />
                <em>straightforward.</em>
              </h2>
              <p className="lp-faq-subcopy">
                Everything you need to know about setting up Unify for your business. We believe great software should never require a month-long training program.
              </p>
              <div className="lp-faq-help-box">
                <strong>Need a custom setup?</strong>
                <p>Our team assists with your initial catalog import and staff training.</p>
                <a href="mailto:support@unify.work" className="lp-faq-contact-btn">
                  Talk to a specialist →
                </a>
              </div>
            </div>

            <div className="lp-home-faq-list">
              <details open>
                <summary>
                  <span>Can I try Unify without entering a credit card?</span>
                  <span className="lp-faq-toggle">+</span>
                </summary>
                <p>
                  Yes, absolutely. You can create your workspace, add your team members, configure your inventory, and test online bookings completely free. You only select a plan when you are ready to process live business.
                </p>
              </details>

              <details>
                <summary>
                  <span>How does Unify handle multiple physical branches?</span>
                  <span className="lp-faq-toggle">+</span>
                </summary>
                <p>
                  Unify is natively built for multi-branch operations. You can switch between branches with one tap, view stock balances across all locations, transfer items between stores, and assign staff to specific schedules.
                </p>
              </details>

              <details>
                <summary>
                  <span>Does Unify support mobile phones for on-the-floor staff?</span>
                  <span className="lp-faq-toggle">+</span>
                </summary>
                <p>
                  Yes! We have native mobile apps for iOS and Android where team members can view their shifts, check in attendees via QR code, accept inventory shipments, and submit purchase orders right from the floor.
                </p>
              </details>

              <details>
                <summary>
                  <span>Can my customers book appointments directly online?</span>
                  <span className="lp-faq-toggle">+</span>
                </summary>
                <p>
                  Yes. You get a dedicated public booking link, embeddable widget for your existing website, and automated email/SMS confirmations that automatically sync with your staff calendar.
                </p>
              </details>
            </div>
          </div>
        </section>

        {/* CONVERSION CLOSING BANNER */}
        <section className="lp-home-close">
          <div className="lp-home-close-glow" aria-hidden="true" />
          <div className="lp-home-shell lp-close-content">
            <span className="lp-close-kicker">YOUR NEXT CALM MONDAY STARTS TODAY</span>
            <h2>
              Do the work.<br />
              <em>Love the flow.</em>
            </h2>
            <p className="lp-close-lede">
              Join hundreds of businesses that have replaced fragmented spreadsheets and missed handovers with one unified, calm workspace.
            </p>
            <div className="lp-close-action-row">
              <Link to="/register" className="lp-home-primary lp-close-cta">
                <span>Start building your workspace for free</span>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
              </Link>
            </div>
            <div className="lp-close-perks">
              <span>✓ No credit card required</span>
              <span>✓ 2-minute instant setup</span>
              <span>✓ Dedicated onboarding support</span>
            </div>
          </div>
        </section>
      </main>

      {/* FOOTER */}
      <footer className="lp-home-footer">
        <div className="lp-home-shell">
          <div className="lp-home-footer-main">
            <Link className="lp-home-brand" to="/">
              <img src="/unify-logo.svg" alt="Unify Logo" />
              <div className="lp-brand-text">
                <span className="lp-brand-name">unify</span>
                <small className="lp-brand-tagline">OPERATIONS · SIMPLIFIED</small>
              </div>
            </Link>
            <p>
              One calm, reliable platform for appointments, people, inventory, and the operational moments that keep your business moving forward.
            </p>
            <Link className="lp-home-footer-cta" to="/register">
              <span>Get started for free</span>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
            </Link>
          </div>

          <div className="lp-home-footer-links">
            <div>
              <b>Platform</b>
              <button type="button" onClick={() => scrollToId('solutions')}>Solutions</button>
              <button type="button" onClick={() => scrollToId('how-it-works')}>How it works</button>
              <button type="button" onClick={() => scrollToId('built-for-you')}>Industries</button>
              <button type="button" onClick={() => scrollToId('faq')}>FAQ</button>
            </div>

            <div>
              <b>Get Started</b>
              <Link to="/register">Create an account</Link>
              <Link to="/login">Sign in</Link>
              <Link to="/embed/book/demo">Public Booking Demo</Link>
              <a href="mailto:hello@unify.work">Contact Support</a>
            </div>
          </div>

          <div className="lp-home-footer-bottom">
            <span>© {new Date().getFullYear()} Unify Systems Ltd. All rights reserved.</span>
            <span className="lp-footer-uptime">
              <i /> All cloud nodes operational
            </span>
            <div className="lp-footer-legal">
              <a href="#privacy">Privacy</a>
              <span>·</span>
              <a href="#terms">Terms</a>
              <span>·</span>
              <a href="#security">Security</a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}

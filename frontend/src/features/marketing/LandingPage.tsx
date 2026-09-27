import { useEffect, useState, useMemo, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { scrollToId } from './scroll/useSmoothScroll';
import './landing.css';
import './landing-enhanced.css';

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
    imageAlt: 'A luxury catamaran sailing on turquoise ocean water with guests enjoying the tour',
    headline: 'Keep every experience, charter, and slot on schedule.',
    description: 'Coordinate excursions, vessel capacities, instructor schedules, and guest gear rentals with zero double-bookings.',
    stats: { label: 'Slot Utilization', value: '98.5%' },
    details: ['Vessel capacity guard', 'Gear & wetsuit rental tracking', 'Instructor schedule sync', 'Instant SMS check-ins'],
  },
  {
    id: 'hospitality',
    name: 'Hospitality & Stays',
    badge: 'HOTELS & RESORTS',
    image: '/landing/hospitality.jpg',
    imageAlt: 'A boutique hotel courtyard in Mirissa with a swimming pool, tropical plants, and villa rooms',
    headline: 'Make every guest check-in feel completely effortless.',
    description: 'Keep room turnover, housekeeping tasks, guest preferences, and multi-branch calendars perfectly in sync.',
    stats: { label: 'Turnaround Time', value: '-35 min' },
    details: ['Room & villa calendar', 'Housekeeping dispatch board', 'Guest dietary & VIP notes', 'Automated folio & payments'],
  },
  {
    id: 'health',
    name: 'Health & Wellness',
    badge: 'CLINICS & SPAS',
    image: '/landing/clinic.jpg',
    imageAlt: 'A physician in a white coat and stethoscope consulting with a patient in a medical office',
    headline: 'Give every client treatment a calm, clinical rhythm.',
    description: 'Bring practitioner schedules, treatment room allocation, recurring appointments, and consumable supplies together.',
    stats: { label: 'Patient Retention', value: '+42%' },
    details: ['Practitioner roster sync', 'Treatment room reservation', 'Automated WhatsApp reminders', 'Medical consumables tracking'],
  },
  {
    id: 'retail',
    name: 'Retail & Boutiques',
    badge: 'SHOPS & COMMERCE',
    image: '/landing/retail.jpg',
    imageAlt: 'An artisanal retail boutique with curated merchandise displays and checkout desk',
    headline: 'Total clarity across shop floor and back-office stock.',
    description: 'Track fast-moving inventory, trigger low-stock purchase orders, manage staff shifts, and review sales trends in seconds.',
    stats: { label: 'Stock Accuracy', value: '99.9%' },
    details: ['Live barcode & SKU count', 'Low stock auto-orders', 'Staff shift schedules', 'Multi-location transfer logs'],
  },
  {
    id: 'education',
    name: 'Education & Studios',
    badge: 'WORKSHOPS & ACADEMIES',
    image: '/landing/education.jpg',
    imageAlt: 'An interactive creative training workshop and learning studio in an open loft',
    headline: 'Make room for deeper focus and better teaching.',
    description: 'Manage class timetables, student enrollments, room capacities, and course materials without administrative clutter.',
    stats: { label: 'Admin Hours Saved', value: '18 hrs/wk' },
    details: ['Batch student enrollments', 'Instructor timetables', 'Materials distribution', 'QR attendance check-in'],
  },
  {
    id: 'services',
    name: 'Professional Services',
    badge: 'AGENCIES & STUDIOS',
    image: '/landing/services.jpg',
    imageAlt: 'A modern collaborative consulting and client strategy studio with glass partitions',
    headline: 'Stay aligned on every project, client, and milestone.',
    description: 'Provide clients with frictionless booking, assign consultants by skill, track billable engagements, and automate follow-ups.',
    stats: { label: 'Client Satisfaction', value: '4.9 / 5.0' },
    details: ['Client appointment booking', 'Consultant utilization', 'Deliverable milestones', 'Automated follow-ups'],
  },
];

interface BranchData {
  name: string;
  location: string;
  bookingsToday: number;
  availableSlots: number;
  teamOnDuty: number;
  stockHealth: string;
  nextEvent: { time: string; title: string; assignee: string };
}

const branches: Record<string, BranchData> = {
  colombo: {
    name: 'Colombo Central HQ',
    location: 'Flagship Hub · Ward Place',
    bookingsToday: 34,
    availableSlots: 4,
    teamOnDuty: 16,
    stockHealth: '98.2% Optimal',
    nextEvent: { time: '09:30 AM', title: 'VIP Catamaran Cruise — 12 Guests', assignee: 'Sarah W. (Lead)' },
  },
  kandy: {
    name: 'Kandy Hillside Studio',
    location: 'Boutique Branch · Peradeniya',
    bookingsToday: 19,
    availableSlots: 8,
    teamOnDuty: 9,
    stockHealth: '100% Synced',
    nextEvent: { time: '10:15 AM', title: 'Ayurveda Wellness Session', assignee: 'Dr. David K.' },
  },
  galle: {
    name: 'Galle Coastal Villa',
    location: 'Resort Station · Fort Ramparts',
    bookingsToday: 26,
    availableSlots: 2,
    teamOnDuty: 12,
    stockHealth: '94.6% Auto-Restocking',
    nextEvent: { time: '11:00 AM', title: 'Sunset Surf & Reef Expedition', assignee: 'Marcus P.' },
  },
};

const testimonials = [
  {
    quote: 'Unify completely replaced 4 fragmented tools: WhatsApp booking groups, paper shift charts, and two messy spreadsheets. Our villa turnaround dropped by 35 minutes.',
    author: 'Sunil Weerakkody',
    role: 'Managing Director',
    company: 'Ceylon Coastal Stays (3 Branches)',
    metric: '-35 min turnaround',
    rating: 5,
  },
  {
    quote: 'Our dive center runs 6 daily catamaran excursions. In 8 months of using Unify, we have had exactly zero double-bookings and never run out of oxygen regulators.',
    author: 'Dilshan Silva',
    role: 'Operations & Safety Lead',
    company: 'Mirissa Blue Water Expeditions',
    metric: '100% conflict-free',
    rating: 5,
  },
  {
    quote: 'The automated stock re-order feature is magic. As soon as clinical serums or consumable kits drop below 20 units, the system drafts the PO before we even notice.',
    author: 'Dr. Ananya Jayawardene',
    role: 'Founder & Head Clinician',
    company: 'Aura Wellness Medical Spa',
    metric: '18 hrs saved/wk',
    rating: 5,
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
    shield: (
      <>
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
        <path d="m9 12 2 2 4-4" />
      </>
    ),
    bot: (
      <>
        <rect x="3" y="11" width="18" height="10" rx="2" />
        <circle cx="12" cy="5" r="2" />
        <path d="M12 7v4M8 15h.01M16 15h.01" />
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
      {paths[name] || paths.calendar}
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

export default function LandingPage() {
  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const saved = localStorage.getItem('unify-home-theme');
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

  const [selectedIndustry, setSelectedIndustry] = useState(0);
  const [activeBranch, setActiveBranch] = useState<'colombo' | 'kandy' | 'galle'>('colombo');
  const [activeDashTab, setActiveDashTab] = useState<'schedule' | 'inventory' | 'team' | 'ai'>('schedule');

  // Interactive Live Sandbox State
  const [stockLevel, setStockLevel] = useState<number>(38);
  const [simulatedBookings, setSimulatedBookings] = useState<number>(14);
  const [justBooked, setJustBooked] = useState<boolean>(false);

  // Interactive ROI Calculator State
  const [teamSize, setTeamSize] = useState<number>(8);
  const [weeklyAppointments, setWeeklyAppointments] = useState<number>(120);

  // Interactive Telemetry Filter
  const [pulseFilter, setPulseFilter] = useState<'all' | 'booking' | 'stock' | 'team' | 'finance'>('all');

  // Live ticking clock for living page feel
  const [liveTime, setLiveTime] = useState<string>(() => {
    return new Date().toLocaleTimeString('en-US', { hour12: true, hour: '2-digit', minute: '2-digit', second: '2-digit' });
  });

  // Auto-rotating live streaming operations events
  const [liveEventIndex, setLiveEventIndex] = useState<number>(0);
  const liveEvents = useMemo(() => [
    { time: 'Just now', title: 'Lagoon Safari VIP Confirmed', branch: 'Colombo HQ', amount: 'LKR 45,000' },
    { time: '4s ago', title: 'Morning Shift Handover Completed', branch: 'Kandy Studio', amount: '12 Staff Active' },
    { time: '9s ago', title: 'Auto-PO #8492 Dispatched to Supplier', branch: 'Galle Coast', amount: '50 Units Restocked' },
    { time: '15s ago', title: 'Ayurveda Spa Package Settled', branch: 'Kandy Studio', amount: 'LKR 82,500' },
    { time: '22s ago', title: 'Catamaran Sunset Cruise Booked', branch: 'Colombo HQ', amount: 'LKR 160,000' },
    { time: '30s ago', title: 'Villa 104 Express Check-in Finished', branch: 'Galle Coast', amount: 'QR Verified' },
  ], []);

  useEffect(() => {
    const clockTimer = setInterval(() => {
      setLiveTime(new Date().toLocaleTimeString('en-US', { hour12: true, hour: '2-digit', minute: '2-digit', second: '2-digit' }));
    }, 1000);
    const eventTimer = setInterval(() => {
      setLiveEventIndex((prev) => (prev + 1) % liveEvents.length);
    }, 3600);
    return () => {
      clearInterval(clockTimer);
      clearInterval(eventTimer);
    };
  }, [liveEvents.length]);

  // FAQ Accordion State
  const [openFaq, setOpenFaq] = useState<number | null>(0);

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

  const branch = branches[activeBranch];

  // Calculated ROI values in LKR
  const hoursSavedPerMonth = useMemo(() => {
    return Math.round(teamSize * 6.2 + weeklyAppointments * 0.18);
  }, [teamSize, weeklyAppointments]);

  const estimatedSavings = useMemo(() => {
    return Math.round(hoursSavedPerMonth * 3800 + weeklyAppointments * 1650);
  }, [hoursSavedPerMonth, weeklyAppointments]);

  const handleSimulateBooking = () => {
    setSimulatedBookings((prev) => prev + 1);
    setJustBooked(true);
    setTimeout(() => setJustBooked(false), 2400);
  };

  return (
    <div className="lp lp-home">
      {/* Dynamic Background Glow Orbs */}
      <div className="lp-bg-mesh" aria-hidden="true">
        <div className="lp-mesh-orb lp-mesh-orb-1" />
        <div className="lp-mesh-orb lp-mesh-orb-2" />
        <div className="lp-mesh-orb lp-mesh-orb-3" />
        <div className="lp-grid-pattern-overlay" />
      </div>

      {/* Floating Glass Navigation */}
      <header className="lp-home-nav">
        <nav className="lp-home-shell lp-nav-inner" aria-label="Primary Navigation">
          <Link className="lp-home-brand" to="/">
            <div className="lp-brand-logo-wrap">
              <img src="/unify-logo.svg" alt="Unify Logo" />
              <span className="lp-logo-glow-dot" />
            </div>
            <div className="lp-brand-text">
              <span className="lp-brand-name">unify</span>
              <small className="lp-brand-tagline">OPERATIONS · OS</small>
            </div>
          </Link>

          <div className="lp-home-nav-links">
            <button type="button" onClick={() => scrollToId('solutions')}>
              Platform
            </button>
            <button type="button" onClick={() => scrollToId('bento-grid')}>
              Capabilities
            </button>
            <button type="button" onClick={() => scrollToId('interactive-lab')}>
              Live Sandbox
            </button>
            <button type="button" onClick={() => scrollToId('built-for-you')}>
              Industries
            </button>
            <button type="button" onClick={() => scrollToId('roi-calculator')}>
              ROI Tool
            </button>
            <button type="button" onClick={() => scrollToId('faq')}>
              FAQ
            </button>
          </div>

          <div className="lp-nav-right">
            {/* Interactive Theme Switcher */}
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
        {/* ==================================================              </p>

              <div className="lp-home-hero-actions">
                <Link className="lp-home-primary" to="/register">
                  <span>Create your workspace free</span>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14M12 5l7 7-7 7" /></svg>
                </Link>
                <button
                  type="button"
                  className="lp-hero-ghost-btn"
                  onClick={() => scrollToId('interactive-lab')}
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" /><polygon points="10 8 16 12 10 16 10 8" /></svg>
                  <span>Explore Live Sandbox</span>
                </button>
              </div>

              <div className="lp-home-trust">
                <div className="lp-home-avatars">
                  <span title="Colombo Marine Hub">C</span>
                  <span title="Villa Ceylon Boutique">V</span>
                  <span title="Kandy Wellness Clinic">K</span>
                  <span title="Artisan Loft Studio">A</span>
                  <span className="lp-avatar-plus">+500</span>
                </div>
                <div>
                  <div className="lp-trust-stars">
                    ★★★★★ <span>4.9 / 5.0 Rating</span>
                  </div>
                  <p>
                    <b>Trusted by 500+ modern multi-branch teams.</b><br />
                    <span>Instant setup in 2 minutes · No credit card required</span>
                  </p>
                </div>
              </div>
            </div>

            {/* HERO VISUAL: MULTI-BRANCH SIMULATOR DECK */}
            <div className="lp-home-visual">
              {/* Photo Showcase in Background */}
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

              {/* Floating Live Badges */}
              <div className="lp-floating-metric-chip lp-chip-left">
                <div className="lp-chip-dot is-cyan" />
                <div>
                  <strong>0 Overlaps Guard</strong>
                  <small>Automated conflict detection</small>
                </div>
              </div>

              <div className="lp-floating-metric-chip lp-chip-right">
                <div className="lp-chip-dot is-emerald" />
                <div>
                  <strong>99.98% Telemetry</strong>
                  <small>Live sync across 3 branches</small>
                </div>
              </div>

              {/* Main Interactive Command Center */}
              <div className="lp-home-dash" aria-label="Interactive Operations Simulator">
                {/* Simulator Header & Branch Selector */}
                <div className="lp-home-dash-top">
                  <div className="lp-home-dash-title">
                    <span className="lp-home-dash-logo">U</span>
                    <strong>Command Deck</strong>
                    <div className="lp-branch-selector-pill">
                      {(['colombo', 'kandy', 'galle'] as const).map((b) => (
                        <button
                          key={b}
                          type="button"
                          className={`lp-branch-chip ${activeBranch === b ? 'is-selected' : ''}`}
                          onClick={() => setActiveBranch(b)}
                        >
                          {b === 'colombo' ? 'Colombo HQ' : b === 'kandy' ? 'Kandy Studio' : 'Galle Coast'}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div className="lp-home-dash-live-badge">
                    <span className="lp-pulse-dot" />
                    <span>{branch.stockHealth}</span>
                  </div>
                </div>

                <div className="lp-home-dash-content">
                  {/* Left Tab Switcher */}
                  <aside className="lp-home-dash-nav">
                    <button
                      type="button"
                      className={activeDashTab === 'schedule' ? 'is-active' : ''}
                      onClick={() => setActiveDashTab('schedule')}
                    >
                      <FeatureIcon name="calendar" />
                      <span>Schedule</span>
                    </button>
                    <button
                      type="button"
                      className={activeDashTab === 'inventory' ? 'is-active' : ''}
                      onClick={() => setActiveDashTab('inventory')}
                    >
                      <FeatureIcon name="inventory" />
                      <span>Inventory</span>
                    </button>
                    <button
                      type="button"
                      className={activeDashTab === 'team' ? 'is-active' : ''}
                      onClick={() => setActiveDashTab('team')}
                    >
                      <FeatureIcon name="team" />
                      <span>Staff Roster</span>
                    </button>
                    <button
                      type="button"
                      className={activeDashTab === 'ai' ? 'is-active' : ''}
                      onClick={() => setActiveDashTab('ai')}
                    >
                      <FeatureIcon name="bot" />
                      <span>AI Copilot</span>
                    </button>
                  </aside>

                  {/* Right View Panel */}
                  <section className="lp-home-dash-view">
                    <div className="lp-home-dash-header-bar">
                      <div>
                        <small>{branch.location}</small>
                        <h4>{branch.name}</h4>
                      </div>
                      <span className="lp-badge-sync">All Nodes Connected</span>
                    </div>

                    {/* Metric Cards */}
                    <div className="lp-home-metrics">
                      <div className="lp-metric-card">
                        <small>TODAY'S BOOKINGS</small>
                        <div className="lp-metric-val">
                          <b>{branch.bookingsToday + simulatedBookings - 14}</b>
                          <span className="lp-trend-up">+18% pace</span>
                        </div>
                      </div>
                      <div className="lp-metric-card">
                        <small>OPEN CAPACITY</small>
                        <div className="lp-metric-val">
                          <b>0{branch.availableSlots}</b>
                          <span className="lp-trend-neutral">Optimized</span>
                        </div>
                      </div>
                      <div className="lp-metric-card">
                        <small>ON DUTY</small>
                        <div className="lp-metric-val">
                          <b>{branch.teamOnDuty}</b>
                          <span className="lp-trend-good">Active Sync</span>
                        </div>
                      </div>
                    </div>

                    {/* Dynamic Tab Body */}
                    {activeDashTab === 'schedule' && (
                      <div className="lp-home-agenda">
                        <div className="lp-home-agenda-title">
                          <b>Today's Operational Flow</b>
                          <button
                            type="button"
                            className="lp-sim-btn"
                            onClick={handleSimulateBooking}
                          >
                            {justBooked ? '✓ Slot Reserved!' : '+ Simulate Booking'}
                          </button>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">{branch.nextEvent.time}</span>
                          <span className="lp-agenda-dot is-cyan" />
                          <div className="lp-agenda-info">
                            <b>{branch.nextEvent.title}</b>
                            <small>{branch.nextEvent.assignee}</small>
                          </div>
                          <span className="lp-status-tag">Confirmed</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">12:30 PM</span>
                          <span className="lp-agenda-dot is-amber" />
                          <div className="lp-agenda-info">
                            <b>Midday Shift Handover & Room Prep</b>
                            <small>All team stations · Checklist auto-verified</small>
                          </div>
                          <span className="lp-status-tag is-pending">Next Up</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">03:45 PM</span>
                          <span className="lp-agenda-dot is-violet" />
                          <div className="lp-agenda-info">
                            <b>Premium Group Booking — 14 Attendees</b>
                            <small>Main Facility · Automated invoice settled</small>
                          </div>
                          <span className="lp-status-tag">Prepared</span>
                        </div>
                      </div>
                    )}

                    {activeDashTab === 'inventory' && (
                      <div className="lp-home-agenda">
                        <div className="lp-home-agenda-title">
                          <b>Stock Telemetry & Auto-Purchase Orders</b>
                          <span className="lp-view-link">Zero Stockouts</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">SKU-402</span>
                          <span className="lp-agenda-dot is-cyan" />
                          <div className="lp-agenda-info">
                            <b>Specialist Equipment & Rental Units</b>
                            <small>148 Units in stock · Threshold: 30 · Healthy</small>
                          </div>
                          <span className="lp-status-tag">Optimal</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">SKU-891</span>
                          <span className="lp-agenda-dot is-amber" />
                          <div className="lp-agenda-info">
                            <b>Essential Consumable Packs (Batch B)</b>
                            <small>12 Units left · Auto-PO #8492 triggered to supplier</small>
                          </div>
                          <span className="lp-status-tag is-pending">Auto-Restock</span>
                        </div>
                      </div>
                    )}

                    {activeDashTab === 'team' && (
                      <div className="lp-home-agenda">
                        <div className="lp-home-agenda-title">
                          <b>Live Shift Roster & Handovers</b>
                          <span className="lp-view-link">{branch.teamOnDuty} Members Active</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">Shift Lead</span>
                          <span className="lp-agenda-dot is-cyan" />
                          <div className="lp-agenda-info">
                            <b>Sarah Wickramasinghe</b>
                            <small>Manager Role · Mobile check-in 08:12 AM</small>
                          </div>
                          <span className="lp-status-tag">On Floor</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">Specialists</span>
                          <span className="lp-agenda-dot is-cyan" />
                          <div className="lp-agenda-info">
                            <b>David Perera, Marcus K. & 7 others</b>
                            <small>Clean handover completed · 0 communication lag</small>
                          </div>
                          <span className="lp-status-tag">In Sync</span>
                        </div>
                      </div>
                    )}

                    {activeDashTab === 'ai' && (
                      <div className="lp-home-agenda">
                        <div className="lp-home-agenda-title">
                          <b>Unify AI Copilot Suggestions</b>
                          <span className="lp-view-link">Real-time Insights</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">AI Plan</span>
                          <span className="lp-agenda-dot is-violet" />
                          <div className="lp-agenda-info">
                            <b>Saturday Afternoon Demand Surge</b>
                            <small>Predicts +35% booking request. Suggests opening 3 additional slots.</small>
                          </div>
                          <span className="lp-status-tag is-ai">Approved</span>
                        </div>
                        <div className="lp-agenda-item">
                          <span className="lp-time">Auto-PO</span>
                          <span className="lp-agenda-dot is-cyan" />
                          <div className="lp-agenda-info">
                            <b>Supplies Reorder Cost Optimization</b>
                            <small>Consolidated 2 supplier shipments into single invoice, saving LKR 18,500.</small>
                          </div>
                          <span className="lp-status-tag">Applied</span>
                        </div>
                      </div>
                    )}
                  </section>
                </div>
              </div>
            </div>
          </div>

          {/* Continuous Capability Marquee */}
          <div className="lp-home-ticker" aria-label="Unify workspace capabilities">
            <div className="lp-ticker-track">
              <span className="lp-ticker-pill"><b /> REAL-TIME ENGINE</span>
              <span>CALENDAR & SLOTS</span><i />
              <span>TEAM ROSTERS</span><i />
              <span>INVENTORY TELEMETRY</span><i />
              <span>AUTOMATED PURCHASE ORDERS</span><i />
              <span>QR CHECK-INS</span><i />
              <span>MULTI-BRANCH DISPATCH</span><i />
              <span>EXECUTIVE ANALYTICS</span><i />
              <span>DIGITAL INVOICING</span><i />
              <span className="lp-ticker-pill"><b /> REAL-TIME ENGINE</span>
              <span>CALENDAR & SLOTS</span><i />
              <span>TEAM ROSTERS</span><i />
              <span>INVENTORY TELEMETRY</span><i />
              <span>AUTOMATED PURCHASE ORDERS</span><i />
              <span>QR CHECK-INS</span><i />
              <span>MULTI-BRANCH DISPATCH</span><i />
              <span>EXECUTIVE ANALYTICS</span><i />
              <span>DIGITAL INVOICING</span>
            </div>
          </div>
        </section>

        {/* ==================================================                </p>
              </div>
            </div>

            <div className="lp-bento-grid">
              {/* Bento Card 1 (Wide): Calendar Engine */}
              <div className="lp-bento-card lp-bento-wide">
                <div className="lp-bento-card-bg-glow is-blue" />
                <div className="lp-bento-card-content">
                  <div className="lp-bento-header">
                    <span className="lp-bento-tag">CORE SCHEDULING</span>
                    <div className="lp-bento-icon is-blue">
                      <FeatureIcon name="calendar" />
                    </div>
                  </div>
                  <h3>Smart Multi-Branch Booking & Slot Engine</h3>
                  <p>
                    Handle walk-ins, phone reservations, and web bookings across every branch with real-time slot conflict prevention and automated customer SMS alerts.
                  </p>
                  <div className="lp-bento-calendar-preview">
                    <div className="lp-bento-timeline-bar">
                      <span className="lp-time-marker">09:00</span>
                      <span className="lp-time-marker">11:00</span>
                      <span className="lp-time-marker">01:00</span>
                      <span className="lp-time-marker">03:00</span>
                      <span className="lp-time-marker">05:00</span>
                    </div>
                    <div className="lp-bento-slot-row">
                      <div className="lp-bento-slot is-filled" style={{ width: '45%' }}>
                        <span>Catamaran Excursion (8 Pax)</span>
                      </div>
                      <div className="lp-bento-slot is-open" style={{ width: '25%' }}>
                        <span>Open Slot</span>
                      </div>
                      <div className="lp-bento-slot is-filled-purple" style={{ width: '30%' }}>
                        <span>Private Charter VIP</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Bento Card 2: Inventory Telemetry */}
              <div className="lp-bento-card">
                <div className="lp-bento-card-bg-glow is-amber" />
                <div className="lp-bento-card-content">
                  <div className="lp-bento-header">
                    <span className="lp-bento-tag">INVENTORY</span>
                    <div className="lp-bento-icon is-amber">
                      <FeatureIcon name="inventory" />
                    </div>
                  </div>
                  <h3>Predictive Stock & Auto-PO</h3>
                  <p>
                    Set min-stock thresholds. When supplies run low, Unify automatically drafts purchase orders to authorized suppliers.
                  </p>
                  <div className="lp-bento-stock-gauge">
                    <div className="lp-gauge-header">
                      <span>Diving Regulators</span>
                      <b>14 left</b>
                    </div>
                    <div className="lp-gauge-track">
                      <div className="lp-gauge-fill is-alert" style={{ width: '28%' }} />
                    </div>
                    <small className="lp-gauge-note">⚡ Auto-PO #9042 Drafted &amp; Ready</small>
                  </div>
                </div>
              </div>

              {/* Bento Card 3: Team Roster */}
              <div className="lp-bento-card">
                <div className="lp-bento-card-bg-glow is-emerald" />
                <div className="lp-bento-card-content">
                  <div className="lp-bento-header">
                    <span className="lp-bento-tag">PEOPLE & ROSTER</span>
                    <div className="lp-bento-icon is-emerald">
                      <FeatureIcon name="team" />
                    </div>
                  </div>
                  <h3>Shift Handover & Mobile Check-in</h3>
                  <p>
                    Staff view assignments on their phones, scan arrival QR codes, and log handover notes in under 60 seconds.
                  </p>
                  <div className="lp-bento-roster-pill">
                    <div className="lp-roster-avatar">S</div>
                    <div>
                      <b>Morning Lead Checked In</b>
                      <small>08:14 AM · 0 delay incidents</small>
                    </div>
                    <span className="lp-pill-ok">Synced</span>
                  </div>
                </div>
              </div>

              {/* Bento Card 4: Customer Self-Service Portal */}
              <div className="lp-bento-card">
                <div className="lp-bento-card-bg-glow is-cyan" />
                <div className="lp-bento-card-content">
                  <div className="lp-bento-header">
                    <span className="lp-bento-tag">GUEST PORTAL</span>
                    <div className="lp-bento-icon is-cyan">
                      <FeatureIcon name="calendar" />
                    </div>
                  </div>
                  <h3>Embeddable Booking & QR Pass</h3>
                  <p>
                    Drop a 2-line booking widget into your existing website. Customers get instant confirmation cards and digital QR passes.
                  </p>
                  <div className="lp-bento-qr-widget">
                    <div className="lp-qr-fake-box">
                      <div className="lp-qr-pixels" />
                      <small>Scan to Check In</small>
                    </div>
                    <div className="lp-qr-details">
                      <b>VIP Pass #8819</b>
                      <span>Confirmed for 2 Guests</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Bento Card 5: AI Planner */}
              <div className="lp-bento-card">
                <div className="lp-bento-card-bg-glow is-violet" />
                <div className="lp-bento-card-content">
                  <div className="lp-bento-header">
                    <span className="lp-bento-tag">INTELLIGENCE</span>
                    <div className="lp-bento-icon is-violet">
                      <FeatureIcon name="bot" />
                    </div>
                  </div>
                  <h3>AI Operations Copilot</h3>
                  <p>
                    Smart forecasting flags upcoming demand peaks, rebalances staff schedules, and optimizes supply purchasing schedules.
                  </p>
                  <div className="lp-bento-ai-bubble">
                    <span className="lp-ai-sparkle">✨</span>
                    <p>
                      "Predicted +25% weekend bookings for Kandy branch. Suggesting 2 extra team slots."
                    </p>
                  </div>
                </div>
              </div>

              {/* Bento Card 6 (Wide): Financial Invoicing & Payments */}
              <div className="lp-bento-card lp-bento-wide">
                <div className="lp-bento-card-bg-glow is-blue" />
                <div className="lp-bento-card-content">
                  <div className="lp-bento-header">
                    <span className="lp-bento-tag">BILLING & FINANCE</span>
                    <div className="lp-bento-icon is-blue">
                      <FeatureIcon name="insights" />
                    </div>
                  </div>
                  <h3>Automated Invoicing, Payment Gateways &amp; Insurance Claims</h3>
                  <p>
                    Generate branded PDF invoices, track card payments via Stripe &amp; local gateways, manage customer subscriptions, and trace insurance claims effortlessly.
                  </p>
                  <div className="lp-bento-finance-strip">
                    <div className="lp-finance-item">
                      <small>TOTAL PROCESSED</small>
                      <b>LKR 4,820,000</b>
                      <span className="lp-trend-up">+24% vs last month</span>
                    </div>
                    <div className="lp-finance-item">
                      <small>SETTLEMENT SPEED</small>
                      <b>Instant</b>
                      <span className="lp-trend-good">0 reconciliation errors</span>
                    </div>
                    <div className="lp-finance-item">
                      <small>INVOICE ACCURACY</small>
                      <b>100%</b>
                      <span className="lp-trend-neutral">Auto-matched to bookings</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* ==================================================              </div>
            </div>
          </div>
        </section>

        {/* ==================================================        <section className="lp-home-industries" id="built-for-you">
          <div className="lp-home-shell">
            <div className="lp-home-industries-head">
              <div>
                <p className="lp-home-section-kicker">TAILORED FOR YOUR BUSINESS</p>
                <h2>
                  One powerful engine.<br />
                  <em>Configured for your exact workflow.</em>
                </h2>
              </div>
              <p>
                Select your industry below to see how Unify adapts its terminology, booking rules, inventory units, and shift handovers to how your business already operates.
              </p>
            </div>

            <div className="lp-home-industry-showcase">
              {/* Tab Selector List */}
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

        {/* ==================================================        <section className="lp-home-pulse">
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

            <div className="lp-home-pulse-visual" aria-label="Streaming Operations Feed">
              <div className="lp-pulse-card-header">
                <div className="lp-pulse-live-indicator">
                  <span className="lp-pulse-dot" />
                  <b>STREAMING TELEMETRY FEED</b>
                </div>
                <div className="lp-pulse-filters">
                  <button
                    type="button"
                    className={`lp-pulse-filter-btn ${pulseFilter === 'all' ? 'is-active' : ''}`}
                    onClick={() => setPulseFilter('all')}
                  >
                    All
                  </button>
                  <button
                    type="button"
                    className={`lp-pulse-filter-btn ${pulseFilter === 'booking' ? 'is-active' : ''}`}
                    onClick={() => setPulseFilter('booking')}
                  >
                    Bookings
                  </button>
                  <button
                    type="button"
                    className={`lp-pulse-filter-btn ${pulseFilter === 'stock' ? 'is-active' : ''}`}
                    onClick={() => setPulseFilter('stock')}
                  >
                    Stock
                  </button>
                </div>
              </div>

              <div className="lp-pulse-stream">
                {(pulseFilter === 'all' || pulseFilter === 'booking') && (
                  <div className="lp-stream-item">
                    <time>08:45 AM</time>
                    <div className="lp-stream-bubble is-cyan">
                      <b>Online Booking Confirmed</b>
                      <p>Party of 4 booked Sunset Lagoon Safari · Slots updated in Colombo &amp; Galle</p>
                    </div>
                    <span className="lp-stream-badge">Auto</span>
                  </div>
                )}

                {(pulseFilter === 'all' || pulseFilter === 'team') && (
                  <div className="lp-stream-item">
                    <time>10:15 AM</time>
                    <div className="lp-stream-bubble is-green">
                      <b>Morning Shift Handover Completed</b>
                      <p>8 staff checked in via mobile QR · 0 maintenance blockers noted</p>
                    </div>
                    <span className="lp-stream-badge is-verified">Verified</span>
                  </div>
                )}

                {(pulseFilter === 'all' || pulseFilter === 'stock') && (
                  <div className="lp-stream-item">
                    <time>11:30 AM</time>
                    <div className="lp-stream-bubble is-amber">
                      <b>Automated Stock Alert Handled</b>
                      <p>Diving Oxygen regulators reached threshold · PO-6719 dispatched</p>
                    </div>
                    <span className="lp-stream-badge">Stock</span>
                  </div>
                )}

                {(pulseFilter === 'all' || pulseFilter === 'finance') && (
                  <div className="lp-stream-item">
                    <time>01:15 PM</time>
                    <div className="lp-stream-bubble is-violet">
                      <b>Daily Revenue Target Achieved</b>
                      <p>LKR 285,000 processed across online portal &amp; floor card terminals</p>
                    </div>
                    <span className="lp-stream-badge is-verified">Settled</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </section>

        {/* ==================================================        <section className="lp-home-faq" id="faq">
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
                <strong>Need a customized onboarding?</strong>
                <p>Our specialists assist with your historical catalog migration, staff training, and branch hardware setup.</p>
                <a href="mailto:support@unify.work" className="lp-faq-contact-btn">
                  Talk to an onboarding specialist →
                </a>
              </div>
            </div>

            <div className="lp-home-faq-list">
              {[
                {
                  q: 'Can I try Unify without entering a credit card?',
                  a: 'Yes, absolutely. You can create your workspace, invite your staff members, configure your inventory, and test online bookings completely free with no credit card required.',
                },
                {
                  q: 'How does Unify handle multiple physical branches?',
                  a: 'Unify is natively built for multi-branch operations. You can switch between branches with one tap, view stock balances across all locations, transfer items between stores, and assign staff to specific schedules.',
                },
                {
                  q: 'Does Unify support mobile phones for floor staff?',
                  a: 'Yes! We have native mobile apps for iOS and Android where team members can view their shifts, check in attendees via QR code, accept inventory shipments, and submit purchase orders right from the floor.',
                },
                {
                  q: 'Can my customers book appointments directly online?',
                  a: 'Yes. You get a dedicated public booking link, embeddable widget for your existing website, and automated email/SMS confirmations that automatically sync with your staff calendar.',
                },
                {
                  q: 'How does the automated inventory re-ordering work?',
                  a: 'You define a reorder point for any item or consumable. When stock falls below that number, Unify immediately drafts a Purchase Order for your review, or can automatically dispatch it to approved suppliers.',
                },
              ].map((item, idx) => {
                const isOpen = openFaq === idx;
                return (
                  <div
                    key={item.q}
                    className={`lp-faq-item ${isOpen ? 'is-open' : ''}`}
                    onClick={() => setOpenFaq(isOpen ? null : idx)}
                  >
                    <div className="lp-faq-q">
                      <span>{item.q}</span>
                      <span className="lp-faq-toggle">{isOpen ? '−' : '+'}</span>
                    </div>
                    {isOpen && <p className="lp-faq-a">{item.a}</p>}
                  </div>
                );
              })}
            </div>
          </div>
        </section>

        {/* ==================================================        <section className="lp-home-close">
          <div className="lp-home-close-glow" aria-hidden="true" />
          <div className="lp-home-shell lp-close-content">
            <span className="lp-close-kicker">YOUR NEXT CALM MONDAY STARTS TODAY</span>
            <h2>
              Do the work.<br />
              <em>Love the flow.</em>
            </h2>
            <p className="lp-close-lede">
              Join hundreds of modern businesses that have replaced fragmented spreadsheets and missed handovers with one unified, calm workspace.
            </p>
            <div className="lp-close-action-row">
              <Link to="/register" className="lp-home-primary lp-close-cta">
                <span>Start building your workspace free</span>
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

      {/* ==================================================      <footer className="lp-home-footer">
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
              <button type="button" onClick={() => scrollToId('solutions')}>Platform</button>
              <button type="button" onClick={() => scrollToId('bento-grid')}>Capabilities</button>
              <button type="button" onClick={() => scrollToId('interactive-lab')}>Live Sandbox</button>
              <button type="button" onClick={() => scrollToId('built-for-you')}>Industries</button>
              <button type="button" onClick={() => scrollToId('roi-calculator')}>ROI Tool</button>
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
              <i /> All cloud nodes operational · 99.98% Telemetry
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

import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { scrollToId } from './scroll/useSmoothScroll';
import './landing.css';

const features = [
  { icon: '◫', title: 'Bookings that stay clear', text: 'Availability, confirmations and customer details in one calm view.', tone: 'mint' },
  { icon: '◌', title: 'Your team in rhythm', text: 'Give every person the right schedule, role and next action.', tone: 'blue' },
  { icon: '↗', title: 'Stock without surprises', text: 'Track what moves, what is low and what needs ordering next.', tone: 'coral' },
  { icon: '✦', title: 'A business view that clicks', text: 'See the useful numbers without building another spreadsheet.', tone: 'violet' },
];

const industries = ['Tourism', 'Hospitality', 'Health & wellness', 'Retail', 'Education', 'Services'];

function MiniDashboard() {
  return <div className="lp-home-dash" aria-label="Example Unify workspace">
    <div className="lp-home-dash-top"><span className="lp-home-dash-logo">u</span><span>Monday, 12 Aug</span><i /></div>
    <div className="lp-home-dash-content">
      <aside><b>Overview</b><span>Bookings</span><span>Calendar</span><span>Inventory</span><span>Team</span></aside>
      <section>
        <div className="lp-home-dash-heading"><div><small>GOOD MORNING, MAYA</small><strong>Your day, at a glance.</strong></div><button>+ New booking</button></div>
        <div className="lp-home-metrics"><div><small>Today's bookings</small><b>24</b><em>+12%</em></div><div><small>Available slots</small><b>08</b><em className="is-neutral">On track</em></div><div><small>Team on duty</small><b>12</b><em>All checked in</em></div></div>
        <div className="lp-home-agenda"><div className="lp-home-agenda-title"><b>Today's schedule</b><span>View calendar →</span></div><p><time>09:30</time><i className="is-teal" /><b>Client appointment — 12 attendees</b><small>Main workspace</small></p><p><time>11:00</time><i className="is-orange" /><b>Team check-in</b><small>Operations task</small></p><p><time>14:15</time><i className="is-purple" /><b>Service session — 8 attendees</b><small>Customer desk</small></p></div>
      </section>
    </div>
  </div>;
}

export default function LandingPage() {
  const [theme, setTheme] = useState<'light' | 'dark'>(() =>
    localStorage.getItem('unify-home-theme') === 'dark' ? 'dark' : 'light',
  );

  useEffect(() => {
    document.documentElement.dataset.unifyTheme = theme;
    localStorage.setItem('unify-home-theme', theme);
    return () => { delete document.documentElement.dataset.unifyTheme; };
  }, [theme]);

  return <div className="lp lp-home">
    <header className="lp-home-nav"><nav className="lp-home-shell" aria-label="Primary">
      <Link className="lp-home-brand" to="/"><img src="/unify-logo.svg" alt="" /><span>unify<small>OPERATIONS, SIMPLIFIED</small></span></Link>
      <div className="lp-home-nav-links"><button type="button" onClick={() => scrollToId('solutions')}>Solutions</button><button type="button" onClick={() => scrollToId('how-it-works')}>How it works</button><button type="button" onClick={() => scrollToId('built-for-you')}>For your business</button></div>
      <div className="lp-home-theme" aria-label="Choose colour theme"><button type="button" className={theme === 'light' ? 'is-active' : ''} onClick={() => setTheme('light')} aria-pressed={theme === 'light'} title="Use light theme">Light</button><button type="button" className={theme === 'dark' ? 'is-active' : ''} onClick={() => setTheme('dark')} aria-pressed={theme === 'dark'} title="Use dark theme">Dark</button></div>
      <div className="lp-home-nav-actions"><Link to="/login">Sign in</Link><Link className="lp-home-nav-cta" to="/register">Start for free <span>→</span></Link></div>
    </nav></header>
    <main>
      <section className="lp-home-hero">
        <div className="lp-home-orb lp-home-orb-a" aria-hidden="true" /><div className="lp-home-orb lp-home-orb-b" aria-hidden="true" />
        <div className="lp-home-shell lp-home-hero-grid"><div className="lp-home-hero-copy">
          <p className="lp-home-eyebrow"><span /> ONE PLACE FOR THE WHOLE DAY</p><h1>Make the busy<br />feel <em>beautiful.</em></h1><p className="lp-home-lede">Unify brings bookings, people, stock and customer moments into one workspace your team will actually enjoy using.</p>
          <div className="lp-home-hero-actions"><Link className="lp-home-primary" to="/register">Create your workspace <span>→</span></Link><button type="button" onClick={() => scrollToId('solutions')}>See what's inside <i>↓</i></button></div>
          <div className="lp-home-trust"><div className="lp-home-avatars"><span>R</span><span>S</span><span>A</span><span>+</span></div><p><b>Made for people who run the real work.</b><br />No credit card. Ready in minutes.</p></div>
        </div><div className="lp-home-visual"><div className="lp-home-generic-photo" aria-label="Connected business workspace illustration"><span className="lp-home-generic-grid" /><div className="lp-home-generic-window"><i /><i /><i /></div><div className="lp-home-generic-person"><b /><b /></div><div className="lp-home-generic-note">TEAM<br /><strong>IN SYNC</strong></div><span>LIVE WORKSPACE <b>●</b></span></div><MiniDashboard /></div></div>
        <div className="lp-home-ticker" aria-label="Unify workspace capabilities"><div>
          <span className="lp-home-ticker-live"><b /> LIVE WORKSPACE</span><i />
          <span>BOOKINGS</span><i /> <span>PEOPLE</span><i /> <span>INVENTORY</span><i /> <span>CUSTOMERS</span><i /> <span>INSIGHTS</span><i /> <span>AUTOMATION</span><i /> <span>REPORTS</span><i />
          <span className="lp-home-ticker-live"><b /> LIVE WORKSPACE</span><i />
          <span>BOOKINGS</span><i /> <span>PEOPLE</span><i /> <span>INVENTORY</span><i /> <span>CUSTOMERS</span><i /> <span>INSIGHTS</span><i /> <span>AUTOMATION</span><i /> <span>REPORTS</span><i />
        </div></div>
      </section>
      <section className="lp-home-intro" id="solutions"><div className="lp-home-shell"><p className="lp-home-section-kicker">DESIGNED FOR THE WHOLE BUSINESS</p><div className="lp-home-intro-row"><h2>Everything talks.<br /><em>Nothing gets lost.</em></h2><p>When your tools work together, your people can spend less time chasing updates and more time making the day better for customers.</p></div><div className="lp-home-feature-grid">{features.map((feature, index) => <article className={`lp-home-feature is-${feature.tone}`} key={feature.title}><span className="lp-home-feature-num">0{index + 1}</span><div className="lp-home-feature-icon">{feature.icon}</div><h3>{feature.title}</h3><p>{feature.text}</p><button type="button" onClick={() => scrollToId('how-it-works')}>Explore <span>→</span></button></article>)}</div></div></section>
      <section className="lp-home-story" id="how-it-works"><div className="lp-home-shell lp-home-story-grid"><div className="lp-home-story-image" aria-label="Business workspace illustration"><div className="lp-home-story-board"><div className="lp-home-story-bar" /><div className="lp-home-story-row"><i /><span /><b /></div><div className="lp-home-story-row"><i /><span /><b /></div><div className="lp-home-story-row"><i /><span /><b /></div><div className="lp-home-story-chart"><i /><i /><i /><i /><i /><i /></div></div><div className="lp-home-float-card"><span>THIS WEEK</span><b>Everything is<br />under control.</b><p><i>✓</i> 86% occupancy</p><p><i>✓</i> 0 scheduling conflicts</p></div></div><div className="lp-home-story-copy"><p className="lp-home-section-kicker">BUILT AROUND YOUR FLOW</p><h2>Start simple.<br /><em>Grow naturally.</em></h2><p>Tell Unify what kind of business you run. We shape your workspace around the way your day already works — then make it easier to manage.</p><ol><li><b>01</b><span><strong>Choose your business</strong><small>A setup that speaks your language from day one.</small></span></li><li><b>02</b><span><strong>Invite your people</strong><small>Clear roles, shared context, zero confusion.</small></span></li><li><b>03</b><span><strong>Run a better day</strong><small>Make confident decisions while the work is happening.</small></span></li></ol><Link to="/register" className="lp-home-text-link">Set up your workspace <span>→</span></Link></div></div></section>
      <section className="lp-home-industries" id="built-for-you"><div className="lp-home-shell"><div className="lp-home-industries-head"><div><p className="lp-home-section-kicker">FITS THE WAY YOU WORK</p><h2>One platform.<br /><em>Your kind of business.</em></h2></div><p>From a busy dive centre to a growing clinic, Unify gives every team a more considered starting point.</p></div><div className="lp-home-industry-list">{industries.map((industry, i) => <div key={industry} className={i === 0 ? 'is-active' : ''}><span>0{i + 1}</span><b>{industry}</b><i>↗</i></div>)}</div></div></section>
      <section className="lp-home-close"><div className="lp-home-close-glow" aria-hidden="true" /><div className="lp-home-shell"><p>YOUR NEXT CALM MONDAY STARTS HERE</p><h2>Do the work.<br /><em>Love the flow.</em></h2><Link to="/register" className="lp-home-primary">Start building for free <span>→</span></Link><small>No credit card required · Set up in minutes</small></div></section>
    </main>
    <footer className="lp-home-footer"><div className="lp-home-shell">
      <div className="lp-home-footer-main"><Link className="lp-home-brand" to="/"><img src="/unify-logo.svg" alt="" /><span>unify<small>OPERATIONS, SIMPLIFIED</small></span></Link><p>One calm place for bookings, people, inventory, and the little decisions that keep a business moving.</p><Link className="lp-home-footer-cta" to="/register">Create your workspace <span>→</span></Link></div>
      <div className="lp-home-footer-links"><div><b>Product</b><button type="button" onClick={() => scrollToId('solutions')}>Workspace</button><button type="button" onClick={() => scrollToId('how-it-works')}>How it works</button><button type="button" onClick={() => scrollToId('built-for-you')}>Business types</button></div><div><b>Get started</b><Link to="/register">Create an account</Link><Link to="/login">Sign in</Link><a href="mailto:hello@unify.work">Contact us</a></div></div>
      <div className="lp-home-footer-bottom"><span>© {new Date().getFullYear()} Unify. Built for the real work.</span><span><i /> All systems operational</span><span>Privacy <b>·</b> Terms</span></div>
    </div></footer>
  </div>;
}

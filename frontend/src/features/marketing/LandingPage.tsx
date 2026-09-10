import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import BusinessTypes from './BusinessTypes';
import HeroScene from './webgl/HeroScene';
import { useSmoothScroll, scrollToId } from './scroll/useSmoothScroll';
import { usePageProgress, useCountUp } from './scroll/usePageProgress';
import { usePinnedProgress, useReveal } from './scroll/useScrollMotion';
import './landing.css';

/* Unify's public landing page.
 *
 * A narrative scroll on a dark canvas with one live object and type doing
 * most of the work. Motion is rationed to three moments - the hero scrub,
 * the pinned business-type swap, and the method's step hand-off - rather
 * than a fade-and-rise on every section.
 *
 * Every figure quoted is one this codebase can back. There are no invented
 * customer counts; the numbers section counts what actually ships.
 */

const CAPABILITY = [
  { name: 'Bookings', body: 'Slots, nights, date ranges or multi-day packages. Double-bookings are refused, gaps between jobs are kept, and repeat bookings are one entry rather than fifty.' },
  { name: 'Resources', body: 'The thing being booked, whatever it is for you: a room, a boat, a chair, a table, a tutor. Each carries its own hours, capacity and days off.' },
  { name: 'Inventory', body: 'What you hold and what it costs. Stock comes down as it is used, and you are told before you run out, not after.' },
  { name: 'Staff', body: 'Who works when, what they are qualified for, and which branch they belong to. Staff see their own day, not everyone else’s.' },
  { name: 'Payments', body: 'What a booking is worth, split by ticket type where that matters, and what is still owed. No per-module pricing on our side either.' },
  { name: 'Reporting', body: 'Takings, occupancy, no-shows and where bookings came from, per branch and per period. Numbers you can act on by Tuesday.' },
];

const METHOD = [
  { n: '01', title: 'Pick your business type', body: 'One choice at sign-up. It decides which modules you get, what the screens are called, and what the booking form asks for.' },
  { n: '02', title: 'The workspace provisions itself', body: 'Your resources, products and roles are created ready to edit. There is no blank slate to configure and no setup call to book.' },
  { n: '03', title: 'Adjust anything you don’t like', body: 'Rename it, switch modules off, add a branch. The starting point is a guess about your trade; you get the last word on all of it.' },
];

const STACK = [
  'React', 'TypeScript', 'Vite', 'WebGL',
  'ASP.NET Core', 'Entity Framework', 'PostgreSQL',
  'Flutter', 'Riverpod', 'LangGraph', 'FastAPI',
];

/** A heading line that rises from behind its own mask. */
function Mask({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([e]) => { if (e.isIntersecting) { setShown(true); io.disconnect(); } },
      { threshold: 0.4 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <span ref={ref} className={`lp-mask${shown ? ' is-revealed' : ''} ${className}`}>
      <span>{children}</span>
    </span>
  );
}

function Figure({ value, suffix, label }: { value: number; suffix?: string; label: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const n = useCountUp(ref, value);
  return (
    <div ref={ref}>
      <div className="lp-figure-value">{n}{suffix}</div>
      <div className="lp-figure-label">{label}</div>
    </div>
  );
}

/** Highlights whichever step has crossed 60% of the viewport, per the brief. */
function useCurrentStep(count: number) {
  const [current, setCurrent] = useState(0);
  const refs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const els = refs.current.filter(Boolean) as HTMLDivElement[];
    if (els.length === 0) return;

    // An observer fires on crossings only. The rAF this replaces measured
    // every step every frame for the life of the page, whether or not the
    // section was even on screen.
    const passed = new Set<number>();
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          const i = els.indexOf(e.target as HTMLDivElement);
          // Deliberately boundingClientRect.top, not isIntersecting: a step
          // that has scrolled off the top has still been passed, and reading
          // intersection alone would un-highlight it on the way out.
          if (e.boundingClientRect.top <= window.innerHeight * 0.6) passed.add(i);
          else passed.delete(i);
        }
        setCurrent(passed.size ? Math.max(...passed) : 0);
      },
      { rootMargin: '0px 0px -40% 0px' },
    );

    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, [count]);

  return { current, refs };
}

export default function LandingPage() {
  useSmoothScroll({ lerp: 0.09 });
  const pageProgress = usePageProgress();

  const heroRef = useRef<HTMLElement>(null);
  const heroProgress = usePinnedProgress(heroRef);

  const capabilityRef = useRef<HTMLElement>(null);
  const stackRef = useRef<HTMLElement>(null);
  const figuresRef = useRef<HTMLElement>(null);
  useReveal(capabilityRef);
  useReveal(stackRef);
  useReveal(figuresRef);

  const { current, refs } = useCurrentStep(METHOD.length);

  return (
    <div className="lp">
      <div className="lp-rail">
        <span className="lp-rail-tag">One platform. Every business.</span>
        <span className="lp-rail-pct">{pageProgress}%</span>
        <span className="lp-rail-track">
          <span className="lp-rail-fill" style={{ transform: `scaleX(${pageProgress / 100})` }} />
        </span>
      </div>

      <header className="lp-nav">
        <nav className="lp-nav-inner" aria-label="Primary">
          <Link className="lp-brand" to="/">
            <span className="lp-brand-mark" aria-hidden="true">U</span>
            <span className="lp-brand-name">
              Unify
              <span className="lp-brand-tag">Innovate. Adapt. Operate.</span>
            </span>
          </Link>
          <div className="lp-nav-links">
            <button type="button" onClick={() => scrollToId('capability')}>Capability</button>
            <button type="button" onClick={() => scrollToId('business-types')}>Business types</button>
            <button type="button" onClick={() => scrollToId('method')}>Method</button>
            <button type="button" onClick={() => scrollToId('stack')}>Stack</button>
          </div>
          <div className="lp-nav-cta">
            <Link className="lp-btn lp-btn-outline" to="/login">Sign in</Link>
            <Link className="lp-btn lp-btn-primary" to="/register">Start free</Link>
          </div>
        </nav>
      </header>

      <main>
        {/* ── Hero ─────────────────────────────────────────────────── */}
        <section className="lp-hero-pin" ref={heroRef} aria-label="Introduction">
          <div className="lp-hero-sticky">
            <div className="lp-shell lp-hero-inner">
              <div>
                <span className="lp-pill">
                  <span className="lp-pill-dot" aria-hidden="true" />
                  Multi-tenant SME platform
                </span>
                <h1 className="lp-display">
                  <Mask>One platform that</Mask>
                  <Mask><span className="lp-brandtext">becomes your business</span></Mask>
                </h1>
                <p className="lp-body" style={{ marginTop: 22 }}>
                  A dive centre and a homestay do not run the same day, so they should not
                  get the same dashboard.
                </p>
                <div className="lp-hero-actions">
                  <Link className="lp-btn lp-btn-primary lp-btn-lg" to="/register">Start a business</Link>
                  <button type="button" className="lp-btn lp-btn-outline lp-btn-lg" onClick={() => scrollToId('capability')}>
                    See what it does
                  </button>
                </div>
              </div>

              <div className="lp-hero-canvas">
                <HeroScene progress={heroProgress} />
              </div>
            </div>

            <div className="lp-cue" aria-hidden="true">
              <span>Scroll</span>
              <span className="lp-cue-track">
                {/* Drains as the hero is scrubbed. */}
                <span className="lp-cue-fill" style={{ transform: `scaleY(${1 - Math.min(heroProgress * 2.4, 1)})` }} />
              </span>
            </div>
          </div>
        </section>

        {/* ── Capability: one core, several surfaces ───────────────── */}
        <section className="lp-section" id="capability" ref={capabilityRef}>
          <div className="lp-shell">
            <div className="lp-section-head">
              <p className="lp-label">
                <span className="lp-label-n">02</span><span className="lp-label-rule" />Capability
              </p>
              <h2 className="lp-h2"><Mask>What it actually does</Mask></h2>
              <p className="lp-body">
                Six things, one core. They share a customer, a calendar and a set of
                permissions, which is why turning one on does not mean reconciling it
                with the others later.
              </p>
            </div>

            <div className="lp-spine">
              {CAPABILITY.map((c, i) => (
                <div className="lp-branch" key={c.name} data-reveal data-reveal-delay={`${i * 60}`}>
                  <div className="lp-branch-row">
                    <h3>{c.name}</h3>
                    <p>{c.body}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        <BusinessTypes />

        {/* ── Method ───────────────────────────────────────────────── */}
        <section className="lp-section" id="method">
          <div className="lp-shell lp-method">
            <div className="lp-method-aside">
              <p className="lp-label">
                <span className="lp-label-n">04</span><span className="lp-label-rule" />Method
              </p>
              <h2 className="lp-h2"><Mask>Set up in minutes</Mask></h2>
              <p className="lp-body">
                Not weeks, and not a call with an implementation consultant. Three steps,
                and the third one is undoing whatever we guessed wrong.
              </p>
            </div>

            <div className="lp-method-steps">
              {METHOD.map((s, i) => (
                <div
                  className={`lp-step${i === current ? ' is-current' : ''}`}
                  key={s.n}
                  ref={(el) => { refs.current[i] = el; }}
                >
                  <span className="lp-step-n">{s.n}</span>
                  <h3>{s.title}</h3>
                  <p>{s.body}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── Stack ────────────────────────────────────────────────── */}
        <section className="lp-section" id="stack" ref={stackRef}>
          <div className="lp-shell">
            <div className="lp-section-head">
              <p className="lp-label">
                <span className="lp-label-n">05</span><span className="lp-label-rule" />Stack
              </p>
              <h2 className="lp-h2"><Mask>What it runs on</Mask></h2>
              <p className="lp-body">
                Listed because people ask, not as a trust signal. Your data sits in its
                own tenant boundary and never shares a table with another business.
              </p>
            </div>
            <div className="lp-stack" data-reveal>
              {STACK.map((t) => <span className="lp-stack-item" key={t}>{t}</span>)}
            </div>
          </div>
        </section>

        {/* ── Numbers ──────────────────────────────────────────────── */}
        <section className="lp-section" ref={figuresRef}>
          <div className="lp-shell">
            <div className="lp-figures" data-reveal>
              <Figure value={12} label="Business types supported" />
              <Figure value={4} label="Booking models" />
              <Figure value={2} label="Apps, one API" />
              <Figure value={5} suffix=" min" label="To your first login" />
            </div>
          </div>
        </section>

        {/* ── Close ────────────────────────────────────────────────── */}
        <section className="lp-close">
          <div className="lp-close-canvas" aria-hidden="true">
            <HeroScene progress={0.5} />
          </div>
          <div className="lp-shell lp-close-inner">
            <h2 className="lp-display" style={{ fontSize: 'clamp(2.2rem, 5.6vw, 4.2rem)' }}>
              <Mask>Start a business</Mask>
            </h2>
            <p className="lp-body" style={{ margin: '20px auto 30px' }}>
              Pick your trade and see the workspace it gives you. Nothing to install.
            </p>
            <Link className="lp-btn lp-btn-primary lp-btn-lg" to="/register">Start a business</Link>
          </div>
        </section>
      </main>

      <footer className="lp-footer">
        <div className="lp-shell lp-footer-inner">
          <Link className="lp-brand" to="/">
            <span className="lp-brand-mark" aria-hidden="true">U</span>
            <span className="lp-brand-name">Unify</span>
          </Link>
          <div className="lp-footer-links">
            <button type="button" onClick={() => scrollToId('capability')}>Capability</button>
            <button type="button" onClick={() => scrollToId('business-types')}>Business types</button>
            <button type="button" onClick={() => scrollToId('method')}>Method</button>
            <Link to="/login">Sign in</Link>
            <Link to="/register">Start free</Link>
          </div>
          <p>Universal SME Management Platform</p>
        </div>
      </footer>
    </div>
  );
}

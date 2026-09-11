import { useRef } from 'react';
import HeroScene from './webgl/HeroScene';
import { usePinnedProgress, useReveal, range } from './scroll/useScrollMotion';

/* Act II: the core becomes a platform.
 *
 * Inside the shell, six module clusters arrive from off-camera and lock onto
 * landing sites on the lattice, one per slice of the act, each drawing a line
 * back to the core as it seats. By the end all six sit on one skeleton with
 * shared edges between them - which is the "one core, six surfaces" claim
 * made structurally instead of asserted in a sentence.
 *
 * The captions and the fallback list are the same six nodes. Rendering them
 * twice - once for the 3D path and once for everything else - is how the two
 * drift apart, and the copy is the part that has to stay true.
 */

export interface Capability {
  name: string;
  body: string;
}

export default function Assembly({ items, live }: { items: Capability[]; live: boolean }) {
  const ref = useRef<HTMLElement>(null);
  const progress = usePinnedProgress(ref);

  // Written to by the scene, every frame, with the projected position of each
  // landing site. Never read by React.
  const captionRefs = useRef<(HTMLElement | null)[]>([]);

  const flatRef = useRef<HTMLDivElement>(null);
  useReveal(flatRef);

  if (!live) {
    /* No WebGL, reduced motion, a narrow screen or a machine without the
     * headroom. The spine carries the same argument in two dimensions: one
     * rail, six things hanging off it. */
    return (
      <section className="lp-section" id="capability" ref={ref as never}>
        <div className="lp-shell" ref={flatRef}>
          <Head />
          <div className="lp-spine">
            {items.map((c, i) => (
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
    );
  }

  /* The head says what the section is, then gets out of the way entirely.
   * Held at a fraction of its opacity it was neither readable nor absent -
   * just grey type lying across the lattice. It stays in the DOM, so it is
   * still the section's heading for anything not looking at pixels. */
  const headFade = 1 - Math.min(Math.max((progress - 0.03) / 0.13, 0), 1);

  return (
    <section className="lp-assembly" id="capability" ref={ref} aria-label="Capability">
      <div className="lp-assembly-sticky">
        {/* Matched to the dissolves either side, so the object appears to
            carry across the seams rather than being handed over. */}
        <div
          className="lp-assembly-stage"
          aria-hidden="true"
          style={{ opacity: range(progress, 0, 0.05) * (1 - range(progress, 0.94, 1)) }}
        >
          <HeroScene progress={progress} act={2} captionRefs={captionRefs} />
        </div>

        <div className="lp-shell lp-assembly-head" style={{ opacity: headFade }}>
          <Head />
        </div>

        <div className="lp-captions">
          {items.map((c, i) => (
            <div
              className="lp-caption"
              key={c.name}
              ref={(el) => { captionRefs.current[i] = el; }}
            >
              <div className="lp-caption-inner">
                <span className="lp-caption-n">{String(i + 1).padStart(2, '0')}</span>
                <h3>{c.name}</h3>
                <p>{c.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Head() {
  return (
    <div className="lp-section-head">
      <p className="lp-label">
        <span className="lp-label-n">02</span><span className="lp-label-rule" />Capability
      </p>
      <h2 className="lp-h2">What it actually does</h2>
      <p className="lp-body">
        Six things, one core. They share a customer, a calendar and a set of
        permissions, which is why turning one on does not mean reconciling it
        with the others later.
      </p>
    </div>
  );
}

/* The hero's right-hand visual for visitors who do not get the WebGL scene.
 *
 * useSceneEnabled switches the scene off for reduced-motion, for viewports
 * at or under 1000px, and for machines reporting little headroom - a large
 * share of real visitors. Before this existed, all of them got the copy on
 * the left and a blank 460px square on the right, because .lp-hero-canvas
 * is only a spacer for the object to rest over.
 *
 * Two stills, staggered like prints on a desk, illustrating the sentence
 * they sit beside: "A dive centre and a homestay do not run the same day."
 * The homestay is the south coast - stilt-fishing poles in the surf - which
 * is the platform's actual market, not a generic tropical stock shot.
 *
 * Rendered only when the scene is off. When it is on, the object occupies
 * exactly this space and a photo underneath it would just be clutter.
 */
export default function HeroStills() {
  return (
    <div className="lp-hero-stills">
      <figure className="lp-still lp-still-a">
        <img
          src="/landing/homestay.jpg"
          alt="A beachfront guesthouse under coconut palms on Sri Lanka's south coast, stilt-fishing poles in the surf"
          width={1000}
          height={667}
          loading="eager"
          decoding="async"
        />
        <figcaption className="lp-still-tag">Homestay</figcaption>
      </figure>
      <figure className="lp-still lp-still-b">
        <img
          src="/landing/dive-centre.jpg"
          alt="Two scuba divers beside a school of yellow fish on a reef wall"
          width={1000}
          height={667}
          loading="eager"
          decoding="async"
        />
        <figcaption className="lp-still-tag">Dive centre</figcaption>
      </figure>
    </div>
  );
}

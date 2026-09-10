/* The web counterpart of the Flutter app's OrbitHero
 * (mobile/sme_mobile/lib/widgets/unify_auth/orbit_hero.dart): intertwined
 * rings orbiting a glowing core.
 *
 * Same four rings, same silver/cyan/magenta ordering and the same staggered
 * speeds - what sells the "intertwined" look is that no two rings share a
 * rhythm, so at any moment some are edge-on while others are face-on.
 *
 * Rings are bordered ellipses rotated in 3D rather than SVG strokes: the
 * browser composites transforms on the GPU, so four spinning at once costs
 * nothing, and the shape stays crisp at any size. */

interface Ring {
  /** Fraction of the container the ring spans. */
  scale: number;
  /** Rotation axis weights - these are what tilt each ring differently. */
  rx: number;
  ry: number;
  /** Seconds per turn. Negative reverses direction. */
  duration: number;
  /** Negative delay starts the ring mid-turn, so they never begin aligned. */
  delay: number;
  color: string;
  opacity: number;
}

const RINGS: Ring[] = [
  { scale: 1.0, rx: 1.15, ry: 0.1, duration: 28, delay: 0, color: '#E8ECF8', opacity: 0.45 },
  { scale: 0.84, rx: 0.55, ry: 0.85, duration: -17, delay: -6, color: '#00E5FF', opacity: 0.5 },
  { scale: 0.68, rx: 1.35, ry: -0.6, duration: 13, delay: -3, color: '#FF2D95', opacity: 0.4 },
  { scale: 0.52, rx: 0.25, ry: 0.35, duration: -10, delay: -8, color: '#CBD5F5', opacity: 0.28 },
];

export default function OrbitHero() {
  return (
    <div className="lp-orbit" aria-hidden="true">
      {RINGS.map((ring, i) => (
        <div
          key={i}
          className="lp-orbit-ring"
          style={{
            width: `${ring.scale * 100}%`,
            height: `${ring.scale * 100}%`,
            borderColor: ring.color,
            opacity: ring.opacity,
            boxShadow: `0 0 24px ${ring.color}40`,
            animationDuration: `${Math.abs(ring.duration)}s`,
            animationDirection: ring.duration < 0 ? 'reverse' : 'normal',
            animationDelay: `${ring.delay}s`,
            // Read by the lp-spin keyframes to give each ring its own axis.
            ['--rx' as string]: ring.rx,
            ['--ry' as string]: ring.ry,
          }}
        />
      ))}
      <div className="lp-orbit-core" />
    </div>
  );
}

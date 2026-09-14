import { Suspense, lazy, type ComponentProps } from 'react';
import type HeroSceneType from './HeroScene';

/* The WebGL scene, split out of the marketing bundle.
 *
 * Every visitor who gets the 3D path pays for the shaders, the matrix maths
 * and the geometry builders - but they are the minority: anyone on a phone,
 * anyone with reduced motion set, anyone on a machine below the headroom
 * threshold renders the flat fallback and would otherwise have downloaded a
 * renderer they will never run.
 *
 * The fallback is null rather than a placeholder. The scene is decoration
 * behind the copy; the page is already complete without it, and a loading
 * state for something with no content of its own is noise.
 */
const HeroScene = lazy(() => import('./HeroScene'));

export type { Act } from './HeroScene';

export default function LazyScene(props: ComponentProps<typeof HeroSceneType>) {
  return (
    <Suspense fallback={null}>
      <HeroScene {...props} />
    </Suspense>
  );
}

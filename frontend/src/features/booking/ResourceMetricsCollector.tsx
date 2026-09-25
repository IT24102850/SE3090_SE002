import { useEffect } from 'react';
import { useGetAvailabilityGridQuery } from '../../api/bookingApi';
import type { Resource } from './types';

export interface ResourceMetrics {
  resourceId: string;
  avgUtilizationPercent: number;
  bookedHours: number;
  estimatedRevenue: number;
}

// Fetches the availability grid for a single resource and reports the
// aggregated metrics up to the parent. Kept as its own component (rather than
// looping the hook call in the parent) to respect the rules of hooks while
// still fanning out one query per resource.
export default function ResourceMetricsCollector({
  resource,
  from,
  to,
  onData,
}: {
  resource: Resource;
  from: string;
  to: string;
  onData: (metrics: ResourceMetrics) => void;
}) {
  const { data } = useGetAvailabilityGridQuery({ id: resource.id, from, to });

  useEffect(() => {
    if (!data) return;
    const openDays = data.filter((d) => d.isOpen);
    const bookedHours = data.reduce((sum, d) => sum + d.bookedHours, 0);
    const avgUtilization = openDays.length
      ? openDays.reduce((sum, d) => sum + d.utilizationPercent, 0) / openDays.length
      : 0;
    onData({
      resourceId: resource.id,
      avgUtilizationPercent: Math.round(avgUtilization * 10) / 10,
      bookedHours,
      estimatedRevenue: bookedHours * (resource.hourlyRate ?? 0),
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]);

  return null;
}

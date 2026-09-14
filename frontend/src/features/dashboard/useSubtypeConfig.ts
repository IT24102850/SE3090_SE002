import { useMemo } from 'react';
import { useSelector } from 'react-redux';
import { useGetTenantQuery } from '../../api/bookingApi';
import type { RootState } from '../../store/store';
import type { SubtypeDashboardConfig } from './subtypes/SubtypeDashboardConfig';
import { GENERIC_CONFIG, getSubtypeConfig } from './subtypes/subtypeRegistry';
import { parseTenantSubType } from './subtypes/tourismSubTypes';

/* The current tenant's dashboard config, for anywhere outside the dashboard
 * that has to speak the operator's own language - sidebar labels, page
 * headings, the booking form's extra fields.
 *
 * Returns GENERIC_CONFIG while the tenant is still loading and for every
 * tenant whose sub-type is unset or unrecognised, so a caller never has to
 * handle an in-between state and a non-tourism business always reads exactly
 * as it did before. The tenant query is cached by RTK Query, so calling this
 * from several components costs one request. */
export function useSubtypeConfig(): SubtypeDashboardConfig {
  const { user } = useSelector((state: RootState) => state.auth);
  const tenantId = user?.tenantId ?? '';
  const { data: tenant } = useGetTenantQuery({ tenantId }, { skip: !tenantId });

  return useMemo(
    () => (tenant ? getSubtypeConfig(parseTenantSubType(tenant.subType)) : GENERIC_CONFIG),
    [tenant],
  );
}

import { useState } from 'react';
import Modal from '../../shared/components/Modal';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { useCreateResourceMutation, useGetStaffUsersQuery, useUpdateResourceMutation } from '../../api/bookingApi';
import { RESOURCE_CATEGORIES, type Resource, type ResourceCategory } from './types';

export default function ResourceFormModal({
  tenantId,
  resource,
  onClose,
}: {
  tenantId: string;
  resource?: Resource | null;
  onClose: () => void;
}) {
  const { show } = useToast();
  const [createResource, { isLoading: creating }] = useCreateResourceMutation();
  const [updateResource, { isLoading: updating }] = useUpdateResourceMutation();
  const { data: staff } = useGetStaffUsersQuery({ tenantId }, { skip: !tenantId });

  const [name, setName] = useState(resource?.name ?? '');
  const [code, setCode] = useState(resource?.code ?? '');
  const [category, setCategory] = useState<ResourceCategory>(resource?.category ?? 'Room');
  const [capacity, setCapacity] = useState(resource?.capacity?.toString() ?? '');
  const [hourlyRate, setHourlyRate] = useState(resource?.hourlyRate?.toString() ?? '');
  const [description, setDescription] = useState(resource?.description ?? '');
  const [specialty, setSpecialty] = useState(resource?.specialty ?? '');
  const [linkedUserId, setLinkedUserId] = useState(resource?.linkedUserId ?? '');
  const [error, setError] = useState<string | null>(null);

  const isLoading = creating || updating;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      if (resource) {
        await updateResource({
          id: resource.id,
          body: {
            name,
            category,
            description: description || undefined,
            capacity: capacity ? Number(capacity) : undefined,
            hourlyRate: hourlyRate ? Number(hourlyRate) : undefined,
            specialty: specialty || undefined,
            linkedUserId: linkedUserId || undefined,
          },
        }).unwrap();
        show('Resource updated.', 'success');
      } else {
        await createResource({
          tenantId,
          name,
          code: code || undefined,
          category,
          description: description || undefined,
          capacity: capacity ? Number(capacity) : undefined,
          hourlyRate: hourlyRate ? Number(hourlyRate) : undefined,
          specialty: specialty || undefined,
          linkedUserId: linkedUserId || undefined,
        }).unwrap();
        show('Resource created.', 'success');
      }
      onClose();
    } catch (err) {
      setError(apiErrorMessage(err, 'Could not save resource.'));
    }
  };

  return (
    <Modal
      title={resource ? 'Edit resource' : 'New resource'}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary" onClick={onClose} type="button">Cancel</button>
          <button className="btn btn-primary" onClick={handleSubmit} disabled={isLoading}>
            {isLoading ? <span className="spinner" /> : resource ? 'Save changes' : 'Create resource'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit}>
        {error && <div className="banner banner-critical">{error}</div>}
        <div className="form-grid">
          <div className="field field-full">
            <label>Name</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          {!resource && (
            <div className="field">
              <label>Code</label>
              <input className="input" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Optional, e.g. RM-101" />
            </div>
          )}
          <div className="field">
            <label>Category</label>
            <select className="input" value={category} onChange={(e) => setCategory(e.target.value as ResourceCategory)}>
              {RESOURCE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          <div className="field">
            <label>Capacity</label>
            <input className="input" type="number" min={0} value={capacity} onChange={(e) => setCapacity(e.target.value)} />
          </div>
          <div className="field">
            <label>Hourly rate</label>
            <input className="input" type="number" min={0} step="0.01" value={hourlyRate} onChange={(e) => setHourlyRate(e.target.value)} />
          </div>
          {category === 'Staff' && (
            <>
              <div className="field">
                <label>Specialty</label>
                <input
                  className="input"
                  value={specialty}
                  onChange={(e) => setSpecialty(e.target.value)}
                  placeholder="e.g. Cardiology"
                />
              </div>
              <div className="field">
                <label>Linked staff login</label>
                <select className="input" value={linkedUserId} onChange={(e) => setLinkedUserId(e.target.value)}>
                  <option value="">None</option>
                  {staff?.map((s) => (
                    <option key={s.id} value={s.id}>{s.fullName} ({s.role})</option>
                  ))}
                </select>
              </div>
            </>
          )}
          <div className="field field-full">
            <label>Description</label>
            <textarea className="input" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
        </div>
      </form>
    </Modal>
  );
}

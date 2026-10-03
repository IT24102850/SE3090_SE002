import Modal from '../../shared/components/Modal';
import StatusBadge from '../../shared/components/StatusBadge';
import { useCancelBookingMutation, useSendReminderMutation } from '../../api/bookingApi';
import { useToast, apiErrorMessage } from '../../shared/components/Toast';
import { formatDateTime } from '../../shared/dateUtils';
import type { Booking } from './types';

export default function BookingDetailsModal({ booking, onClose }: { booking: Booking; onClose: () => void }) {
  const { show } = useToast();
  const [cancelBooking, { isLoading: cancelling }] = useCancelBookingMutation();
  const [sendReminder, { isLoading: reminding }] = useSendReminderMutation();

  const handleCancel = async () => {
    try {
      await cancelBooking(booking.id).unwrap();
      show('Booking cancelled.', 'success');
      onClose();
    } catch (err) {
      show(apiErrorMessage(err, 'Could not cancel this booking.'), 'error');
    }
  };

  const handleRemind = async () => {
    try {
      await sendReminder({ id: booking.id, channel: 'Email' }).unwrap();
      show('Reminder sent.', 'success');
    } catch (err) {
      show(apiErrorMessage(err, 'Could not send reminder.'), 'error');
    }
  };

  return (
    <Modal
      title={booking.title || booking.bookingTypeName}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-secondary btn-sm" onClick={handleRemind} disabled={reminding}>
            {reminding ? <span className="spinner spinner-dark" /> : 'Send reminder'}
          </button>
          {booking.status !== 'Cancelled' && (
            <button className="btn btn-danger btn-sm" onClick={handleCancel} disabled={cancelling}>
              {cancelling ? <span className="spinner spinner-dark" /> : 'Cancel booking'}
            </button>
          )}
          <button className="btn btn-primary btn-sm" onClick={onClose}>Close</button>
        </>
      }
    >
      <div className="field">
        <label>Status</label>
        <div><StatusBadge status={booking.status} /></div>
      </div>
      <div className="field">
        <label>Resource</label>
        <div>{booking.resourceName}</div>
      </div>
      <div className="field">
        <label>Booking type</label>
        <div>
          <span className="badge" style={{ background: `${booking.colorHex}22`, color: booking.colorHex }}>
            {booking.bookingTypeName}
          </span>
        </div>
      </div>
      <div className="field">
        <label>When</label>
        <div>{formatDateTime(booking.startTime)} – {formatDateTime(booking.endTime)}</div>
      </div>
      {booking.notes && (
        <div className="field">
          <label>Notes</label>
          <div>{booking.notes}</div>
        </div>
      )}
    </Modal>
  );
}

import { useEffect, useRef, useState } from 'react';
import QrScanner from 'qr-scanner';

type QrCheckInModalProps = {
  bookingLabel: string;
  processing: boolean;
  onScan: (bookingId: string) => Promise<boolean>;
  onClose: () => void;
};

export default function QrCheckInModal({
  bookingLabel,
  processing,
  onScan,
  onClose,
}: QrCheckInModalProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const processingRef = useRef(processing);
  const scanningRef = useRef(true);
  const [cameraError, setCameraError] = useState('');
  processingRef.current = processing;

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const scanner = new QrScanner(
      video,
      async ({ data }) => {
        if (!data.trim() || !scanningRef.current || processingRef.current) return;
        scanningRef.current = false;
        scanner.pause();
        const accepted = await onScan(data.trim());
        if (!accepted) {
          scanningRef.current = true;
          scanner.start().catch(() => setCameraError('The camera could not be restarted. Use Back and try again.'));
        }
      },
      { highlightScanRegion: false, highlightCodeOutline: false },
    );
    scanner.start().catch(() => {
      setCameraError('Camera access is unavailable. Allow camera access or use the booking ID field instead.');
    });

    return () => {
      scanner.destroy();
    };
  }, [onScan]);

  return (
    <div className="qr-checkin-backdrop" role="presentation">
      <section className="qr-checkin-modal" role="dialog" aria-modal="true" aria-labelledby="qr-checkin-title">
        <header className="qr-checkin-header">
          <button type="button" className="btn btn-ghost qr-checkin-back" onClick={onClose}>
            ← Back
          </button>
          <div>
            <span className="qr-checkin-kicker">CAMERA CHECK-IN</span>
            <h2 id="qr-checkin-title">Scan {bookingLabel.toLowerCase()} QR</h2>
          </div>
          <button type="button" className="qr-checkin-close" onClick={onClose} aria-label="Close scanner">×</button>
        </header>
        <div className="qr-checkin-body">
          <div className="qr-checkin-viewfinder">
            <video ref={videoRef} muted playsInline />
            <span className="qr-checkin-reticle" aria-hidden="true" />
            {processing && <div className="qr-checkin-status">Checking in…</div>}
          </div>
          <p className="qr-checkin-instruction">
            Point the camera at the {bookingLabel.toLowerCase()} confirmation QR code.
          </p>
          {cameraError && <p className="qr-checkin-error" role="alert">{cameraError}</p>}
        </div>
      </section>
    </div>
  );
}

/* Unify booking widget loader.
 *
 * A business pastes this on its own website:
 *
 *   <div data-unify-booking="TENANT-ID"></div>
 *   <script src="https://YOUR-UNIFY-HOST/embed.js" async></script>
 *
 * For each such element it mounts an iframe of /embed/book/<tenant-id>,
 * keeps the iframe's height matched to its content (the widget posts its
 * height as it changes), and forwards a "booked" event to the host page as
 * a DOM CustomEvent so the site can, say, fire an analytics goal.
 *
 * Optional attributes on the element:
 *   data-accent="#0d3b66"   the widget's button/link colour (any hex)
 *   data-theme="dark"       dark ground instead of light
 *   data-min-height="520"   height before the first measurement arrives
 *   data-whatsapp="94777728439"
 *                           the business's WhatsApp number (country code, digits
 *                           only). When set, confirming a booking also opens
 *                           WhatsApp with the booking details, the way a
 *                           hand-made "send via WhatsApp" form would - so the
 *                           team still gets the message they are used to and
 *                           Unify has the record. Falls back to the contact
 *                           phone on the business's Unify profile.
 *
 * Plain script, no build step, works on any site (static HTML, WordPress,
 * Wix custom-code blocks, Squarespace code injection). Idempotent: running
 * it twice mounts nothing twice.
 */
(function () {
  'use strict';

  var script = document.currentScript;
  var origin;
  try {
    origin = new URL(script && script.src ? script.src : window.location.href).origin;
  } catch (e) {
    origin = window.location.origin;
  }

  function mount(host) {
    if (host.getAttribute('data-unify-mounted') === '1') return;
    var tenantId = host.getAttribute('data-unify-booking');
    if (!tenantId) return;
    host.setAttribute('data-unify-mounted', '1');

    var params = [];
    var accent = host.getAttribute('data-accent');
    var theme = host.getAttribute('data-theme');
    if (accent) params.push('accent=' + encodeURIComponent(accent.replace('#', '')));
    if (theme) params.push('theme=' + encodeURIComponent(theme));
    var whatsapp = host.getAttribute('data-whatsapp');
    if (whatsapp) params.push('whatsapp=' + encodeURIComponent(whatsapp.replace(/[^0-9]/g, '')));

    var frame = document.createElement('iframe');
    frame.src = origin + '/embed/book/' + encodeURIComponent(tenantId) + (params.length ? '?' + params.join('&') : '');
    frame.title = 'Book online';
    frame.setAttribute('loading', 'lazy');
    frame.setAttribute('scrolling', 'no');
    frame.style.cssText = 'width:100%;max-width:100%;border:0;display:block;background:transparent;' +
      'height:' + (parseInt(host.getAttribute('data-min-height') || '520', 10)) + 'px;transition:height .2s ease;';
    frame.allow = 'clipboard-write';

    host.innerHTML = '';
    host.appendChild(frame);

    window.addEventListener('message', function (event) {
      if (event.origin !== origin || event.source !== frame.contentWindow) return;
      var data = event.data || {};
      if (data.source !== 'unify-booking') return;
      if (data.type === 'unify-booking:height' && typeof data.height === 'number') {
        frame.style.height = Math.max(200, data.height + 8) + 'px';
      } else if (data.type === 'unify-booking:booked') {
        host.dispatchEvent(new CustomEvent('unify:booked', { bubbles: true, detail: { reference: data.reference } }));
        try { frame.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (e) { /* older browsers */ }
      }
    });
  }

  function mountAll() {
    var hosts = document.querySelectorAll('[data-unify-booking]');
    for (var i = 0; i < hosts.length; i++) mount(hosts[i]);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mountAll);
  } else {
    mountAll();
  }

  // Sites that render content later (tabs, SPAs) can call this themselves.
  window.UnifyBooking = { mount: mountAll };
})();

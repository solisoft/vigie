// Vigie — live status. The page (or the admin dashboard) carries
// data-live-url, an SSE endpoint; on each "status" event the
// [data-live-region] is fetched again and swapped in place, and a polite
// live region tells screen readers. Idempotent under instant navigation.
(function () {
  var source = null;
  var timer = null;

  function setState(on) {
    document.querySelectorAll('[data-live-dot]').forEach(function (dot) {
      dot.setAttribute('data-state', on ? 'on' : 'off');
    });
    document.querySelectorAll('[data-live-text]').forEach(function (text) {
      text.textContent = on ? '· en direct' : '';
    });
  }

  function refresh() {
    fetch(location.href, { cache: 'no-store', headers: { Accept: 'text/html' } })
      .then(function (response) { return response.text(); })
      .then(function (html) {
        var fresh = new DOMParser().parseFromString(html, 'text/html').querySelector('[data-live-region]');
        var current = document.querySelector('[data-live-region]');
        if (!fresh || !current) return;
        current.replaceWith(fresh);
        setState(true);
        var announce = document.querySelector('[data-live-announce]');
        if (announce) announce.textContent = 'Statut mis à jour à ' + new Date().toLocaleTimeString('fr-FR');
      })
      .catch(function () {});
  }

  function init() {
    var root = document.querySelector('[data-live-url]');
    var url = root ? root.getAttribute('data-live-url') : null;
    if (source && source.__url === url) return;
    if (source) { source.close(); source = null; }
    if (!url || !window.EventSource) return;
    source = new EventSource(url);
    source.__url = url;
    source.onopen = function () { setState(true); };
    source.onerror = function () { setState(false); };
    source.addEventListener('status', function () {
      clearTimeout(timer);
      timer = setTimeout(refresh, 600);
    });
  }

  // Monitor forms (a select, or radios on a service): show only the fields
  // of the chosen kind.
  function kindForms() {
    document.querySelectorAll('[data-kind-form]:not([data-kind-ready])').forEach(function (form) {
      form.setAttribute('data-kind-ready', '');
      var select = form.querySelector('[data-kind-select]');
      var radios = form.querySelectorAll('[data-kind-radio]');
      if (!select && !radios.length) return;
      function current() {
        if (select) return select.value;
        var checked = form.querySelector('[data-kind-radio]:checked');
        return checked ? checked.value : '';
      }
      function sync() {
        var kind = current();
        form.querySelectorAll('[data-kind]').forEach(function (fieldset) {
          fieldset.hidden = fieldset.getAttribute('data-kind') !== kind;
        });
      }
      if (select) select.addEventListener('change', sync);
      radios.forEach(function (radio) { radio.addEventListener('change', sync); });
      sync();
    });
  }

  function boot() { init(); kindForms(); }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
  document.addEventListener('soli:load', boot);
})();

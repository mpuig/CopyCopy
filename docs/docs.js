/* CopyCopy docs — progressive enhancement only.
   The pages are fully readable without this script; it just adds
   copy-to-clipboard buttons and TOC scroll-spy. */
(function () {
  'use strict';

  /* ---- Copy buttons on code blocks ---- */
  var COPY = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="5.5" y="5.5" width="8" height="8" rx="1.5"/><path d="M3.5 10.5h-1A1.5 1.5 0 011 9V2.5A1.5 1.5 0 012.5 1H9a1.5 1.5 0 011.5 1.5v1"/></svg>';
  var DONE = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 4.5L6.5 11 3 7.5"/></svg>';

  document.querySelectorAll('.codeblock').forEach(function (block) {
    if (block.classList.contains('flow')) return; // diagrams aren't copyable
    var pre = block.querySelector('pre');
    if (!pre) return;
    var btn = document.createElement('button');
    btn.className = 'codeblock__copy';
    btn.type = 'button';
    btn.setAttribute('aria-label', 'Copy code');
    btn.innerHTML = COPY;
    btn.addEventListener('click', function () {
      var text = pre.innerText;
      var finish = function () {
        btn.innerHTML = DONE; btn.classList.add('is-done');
        setTimeout(function () { btn.innerHTML = COPY; btn.classList.remove('is-done'); }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(finish).catch(finish);
      } else { finish(); }
    });
    block.appendChild(btn);
  });

  /* ---- TOC scroll-spy ---- */
  var links = Array.prototype.slice.call(document.querySelectorAll('.toc__list a'));
  if (!links.length || !('IntersectionObserver' in window)) return;
  var byId = {};
  links.forEach(function (a) {
    var id = a.getAttribute('href');
    if (id && id.charAt(0) === '#') byId[id.slice(1)] = a;
  });
  var visible = {};
  var spy = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      visible[e.target.id] = e.isIntersecting ? e.intersectionRatio : 0;
    });
    var best = null, bestR = 0;
    Object.keys(visible).forEach(function (id) {
      if (visible[id] > bestR) { bestR = visible[id]; best = id; }
    });
    if (best) {
      links.forEach(function (a) { a.classList.remove('is-active'); });
      if (byId[best]) byId[best].classList.add('is-active');
    }
  }, { rootMargin: '-72px 0px -65% 0px', threshold: [0, 0.5, 1] });

  Object.keys(byId).forEach(function (id) {
    var el = document.getElementById(id);
    if (el) spy.observe(el);
  });
})();

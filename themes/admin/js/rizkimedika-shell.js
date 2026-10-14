/* Shell Rizki Medika: sidebar collapse (Ctrl+B), off-canvas di mobile, penanda menu aktif. Hanya mengatur tampilan. */
(function ($) {
  var KEY = 'rm-sidebar-collapsed';
  var $body = $('body');

  function store(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  function read(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }

  if (read(KEY) === '1') $body.addClass('rm-collapsed');

  function toggleCollapse() {
    $body.toggleClass('rm-collapsed');
    store(KEY, $body.hasClass('rm-collapsed') ? '1' : '0');
  }

  $('#rm-collapse').on('click', toggleCollapse);
  $('#rm-open').on('click', function () { $body.addClass('rm-open'); });
  $('#rm-backdrop').on('click', function () { $body.removeClass('rm-open'); });

  $(document).on('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && (e.key === 'b' || e.key === 'B')) {
      e.preventDefault();
      if (window.innerWidth < 992) $body.toggleClass('rm-open'); else toggleCollapse();
    }
    if (e.key === 'Escape') $body.removeClass('rm-open');
  });

  // Saat sidebar mode ikon, klik grup akan membuka sidebar lebih dulu
  $('.rm-group-toggle').on('click', function () {
    if ($body.hasClass('rm-collapsed')) { $body.removeClass('rm-collapsed'); store(KEY, '0'); }
  });

  // Tandai menu aktif dan buka grup induknya (cocokkan path modul: /admin/<modul>/...)
  var here = window.location.pathname.replace(/\/+$/, '');
  var best = null, bestLen = 0;
  $('.rm-nav a[href]').each(function () {
    var href = this.getAttribute('href');
    if (!href || href.charAt(0) === '#' || this.target === '_blank' || $(this).data('toggle')) return;
    var path;
    try { path = new URL(href, window.location.href).pathname.replace(/\/+$/, ''); } catch (e) { return; }
    if (here === path || here.indexOf(path + '/') === 0) {
      if (path.length > bestLen) { best = this; bestLen = path.length; }
    }
  });
  if (best) {
    $(best).addClass('rm-active');
    $(best).parents('.collapse').addClass('in').each(function () {
      $('[href="#' + this.id + '"]').removeClass('collapsed').attr('aria-expanded', 'true');
    });
  }
})(jQuery);

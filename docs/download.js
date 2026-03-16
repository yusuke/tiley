(function () {
  var script = document.currentScript;
  var base = script.src.substring(0, script.src.lastIndexOf('/') + 1);
  fetch(base + 'appcast.xml')
    .then(function (r) { return r.text(); })
    .then(function (xml) {
      var doc = new DOMParser().parseFromString(xml, 'application/xml');
      var url = doc.querySelector('item > enclosure')?.getAttribute('url');
      if (url) {
        document.querySelectorAll('.download-link').forEach(function (a) { a.href = url; });
      }
    })
    .catch(function () {});
})();

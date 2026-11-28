import 'package:test/test.dart';

import '../../tool/serving.dart';

const _files = {
  'index.html',
  'main.wasm',
  'main.mjs',
  'wterm/dom/dist/index.js',
  'recordings/permission.80x20.rec.json',
};

void main() {
  test('files are served as they are, under the base', () {
    expect(serve('/main.wasm', '/', _files), const ServedFile('main.wasm'));
    expect(
      serve('/chord/wterm/dom/dist/index.js', '/chord/', _files),
      const ServedFile('wterm/dom/dist/index.js'),
    );
  });

  test('a page path with no extension gets index.html', () {
    for (final (path, base) in [
      ('/', '/'),
      ('/chord_tui/markdown', '/'),
      ('/chord_tui/markdown/', '/'),
      ('/chord/', '/chord/'),
      ('/chord', '/chord/'),
      ('/chord/chord_tui/gallery', '/chord/'),
      ('/x/y/z', '/'),
    ]) {
      expect(
        serve(path, base, _files),
        const ServedFile('index.html'),
        reason: path,
      );
    }
  });

  test('a missing file with an extension is a 404, not the page', () {
    expect(serve('/x/main.wasm', '/', _files), const NotServed());
    expect(serve('/chord_tui/main.mjs', '/', _files), const NotServed());
    expect(
      serve('/recordings/start.80x20.rec.json', '/', _files),
      const NotServed(),
    );
  });

  test('outside the base, or climbing out of it, is a 404', () {
    expect(serve('/main.wasm', '/chord/', _files), const NotServed());
    expect(serve('/../etc/passwd', '/', _files), const NotServed());
    expect(serve('/%2e%2e/secret', '/', _files), const NotServed());
  });

  test('wasm is served as application/wasm', () {
    expect(contentTypeOf('main.wasm'), 'application/wasm');
    expect(contentTypeOf('main.mjs'), startsWith('text/javascript'));
    expect(contentTypeOf('index.html'), startsWith('text/html'));
    expect(contentTypeOf('fonts/mono.woff2'), 'font/woff2');
  });

  test('the base starts and ends with a slash', () {
    expect(checkedBase('/'), '/');
    expect(checkedBase('/chord/'), '/chord/');
    for (final bad in ['chord/', '/chord', '', '//']) {
      expect(() => checkedBase(bad), throwsFormatException, reason: bad);
    }
  });
}

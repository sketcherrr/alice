"""Browser checks for the published page; requires Playwright + Chromium."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
SCREENSHOTS = ROOT / 'dist/website-preview'
SCREENSHOTS.mkdir(parents=True, exist_ok=True)
handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT / 'dist/site'))
server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
Thread(target=server.serve_forever, daemon=True).start()
url = f'http://127.0.0.1:{server.server_port}/'

try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        for width, height in [(1440, 1080), (768, 1024), (390, 844), (320, 740)]:
            page = browser.new_page(viewport={'width': width, 'height': height}, device_scale_factor=1)
            errors = []
            failures = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('requestfailed', lambda request: failures.append(request.url))
            page.goto(url, wait_until='networkidle')
            expect(page.locator('#pet-canvas')).to_be_visible()
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'Horizontal overflow at {width}px'
            assert page.locator('h1').count() == 1
            if width in (1440, 390):
                page.screenshot(path=str(SCREENSHOTS / f'alice-{width}.png'), full_page=True)
                page.screenshot(path=str(SCREENSHOTS / f'alice-hero-{width}.png'))

            page.locator('[data-action="happy"]').click()
            expect(page.locator('#pet-bubble')).to_contain_text('快乐')
            expect(page.locator('[data-action="happy"]')).to_have_attribute('aria-pressed', 'true')
            page.locator('[data-action="tea"]').click()
            expect(page.locator('#pet-caption')).to_contain_text('喝茶')
            first = page.locator('canvas').evaluate('(el) => el.toDataURL()')
            page.wait_for_timeout(1100)
            assert first != page.locator('canvas').evaluate('(el) => el.toDataURL()'), 'Animation frame did not change'
            page.locator('#motion-toggle').click()
            expect(page.locator('#motion-toggle')).to_have_attribute('aria-pressed', 'true')
            first = page.locator('canvas').evaluate('(el) => el.toDataURL()')
            page.wait_for_timeout(350)
            assert first == page.locator('canvas').evaluate('(el) => el.toDataURL()'), 'Paused animation changed'
            page.locator('[data-action="sleeping"]').click()
            expect(page.locator('#pet-caption')).to_contain_text('省电模式')
            expect(page.locator('[data-action="sleeping"]')).to_contain_text('醒醒啦')
            page.locator('[data-action="sleeping"]').click()
            expect(page.locator('#pet-bubble')).to_contain_text('珍珠海')
            expect(page.locator('[data-action="sleeping"]')).to_contain_text('睡会儿')

            for persona, phrase in [('playful', '零食'), ('quiet', '声音放轻'), ('gentle', '晚饭')]:
                page.locator(f'[data-persona="{persona}"]').click()
                expect(page.locator('#persona-reply')).to_contain_text(phrase)
                assert page.locator('[data-persona][aria-pressed="true"]').count() == 1
            for item in page.locator('details').all():
                item.locator('summary').click()
                expect(item.locator('p')).to_be_visible()
                item.locator('summary').click()
                expect(item.locator('p')).not_to_be_visible()
            for link in page.locator('a[href^="#"]').all():
                target = link.get_attribute('href')
                if target != '#':
                    assert page.locator(target).count() == 1, f'Missing anchor {target}'
            assert not errors, errors
            assert not failures, failures
            print(f'PASS: {width}px layout, image loading, animation, pause, activities, personas, FAQ and anchors')
            page.close()

        reduced = browser.new_page(reduced_motion='reduce')
        reduced.goto(url, wait_until='networkidle')
        expect(reduced.locator('#motion-toggle')).to_have_attribute('aria-pressed', 'true')
        reduced.locator('[data-action="tea"]').click()
        first = reduced.locator('canvas').evaluate('(el) => el.toDataURL()')
        reduced.wait_for_timeout(1200)
        assert first == reduced.locator('canvas').evaluate('(el) => el.toDataURL()')
        print('PASS: system reduced-motion preference')
        reduced.close()

        no_js = browser.new_page(java_script_enabled=False)
        no_js.goto(url, wait_until='networkidle')
        expect(no_js.locator('h1')).to_be_visible()
        expect(no_js.locator('#pet-fallback')).to_be_visible()
        assert 'macos-test.yml' in no_js.locator('#mac-download').get_attribute('href')
        no_js.locator('details').first.locator('summary').click()
        expect(no_js.locator('details').first.locator('p')).to_be_visible()
        print('PASS: no-JavaScript content, download link and native FAQ')
        no_js.close()

        fallback = browser.new_page()
        fallback.route('**/calm.png', lambda route: route.abort())
        fallback.goto(url, wait_until='networkidle')
        expect(fallback.locator('#pet-fallback')).to_be_visible()
        expect(fallback.locator('#pet-canvas')).not_to_be_visible()
        fallback.locator('[data-action="happy"]').click()
        expect(fallback.locator('#pet-bubble')).to_contain_text('快乐')
        print('PASS: missing animation asset retains illustration and interactions')
        browser.close()
finally:
    server.shutdown()
    server.server_close()

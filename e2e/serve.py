"""Отдача собранного веб-клиента.

Многопоточная: Flutter тянет canvaskit, main.dart.js, шрифты и wasm
параллельно, и однопоточный http.server на этом встаёт.
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        '.wasm': 'application/wasm',
        '.js': 'text/javascript',
        '.mjs': 'text/javascript',
        '.json': 'application/json',
    }

    def end_headers(self):
        # Заголовки для SharedArrayBuffer: без них drift не поднимет
        # многопоточную SQLite в браузере.
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, *args):
        pass

if __name__ == '__main__':
    root, port = sys.argv[1], int(sys.argv[2])
    ThreadingHTTPServer(('127.0.0.1', port), partial(Handler, directory=root)).serve_forever()

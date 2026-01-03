
import http.server
import socketserver
import json
import threading
import os
import time
import queue

# Global State
GAME_STATE = {'phase': 'WAITING', 'hands': [[],[],[],[]], 'logs': []}
PENDING_ACTION = {'context': None, 'data': None} # If Human Input needed: {context: 'BID'/'PLAY', data: {...}}
ACTION_QUEUE = queue.Queue() # From UI to HumanPlayer

STATE_LOCK = threading.Lock()

class ArenaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Determine static directory
        self.static_dir = os.path.join(os.path.dirname(__file__), 'static')
        super().__init__(*args, directory=self.static_dir, **kwargs)

    def do_GET(self):
        if self.path == '/arena_state':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            with STATE_LOCK:
                response = {
                    'game_state': GAME_STATE,
                    'pending_action': PENDING_ACTION
                }
                self.wfile.write(json.dumps(response).encode('utf-8'))
        elif self.path == '/' or self.path == '':
            self.path = '/play.html'
            return super().do_GET()
        else:
            return super().do_GET()

    def do_POST(self):
        if self.path == '/action':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            
            # Reset Pending
            # PENDING_ACTION['context'] = None # Done by Player thread? Better here for UI responsiveness?
            # No, let Player thread clear it after taking from Queue.
            
            ACTION_QUEUE.put(data)
            
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')

def set_game_state(state):
    global GAME_STATE
    with STATE_LOCK:
        GAME_STATE = state

def set_human_pending_action(context, data, error=None):
    global PENDING_ACTION
    with STATE_LOCK:
        PENDING_ACTION = {'context': context, 'data': data, 'error': error}

class ArenaServer(socketserver.TCPServer):
    allow_reuse_address = True

def run_server(port=8001):
    max_retries = 5
    for i in range(max_retries):
        try:
            with ArenaServer(("", port), ArenaHandler) as httpd:
                print(f"Arena Server running at http://localhost:{port}")
                httpd.serve_forever()
                break
        except OSError as e:
            if i < max_retries - 1:
                print(f"Port {port} busy, retrying in 1s... ({i+1}/{max_retries})")
                time.sleep(1)
            else:
                print(f"Error: Could not bind to port {port} after {max_retries} retries.")
                raise e

def start_arena_server(q):
    # q is the ACTION_QUEUE passed to WebHumanPlayer
    # But wait, queue is creating inside WebHumanPlayer usually?
    # No, we need to pass the SERVER'S queue TO the player.
    # Actually, the file above has ACTION_QUEUE global. 
    # We need to bridge them.
    t = threading.Thread(target=run_server, daemon=True)
    t.start()
    return ACTION_QUEUE

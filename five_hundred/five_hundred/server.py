import http.server
import socketserver
import json
import threading
import os
import time

# Global state to be shared
GAME_STATE = {}
CONTROL_STATE = {"running": False} # Default paused
LOG_BUFFER = []
LOSS_BUFFER = []
REWARD_BUFFER = []
TOTAL_STEPS = 0
STATE_LOCK = threading.Lock()

class StateHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/state':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*') 
            self.end_headers()
            
            with STATE_LOCK:
                # Merge game state and control state
                combined = {
                    **GAME_STATE, 
                    "control": CONTROL_STATE,
                    "logs": LOG_BUFFER[-50:], # Send last 50 logs
                    "steps": TOTAL_STEPS
                }
                
                # Sampling for charts if too big (limit to 1000 points)
                max_pts = 1000
                
                # Loss
                if len(LOSS_BUFFER) > max_pts:
                     step = len(LOSS_BUFFER) // max_pts
                     combined["loss"] = LOSS_BUFFER[::step]
                else:
                     combined["loss"] = LOSS_BUFFER
                     
                # Reward
                if len(REWARD_BUFFER) > max_pts:
                     step = len(REWARD_BUFFER) // max_pts
                     combined["reward"] = REWARD_BUFFER[::step]
                else:
                     combined["reward"] = REWARD_BUFFER
                
                response = json.dumps(combined)
            
            self.wfile.write(response.encode('utf-8'))
        else:
            # Serve static files
            super().do_GET()

    def do_POST(self):
        if self.path == '/control':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            
            with STATE_LOCK:
                if 'running' in data:
                    CONTROL_STATE['running'] = bool(data['running'])
            
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')

def get_control_state():
    with STATE_LOCK:
        return CONTROL_STATE.copy()

def log_message(msg):
    with STATE_LOCK:
        LOG_BUFFER.append(msg)
        if len(LOG_BUFFER) > 200:
            LOG_BUFFER.pop(0)

def record_loss(loss_val):
    with STATE_LOCK:
        LOSS_BUFFER.append(loss_val)

def record_reward(reward_val):
    with STATE_LOCK:
        REWARD_BUFFER.append(reward_val)

def increment_steps():
    global TOTAL_STEPS
    with STATE_LOCK:
        TOTAL_STEPS += 1

def update_state(new_state):
    global GAME_STATE
    with STATE_LOCK:
        GAME_STATE = new_state

def run_server(start_port=8000):
    port = start_port
    while port < start_port + 10:
        try:
            print(f"Attempting to start server on port {port}...")
            web_dir = os.path.join(os.path.dirname(__file__), 'static')
            if not os.path.exists(web_dir):
                print(f"ERROR: Static dir not found: {web_dir}")
                return
                
            os.chdir(web_dir) 
            
            class ReusableTCPServer(socketserver.TCPServer):
                allow_reuse_address = True
    
            with ReusableTCPServer(("", port), StateHandler) as httpd:
                print(f"Serving UI at http://localhost:{port}")
                # Save port to a global if needed, or print clearly
                httpd.serve_forever()
                return # Should not reach here
        except OSError as e:
            if e.errno == 48: # Address in use
                print(f"Port {port} in use, trying next...")
                port += 1
                time.sleep(1)
            else:
                raise e
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"SERVER CRASH: {e}")
            return
            
    print("Could not find open port after 10 attempts.")

def start_server_thread():
    print("Launching server thread...")
    t = threading.Thread(target=run_server, daemon=True)
    t.start()
    return t

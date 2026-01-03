import sys
import os
import time
import subprocess
import threading

WATCH_EXTS = ['.py', '.html', '.css', '.js', '.pth']
IGNORE_DIRS = ['__pycache__', '.git', '.gemini']

def get_mtimes(path):
    mtimes = {}
    for root, dirs, files in os.walk(path):
        # Filter directories to ignore
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        
        for f in files:
            if any(f.endswith(ext) for ext in WATCH_EXTS):
                full_path = os.path.join(root, f)
                try:
                    mtimes[full_path] = os.stat(full_path).st_mtime
                except OSError:
                    continue
    return mtimes

def main():
    target_script = 'play_game.py'
    if not os.path.exists(target_script):
        print(f"Error: {target_script} not found in current directory.")
        return

    print(f"--- 🔄 Auto-Reload Monitor Starting for {target_script} ---")
    print(f"Watching for changes in: {WATCH_EXTS}")

    process = None

    def start_process():
        nonlocal process
        # Wait a moment to ensure port is released
        time.sleep(1)
        print(f"[{time.strftime('%H:%M:%S')}] Starting server...")
        # Use sys.executable to ensure we use the same python interpreter
        process = subprocess.Popen([sys.executable, target_script])

    def stop_process():
        nonlocal process
        if process:
            print(f"[{time.strftime('%H:%M:%S')}] Detected change. Restarting...")
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
            process = None

    start_process()
    
    # Snapshot initial state
    last_mtimes = get_mtimes('.')

    try:
        while True:
            time.sleep(1)
            current_mtimes = get_mtimes('.')
            
            changed = False
            # Check for modifications or new files
            for f, mtime in current_mtimes.items():
                if f not in last_mtimes or last_mtimes[f] != mtime:
                    changed = True
                    break
            
            # Check for deleted files
            if not changed and len(last_mtimes) != len(current_mtimes):
                changed = True

            if changed:
                stop_process()
                start_process()
                last_mtimes = current_mtimes

    except KeyboardInterrupt:
        print("\nStopping monitor...")
        if process:
            process.terminate()

if __name__ == "__main__":
    main()

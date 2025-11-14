#!/usr/bin/env python3

import os
import time
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

PORT = int(os.environ.get('HEALTH_PORT', 8080))
HEALTH_FILE = os.environ.get('HEALTH_FILE', '/tmp/health/heartbeat')
MAX_AGE = 120  # Maximum age of heartbeat file in seconds
MAX_ERROR_RATE = 80  # Maximum acceptable error rate percentage

def check_health():
    """Check the health of the main application."""
    
    # Check 1: Is the main process running?
    try:
        result = subprocess.run(['pgrep', '-f', 'neko-init.sh'], 
                              capture_output=True, timeout=5)
        if result.returncode != 0:
            return False, "UNHEALTHY: neko-init.sh process not found"
    except Exception as e:
        return False, f"UNHEALTHY: Process check failed: {e}"
    
    # Check 2: Does the heartbeat file exist and is it recent?
    if not os.path.exists(HEALTH_FILE):
        return False, "UNHEALTHY: Heartbeat file missing"
    
    try:
        file_time = os.path.getmtime(HEALTH_FILE)
        current_time = time.time()
        age = int(current_time - file_time)
        
        if age > MAX_AGE:
            return False, f"UNHEALTHY: Heartbeat file too old ({age}s > {MAX_AGE}s)"
        
        # Check 3: Read metrics from heartbeat file
        with open(HEALTH_FILE, 'r') as f:
            content = f.read()
            
        success_count = None
        error_count = None
        
        for line in content.split('\n'):
            if line.startswith('SUCCESS_COUNT='):
                success_count = int(line.split('=')[1])
            elif line.startswith('ERROR_COUNT='):
                error_count = int(line.split('=')[1])
        
        if success_count is not None and error_count is not None:
            total = success_count + error_count
            
            if total > 10:
                error_rate = int((error_count * 100) / total)
                
                if error_rate > MAX_ERROR_RATE:
                    return False, f"UNHEALTHY: Error rate too high ({error_rate}% > {MAX_ERROR_RATE}%)"
        
        return True, f"HEALTHY: All checks passed (heartbeat age: {age}s)"
        
    except Exception as e:
        return False, f"UNHEALTHY: Error reading heartbeat: {e}"

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests."""
        healthy, message = check_health()
        
        if healthy:
            self.send_response(200)
        else:
            self.send_response(503)
        
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        
        response = {
            'status': 'healthy' if healthy else 'unhealthy',
            'message': message
        }
        
        self.wfile.write(json.dumps(response).encode())
    
    def log_message(self, format, *args):
        """Suppress default logging, only log errors."""
        if '200' not in args[1]:
            print(f"[HEALTH-SERVER] {args[0]} - {args[1]}")

if __name__ == '__main__':
    server_address = ('0.0.0.0', PORT)
    httpd = HTTPServer(server_address, HealthHandler)
    print(f'[HEALTH-SERVER] Starting health server on port {PORT}...')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('[HEALTH-SERVER] Shutting down...')
        httpd.shutdown()

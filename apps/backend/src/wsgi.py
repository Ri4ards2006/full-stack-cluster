"""
Production WSGI Entry Point for Gunicorn
"""

from app import app

if __name__ == "__main__":
    app.run()

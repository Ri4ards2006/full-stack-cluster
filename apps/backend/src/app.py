"""
Ticket System REST API Backend
Production-grade Flask microservice with database connection pooling and health checks.
"""

import os
import time
import logging
from flask import Flask, jsonify, request
from psycopg2 import pool, OperationalError

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s"
)
logger = logging.getLogger("ticket-backend")

app = Flask(__name__)

# Database configuration from environment variables (Zero hardcoded secrets)
DB_HOST = os.environ.get("DB_HOST", "ticket-db")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "ticket_db")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

db_pool = None

def get_connection_pool():
    global db_pool
    if db_pool is None or db_pool.closed:
        max_retries = 10
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(f"Connecting to database {DB_USER}@{DB_HOST}:{DB_PORT}/{DB_NAME} (attempt {attempt}/{max_retries})...")
                db_pool = pool.SimpleConnectionPool(
                    minconn=1,
                    maxconn=20,
                    host=DB_HOST,
                    port=DB_PORT,
                    database=DB_NAME,
                    user=DB_USER,
                    password=DB_PASSWORD,
                    connect_timeout=3
                )
                logger.info("Database connection pool established successfully.")
                break
            except OperationalError as e:
                logger.warning(f"Database connection attempt {attempt} failed: {e}")
                if attempt == max_retries:
                    logger.error("Exhausted database connection retries.")
                    raise
                time.sleep(3)
    return db_pool

def init_db():
    """Initializes schema and seeds default data if table is empty."""
    pool_instance = get_connection_pool()
    conn = pool_instance.getconn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS tickets (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    priority VARCHAR(50) DEFAULT 'Low',
                    status VARCHAR(50) DEFAULT 'Open',
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
                );
            """)
            cur.execute("SELECT COUNT(*) FROM tickets;")
            count = cur.fetchone()[0]
            if count == 0:
                logger.info("Database empty. Seeding initial tickets...")
                cur.execute("INSERT INTO tickets (title, priority, status) VALUES (%s, %s, %s);",
                            ("Cluster Network MTU verification", "High", "Open"))
                cur.execute("INSERT INTO tickets (title, priority, status) VALUES (%s, %s, %s);",
                            ("CoreDNS upstream fallback validation", "Medium", "In Progress"))
                cur.execute("INSERT INTO tickets (title, priority, status) VALUES (%s, %s, %s);",
                            ("RBAC scoped least-privilege review", "Low", "Closed"))
            conn.commit()
            logger.info("Database schema verified and ready.")
    finally:
        pool_instance.putconn(conn)

@app.route("/api/health", methods=["GET"])
def health():
    """Liveness/Readiness probe endpoint with active database ping."""
    try:
        pool_instance = get_connection_pool()
        conn = pool_instance.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
            return jsonify({
                "status": "healthy",
                "database": "connected",
                "service": "ticket-backend"
            }), 200
        finally:
            pool_instance.putconn(conn)
    except Exception as e:
        logger.error(f"Health check failure: {e}")
        return jsonify({
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e)
        }), 500

@app.route("/api/tickets", methods=["GET"])
def get_tickets():
    """Fetches all tickets ordered by ID descending."""
    try:
        pool_instance = get_connection_pool()
        conn = pool_instance.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT id, title, priority, status, created_at FROM tickets ORDER BY id DESC;")
                rows = cur.fetchall()
                tickets = [
                    {
                        "id": r[0],
                        "title": r[1],
                        "priority": r[2],
                        "status": r[3],
                        "created_at": r[4].isoformat() if r[4] else None
                    }
                    for r in rows
                ]
                return jsonify(tickets), 200
        finally:
            pool_instance.putconn(conn)
    except Exception as e:
        logger.error(f"Error fetching tickets: {e}")
        return jsonify({"error": "Failed to retrieve tickets", "details": str(e)}), 500

@app.route("/api/tickets", methods=["POST"])
def create_ticket():
    """Creates a new incident ticket."""
    try:
        data = request.get_json(force=True, silent=True)
        if not data or not data.get("title"):
            return jsonify({"error": "Field 'title' is required"}), 400

        title = str(data["title"]).strip()
        priority = str(data.get("priority", "Low")).strip()
        status = "Open"

        if not title:
            return jsonify({"error": "Field 'title' cannot be empty"}), 400

        pool_instance = get_connection_pool()
        conn = pool_instance.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO tickets (title, priority, status) VALUES (%s, %s, %s) RETURNING id, created_at;",
                    (title, priority, status)
                )
                res = cur.fetchone()
                ticket_id = res[0]
                created_at = res[1].isoformat() if res[1] else None
                conn.commit()
                logger.info(f"Ticket #{ticket_id} created successfully.")
                return jsonify({
                    "id": ticket_id,
                    "title": title,
                    "priority": priority,
                    "status": status,
                    "created_at": created_at
                }), 201
        finally:
            pool_instance.putconn(conn)
    except Exception as e:
        logger.error(f"Error creating ticket: {e}")
        return jsonify({"error": "Failed to create ticket", "details": str(e)}), 500

# Perform startup DB initialization safely
try:
    init_db()
except Exception as err:
    logger.warning(f"Initial DB bootstrap deferred: {err}")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

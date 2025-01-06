import os
import pymysql
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS

app = Flask(__name__)

# 환경변수로부터 DB 정보 가져오기
DB_HOST = os.getenv("DB_HOST")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")
# CORS 설정 추가
CORS(app, resources={r"/*": {"origins": "*"}})

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME
    )

@app.route("/healthz")
def health_check():
    return "OK"

@app.route('/app-one/register', methods=['POST', 'OPTIONS'])
def register_user():
    if request.method == 'OPTIONS':
        response = jsonify({"message": "CORS preflight passed"})
        response.headers.add("Access-Control-Allow-Origin", "*")
        response.headers.add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        response.headers.add("Access-Control-Allow-Headers", "Content-Type, Authorization")
        return response, 200

    data = request.get_json()
    app.logger.debug(f"Received data: {data}")

    if not data:
        return jsonify({"success": False, "error": "No data provided"}), 400

    username = data.get("username")
    password = data.get("password")
    email    = data.get("email")

    if not username or not password or not email:
        return jsonify({"success": False, "error": "Missing fields"}), 400

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            sql = "INSERT INTO users (username, password, email) VALUES (%s, %s, %s)"
            cursor.execute(sql, (username, password, email))
        conn.commit()
        return jsonify({"success": True, "message": "User registered successfully"}), 201

    except Exception as e:
        app.logger.error(f"DB Connection Failed: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 400

    finally:
        if conn:
            conn.close()

# 필요하다면 다른 엔드포인트들도 추가
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

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

# DB 초기화 로직
def init_db():
    conn = get_db_connection()

    try:
        with conn.cursor() as cursor:
            # users 테이블이 존재하지 않으면 생성
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    username VARCHAR(50) NOT NULL,
                    password VARCHAR(100) NOT NULL,
                    email VARCHAR(100) NOT NULL
                );
            """)
        conn.commit()
    finally:
        conn.close()

@app.route("/healthz")
def health_check():
    return "OK"

@app.route('/app-one/register', methods=['POST', 'OPTIONS'])
def register_user():
    
    if request.method == 'OPTIONS':
        response = jsonify({"message": "CORS preflight passed"})
        response.headers.add("Access-Control-Allow-Origin", "https://www.ljhun.shop")
        response.headers.add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        response.headers.add("Access-Control-Allow-Headers", "Content-Type, Authorization")
        return response, 200

    data = request.get_json()
    username = data.get("username")
    password = data.get("password")
    email    = data.get("email")   # email 받기

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            sql = "INSERT INTO users (username, password, email) VALUES (%s, %s, %s)"
            cursor.execute(sql, (username, password, email))
        conn.commit()

        # 프론트엔드에서 "response.ok && data.success" 체킹을 하므로, success 필드를 함께 내려줍니다.
        return jsonify({"success": True, "message": "User registered successfully"}), 201

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 400

    finally:
        conn.close()

# 필요하다면 다른 엔드포인트들도 추가
if __name__ == "__main__":
    init_db()  # RDS 초기화 실행
    app.run(host="0.0.0.0", port=5000)

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

#app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///users.db'
#app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
#db = SQLAlchemy(app)

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME
    )

@app.route('/app-two/login', methods=['GET', 'POST', 'OPTIONS'])
def login():
    app.logger.info(f"Request received: {request.method} {request.path}")

    if request.method == 'OPTIONS':
        response = jsonify({"message": "CORS preflight passed"})
        response.headers.add("Access-Control-Allow-Origin", "*")
        response.headers.add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        response.headers.add("Access-Control-Allow-Headers", "Content-Type, Authorization")
        return response, 200

    if request.method == 'GET':
        return jsonify({"success": True, "message": "Health Check Passed"}), 200  # Route 53용 응답 추가

    data = request.get_json()
    app.logger.debug(f"Received data: {data}")

    if not data:
        return jsonify({"success": False, "error": "No data provided"}), 400

    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify({"success": False, "error": "Missing fields"}), 400

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            # username과 password를 비교하는 SQL 쿼리
            sql = "SELECT * FROM users WHERE username = %s AND password = %s"
            cursor.execute(sql, (username, password))

            # 결과가 존재하는지 확인
            result = cursor.fetchone()

            if result:
                return jsonify({"success": True, "message": "Login Succeed"}), 200
            else:
                return jsonify({"success": False, "error": "Invalid credentials"}), 201
        conn.commit()    
    except Exception as e:
        app.logger.error(f"DB Connection Failed: {str(e)}")
        return jsonify({"success": False, "error": str(e)}), 400

    finally:
        if conn:
            conn.close()

@app.route("/healthz", methods=["GET"])
def health_check():
    app.logger.info(f"Health check received from: {request.headers.get('X-Forwarded-For', 'unknown')}")
    app.logger.info(f"User-Agent: {request.headers.get('User-Agent', 'unknown')}")
    app.logger.info("Responding with 200 OK")
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
from flask import Flask

app = Flask(__name__)

@app.route("/healthz")
def healthz():
    return "OK", 200  # Kubernetes가 정상으로 간주할 응답

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

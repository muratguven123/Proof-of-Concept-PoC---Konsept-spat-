from flask import Flask, request, jsonify
import base64
import json

app = Flask(__name__)


@app.route("/me", methods=["GET"])
def get_current_user():
    """
    JWT token'dan kullanici bilgilerini doner.
    Veritabanina gitmez - tamamen stateless.
    Kong zaten token'i dogruladi, biz sadece claims'leri okuyoruz.
    """
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return jsonify({"error": "Token bulunamadi"}), 401

    token = auth_header.split(" ")[1]

    try:
        # JWT yapisi: header.payload.signature
        # Payload kismini decode et (base64url)
        payload_b64 = token.split(".")[1]

        # Base64url padding ekle
        padding = 4 - len(payload_b64) % 4
        if padding != 4:
            payload_b64 += "=" * padding

        claims = json.loads(base64.urlsafe_b64decode(payload_b64))

        return jsonify({
            "user_id": claims.get("sub"),
            "username": claims.get("preferred_username"),
            "email": claims.get("email"),
            "first_name": claims.get("given_name"),
            "last_name": claims.get("family_name"),
            "full_name": claims.get("name"),
            "roles": claims.get("realm_access", {}).get("roles", []),
            "client_roles": claims.get("resource_access", {}),
            "scope": claims.get("scope"),
            "token_issuer": claims.get("iss"),
        })

    except Exception as e:
        return jsonify({"error": f"Token decode hatasi: {str(e)}"}), 400


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "up", "service": "account-service"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

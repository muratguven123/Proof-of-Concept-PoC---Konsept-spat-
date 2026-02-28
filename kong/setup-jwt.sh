#!/bin/bash
# =============================================================
#  Kong JWT Dogrulama Kurulum Scripti
#
#  Bu script Keycloak'ta realm olusturduktan sonra calistirilir.
#  Keycloak'tan public key'i alir ve Kong'a JWT dogrulama ekler.
#
#  Kullanim: ./kong/setup-jwt.sh [realm-adi]
#  Ornek:    ./kong/setup-jwt.sh orion-realm
# =============================================================

set -e

KONG_ADMIN="http://localhost:8001"
KONG_PROXY="http://localhost:8000"
KEYCLOAK_DIRECT="http://localhost:8080"
REALM="${1:-orion-realm}"

echo ""
echo "============================================"
echo "  Kong JWT Dogrulama Kurulumu"
echo "============================================"
echo ""

# ------------------------------------------
# 1. Kong kontrolu
# ------------------------------------------
echo "[1/4] Kong kontrol ediliyor..."
if ! curl -s "$KONG_ADMIN/status" > /dev/null 2>&1; then
    echo "  HATA: Kong calismiyor!"
    echo "  Once calistirin: docker-compose up -d"
    exit 1
fi
echo "  OK - Kong calisiyor."

# ------------------------------------------
# 2. Keycloak realm kontrolu
# ------------------------------------------
echo "[2/4] Keycloak '$REALM' realm kontrol ediliyor..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$KEYCLOAK_DIRECT/realms/$REALM")

if [ "$HTTP_CODE" != "200" ]; then
    echo "  HATA: '$REALM' realm bulunamadi (HTTP $HTTP_CODE)!"
    echo ""
    echo "  Keycloak Admin Console'a gidin ve realm olusturun:"
    echo "    URL:       $KEYCLOAK_DIRECT"
    echo "    Kullanici: admin"
    echo "    Sifre:     admin"
    echo ""
    echo "  Realm olusturduktan sonra bu scripti tekrar calistirin."
    exit 1
fi
echo "  OK - '$REALM' realm bulundu."

# ------------------------------------------
# 3. Public key ve issuer bilgilerini al
# ------------------------------------------
echo "[3/4] Public key ve issuer aliniyor..."

# Public key'i Keycloak'tan al
PUBLIC_KEY_RAW=$(curl -s "$KEYCLOAK_DIRECT/realms/$REALM" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['public_key'])" 2>/dev/null)

if [ -z "$PUBLIC_KEY_RAW" ]; then
    echo "  HATA: Public key alinamadi!"
    echo "  python3 yuklu oldugundan emin olun."
    exit 1
fi

# Issuer'i Kong uzerinden al (preserve_host sayesinde dogru issuer doner)
ISSUER=$(curl -s "$KONG_PROXY/auth/realms/$REALM/.well-known/openid-configuration" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['issuer'])" 2>/dev/null)

if [ -z "$ISSUER" ]; then
    echo "  UYARI: Kong uzerinden issuer alinamadi, dogrudan Keycloak'tan aliniyor..."
    ISSUER=$(curl -s "$KEYCLOAK_DIRECT/realms/$REALM/.well-known/openid-configuration" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['issuer'])" 2>/dev/null)
fi

if [ -z "$ISSUER" ]; then
    echo "  HATA: Issuer alinamadi!"
    exit 1
fi

# PEM formatina cevir (64 karakter satirlar)
PEM_LINES=$(echo "$PUBLIC_KEY_RAW" | fold -w 64)

echo "  Issuer: $ISSUER"
echo "  Public Key: ${PUBLIC_KEY_RAW:0:30}..."

# ------------------------------------------
# 4. Kong config olustur ve yukle
# ------------------------------------------
echo "[4/4] Kong yapilandirmasi guncelleniyor..."

CONFIG_FILE=$(mktemp)

cat > "$CONFIG_FILE" << YAML
_format_version: "3.0"

consumers:
  - username: keycloak-consumer
    jwt_secrets:
      - key: "$ISSUER"
        algorithm: RS256
        rsa_public_key: |
          -----BEGIN PUBLIC KEY-----
$(echo "$PEM_LINES" | sed 's/^/          /')
          -----END PUBLIC KEY-----

services:
  # Keycloak - Token endpoint (Kong uzerinden)
  - name: keycloak-service
    url: http://keycloak:8080
    routes:
      - name: keycloak-route
        paths:
          - /auth
        strip_path: true
        preserve_host: true

  # Account Service - JWT dogrulama ile korunan
  - name: account-service
    url: http://account-service:5000
    routes:
      - name: account-route
        paths:
          - /account
        strip_path: true
    plugins:
      - name: jwt
        config:
          key_claim_name: iss
          claims_to_verify:
            - exp
YAML

# Kong'a yeni config'i yukle
RESULT=$(curl -s -w "\n%{http_code}" -X POST "$KONG_ADMIN/config" \
    -F "config=@$CONFIG_FILE")
HTTP_CODE=$(echo "$RESULT" | tail -1)

rm -f "$CONFIG_FILE"

if [ "$HTTP_CODE" = "201" ]; then
    echo "  OK - Yapilandirma yuklendi."
    echo ""
    echo "============================================"
    echo "  KURULUM BASARILI!"
    echo "============================================"
    echo ""
    echo "  Postman'de test edin:"
    echo ""
    echo "  1) TOKEN AL:"
    echo "     POST $KONG_PROXY/auth/realms/$REALM/protocol/openid-connect/token"
    echo "     Body (x-www-form-urlencoded):"
    echo "       client_id    = <client_id>"
    echo "       grant_type   = password"
    echo "       username     = <kullanici_adi>"
    echo "       password     = <sifre>"
    echo ""
    echo "  2) KIM OLDUGUNU OGREN (stateless):"
    echo "     GET $KONG_PROXY/account/me"
    echo "     Headers:"
    echo "       Authorization: Bearer <token>"
    echo ""
    echo "  3) TOKEN OLMADAN DENE (401 donmeli):"
    echo "     GET $KONG_PROXY/account/me"
    echo ""
    echo "  ONEMLI: Token her zaman Kong uzerinden (port 8000)"
    echo "  alinmalidir. Dogrudan Keycloak'tan (port 8080) alinan"
    echo "  tokenlar farkli issuer icerdigi icin reddedilecektir."
    echo ""
else
    echo "  HATA: Kong yapilandirmasi yuklenemedi (HTTP $HTTP_CODE)"
    BODY=$(echo "$RESULT" | head -n -1)
    echo "  $BODY"
    exit 1
fi

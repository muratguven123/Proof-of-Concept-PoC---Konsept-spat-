# Orion PoC - API Gateway ile Stateless Kimlik Dogrulama

Keycloak + Kong API Gateway + Account Service kullanarak, veritabanina gitmeden
JWT token uzerinden kullanici kimligini dogrulayan bir Proof of Concept projesi.

## Mimari

```
                         ┌─────────────────────────────────────────┐
                         │        Kong API Gateway (:8000)         │
                         │                                         │
  Client (Postman)  ──►  │  /auth/*     ──►  Keycloak (token al)  │
                         │  /account/*  ──►  Account Service       │
                         │      │                                  │
                         │      ▼                                  │
                         │  JWT Dogrulama                          │
                         │  (Keycloak Public Key ile)              │
                         └─────────────────────────────────────────┘
                              │                     │
                              ▼                     ▼
                    ┌──────────────────┐  ┌────────────────────┐
                    │    Keycloak      │  │  Account Service   │
                    │    (:8080)       │  │  (:5000)           │
                    │                  │  │                    │
                    │  Token uretir    │  │  JWT decode eder   │
                    │  Public key      │  │  DB yok!           │
                    │  saglar          │  │  Tamamen stateless │
                    └──────────────────┘  └────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   PostgreSQL     │
                    │   (:5432)        │
                    │                  │
                    │   Sadece         │
                    │   Keycloak icin  │
                    └──────────────────┘
```

## Temel Konsept

**Stateless Kimlik Dogrulama:** Kullanicinin kim oldugunu anlamak icin veritabanina
gitmiyoruz. JWT token zaten kullanicinin tum bilgilerini (ID, isim, email, roller)
icinde tasiyor. Kong token'i Keycloak'in public key'i ile dogruladiktan sonra,
Account Service sadece token'i decode ederek kullanici bilgisini donuyor.

## Servisler

| Servis | Port | Gorev |
|--------|------|-------|
| **Kong API Gateway** | 8000 | Tum istekleri yonlendirir, JWT dogrular |
| **Kong Admin API** | 8001 | Kong yapilandirma API'si |
| **Keycloak** | 8080 | Token uretir, kullanici yonetimi |
| **Account Service** | 5000 (dahili) | JWT'den kullanici bilgisi cikarir |
| **PostgreSQL** | 5432 | Sadece Keycloak veritabani |

## Kurulum

### Gereksinimler

- Docker & Docker Compose
- curl
- python3

### 1. Container'lari Baslat

```bash
docker-compose up -d
```

### 2. Keycloak Yapilandirmasi

Keycloak Admin Console'a gidin: http://localhost:8080

**Giris:** admin / admin

#### Realm Olustur
1. Sol ust koseden "Create Realm" tiklayin
2. Realm name: `orion-realm`
3. "Create" tiklayin

#### Client Olustur
1. Clients > "Create client"
2. Client ID: `orion-client`
3. Client authentication: **OFF** (public client)
4. Valid redirect URIs: `*`
5. "Save"

#### Test Kullanicisi Olustur
1. Users > "Add user"
2. Username: `testuser`
3. Email: `test@orion.com`
4. First name: `Test`, Last name: `User`
5. "Create"
6. Credentials sekmesi > "Set password"
7. Password: `123456`, Temporary: **OFF**
8. "Save"

### 3. JWT Dogrulamayi Aktif Et

```bash
./kong/setup-jwt.sh orion-realm
```

Bu script:
- Keycloak'tan RSA public key'i alir
- Kong'a JWT dogrulama plugin'i yukler
- `/account/*` endpoint'ini koruma altina alir

## Postman ile Test

### 1) Token Al

```
POST http://localhost:8000/auth/realms/orion-realm/protocol/openid-connect/token

Body (x-www-form-urlencoded):
  client_id    = orion-client
  grant_type   = password
  username     = testuser
  password     = 123456
```

Yanit:
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 300
}
```

### 2) Kullanici Bilgisini Al (Stateless)

```
GET http://localhost:8000/account/me

Headers:
  Authorization: Bearer <access_token>
```

Yanit (veritabanina gitmeden, sadece JWT'den):
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "testuser",
  "email": "test@orion.com",
  "first_name": "Test",
  "last_name": "User",
  "full_name": "Test User",
  "roles": ["default-roles-orion-realm", "uma_authorization"],
  "scope": "openid profile email"
}
```

### 3) Token Olmadan Dene (401 Beklenir)

```
GET http://localhost:8000/account/me
```

Yanit:
```json
{
  "message": "Unauthorized"
}
```

## Proje Yapisi

```
.
├── docker-compose.yaml        # Tum servislerin tanimi
├── kong/
│   ├── kong.yml               # Kong declarative config (DB-less)
│   └── setup-jwt.sh           # JWT dogrulama kurulum scripti
├── account-service/
│   ├── app.py                 # Flask API - JWT decode
│   ├── requirements.txt       # Python bagimliklar
│   └── Dockerfile             # Container tanimi
└── README.md
```

## Nasil Calisiyor?

```
1. Client, Kong uzerinden Keycloak'tan token alir
   POST :8000/auth/realms/orion-realm/protocol/openid-connect/token
                    │
                    ▼
2. Keycloak, JWT token uretir (RSA256 ile imzalar)
   Token icinde: sub, username, email, roles, exp, iss
                    │
                    ▼
3. Client, token ile Account Service'e istek atar
   GET :8000/account/me  +  Authorization: Bearer <token>
                    │
                    ▼
4. Kong, JWT'yi Keycloak'in public key'i ile dogrular
   - Imza gecerli mi?
   - Token suresi dolmus mu? (exp claim)
   - Issuer dogru mu? (iss claim)
                    │
                    ▼
5. Dogrulama basariliysa, istek Account Service'e iletilir
                    │
                    ▼
6. Account Service, JWT payload'ini decode eder (base64)
   - Veritabanina GITMEZ
   - Kripto dogrulama YAPMAZ (Kong zaten yapti)
   - Sadece claims'leri okur ve JSON olarak doner
```

## Notlar

- **Kong DB-less mod:** Kong kendi veritabanini kullanmaz, yapilandirma dosyadan yuklenir
- **Token her zaman Kong uzerinden alinmali:** Dogrudan Keycloak'tan (port 8080)
  alinan tokenlar farkli `iss` claim'i icerdiginden Kong tarafindan reddedilir
- **setup-jwt.sh tekrar calistirilabilir:** Keycloak'in public key'i degisirse
  scripti tekrar calistirmak yeterlidir

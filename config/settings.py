import os
from pathlib import Path
from dotenv import load_dotenv
from mongoengine import connect

# --------------------------------------------------
# Base
# --------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

# --------------------------------------------------
# Security / Debug
# --------------------------------------------------
SECRET_KEY = os.getenv("SECRET_KEY", "django-insecure-dev-key")

DEBUG = os.getenv("DEBUG", "True") == "True"

ALLOWED_HOSTS = os.getenv(
    "ALLOWED_HOSTS", "127.0.0.1,localhost"
).split(",")

# --------------------------------------------------
# Applications
# --------------------------------------------------
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",

    "rest_framework",

    "apps.accounts",
    "apps.monitoring",
]

# --------------------------------------------------
# Middleware
# --------------------------------------------------
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

# --------------------------------------------------
# URLs / WSGI
# --------------------------------------------------
ROOT_URLCONF = "config.urls_config"

WSGI_APPLICATION = "config.wsgi.application"

# --------------------------------------------------
# Templates (required even if API-only)
# --------------------------------------------------
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

# --------------------------------------------------
# Database (MongoDB via MongoEngine)
# --------------------------------------------------
MONGODB_URI = os.getenv(
    "MONGODB_URI", "mongodb://localhost:27017/sava"
)

connect(
    host=MONGODB_URI,
    uuidRepresentation="standard"
)

# --------------------------------------------------
# Static files
# --------------------------------------------------
STATIC_URL = "/static/"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AI_SERVER_URL = os.getenv("AI_SERVER_URL", "http://127.0.0.1:5000")
AI_FACE_ENDPOINT = os.getenv("AI_FACE_ENDPOINT", "/analyze-face")

FACE_UNKNOWN_THRESHOLD = float(os.getenv("FACE_UNKNOWN_THRESHOLD", "0.80"))
ALERT_COOLDOWN_SECONDS = int(os.getenv("ALERT_COOLDOWN_SECONDS", "60"))
print("DJANGO MONGODB_URI =", MONGODB_URI)

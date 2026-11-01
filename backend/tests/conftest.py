import os

os.environ.setdefault("GOLDBRAIN_ENVIRONMENT", "test")
os.environ.setdefault("GOLDBRAIN_DATABASE_URL", "sqlite:///./data/test_goldbrain.db")
os.environ.setdefault("GOLDBRAIN_AUTO_CREATE_TABLES", "false")
# Tests must never consume a developer's trial quota or expose an inherited
# provider key in a failed mock request URL.
os.environ["NAVASAN_API_KEY"] = ""
os.environ["COINGECKO_DEMO_API_KEY"] = ""
# No test may inherit real SMTP credentials or accidentally send email.
os.environ["GOLDBRAIN_SMTP_HOST"] = ""
os.environ["GOLDBRAIN_SMTP_PASSWORD"] = ""

import os

os.environ["JWT_SECRET_KEY"] = "pytest-only-secret-key-long-enough-for-hs256"

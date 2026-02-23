import os
from huggingface_hub import snapshot_download

REPO_ID = "apple/coreml-mobileclip"
MODELS = ["clip_text_s1.mlpackage", "clip_image_s1.mlpackage"]
DEST_DIR = "MiniClone/Models"

os.makedirs(DEST_DIR, exist_ok=True)

for model_name in MODELS:
    print(f"Downloading {model_name}...")
    
    # mlpackage is a directory, so we need to download the folder contents
    snapshot_download(
        repo_id=REPO_ID,
        allow_patterns=f"{model_name}/**",
        local_dir=DEST_DIR,
        local_dir_use_symlinks=False
    )
    print(f"Successfully downloaded {model_name} to {DEST_DIR}")

print("All models downloaded successfully.")

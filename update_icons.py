import os
from PIL import Image

logo_path = os.path.join("assets", "banadana_logo.png")
if not os.path.exists(logo_path):
    print(f"Error: {logo_path} does not exist")
    exit(1)

img = Image.open(logo_path)
print(f"Loaded logo: {img.size}, mode: {img.mode}")

# Android standard mipmap sizes
sizes = {
    "mipmap-mdpi": (48, 48),
    "mipmap-hdpi": (72, 72),
    "mipmap-xhdpi": (96, 96),
    "mipmap-xxhdpi": (144, 144),
    "mipmap-xxxhdpi": (192, 192),
}

res_dir = os.path.join("android", "app", "src", "main", "res")

for folder, size in sizes.items():
    target_dir = os.path.join(res_dir, folder)
    os.makedirs(target_dir, exist_ok=True)
    target_file = os.path.join(target_dir, "ic_launcher.png")
    
    # Resize with high quality LANCZOS filter
    resized = img.resize(size, Image.Resampling.LANCZOS)
    resized.save(target_file, "PNG")
    print(f"Saved {target_file} ({size[0]}x{size[1]})")

print("All Android launcher icons updated successfully!")

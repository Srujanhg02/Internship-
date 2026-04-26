"""
Export YOLOv8n (fine-tuned for license plates) to TFLite format.
Uses the ultralytics package with the keremberke plate detection weights.
Falls back to base yolov8n if plate-specific weights unavailable.
"""
from ultralytics import YOLO
import os, shutil

MODEL_NAME = "keremberke/yolov8n-license-plate-detection"
OUT_DIR = r"c:\Users\sruja\TKAP_1\assets\models"
OUT_FILE = os.path.join(OUT_DIR, "plate_detector.tflite")

os.makedirs(OUT_DIR, exist_ok=True)

print("Loading YOLOv8n license plate detection model...")
try:
    model = YOLO(MODEL_NAME)
    print("Loaded keremberke plate model.")
except Exception as e:
    print(f"Could not load plate model ({e}), using base yolov8n...")
    model = YOLO("yolov8n.pt")

print("Exporting to TFLite (int8 quantized, 320x320)...")
export_path = model.export(
    format="tflite",
    imgsz=320,
    int8=False,   # float32 for maximum compatibility
    nms=False,    # raw output — we handle NMS in Dart
)
print(f"Exported to: {export_path}")

# Move the exported .tflite to our assets folder
for root, dirs, files in os.walk("."):
    for f in files:
        if f.endswith(".tflite"):
            src = os.path.join(root, f)
            shutil.copy(src, OUT_FILE)
            print(f"Copied {src} -> {OUT_FILE}")
            break

print("Done!")

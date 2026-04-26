"""
Convert YOLO ONNX → TFLite using ORT backend for TF, avoiding PyFunc ops.
Uses onnxruntime's tensorflow backend which generates proper TF ops.
"""
import numpy as np
import os, shutil, subprocess, sys

OUT_DIR = r"c:\Users\sruja\TKAP_1\assets\models"
OUT_FILE = os.path.join(OUT_DIR, "plate_detector.tflite")
IMGSZ = 320

os.makedirs(OUT_DIR, exist_ok=True)

#── Step 1: Export YOLO to ONNX with correct format ─────────────────────────
print("[1/3] Exporting YOLOv8n to ONNX...")

import torch, warnings
from ultralytics import YOLO

model = YOLO("yolov8n.pt")
pytorch_model = model.model.eval()
dummy = torch.zeros(1, 3, IMGSZ, IMGSZ)

ONNX_PATH = os.path.join(OUT_DIR, "temp.onnx")

# Use ultralytics' own .export() which handles all the right ONNX settings
import contextlib
from io import StringIO
# Redirect stdout to suppress ultralytics banner
with contextlib.redirect_stdout(StringIO()):
    result = model.export(format='onnx', imgsz=IMGSZ, simplify=True)
print(f"   ✅ ONNX at: {result}")

# Copy to our temp path
shutil.copy(str(result), ONNX_PATH)

#── Step 2: Validate ONNX ───────────────────────────────────────────────────
print("[2/3] Validating ONNX with onnxruntime...")
import onnxruntime as ort
sess = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
dummy_np = np.zeros((1, 3, IMGSZ, IMGSZ), dtype=np.float32)
out = sess.run(None, {sess.get_inputs()[0].name: dummy_np})
print(f"   Output shape: {out[0].shape}")

#── Step 3: TFLite via subprocess tf2onnx pipeline ──────────────────────────
print("[3/3] Trying tf2onnx saved_model → TFLite route...")

# Install tf2onnx if needed
subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q", "tf2onnx"],
    capture_output=True
)

SAVED_MODEL_DIR = os.path.join(OUT_DIR, "saved_model")
result2 = subprocess.run([
    sys.executable, "-m", "tf2onnx.convert",
    "--onnx", ONNX_PATH,
    "--output", os.path.join(OUT_DIR, "out.onnx"),  # not what we want
    "--opset", "13",
], capture_output=True, text=True)

# Actually: use onnx_tf to convert onnx->SavedModel->TFLite
# Try installing an older compatible version of onnx-tf
subprocess.run(
    [sys.executable, "-m", "pip", "install", "-q", "onnx==1.14.1", "onnx-tf==1.10.0"],
    capture_output=True
)
try:
    from onnx_tf.backend import prepare
    import onnx
    onnx_model = onnx.load(ONNX_PATH)
    tf_rep = prepare(onnx_model, strict=False)
    tf_rep.export_graph(SAVED_MODEL_DIR)
    print(f"   ✅ TF SavedModel: {SAVED_MODEL_DIR}")

    import tensorflow as tf
    converter = tf.lite.TFLiteConverter.from_saved_model(SAVED_MODEL_DIR)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    with open(OUT_FILE, 'wb') as f:
        f.write(tflite_model)
    print(f"\n✅ Done! {os.path.getsize(OUT_FILE)/1e6:.1f} MB → {OUT_FILE}")
except Exception as e:
    print(f"   onnx-tf failed: {e}")
    print("   Falling back: using onnxruntime session packaged as custom TFLite op is unsupported.")
    print("   Alternative: use tflite_flutter with onnxruntime_flutter instead.")

# Cleanup
for p in [ONNX_PATH, SAVED_MODEL_DIR, os.path.join(OUT_DIR, "out.onnx")]:
    if os.path.isdir(p): shutil.rmtree(p, ignore_errors=True)
    elif os.path.isfile(p): os.remove(p)

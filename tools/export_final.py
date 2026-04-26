"""
All-in-one: PyTorch → ONNX → SavedModel → TFLite
"""
import numpy as np
import tensorflow as tf
import torch
import os, shutil

from ultralytics import YOLO

OUT_DIR = r"c:\Users\sruja\TKAP_1\assets\models"
OUT_FILE = os.path.join(OUT_DIR, "plate_detector.tflite")
ONNX_PATH = os.path.join(OUT_DIR, "temp.onnx")
SAVED_MODEL_PATH = os.path.join(OUT_DIR, "temp_saved_model")
IMGSZ = 320

os.makedirs(OUT_DIR, exist_ok=True)

# ── Step 1: Export YOLO to ONNX ──────────────────────
print("[1/3] Loading and exporting YOLOv8n to ONNX...")
model = YOLO("yolov8n.pt")
pytorch_model = model.model.eval()
dummy = torch.zeros(1, 3, IMGSZ, IMGSZ)
with torch.no_grad():
    _ = pytorch_model(dummy)

import warnings
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    torch.onnx.export(
        pytorch_model,
        dummy,
        ONNX_PATH,
        opset_version=18,
        input_names=["images"],
        output_names=["output0"],
    )
print(f"   ✅ ONNX saved: {ONNX_PATH}")

# ── Step 2: Create onnxruntime-backed SavedModel ──────
print("[2/3] Wrapping ONNX in TF SavedModel...")
import onnxruntime as ort

session = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
in_name  = session.get_inputs()[0].name
out_name = session.get_outputs()[0].name

def run_onnx(x: np.ndarray) -> np.ndarray:
    return session.run([out_name], {in_name: x})[0]

@tf.function(input_signature=[
    tf.TensorSpec(shape=(1, 3, IMGSZ, IMGSZ), dtype=tf.float32)
])
def infer(x):
    r = tf.numpy_function(run_onnx, [x], tf.float32)
    r.set_shape((1, 84, 2100))
    return r

module = tf.Module()
module.infer = infer
tf.saved_model.save(module, SAVED_MODEL_PATH)
print(f"   ✅ SavedModel saved: {SAVED_MODEL_PATH}")

# ── Step 3: Convert SavedModel → TFLite ───────────────
print("[3/3] Converting SavedModel → TFLite...")
converter = tf.lite.TFLiteConverter.from_saved_model(SAVED_MODEL_PATH)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

with open(OUT_FILE, 'wb') as f:
    f.write(tflite_model)

size_mb = os.path.getsize(OUT_FILE) / (1024 * 1024)
print(f"\n✅ Done! plate_detector.tflite = {size_mb:.1f} MB")
print(f"   Location: {OUT_FILE}")

# Cleanup temp files
for p in [ONNX_PATH, SAVED_MODEL_PATH]:
    if os.path.isdir(p):
        shutil.rmtree(p, ignore_errors=True)
    elif os.path.isfile(p):
        os.remove(p)

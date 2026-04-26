"""
Alternative TFLite export: PyTorch → ONNX → TFLite using tensorflow directly.
Does not require onnx2tf.
"""
import torch
import tensorflow as tf
import numpy as np
import os
import shutil

from ultralytics import YOLO

OUT_DIR = r"c:\Users\sruja\TKAP_1\assets\models"
OUT_FILE = os.path.join(OUT_DIR, "plate_detector.tflite")
IMGSZ = 320

os.makedirs(OUT_DIR, exist_ok=True)

print("[1/4] Loading YOLOv8n model...")
model = YOLO("yolov8n.pt")
pytorch_model = model.model.eval()

print("[2/4] Tracing model to TorchScript...")
dummy = torch.zeros(1, 3, IMGSZ, IMGSZ)
with torch.no_grad():
    _ = pytorch_model(dummy)

print("[3/4] Exporting to ONNX (via ultralytics)...")
onnx_path = "yolov8n_temp.onnx"
torch.onnx.export(
    pytorch_model,
    dummy,
    onnx_path,
    opset_version=12,
    input_names=["images"],
    output_names=["output0"],
    dynamic_axes={"images": {0: "batch"}, "output0": {0: "batch"}},
)
print(f"   ONNX saved: {onnx_path}")

print("[4/4] Converting ONNX → TFLite via tensorflow...")
# Use tf2onnx approach via subprocess if direct not available
try:
    import onnx
    import onnxruntime as ort
    session = ort.InferenceSession(onnx_path)
    dummy_np = np.zeros((1, 3, IMGSZ, IMGSZ), dtype=np.float32)
    outputs = session.run(None, {"images": dummy_np})
    print(f"   ONNX Runtime test: output shape = {outputs[0].shape}")
except Exception as e:
    print(f"   ONNX test failed: {e}")

# Create a simple TFLite model wrapping the ONNX via tensorflow's ONNX support
try:
    # Try subprocess approach with tf2onnx
    import subprocess
    result = subprocess.run([
        "python", "-m", "tf2onnx.convert",
        "--onnx", onnx_path,
        "--output", "temp_saved_model",
        "--opset", "12"
    ], capture_output=True, text=True)
    print(result.stdout, result.stderr)
except Exception as e:
    print(f"tf2onnx failed: {e}")

# Try the direct TFLite lite interpreter route
try:
    from onnx_tf.backend import prepare
    import onnx as ox
    onnx_model = ox.load(onnx_path)
    tf_rep = prepare(onnx_model)
    tf_rep.export_graph("temp_tf_model")
    
    converter = tf.lite.TFLiteConverter.from_saved_model("temp_tf_model")
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    
    with open(OUT_FILE, 'wb') as f:
        f.write(tflite_model)
    print(f"   ✅ TFLite saved: {OUT_FILE} ({len(tflite_model)//1024} KB)")
except Exception as e:
    print(f"onnx-tf failed: {e}")

# Cleanup
for p in [onnx_path, "temp_tf_model", "temp_saved_model"]:
    if os.path.exists(p):
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
        else:
            os.remove(p)

if os.path.exists(OUT_FILE):
    size_mb = os.path.getsize(OUT_FILE) / (1024*1024)
    print(f"\n✅ Done! plate_detector.tflite = {size_mb:.1f} MB")
else:
    print("\n❌ TFLite file was not created.")

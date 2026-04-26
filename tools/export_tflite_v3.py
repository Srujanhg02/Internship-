"""
Convert ONNX model to TFLite using only tensorflow (no onnx2tf needed).
Uses: torch → ONNX (already done) → tf.saved_model via onnxruntime → TFLite
"""
import numpy as np
import tensorflow as tf
import os, shutil

OUT_DIR = r"c:\Users\sruja\TKAP_1\assets\models"
OUT_FILE = os.path.join(OUT_DIR, "plate_detector.tflite")
ONNX_PATH = "yolov8n_temp.onnx"
IMGSZ = 320

os.makedirs(OUT_DIR, exist_ok=True)

# We wrap the ONNX model using onnxruntime as a TF function, 
# then convert with TFLiteConverter.

class OnnxWrapper(tf.Module):
    """Wraps ONNX inference session as a tf.Module for TFLite conversion."""
    def __init__(self, onnx_path):
        import onnxruntime as ort
        self.session = ort.InferenceSession(onnx_path)
        self.input_name = self.session.get_inputs()[0].name

    @tf.function(input_signature=[
        tf.TensorSpec(shape=[1, 3, IMGSZ, IMGSZ], dtype=tf.float32, name='images')
    ])
    def __call__(self, images):
        # This path won't work for TFLite — need SavedModel path
        pass


# Better approach: use onnx-to tf via onnx_tf (fixed for older onnx API)
# Since onnx >= 1.17 changed mapping, we use onnxruntime directly with 
# a representative Keras wrapper.

print("[1/3] Creating Keras model that calls ONNX via numpy...")

import onnxruntime as ort

session = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
input_name = session.get_inputs()[0].name
output_name = session.get_outputs()[0].name

print(f"   Input: {input_name} {session.get_inputs()[0].shape}")
print(f"   Output: {output_name} {session.get_outputs()[0].shape}")

print("[2/3] Building and saving TF SavedModel wrapping onnxruntime...")

# Create a concrete tf.function that wraps onnxruntime
@tf.function(input_signature=[
    tf.TensorSpec(shape=(1, 3, IMGSZ, IMGSZ), dtype=tf.float32)
])
def inference(x):
    result = tf.numpy_function(
        func=lambda inp: session.run(
            [output_name], {input_name: inp.astype(np.float32)})[0],
        inp=[x],
        Tout=tf.float32,
    )
    result.set_shape((1, 84, 2100))
    return result

module = tf.Module()
module.inference = inference
save_path = "temp_saved_model"
tf.saved_model.save(module, save_path)
print(f"   ✅ SavedModel saved at {save_path}")

print("[3/3] Converting SavedModel → TFLite...")
converter = tf.lite.TFLiteConverter.from_saved_model(save_path)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

with open(OUT_FILE, 'wb') as f:
    f.write(tflite_model)

size_mb = os.path.getsize(OUT_FILE) / (1024 * 1024)
print(f"\n✅ Done! plate_detector.tflite = {size_mb:.1f} MB at {OUT_FILE}")

# Cleanup
shutil.rmtree(save_path, ignore_errors=True)

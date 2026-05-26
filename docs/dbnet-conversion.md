# DBNet (PaddleOCR) → TFLite — bundling guide

The camera pipeline ships with an opt-in DBNet text detector
([dbnet_text_detector.dart](../lib/core/camera/dbnet_text_detector.dart))
that runs as a safety-net pass over the ML Kit 4-pass result. It is a
no-op until you drop the converted model at
`assets/models/dbnet_paddleocr.tflite`. This guide is the conversion
recipe — once you have the `.tflite` file you bundle it as a regular
Flutter asset and the detector activates on next launch.

The reference model is PaddleOCR `ch_PP-OCRv4_det` (mobile, multi-script
CJK + Latin, Apache-2.0). The flow below converts it to TFLite via
ONNX, the most-supported intermediate format.

## 1. Pull the PaddleOCR detector

```bash
mkdir -p ~/work/paddle-to-tflite && cd $_
wget https://paddleocr.bj.bcebos.com/PP-OCRv4/chinese/ch_PP-OCRv4_det_infer.tar
tar -xf ch_PP-OCRv4_det_infer.tar
```

You should see `inference.pdmodel` and `inference.pdiparams`.

## 2. Convert Paddle → ONNX

```bash
pip install paddle2onnx==1.1.0 onnx==1.15.0
paddle2onnx \
  --model_dir ch_PP-OCRv4_det_infer \
  --model_filename inference.pdmodel \
  --params_filename inference.pdiparams \
  --save_file dbnet.onnx \
  --opset_version 13
```

## 3. Convert ONNX → TFLite

```bash
pip install -U onnx2tf tensorflow==2.16.* onnxsim
onnxsim dbnet.onnx dbnet_sim.onnx
onnx2tf -i dbnet_sim.onnx -o dbnet_tf -coion -nuo -kt
```

`-coion` keeps NHWC ordering (TFLite preference), `-nuo` removes useless
ops, `-kt` keeps tensor names. The output folder contains
`model_float32.tflite` — that is the file you want.

> Quantisation is optional. INT8 cuts the model ~3 MB → ~1 MB but
> drops recall a few percent on small text. Keep float32 for the first
> integration; quantise later once you have a baseline.

## 4. Drop into the app

```bash
cp dbnet_tf/model_float32.tflite \
   transkey-mobile/assets/models/dbnet_paddleocr.tflite
```

Then register the asset in `transkey-mobile/pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/dbnet_paddleocr.tflite
```

`flutter pub get` → rebuild. On next launch the detector logs
`[DbnetTextDetector] model loaded` and the safety-net pass starts firing.

## 5. Verify

Capture a dense menu the ML Kit pipeline used to mis-read. The
`[CameraService] DBNet filled in N region(s) ML Kit missed` log line
appears whenever DBNet caught real text ML Kit skipped. If the log
stays silent on captures where text is clearly missed, raise the
detector's `_kBinThreshold` and `_kUnclipRatio` tuning (defaults 0.3 /
1.5 match the published PaddleOCR config).

## Cost / size budget

| Asset | Size on disk |
|---|---|
| tflite_flutter native lib | ~2.5 MB (split per ABI) |
| dbnet_paddleocr.tflite (float32) | ~4 MB |
| dbnet_paddleocr.tflite (int8) | ~1.2 MB |

Inference latency on a Snapdragon 7+ Gen 2 mid-range device: ~180-280 ms
for a 960-px-long-side capture. The crop-and-recognise step adds
50-100 ms per uncovered region, fired only for the handful of boxes
ML Kit missed.

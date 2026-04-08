import sys
import cv2
import argparse
import numpy as np
import onnxruntime as ort
import yaml
import os

sys.stdout.reconfigure(line_buffering=True)

MODEL_W, MODEL_H = 360, 240


def load_pose_cfg(model_path):
    cfg_path = os.path.join(os.path.dirname(os.path.abspath(model_path)), "pose_cfg.yaml")
    stride = 8.0
    locref_stdev = 7.2801
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, "r") as f:
                cfg = yaml.safe_load(f)
            stride = float(cfg.get("stride", stride))
            locref_stdev = float(cfg.get("locref_stdev", locref_stdev))
        except Exception:
            pass
    return stride, locref_stdev


def process_frame(frame, H, W, field_offsets, scale_x, scale_y, sess, inp_name,
                  out_names, has_locref, MODEL_STRIDE, LOCREF_STDEV, frame_num):
    h2, w2 = H // 2, W // 2
    for i, (ox, oy) in enumerate(field_offsets):
        crop_bgr = frame[oy:oy + h2, ox:ox + w2]
        crop_rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
        if crop_rgb.shape[1] != MODEL_W or crop_rgb.shape[0] != MODEL_H:
            crop_rgb = cv2.resize(crop_rgb, (MODEL_W, MODEL_H))
        img_batch = np.expand_dims(crop_rgb.astype(np.float32), axis=0)

        results = sess.run(
            out_names[:2] if has_locref else out_names[:1],
            {inp_name: img_batch}
        )
        scoremap = results[0]
        locref = results[1] if has_locref else None
        heatmap_nose = scoremap[0, :, :, 0]
        heatmap_body = scoremap[0, :, :, 1] if scoremap.shape[3] > 1 else None

        # Nose
        _, p, _, peak = cv2.minMaxLoc(heatmap_nose)
        px, py = peak
        x = (px + 0.5) * MODEL_STRIDE
        y = (py + 0.5) * MODEL_STRIDE
        if locref is not None:
            x += locref[0, py, px, 0] * LOCREF_STDEV
            y += locref[0, py, px, 1] * LOCREF_STDEV
        if p > 0.05:
            sys.stdout.write(
                f"TRACK,{i},{x * scale_x + ox:.2f},{y * scale_y + oy:.2f},"
                f"{p:.4f},{frame_num}\n"
            )

        # Body
        if heatmap_body is not None:
            _, pb, _, peak_b = cv2.minMaxLoc(heatmap_body)
            pbx, pby = peak_b
            xb = (pbx + 0.5) * MODEL_STRIDE
            yb = (pby + 0.5) * MODEL_STRIDE
            if locref is not None:
                xb += locref[0, pby, pbx, 2] * LOCREF_STDEV
                yb += locref[0, pby, pbx, 3] * LOCREF_STDEV
            if pb > 0.05:
                sys.stdout.write(
                    f"BODY,{i},{xb * scale_x + ox:.2f},{yb * scale_y + oy:.2f},"
                    f"{pb:.4f},{frame_num}\n"
                )
    sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model",  default="Network-MemoryLab-v2.onnx")
    parser.add_argument("--video",  required=True)
    args = parser.parse_args()

    try:
        sess = ort.InferenceSession(args.model, providers=['CPUExecutionProvider'])
    except Exception as e:
        sys.stdout.write(f"ERRO,Falha ao carregar o modelo ONNX: {e}\n")
        return

    inp_name = sess.get_inputs()[0].name
    out_names = [o.name for o in sess.get_outputs()]
    has_locref = len(out_names) >= 2
    MODEL_STRIDE, LOCREF_STDEV = load_pose_cfg(args.model)

    source = int(args.video) if args.video.isdigit() else args.video
    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        sys.stdout.write("ERRO,Nao foi possivel abrir o video.\n")
        return

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    sys.stdout.write(f"FPS,{fps:.4f}\n")
    sys.stdout.flush()

    ret, first = cap.read()
    if not ret:
        return
    H, W = first.shape[:2]
    h2, w2 = H // 2, W // 2

    field_offsets = [(0, 0), (w2, 0), (0, h2)]
    scale_x = w2 / MODEL_W
    scale_y = h2 / MODEL_H

    sys.stdout.write(f"DIMS,{W},{H}\n")
    sys.stdout.write("READY\n")
    sys.stdout.flush()

    # Reset to frame 0 — the first cap.read() above was only to get dimensions
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    frame_num = 0

    while frame_num < total_frames:
        ret, frame = cap.read()
        if not ret:
            break

        process_frame(frame, H, W, field_offsets, scale_x, scale_y, sess,
                      inp_name, out_names, has_locref, MODEL_STRIDE, LOCREF_STDEV,
                      frame_num)

        frame_num += 1

    sys.stdout.write("FIM\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()

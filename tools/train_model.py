#!/usr/bin/env python3
"""
Treina o modelo de deteção de falhas para a app e exporta-o para TFLite.

Requisitos (num PC; com GPU NVIDIA é muito mais rápido, mas CPU também serve):
    pip install ultralytics

Dataset: qualquer dataset em formato YOLO (pasta com data.yaml), por exemplo
um dataset de "spaghetti" do Roboflow Universe exportado como "YOLOv8".
Recomendado: juntar fotos da TUA câmara da CC1 (boas e com falhas) e
etiquetá-las. É isso que mais reduz os falsos alarmes.

Uso:
    python tools/train_model.py --data caminho/para/data.yaml
    python tools/train_model.py --data data.yaml --epochs 120 --imgsz 320

No fim copia o modelo e as etiquetas para assets/ai/ automaticamente.
"""
import argparse
import glob
import os
import shutil

from ultralytics import YOLO

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "ai")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="data.yaml do dataset YOLO")
    ap.add_argument("--epochs", type=int, default=80)
    ap.add_argument("--imgsz", type=int, default=320,
                    help="320 é rápido no telemóvel; 640 é mais preciso mas mais lento")
    ap.add_argument("--base", default="yolov8n.pt", help="modelo base (n = mais leve)")
    args = ap.parse_args()

    model = YOLO(args.base)
    model.train(data=args.data, epochs=args.epochs, imgsz=args.imgsz, batch=16,
                patience=20, project=os.path.join(ROOT, "runs"), name="failure")
    best = model.trainer.best
    print(f"\nMelhor modelo: {best}")

    trained = YOLO(best)
    trained.export(format="tflite", imgsz=args.imgsz)  # gera *_saved_model/*_float32.tflite

    exported = glob.glob(os.path.join(os.path.dirname(best), "*_saved_model", "*_float32.tflite"))
    if not exported:
        raise SystemExit("Exportação TFLite não encontrada — vê os logs acima.")
    os.makedirs(ASSETS, exist_ok=True)
    shutil.copy(exported[0], os.path.join(ASSETS, "failure.tflite"))

    names = trained.names
    labels = [names[i] for i in sorted(names)]
    with open(os.path.join(ASSETS, "labels.txt"), "w") as f:
        f.write("\n".join(labels) + "\n")

    print(f"\nCopiado para {ASSETS}/failure.tflite")
    print(f"Classes: {labels}")
    print("Agora corre 'flutter run' — a Vigilância IA fica disponível.")


if __name__ == "__main__":
    main()

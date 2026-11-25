# Modelo da Vigilância IA

A app procura aqui dois ficheiros:

- `failure.tflite`: o modelo YOLO (v5 ou v8) exportado para TFLite.
- `labels.txt`: uma classe por linha, pela ordem do treino (ex.: `spaghetti`).

Sem eles, a app funciona normalmente, mas o interruptor da Vigilância IA fica desativado.

## Como obter o modelo

1. Arranja um dataset de falhas em formato YOLO. Há vários gratuitos no Roboflow Universe (procura "3d print spaghetti"). Exporta-o como **YOLOv8**.
2. Junta-lhe fotos da tua câmara da CC1. É o passo que mais melhora o resultado, porque o ângulo e a luz da tua câmara são diferentes dos do dataset. Tira screenshots na app durante impressões boas e más e etiqueta-as no Roboflow.
3. Treina e exporta:
   ```bash
   pip install ultralytics
   python tools/train_model.py --data caminho/para/data.yaml
   ```
   O script copia `failure.tflite` e `labels.txt` para esta pasta.

As classes que descrevem a peça ou o extrusor (`part`, `extruder`, `nozzle`…) são ignoradas. Todas as outras contam como falha.

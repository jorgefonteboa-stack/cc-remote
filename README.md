# CC Remote — app para a Elegoo Centauri Carbon (CC1)

App Flutter (Android + iPhone) ao estilo do Bambu Handy:

- **Descoberta** da impressora na rede (UDP 3000, `M99999`) ou por IP.
- **Câmara ao vivo** (MJPEG, porta 3031).
- **Estado em tempo real**: progresso, camada, tempo restante, temperaturas.
- **Controlos**: pausa, retomar, stop (com confirmação), luz, lista de ficheiros e iniciar impressão.
- **Slicing no telemóvel**: escolhes um `.stl`, ajustas material, camada, paredes, enchimento e suportes. O G-code é gerado no próprio telemóvel e enviado para a impressora, que começa a imprimir.

- **CANVAS**: o painel mostra os 4 slots (cor, material, intervalo de temperatura e slot ativo). No ecrã de slicing, o botão **"Configurar pela máquina"** lê os slots, escolhe o filamento ativo e ajusta material e temperaturas. Tocar noutro slot imprime com esse.

- **Vigilância IA**: durante a impressão, um modelo YOLO analisa a câmara no telemóvel a cada 10 s. Se detetar a mesma falha em várias verificações seguidas (esparguete, peça descolada…), **pausa a impressora**, envia uma notificação e mostra a imagem com as opções "Falso alarme, retomar" e "Parar impressão".

- **Cancelar objetos**: com várias peças na mesa, mostra um mapa com cada objeto e permite cancelar só o que está a correr mal. Os outros continuam. A app deteta sozinha se a impressora suporta esta função:
  - **Klipper/Moonraker** (Creality, Sovol, Voron, CC1 com o firmware COSMOS…): ✅ compatível. No slicer, ativa "Exclude objects" (em Outros).
  - **Firmware oficial Elegoo (CC1 V1.4.49):** mostra "Não compatível". O módulo existe no código-fonte publicado pela Elegoo, mas não está ativo nem tem comando de rede.

Tudo funciona na rede local, sem cloud. A comunicação usa o protocolo SDCP v3 (WebSocket `ws://IP:3030/websocket`), documentado pelo projeto OpenCentauri.

## Instalar no Android (sem programar)

Cada alteração ao código gera automaticamente uma app nova. Abre no telemóvel a página **Releases** deste repositório, toca em **CC-Remote.apk** e instala.

O ficheiro `tools/web/CC1-Controlo.html` é uma versão de controlo que abre no browser de um computador, sem instalar nada.

## Arrancar (para quem programa)

Requisitos: Flutter 3.22+, Android Studio (para Android) e Xcode num Mac (para iPhone).

```bash
cd cc_remote
chmod +x setup.sh && ./setup.sh   # gera android/ e ios/ e aplica as permissões
flutter run                        # com o telemóvel ligado por USB
```

O telemóvel tem de estar na **mesma rede Wi-Fi** que a impressora.

## Estrutura

```
lib/
  main.dart
  printer/
    sdcp_client.dart     # descoberta, WebSocket SDCP, comandos, upload
    printer_status.dart  # parsing do estado
  slicer/
    slicer.dart          # interface do slicer + parâmetros
    kiri_slicer.dart     # motor Kiri:Moto num WebView invisível
  ui/
    home_screen.dart     # procurar / ligar por IP
    printer_screen.dart  # câmara, estado, controlos
    slice_screen.dart    # escolher STL → slicing → enviar e imprimir
    mjpeg_view.dart      # leitor MJPEG sem dependências
  ai/
    failure_detector.dart  # modelo YOLO TFLite no telemóvel
    print_guard.dart       # decisão (limites, suspeitas seguidas) e pausa
    notifier.dart          # notificações locais
assets/slicer/slicer.html  # ponte JS ↔ Dart e perfil da CC1
assets/ai/                 # failure.tflite + labels.txt (gerados pelo treino)
tools/train_model.py       # treino e exportação do modelo
```

## Coisas a validar com a impressora real

Também confirmados (V1.4.49): ligação SDCP, câmara (Cmd 386 devolve o `VideoUrl` sem `http://`, e o código já trata disso) e lista de ficheiros (Cmd 258, nomes com o prefixo `/local/`).

O código não foi compilado nem testado contra uma CC1. Estes pontos dependem do firmware e é aqui que vais ter de afinar:

| O quê | Onde | Nota |
|---|---|---|
| Comando da luz | `SdcpClient.setLight` | ✅ Confirmado (V1.4.49): Cmd 403 com `LightStatus`. |
| Nome do ficheiro ao iniciar | `SdcpClient.startPrint` | Envia só o nome. Se falhar, experimenta `/local/nome.gcode`. |
| Campos do upload | `SdcpClient.upload` | Vão como campos multipart. Se a impressora rejeitar, envia-os também como cabeçalhos HTTP. |
| Códigos de estado e tempo | `PrintInfo.label`, `remaining` | Os códigos e as unidades dos "ticks" vêm de observações da comunidade. |
| Leitura do CANVAS | `SdcpClient.readCanvas` | ✅ Confirmado (V1.4.49): os dados vêm na própria resposta ao Cmd 324. |
| Escolha do slot | `slicer.html` (insere `T<n>`) | Confirma que a CC1 aceita `T<n>` nesse ponto do G-code. Se não aceitar, compara com um G-code multicor exportado pelo ElegooSlicer. |
| G-code inicial e final | `assets/slicer/slicer.html` → `CC1_DEVICE` | É genérico. Compara com o perfil CC1 do ElegooSlicer (bed mesh, purga, etc.) antes de imprimir peças importantes. |

Dica: o `pycentauri` (`pip install pycentauri`) e a integração `elegoo-homeassistant` são boas referências para confirmar comandos.

## Vigilância IA

**Como decide:** cada verificação dá uma confiança de falha entre 0 e 100%. Só conta como suspeita acima do limite da sensibilidade escolhida, e só pausa quando há várias suspeitas seguidas. Assim, um reflexo ou o braço do extrusor num frame não param a impressão.

| Sensibilidade | Limite | Suspeitas seguidas | Tempo até pausar |
|---|---|---|---|
| Baixa | 70% | 4 | ~40 s |
| Média | 55% | 3 | ~30 s |
| Alta | 40% | 2 | ~20 s |

Só vigia com a impressora no estado "a imprimir" (não durante o aquecimento, o nivelamento ou uma pausa).

**O modelo não vem incluído.** Tens de o treinar uma vez com `tools/train_model.py` (instruções em `assets/ai/LEIA-ME.md`). O que mais ajuda é usar fotos da tua própria câmara.

**Limitações:**
- A app tem de estar **aberta** com a câmara visível. O ecrã fica ligado enquanto vigia. O iOS (e o Android, sem um serviço em primeiro plano) suspende apps em segundo plano, por isso a vigilância não funciona com a app fechada. Para vigilância 24/7, o passo seguinte é correr o mesmo modelo num Raspberry Pi ou num telemóvel antigo ligado à corrente.
- Haverá falsos alarmes no início. Por isso a pausa é sempre uma pausa e nunca um stop.

**Android:** o `flutter_local_notifications` exige *core library desugaring*. Em `android/app/build.gradle(.kts)`, adiciona `isCoreLibraryDesugaringEnabled = true` em `compileOptions` e `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` em `dependencies`.

## Notas por plataforma

**iPhone.** A descoberta automática por broadcast UDP exige o entitlement `com.apple.developer.networking.multicast`, que tens de pedir à Apple. Sem ele, usa "Ligar por IP" (funciona por unicast). Na primeira utilização, o iOS pede autorização para aceder à rede local.

**Android.** O tráfego HTTP para o IP da impressora (câmara e upload) exige `usesCleartextTraffic`, e o `setup.sh` já trata disso.

## Slicing: o que existe agora e para onde evoluir

**Agora:** o slicing usa o [Kiri:Moto](https://grid.space/kiri) (open-source, MIT), um motor em JavaScript que corre num WebView invisível dentro do telemóvel. O modelo nunca sai do telemóvel. Por omissão, o código do motor é descarregado de `grid.space` na primeira utilização.

**Slicing offline:** copia o build do motor (repositório `GridSpace/grid-apps`) para `assets/slicer/` e serve-o com o `InAppLocalhostServer` do `flutter_inappwebview`, em vez de usar o `baseUrl` remoto.

**Qualidade ao nível do Orca/Bambu:** compila o `libslic3r` do OrcaSlicer (ou o CuraEngine) para Android (NDK) e iOS, e liga-o por `dart:ffi` numa nova classe que implemente `Slicer`. É o passo mais pesado do projeto (dependências como Boost, TBB e CGAL), mas a UI não precisa de mudar.

## Próximos passos sugeridos

1. Testar a ligação, a câmara e os controlos com a CC1 e corrigir os comandos da tabela acima.
2. Afinar o perfil CC1 no `slicer.html` e fazer uma impressão de teste (cubo de calibração).
3. Impressão multicor (várias cores numa peça): precisa de `.3mf` com partes ou pintura, trocas de ferramenta e torre de purga. Fica para o motor nativo (Orca), porque o Kiri:Moto não faz isto bem.
4. Pré-visualização 3D do STL e das camadas do G-code.
5. Suporte para `.3mf`.
6. Notificações de fim de impressão e acesso fora de casa (Tailscale ou um relay).

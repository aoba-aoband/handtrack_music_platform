# Handtrack Music Platform 日本語クイックガイド

## このファイルの目的

このファイルは、プロトタイプを起動して音を出すための日本語ガイドです。

このプロジェクトは完成アプリではなく、練習・検証用プロトタイプです。UIもまだ仮のもので、Python側はOpenCV trackbar、SuperCollider側は簡易GUIを使っています。

## システム全体の概要

```text
Webカメラ
-> Python / OpenCV / MediaPipe
-> 手のランドマーク検出
-> pitch / scale / quantization / final_freq 生成
-> OSC送信
-> SuperCollider
-> Synth発音
```

Python側は手の検出、音程、スケール、量子化、OSC送信を担当します。

SuperCollider側は、Pythonから届いた `final_freq` を使って発音し、Lag、ポルタメント、ソフトクリッピング、フィルター、Performance Gateなどを担当します。

## 初回セットアップ

Windows PowerShell想定:

```powershell
git clone https://github.com/aoba-aoband/handtrack_music_platform.git
cd handtrack_music_platform
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

PowerShellでvenv有効化が止まる場合:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## SuperCollider側の起動

1. SuperColliderを起動します。
2. `sc/basic_receiver.scd` を開きます。
3. ファイル全体、または外側のブロックを評価します。
4. Post windowに以下のような表示が出ればOKです。

```text
creating probe synth
Listening for generic hand control events on port 57120
Listening for sample mapping events that control the probe synth.
```

SC側は `127.0.0.1:57120` でOSCを待ち受けます。

評価すると `Probe Synth Controls` window が出ます。初期状態では Performance Gate がOFFなので、音が出ない場合は Gate button または spacebar を押してください。

## Python側の起動

通常起動:

```powershell
python main.py hands --sample-mapping --send-osc --show-pitch-guides --show-settings-panel
```

量子化ON:

```powershell
python main.py hands --sample-mapping --send-osc --show-pitch-guides --show-settings-panel --quantize-pitch
```

起動すると、カメラpreviewと `Pitch Settings` window が開きます。

- `q` で終了します。
- `--send-osc` がないとSCに値が送られません。
- `--sample-mapping` がないと右手pitch / 左手pinchのサンプル音楽マッピングが出ません。

## 基本操作

- 右手上下でpitch candidateを操作します。
- 右手の中指を人差し指より上にすると1オクターブ上がります。
- 左手pinchでamp candidateを操作します。
- SuperCollider側のGateがOFFだと音は出ません。
- SC側Gate buttonまたはspacebarで音を立ち上げ/立ち下げします。
- Python preview windowで `q` を押すと終了します。

## Python側UI: Pitch Settings

- Pitch Min note
- Pitch Max note
- Root
- Scale
- Quantize
- Guide Mode

## SuperCollider側UI: Probe Synth Controls

Performance / Gate:

- Gate button / spacebar
- crescendoTime
- decrescendoTime

Lag / Portamento:

- freqLag
- ampLag
- portamento
- portamentoTime

Soft clipping:

- softClip
- softClipDrive
- softClipMix

Filter:

- filter
- filterCutoff
- filterRq
- filterMix
- filterLag

Output / amp range:

- outputLevel
- ampMin
- ampMax
- Reset defaults

## SuperCollider側の音作りモニター

`sc/basic_receiver.scd` を評価すると、従来の `Probe Synth Controls` に加えて
`Probe Synth Monitor` が開きます。これは完成UIではなく、probe synth の
音作りを確認するための小さなモニターです。

- `targetFreq` / `followedFreq` で、Pythonから届いた周波数とSynth内部で追従中の周波数を確認できます。
- `targetAmp` / `followedAmp` で、左手pinchから作られたampとSynth内部のampを確認できます。
- Gate状態、`performanceEnv`、`outputLevel`、softClip、filter、`filterFreq` を確認できます。
- `Open Scope` で最終出力の波形を見られます。
- `Open FreqScope` で、softClipやfilter調整時の倍音・高域の変化を見られます。

softClipやfilterを調整するときの目安として使ってください。Python側のOSCアドレスや起動コマンドは変わりません。

## よくあるトラブル

音が出ない:

- SuperColliderで `sc/basic_receiver.scd` を評価したか確認します。
- `Probe Synth Controls` のGateがONか確認します。
- Python起動コマンドに `--send-osc` があるか確認します。
- 左手pinchや `ampMin` / `ampMax`、`outputLevel` を確認します。

カメラは出るが音が変わらない:

- Python起動コマンドに `--sample-mapping` があるか確認します。
- SuperColliderのPost windowにOSC受信メッセージが出ているか確認します。
- 右手/左手のhandednessが想定と逆になっていないか確認します。

Quantizeしているのにガイドと音が合わない:

- Python側のPitch SettingsでRoot / Scaleを確認します。
- Guide Modeがscaleになっているか確認します。
- guide設定とquantize設定が同じ値になっているか確認します。

SC側でスペースバーが効かない:

- `Probe Synth Controls` windowにフォーカスがあるか確認します。
- Gate buttonでも同じ操作ができます。

## 現在の制限

- OpenCV trackbar UIは仮です。
- Root / Scaleは数値UIで直感的ではありません。
- hand index / handednessはまだ完全な安定ロール追跡ではありません。
- tracking dropoutで音が跳ぶことがあります。
- SC音色はまだprobe synthです。
- Ableton / Max for Live連携は今後の課題です。

## 確認ポイント

- `sc/basic_receiver.scd` を評価してエラーがない。
- `Probe Synth Controls` windowにfilter系UIが出る。
- filterをONにすると音色が丸くなる。
- filterCutoffを下げると高域が削れる。
- filterRqを変えるとcutoff付近の癖が変わる。
- filterMixでdry/filterの混ざり方が変わる。
- softClip + filterの組み合わせで、歪ませた音を丸められる。

## 次に分けたい低遅延化

低遅延計測や `--low-latency` はまだ未実装です。次のような別作業として分けるのがよさそうです。

```text
次は Python側の --show-performance-stats と --low-latency を追加してください。
sc/basic_receiver.scd は変更しないでください。
```
